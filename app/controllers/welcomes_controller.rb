# frozen_string_literal: true

# The link an admin hands someone whose account they made: it lets them choose a
# password and signs them in. It works once, and for a week (User::WELCOME_LINK_LIFETIME).
class WelcomesController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { redirect_to login_path, alert: _("Try again later.") }

  def show
  end

  def update
    if params[:password].blank?
      flash.now[:alert] = _("Choose a password.")
      return render :show, status: :unprocessable_entity
    end

    if @user.update(params.permit(:password, :password_confirmation))
      terminate_session if authenticated?
      start_new_session_for(@user)
      redirect_to root_path, notice: _("Welcome to %{app_name}, %{first_name}!", app_name: helpers.app_name, first_name: @user.first_name)
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_token_for(:welcome, params[:token])
    redirect_to login_path, alert: _("This welcome link has been used or has expired. Ask your admin for a new one.") unless @user
  end
end
