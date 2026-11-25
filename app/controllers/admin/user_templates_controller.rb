# frozen_string_literal: true

module Admin
  # What a new account starts with. Changing a template changes nothing for the
  # accounts already made from it.
  class UserTemplatesController < BaseController
    before_action :set_template, only: %i[edit update destroy]

    def index
      @templates = UserTemplate.order(:name)
    end

    def new
      @template = UserTemplate.new
    end

    def create
      @template = UserTemplate.new(template_params)

      if @template.save
        redirect_to admin_user_templates_path, notice: _("%{name} created successfully.", name: @template.name)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @template.update(template_params)
        redirect_to admin_user_templates_path, notice: _("%{name} updated successfully.", name: @template.name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @template.destroy!
      redirect_to admin_user_templates_path, notice: _("%{name} deleted successfully.", name: @template.name)
    end

    private

    def set_template
      @template = UserTemplate.find(params[:id])
    end

    def template_params
      params.require(:user_template).permit(
        :name, :mail, :mail_tool_name,
        :mail_imap_host, :mail_imap_port, :mail_imap_ssl,
        :mail_smtp_host, :mail_smtp_port, :mail_smtp_auth, :mail_smtp_tls,
        shared_tool_ids: [],
        chosen_tools: UserTemplate::OWN_TOOL_TYPES.index_with { %i[on name] }
      )
    end
  end
end
