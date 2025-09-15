module HandleFileUpload
  extend ActiveSupport::Concern

  FileUploadClient = Object.const_get(Plugins.config_for('archivesspace-file-upload')["model_class"])

  ####################
  # Copied from handle_crud(opts) in 
  # frontend/app/controllers/application_controller.rb
  # with minor changes to include file upload handling.
  #
  def handle_crud_with_file_uploads(opts)
    begin
      # Start with the JSONModel object provided, or an empty one if none was
      # given.  Update it from the user's parameters
      model = opts[:model] || JSONModel(opts[:instance])
      obj = opts[:obj] || model.new

      obj.instance_data[:find_opts] = opts[:find_opts] if opts.has_key? :find_opts


      #### added for file upload handling
      if opts[:instance] == :digital_object
        object_id = :digital_object_id 
        obj_last_id = obj.digital_object_id
      elsif opts[:instance] == :digital_object_component
        object_id = :component_id
        obj_last_id = obj.component_id

        if params[opts[:instance]][object_id].empty?
          params[opts[:instance]][object_id] = SecureRandom.uuid
        end
      end

      params[opts[:instance]][object_id].strip!
      if params[opts[:instance]].has_key?(:file_versions)
        params[opts[:instance]][:file_versions].each do |k, v|
          if v[:file_upload].is_a?(ActionDispatch::Http::UploadedFile)
            params[opts[:instance]][:file_versions][k][:file_uri] = v[:file_upload].original_filename
            params[opts[:instance]][:file_versions][k][:file_size_bytes] = v[:file_upload].size
            # params[opts[:instance]][:file_versions][k][:file_format_name] = v[:file_upload].content_type
          end
        end
      end
      ####

      # We need to retain any restricted properties from the existing object. i.e.
      # properties that exist for the record but the user was not allowed to edit
      unless params[:action] == 'copy'
        if params[opts[:instance]].key?(:restricted_properties)
          params[opts[:instance]][:restricted_properties].each do |restricted|
            next unless obj.has_key? restricted

            params[opts[:instance]][restricted] = obj[restricted].dup
          end
        end
      end

      # Param validations that don't have to do with the JSON validator
      opts[:params_check].call(obj, params) if opts[:params_check]

      instance = cleanup_params_for_schema(params[opts[:instance]], model.schema)

      if opts[:before_hooks]
        opts[:before_hooks].each { |hook| hook.call(instance) }
      end

      if opts[:replace] || opts[:replace].nil?
        obj.replace(instance)
      elsif opts[:copy]
        obj.name = "Copy of " + obj.name
        obj.uri = ''
      else
        obj.update(instance)
      end

      if opts[:required_fields]
        opts[:required_fields].add_errors(obj)
      end

      # Make the updated object available to templates
      instance_variable_set("@#{opts[:instance]}".intern, obj)

      if not params.has_key?(:ignorewarnings) and not obj._warnings.empty?
        # Throw the form back to the user to confirm warnings.
        instance_variable_set("@exceptions".intern, obj._exceptions)
        return opts[:on_invalid].call
      end

      if obj._exceptions[:errors]
        instance_variable_set("@exceptions".intern, clean_exceptions(obj._exceptions))
        return opts[:on_invalid].call
      end

      #### added for file upload handling
      begin
        result = JSONModel::HTTP.get_json("/repositories/#{session[:repo_id]}/find_by_id/#{opts[:instance].to_s}s", {
          "#{object_id.to_s}[]": params[opts[:instance]][object_id],
        })["#{opts[:instance].to_s}s"]

        if (result.length > 0) && (obj.uri != result[0]['ref'])
          obj.add_error(object_id.to_s, :must_be_unique)
          instance_variable_set("@exceptions".intern, obj._exceptions)
          return opts[:on_invalid].call
        end
        FileUploadClient.create_or_update(obj_last_id, obj, params[opts[:instance]])
      rescue SocketError => e
        obj.add_error("file_versions", :file_server_error)
        instance_variable_set("@exceptions".intern, obj._exceptions)
        return opts[:on_invalid].call
      end
      ####

      if opts.has_key?(:save_opts)
        id = obj.save(opts[:save_opts])
      elsif opts[:instance] == :user and !params['user']['password'].blank?
        id = obj.save(:password => params['user']['password'])
      else
        id = obj.save
      end

      opts[:on_valid].call(id)
    rescue ConflictException
      instance_variable_set(:"@record_is_stale".intern, true)
      opts[:on_invalid].call
    rescue JSONModel::ValidationException => e
      # Throw the form back to the user to display error messages.
      instance_variable_set("@exceptions".intern, obj._exceptions)
      opts[:on_invalid].call
    end
  end
  #from commit 1bf3272

end
