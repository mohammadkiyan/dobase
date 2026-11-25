# frozen_string_literal: true

module Admin
  # The accounts of this installation. A new one is made from a template, and its
  # person chooses a password through the welcome link its page shows.
  class UsersController < BaseController
    before_action :set_user, only: %i[show update destroy]
    before_action :not_yourself, only: %i[update destroy]

    def index
      @users = User.order(:first_name, :last_name, :id)
    end

    def show
      @welcome_link = welcome_url(@user.generate_token_for(:welcome)) if @user.welcome_pending?
      @tools = @user.accessible_tools.includes(:tool_type).order(:name)
    end

    def new
      @setup = UserSetup.new(user_template_id: UserTemplate.order(:name).first&.id)
    end

    def create
      @setup = UserSetup.new(setup_params)
      @setup.made_by = Current.user

      if @setup.save
        notice = _("%{name}'s account is ready. Send them the welcome link below.", name: @setup.user.name)
        if @setup.skipped_tools.any?
          notice += " " + _("Not added to %{tools}: only an owner of a tool can add someone to it.",
            tools: @setup.skipped_tools.map(&:name).to_sentence)
        end
        redirect_to admin_user_path(@setup.user), notice: notice
      else
        render :new, status: :unprocessable_entity
      end
    end

    # Making someone an admin, or no longer one
    def update
      @user.update!(admin: params.require(:user)[:admin] == "1")
      redirect_to admin_user_path(@user), notice: @user.admin? ?
        _("%{name} is an admin now.", name: @user.name) : _("%{name} is no longer an admin.", name: @user.name)
    end

    def destroy
      @user.destroy!
      redirect_to admin_users_path, notice: _("%{name}'s account was deleted.", name: @user.name)
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    # An admin can't take their own rights away or delete themselves: there might be nobody left
    def not_yourself
      redirect_to admin_user_path(@user), alert: _("That can't be done to your own account.") if @user == Current.user
    end

    def setup_params
      params.require(:user_setup).permit(:first_name, :last_name, :email_address, :admin,
        :user_template_id, :mail_address, :mail_username, :mail_password)
    end
  end
end
