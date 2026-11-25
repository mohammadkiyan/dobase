# frozen_string_literal: true

require "test_helper"

class WelcomesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(first_name: "Ann", last_name: "Lee", email_address: "ann@example.com", password: SecureRandom.base58(32), welcome_pending: true)
    @token = @user.generate_token_for(:welcome)
  end

  test "the link lets them choose a password and signs them in, once" do
    get welcome_path(@token)
    assert_response :success
    assert_select "h1", text: "Welcome, Ann"

    patch welcome_path(@token), params: { password: "a-good-password", password_confirmation: "a-good-password" }
    assert_redirected_to root_path
    assert_not @user.reload.welcome_pending?
    assert @user.authenticate("a-good-password")
    assert cookies[:session_id].present?

    get welcome_path(@token)
    assert_redirected_to login_path
  end

  test "a password that doesn't do is said, and the link still works" do
    patch welcome_path(@token), params: { password: "short", password_confirmation: "short" }

    assert_response :unprocessable_entity
    assert @user.reload.welcome_pending?
    get welcome_path(@token)
    assert_response :success
  end

  test "a link is good for a week" do
    travel User::WELCOME_LINK_LIFETIME + 1.minute do
      get welcome_path(@token)
      assert_redirected_to login_path
    end
  end

  test "an account that chose its password another way has no welcome link" do
    @user.update!(password: "chosen-elsewhere")
    get welcome_path(@token)
    assert_redirected_to login_path
  end
end
