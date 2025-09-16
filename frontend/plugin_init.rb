Rails.application.config.after_initialize do
  
  class DigitalObjectsController
    include HandleFileUpload

    def create
      handle_crud_with_file_uploads(:instance => :digital_object,
                  :on_invalid => ->() {
                    return render_aspace_partial :partial => "new" if inline?
                    render :action => "new"
                  },
                  :on_valid => ->(id) {
                    flash[:success] = t("digital_object._frontend.messages.created", digital_object_title: clean_mixed_content(@digital_object.title))

                    if @digital_object["is_slug_auto"] == false &&
                      @digital_object["slug"] == nil &&
                      params["digital_object"] &&
                      params["digital_object"]["is_slug_auto"] == "1"

                      flash[:warning] = t("slug.autogen_disabled")
                    end

                    return render :json => @digital_object.to_hash if inline?
                    redirect_to({
                                  :controller => :digital_objects,
                                  :action => :edit,
                                  :id => id
                                })
                  })
    end


    def update
      handle_crud_with_file_uploads(:instance => :digital_object,
                  :obj => JSONModel(:digital_object).find(params[:id], find_opts),
                  :on_invalid => ->() {
                    render_aspace_partial :partial => "edit_inline"
                  },
                  :on_valid => ->(id) {

                    flash.now[:success] = t("digital_object._frontend.messages.updated", digital_object_title: clean_mixed_content(@digital_object.title))
                    if @digital_object["is_slug_auto"] == false &&
                      @digital_object["slug"] == nil &&
                      params["digital_object"] &&
                      params["digital_object"]["is_slug_auto"] == "1"

                      flash.now[:warning] = t("slug.autogen_disabled")
                    end

                    render_aspace_partial :partial => "edit_inline"
                  })
    end


    def delete
      digital_object = JSONModel(:digital_object).find(params[:id])

      begin
        FileUploadClient.delete(digital_object.digital_object_id)
        digital_object.delete
      rescue ConflictException => e
        flash[:error] = t("digital_object._frontend.messages.delete_conflict", :error => t("errors.#{e.conflicts}", :default => e.message))
        return redirect_to(:controller => :digital_objects, :action => :show, :id => params[:id])
      end

      flash[:success] = t("digital_object._frontend.messages.deleted", digital_object_title: clean_mixed_content(digital_object.title))
      redirect_to(:controller => :digital_objects, :action => :index, :deleted_uri => digital_object.uri)
    end

  end


  class DigitalObjectComponentsController < ApplicationController
    include HandleFileUpload

    def create
      handle_crud_with_file_uploads(:instance => :digital_object_component,
                  :find_opts => find_opts,
                  :on_invalid => ->() { return render_aspace_partial :partial => "new_inline" },
                  :on_valid => ->(id) {
                    # Refetch the record to ensure all sub records are resolved
                    # (this object isn't marked as stale upon create like Archival Objects,
                    # so need to do it manually)
                    @digital_object_component = JSONModel(:digital_object_component).find(id, find_opts)
                    digital_object = @digital_object_component['digital_object']['_resolved']
                    parent = @digital_object_component['parent']? @digital_object_component['parent']['_resolved'] : false

                    flash[:success] = @digital_object_component.parent ?
                      t("digital_object_component._frontend.messages.created_with_parent", digital_object_component_display_string: clean_mixed_content(@digital_object_component.title), digital_object_title: clean_mixed_content(digital_object['title']), parent_display_string: clean_mixed_content(parent['title'])) :
                      t("digital_object_component._frontend.messages.created", digital_object_component_display_string: clean_mixed_content(@digital_object_component.title), digital_object_title: clean_mixed_content(digital_object['title']))

                    if @digital_object_component["is_slug_auto"] == false &&
                      @digital_object_component["slug"] == nil &&
                      params["digital_object_component"] &&
                      params["digital_object_component"]["is_slug_auto"] == "1"

                      flash[:warning] = t("slug.autogen_disabled")
                    end

                    render_aspace_partial :partial => "digital_object_components/edit_inline"
                  })
    end


    def update
      params['digital_object_component']['position'] = params['digital_object_component']['position'].to_i if params['digital_object_component']['position']

      @digital_object_component = JSONModel(:digital_object_component).find(params[:id], find_opts)
      digital_object = @digital_object_component['digital_object']['_resolved']
      parent = @digital_object_component['parent'] ? @digital_object_component['parent']['_resolved'] : false

      handle_crud_with_file_uploads(:instance => :digital_object_component,
                  :obj => @digital_object_component,
                  :on_invalid => ->() { return render_aspace_partial :partial => "edit_inline" },
                  :on_valid => ->(id) {

                    flash.now[:success] = parent ?
                      t("digital_object_component._frontend.messages.updated_with_parent", digital_object_component_display_string: clean_mixed_content(@digital_object_component.title)) :
                      t("digital_object_component._frontend.messages.updated", digital_object_component_display_string: clean_mixed_content(@digital_object_component.title))
                    if @digital_object_component["is_slug_auto"] == false &&
                      @digital_object_component["slug"] == nil &&
                      params["digital_object_component"] &&
                      params["digital_object_component"]["is_slug_auto"] == "1"

                      flash.now[:warning] = t("slug.autogen_disabled")
                    end

                    render_aspace_partial :partial => "edit_inline"
                  })
    end


    def delete
      digital_object_component = JSONModel(:digital_object_component).find(params[:id])
      FileUploadClient.delete(digital_object_component.component_id)
      digital_object_component.delete

      flash[:success] = t("digital_object_component._frontend.messages.deleted", digital_object_component_display_string: clean_mixed_content(digital_object_component.title))

      resolver = Resolver.new(digital_object_component['digital_object']['ref'])
      redirect_to resolver.view_uri
    end

  end
  #from commit 1bf3272

end