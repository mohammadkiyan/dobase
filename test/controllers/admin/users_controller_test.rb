# frozen_string_literal: true

require "test_helper"

module Admin
  class UsersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = users(:one)
      @admin.update!(admin: true)
      sign_in_as @admin
      @template = UserTemplate.create!(name: "Staff", chosen_tools: { "todos" => { on: "1", name: "My work" }, "docs" => { on: "1" } },
        shared_tool_ids: [ tools(:project_board).id ])
    end

    test "only an admin finds the console" do
      sign_in_as users(:two)

      get admin_users_path
      assert_response :not_found
      post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com" } }
      assert_response :not_found
      assert_not User.exists?(email_address: "ann@example.com")
    end

    test "an access token never reaches it" do
      get admin_users_path, headers: api_headers(@admin), as: :json
      assert_response :forbidden
    end

    test "the console lists everyone and says who hasn't signed in yet" do
      users(:two).update_column(:welcome_pending, true)

      get admin_users_path

      assert_response :success
      assert_select "a[href=?]", admin_user_path(users(:two)), text: users(:two).name
      assert_select ".badge", text: "Not signed in yet", count: 1
    end

    test "an account made from a template has its tools, joins the admin's, and gets a welcome link" do
      assert_difference -> { User.count } => 1, -> { Tool.count } => 2 do
        post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "Ann@Example.com", user_template_id: @template.id } }
      end

      ann = User.find_by!(email_address: "ann@example.com")
      assert_redirected_to admin_user_path(ann)
      assert ann.welcome_pending?
      assert_not ann.admin?
      assert_equal [ "Docs", "My work" ], ann.owned_tools.order(:name).pluck(:name)
      assert ann.owned_tools.all? { |tool| tool.owned_by?(ann) }
      assert tools(:project_board).accessible_by?(ann)
      assert_not tools(:project_board).owned_by?(ann)

      follow_redirect!
      link = css_select("[data-clipboard-target='source']").first["value"]
      assert_match %r{/welcome/}, link
      assert_equal ann, User.find_by_token_for(:welcome, link.split("/").last)
    end

    test "a tool the admin doesn't own isn't joined" do
      @template.update!(shared_tool_ids: [ tools(:other_todos).id ])

      post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com", user_template_id: @template.id } }

      assert_not tools(:other_todos).accessible_by?(User.find_by!(email_address: "ann@example.com"))
      assert_match "Not added to", flash[:notice]
    end

    test "a template with a mailbox connects it with the login given" do
      @template.update!(mail: true, mail_tool_name: "Work mail", mail_imap_host: "imap.example.com", mail_smtp_host: "smtp.example.com")
      imap = FakeImapServer.new

      assert_enqueued_jobs 1, only: SyncEmailsJob do
        with_mail_servers(imap: imap) do
          post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com",
            user_template_id: @template.id, mail_password: "secret" } }
        end
      end

      ann = User.find_by!(email_address: "ann@example.com")
      account = ann.owned_tools.find_by!(name: "Work mail").mail_account
      assert_equal [ [ "ann@example.com", "secret" ] ], imap.tried_logins
      assert_equal "ann@example.com", account.email_address
      assert_equal "secret", account.password
    end

    test "a mailbox that turns the login down makes nothing" do
      @template.update!(mail: true, mail_imap_host: "imap.example.com", mail_smtp_host: "smtp.example.com")

      assert_no_difference -> { User.count } do
        with_mail_servers(imap: FakeImapServer.new(refuses_login: "Invalid credentials")) do
          post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com",
            user_template_id: @template.id, mail_password: "wrong" } }
        end
      end

      assert_response :unprocessable_entity
      assert_select ".flash-error", text: /The mailbox couldn't be connected/
    end

    test "an address someone already has is refused" do
      assert_no_difference -> { User.count } do
        post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: users(:two).email_address } }
      end

      assert_response :unprocessable_entity
      assert_select ".flash-error", text: /already been taken/
    end

    test "an admin makes someone an admin, and can't undo their own" do
      patch admin_user_path(users(:two)), params: { user: { admin: "1" } }
      assert users(:two).reload.admin?

      patch admin_user_path(@admin), params: { user: { admin: "0" } }
      assert @admin.reload.admin?
      assert_equal "That can't be done to your own account.", flash[:alert]
    end

    test "an admin deletes someone else's account but not their own" do
      assert_difference -> { User.count }, -1 do
        delete admin_user_path(users(:two))
      end
      assert_redirected_to admin_users_path

      assert_no_difference -> { User.count } do
        delete admin_user_path(@admin)
      end
    end
  end
end
