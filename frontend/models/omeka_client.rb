require 'uri'
require 'net/http'
require 'json'
require 'multipart_post'

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
