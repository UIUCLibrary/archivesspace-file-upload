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
                    flash[:success] = I18n.t("digital_object._frontend.messages.created", JSONModelI18nWrapper.new(:digital_object => @digital_object).enable_parse_mixed_content!(url_for(:root)))

                    if @digital_object["is_slug_auto"] == false &&
                      @digital_object["slug"] == nil &&
                      params["digital_object"] &&
                      params["digital_object"]["is_slug_auto"] == "1"

                      flash[:warning] = I18n.t("slug.autogen_disabled")
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

                    flash.now[:success] = I18n.t("digital_object._frontend.messages.updated", JSONModelI18nWrapper.new(:digital_object => @digital_object).enable_parse_mixed_content!(url_for(:root)))

                    if @digital_object["is_slug_auto"] == false &&
                      @digital_object["slug"] == nil &&
                      params["digital_object"] &&
                      params["digital_object"]["is_slug_auto"] == "1"

                      flash.now[:warning] = I18n.t("slug.autogen_disabled")
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
        flash[:error] = I18n.t("digital_object._frontend.messages.delete_conflict", :error => I18n.t("errors.#{e.conflicts}", :default => e.message))
        return redirect_to(:controller => :digital_objects, :action => :show, :id => params[:id])
      end

      flash[:success] = I18n.t("digital_object._frontend.messages.deleted", JSONModelI18nWrapper.new(:digital_object => digital_object).enable_parse_mixed_content!(url_for(:root)))
      redirect_to(:controller => :digital_objects, :action => :index, :deleted_uri => digital_object.uri)
    end

  end


  class DigitalObjectComponentsController < ApplicationController
    include HandleFileUpload

    def create
      handle_crud_with_file_uploads(:instance => :digital_object_component,
                  :find_opts => find_opts,
                  :on_invalid => ->() { render_aspace_partial :partial => "new_inline" },
                  :on_valid => ->(id) {
                    # Refetch the record to ensure all sub records are resolved
                    # (this object isn't marked as stale upon create like Archival Objects,
                    # so need to do it manually)
                    @digital_object_component = JSONModel(:digital_object_component).find(id, find_opts)

                    flash[:success] = @digital_object_component.parent ?
                      I18n.t("digital_object_component._frontend.messages.created_with_parent", JSONModelI18nWrapper.new(:digital_object_component => @digital_object_component, :digital_object => @digital_object_component['digital_object']['_resolved'], :parent => @digital_object_component['parent']['_resolved']).enable_parse_mixed_content!(url_for(:root))) :
                      I18n.t("digital_object_component._frontend.messages.created", JSONModelI18nWrapper.new(:digital_object_component => @digital_object_component, :digital_object => @digital_object_component['digital_object']['_resolved']).enable_parse_mixed_content!(url_for(:root)))

                    if @digital_object_component["is_slug_auto"] == false &&
                      @digital_object_component["slug"] == nil &&
                      params["digital_object_component"] &&
                      params["digital_object_component"]["is_slug_auto"] == "1"

                      flash[:warning] = I18n.t("slug.autogen_disabled")
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
                      I18n.t("digital_object_component._frontend.messages.updated_with_parent", JSONModelI18nWrapper.new(:digital_object_component => @digital_object_component, :digital_object => digital_object, :parent => parent).enable_parse_mixed_content!(url_for(:root))) :
                      I18n.t("digital_object_component._frontend.messages.updated", JSONModelI18nWrapper.new(:digital_object_component => @digital_object_component, :digital_object => digital_object).enable_parse_mixed_content!(url_for(:root)))

                    if @digital_object_component["is_slug_auto"] == false &&
                      @digital_object_component["slug"] == nil &&
                      params["digital_object_component"] &&
                      params["digital_object_component"]["is_slug_auto"] == "1"

                      flash.now[:warning] = I18n.t("slug.autogen_disabled")
                    end

                    render_aspace_partial :partial => "edit_inline"
                  })
    end


    def delete
      digital_object_component = JSONModel(:digital_object_component).find(params[:id])
      FileUploadClient.delete(digital_object_component.component_id)
      digital_object_component.delete

      flash[:success] = I18n.t("digital_object_component._frontend.messages.deleted", JSONModelI18nWrapper.new(:digital_object_component => digital_object_component).enable_parse_mixed_content!(url_for(:root)))

      resolver = Resolver.new(digital_object_component['digital_object']['ref'])
      redirect_to resolver.view_uri
    end

  end
  #from commit e66cd04

end