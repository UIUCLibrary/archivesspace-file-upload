Rails.application.config.after_initialize do

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

  end
  #from commit e66cd04

end