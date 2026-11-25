# frozen_string_literal: true

module Admin
  # The accounts of this installation. A new one is made from a template, and its
  # person chooses a password through the welcome link its page shows.
  class UsersController < BaseController
    before_action :set_user, only: %i[show update destroy]
    before_action :not_yourself, only: %i[update destroy]

    def index
      @users = User.order(:first_name, :last_name, :id)
      # How many tools each person is on, how many of them they use, and when they last opened one
      @tool_counts = Collaborator.group(:user_id).count
      @active_tool_counts = Collaborator.active.group(:user_id).count
      @last_active = Collaborator.group(:user_id).maximum(:last_seen_at)
    end

    # The tools someone is on, the ones they use first
    def show
      @welcome_link = welcome_url(@user.generate_token_for(:welcome)) if @user.welcome_pending?
      @memberships = Collaborator.where(user: @user).joins(:tool).includes(tool: %i[tool_type mail_account])
        .order(Arel.sql("collaborators.last_seen_at IS NULL"), last_seen_at: :desc).order("tools.name")
      @people_counts = Collaborator.where(tool_id: @memberships.map(&:tool_id)).group(:tool_id).count
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
        if @setup.mailbox_waiting?
          notice += " " + _("The mail server hasn't taken the new mailbox %{address} yet: its mail shows once it has.",
            address: @setup.mailbox_address)
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
