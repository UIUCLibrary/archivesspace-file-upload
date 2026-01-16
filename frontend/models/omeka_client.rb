require 'uri'
require 'net/http'
require 'json'

def parse_date(date)
    label_value = date.fetch('label', date['date_label'])
    begin_date  = date.fetch('begin', date.fetch('structured_date_range', {})['begin_date_standardized'])
    end_date    = date.fetch('end',   date.fetch('structured_date_range', {})['end_date_standardized'])

    if !label_value.blank?
        if label_value == 'creation'
        label = ''
        else
        label = "#{I18n.t('enumerations.date_label.' + label_value, default: label_value)}: "
        end
    else
        label = ''
    end

    exp = date['expression'] || ''
    if exp.blank?
        exp = begin_date unless begin_date.blank?
        unless end_date.blank?
        exp = (exp.blank? ? '' : exp + ' - ') + end_date
        end
    end

    if date['date_type'] == 'bulk'
        exp = exp.sub('bulk', '').sub('()', '').strip
        exp = begin_date == end_date ? I18n.t('bulk._singular', :dates => exp) :
                I18n.t('bulk._plural', :dates => exp)
    end

    [label, exp, label_value]
end

class OmekaClient
    @@config = Plugins.config_for('archivesspace-file-upload')

    def self.http_conn
        @http ||= Net::HTTP::Persistent.new name: 'omeka_client'
        @http.read_timeout = 1200
        @http
    end

    def self.do_http_request(url, request)
        response = http_conn.request(url, request)

        response
    end

    def self.set_url(path, query_params = {})
        params = {
            key_identity: @@config['api_key_identity'],
            key_credential: @@config['api_key_credential']
        }.merge(query_params)
        url = URI.join(@@config['baseurl'], path)
        url.query = URI.encode_www_form(params)
        return url
    end

    def self.add_subject_to_data(subject_src, data_dst)
        term_types = {
            "genre_form" => "schema:genre",
            "geographic" => "dcterms:spatial",
            "topical" => "dcterms:subject",
#                "occupation" => "schema:occupation",
#                "uniform_title" => "dcterms:alternative"
        }
        subject_src["terms"].each do |term_entry|
            if term_types.has_key?(term_entry["term_type"])
                data_dst[term_types[term_entry["term_type"]]] ||= []
                data_dst[term_types[term_entry["term_type"]]].push({
                    "property_id": "auto",
                    "@value": term_entry["term"],
                    "type": "literal"
                })
            end
        end
    end

    def self.prepare_item_data(params, primary_media, new_item = true)
        property_id = params.has_key?(:component_id) ? params[:component_id] : params[:digital_object_id] 
        data = {
            "dcterms:title": [{
                "property_id": "auto",
                "@value": params[:title],
                "type": "literal"
            }],
            "dcterms:identifier": [{
                "property_id": "auto",
                "@value": property_id,
                "type": "literal"
            }],
            "@type": "o:Item",
            "o:is_public": params[:publish],
        }

        if params.has_key?(:lang_materials)
            params[:lang_materials].each do |k, v|
                data["dcterms:language"] ||= []
                if v.has_key?(:language_and_script)
                    language = I18n.t('enumerations.language_iso639_2.'+v[:language_and_script][:language])
                    language += " - " + I18n.t('enumerations.script_iso15924.'+v[:language_and_script][:script]) unless v[:language_and_script][:script].blank?
                    data["dcterms:language"].push({
                        "property_id": "auto",
                        "@value": language,
                        "type": "literal"
                    })
                elsif v.has_key?(:notes)
                    v[:notes].each do |k2, v2|
                        v2[:content].each do |k2, v3|
                            data["dcterms:language"].push({
                                "property_id": "auto",
                                "@value": v3,
                                "type": "literal"
                            })
                        end
                    end
                end
            end
        end

        if params.has_key?(:dates)
            params[:dates].each do |k, v|
                data["dcterms:date"] ||= []
                parsed_date = parse_date(v)
                data["dcterms:date"].push({
                    "property_id": "auto",
                    "@value": "#{parsed_date[0]} #{parsed_date[1]}".strip,
                    "type": "literal"
                })
            end
        end

        if params.has_key?(:linked_agents)
            agent_types = {
                "creator" => "dcterms:creator",
    #            "subject" => "",
    #            "source" => ""
            }
            params[:linked_agents].each do |k, v|
                if agent_types.has_key?(v[:role])
                    data[agent_types[v[:role]]] ||= []
                    begin
                        creator = JSON.parse(v[:_resolved])
                        data[agent_types[v[:role]]].push({
                            "property_id": "auto",
                            "@value": creator["title"],
                            "type": "literal"
                        })
                    rescue TypeError
                        v[:_resolved].each do |v2|
                            creator = JSON.parse(v2)
                            data[agent_types[v[:role]]].push({
                                "property_id": "auto",
                                "@value": creator["title"],
                                "type": "literal"
                            })
                        end
                    end
                end
            end
        end

        if params.has_key?(:subjects)
            params[:subjects].each do |k, v|
                begin
                    subject = JSON.parse(v[:_resolved])
                    self.add_subject_to_data(subject, data)
                rescue NoMethodError
                    subject = JSON.parse(JSON.parse(v[:_resolved])["json"])
                    self.add_subject_to_data(subject, data)
                rescue TypeError
                    v[:_resolved].each do |v2|
                        subject = JSON.parse(JSON.parse(v2)["json"])
                        self.add_subject_to_data(subject, data)
                    end
                end
            end
        end

        if params.has_key?(:notes)
            note_types = { 
                "summary" => "dcterms:description",
                "physdesc" => "dcterms:extent",
                "note" => "dcterms:contributor",
                "userestrict" => "dcterms:accessRights"
            }
            params[:notes].each do |k, v|
                if note_types.has_key?(v[:type])
                    data[note_types[v[:type]]] ||= []
                    data[note_types[v[:type]]].push({
                        "property_id": "auto",
                        "@value": v[:content].values.join("\n\n"),
                        "type": "literal",
                        "is_public": v[:publish] ? true : false 
                    })
                end
            end
        end

        if primary_media.is_a?(Integer)
            data["o:primary_media"] = {
                "o:id": primary_media
            }
        end

        # for update, just return the data as JSON
        if !new_item
            return data
        end

        # for create, prepare the form data with files
        form_data = []
        data["o:media"] = []
        if params.has_key?(:file_versions)
            i = 0
            params[:file_versions].each do |k, v|
                if v[:file_upload].is_a?(ActionDispatch::Http::UploadedFile)
                    data["o:media"].push({
                        "o:ingester": "upload",
                        "file_index": i,
                        "o:is_public": v[:publish],
                        "dcterms:title": [{
                            "property_id": "auto",
                            "@value": v[:caption],
                            "type": "literal"
                        }]
                    })
                    form_data.push(["file[#{i}]", File.open(v[:file_upload].tempfile.path)])
                    i += 1
                end
            end
        end

        return form_data.push(['data', JSON.generate(data)])
    end


    def self.create_or_update(obj_last_id, obj, params)
        if obj_last_id.nil?
            return self.create(obj, params)
        else
            return self.update(obj_last_id, obj, params)
        end
    end

    def self.create(obj, params)
        url = self.set_url("/api/items")
        request = Net::HTTP::Post.new(url)
        request.set_form(self.prepare_item_data(params, nil, true), 'multipart/form-data')
        response = self.do_http_request(url, request)

        result = JSON.parse(response.read_body)

        if params.has_key?(:file_versions)
            media_list = result["o:media"]
            i = 0
            j = 0
            params[:file_versions].each do |k, v|
                if v[:file_upload].is_a?(ActionDispatch::Http::UploadedFile)
                    obj.file_versions[i]["file_uri"] = media_list[j]['@id']
                    obj.file_versions[i]["file_size_bytes"] = v[:file_upload].size
                    # obj.file_versions[i]["file_format_name"] = v[:file_upload].content_type
                    j += 1
                end
                i += 1
            end
        end

        return result
    end

    def self.read(obj_id)
        url = self.set_url("/api/items", {
            "property[0][property]": "dcterms:identifier",
            "property[0][type]": "eq",
            "property[0][text]": obj_id,
        })

        response = self.do_http_request(url, Net::HTTP::Get.new(url))

        return JSON.parse(response.read_body)
    end

    def self.update(obj_last_id, obj, params)
        item = self.read(obj_last_id)
        if item.length == 0
            return self.create(obj, params)
        end

        media_list = item[0]["o:media"].map { |media| [media['@id'], media['o:id']] }.to_h
        primary_media = nil
        if params.has_key?(:file_versions)
            i = 0
            params[:file_versions].each do |k, v|
                # if there is a new file, create it (and later delete the current media if exists)
                if v[:file_upload].is_a?(ActionDispatch::Http::UploadedFile)
                    data = {
                        "o:ingester": "upload",
                        "file_index": 0,
                        "o:item": {"o:id": item[0]['o:id']},
                        "o:is_public": v[:publish],
                        "dcterms:title": [{
                            "property_id": "auto",
                            "@value": v[:caption],
                            "type": "literal"
                        }]
                    }
                    form_data = [
                        ['data', JSON.generate(data)],
                        ["file[0]", File.open(v[:file_upload].tempfile.path)]
                    ]

                    url = self.set_url("/api/media")
                    request = Net::HTTP::Post.new(url)
                    request.set_form(form_data, 'multipart/form-data')

                    response = self.do_http_request(url, request)

                    obj.file_versions[i]["file_uri"] = JSON.parse(response.read_body)['@id']
                    obj.file_versions[i]["file_size_bytes"] = v[:file_upload].size
                    # obj.file_versions[i]["file_format_name"] = v[:file_upload].content_type

                    if v[:is_representative] == '1'
                        primary_media = JSON.parse(response.read_body)['o:id']
                    end

                # if already exists in Omeka, just update the metadata
                elsif media_list.has_key?(v[:file_uri])
                    data = {
                        "o:is_public": v[:publish],
                        "dcterms:title": [{
                            "property_id": "auto",
                            "@value": v[:caption],
                            "type": "literal"
                        }],
                        "@type": "o:Media",
                    }
                    if v[:is_representative] == '1'
                        primary_media = media_list[v[:file_uri]]
                    end

                    url = self.set_url("/api/media/#{media_list[v[:file_uri]]}")
                    request = Net::HTTP::Patch.new(url, 'Content-Type' => 'application/json')
                    request.body = JSON.generate(data)

                    response = self.do_http_request(url, request)
                    media_list.delete(v[:file_uri])
                end
                i += 1
            end
        end
        # delete from Omeka the rest of media that were not processed (not in params)
        media_list.each do |k, v|
            url = self.set_url("/api/media/#{v}")
            response = self.do_http_request(url, Net::HTTP::Delete.new(url))
        end

        # finally, update the item metadata
        url = self.set_url("/api/items/#{item[0]['o:id']}")
        request = Net::HTTP::Patch.new(url, 'Content-Type' => 'application/json')
        request.body = JSON.generate(self.prepare_item_data(params, primary_media, false))
        response = self.do_http_request(url, request)

        return JSON.parse(response.read_body)
    end

    def self.delete(obj_id)
        item = self.read(obj_id)
        return item if item.length == 0

        url = self.set_url("/api/items/#{item[0]['o:id']}")
        response = self.do_http_request(url, Net::HTTP::Delete.new(url))

        return JSON.parse(response.read_body)
    end
end
