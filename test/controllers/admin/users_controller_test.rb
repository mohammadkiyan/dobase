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

    test "a template that makes the mailbox adds it to the mail server and connects it" do
      with_mail_server do |file|
        @template.update!(mail: true, make_mailbox: true, mail_tool_name: "Work mail")
        imap = FakeImapServer.new

        assert_enqueued_jobs 1, only: SyncEmailsJob do
          with_mail_servers(imap: imap) do
            post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann.lee@example.com",
              user_template_id: @template.id, mail_password: "ignored" } }
          end
        end

        ann = User.find_by!(email_address: "ann.lee@example.com")
        assert_redirected_to admin_user_path(ann)
        account = ann.owned_tools.find_by!(name: "Work mail").mail_account
        assert_equal "ann.lee@dobase.test", account.email_address
        assert_equal "ann.lee@dobase.test", account.username
        assert_equal [ "mailserver", 143, false, "mailserver", 587, false ],
          account.slice(:imap_host, :imap_port, :imap_ssl, :smtp_host, :smtp_port, :smtp_tls).values
        assert_not_equal "ignored", account.password

        address, hash = File.read(file).chomp.split("|{SHA512-CRYPT}")
        assert_equal "ann.lee@dobase.test", address
        assert_equal hash, account.password.crypt(hash)
        assert_equal [ [ "ann.lee@dobase.test", account.password ] ], imap.tried_logins.uniq
      end
    end

    test "a Calendar tool of a mailbox made here is on the calendar server, with the mailbox's login" do
      with_mail_server(caldav_url: "http://calendar:5232/") do
        @template.update!(mail: true, make_mailbox: true, chosen_tools: { "calendar" => { on: "1", name: "Plans" } })

        assert_enqueued_with(job: SyncCalendarsJob) do
          with_mail_servers do
            post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com", user_template_id: @template.id } }
          end
        end

        ann = User.find_by!(email_address: "ann@example.com")
        mailbox = ann.owned_tools.joins(:tool_type).find_by!(tool_types: { slug: "mail" }).mail_account
        calendar = ann.owned_tools.find_by!(name: "Plans").calendar_account
        assert_equal [ "custom", "http://calendar:5232/", "ann@dobase.test" ], [ calendar.provider, calendar.caldav_url, calendar.username ]
        assert_equal mailbox.password, calendar.password
        assert_enqueued_with(job: SyncCalendarsJob, args: [ calendar.id, { discover: true } ])
      end
    end

    test "without a calendar server, a Calendar tool is left for them to set up" do
      with_mail_server do
        @template.update!(mail: true, make_mailbox: true, chosen_tools: { "calendar" => { on: "1" } })

        assert_no_enqueued_jobs only: SyncCalendarsJob do
          with_mail_servers do
            post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com", user_template_id: @template.id } }
          end
        end

        assert_nil User.find_by!(email_address: "ann@example.com").owned_tools.find_by!(name: "Calendar").calendar_account
      end
    end

    test "a mailbox made here is the person's own address when it is at the domain, or the one given" do
      with_mail_server do
        @template.update!(mail: true, make_mailbox: true)

        with_mail_servers do
          post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@dobase.test", user_template_id: @template.id } }
          post admin_users_path, params: { user_setup: { first_name: "Bo", last_name: "Ng", email_address: "bo@example.com",
            mail_address: "bo.ng@dobase.test", user_template_id: @template.id } }
        end

        assert MailServer.mailbox?("ann@dobase.test")
        assert MailServer.mailbox?("bo.ng@dobase.test")
      end
    end

    test "a mailbox that is taken, or at another domain, makes nothing" do
      with_mail_server do |file|
        @template.update!(mail: true, make_mailbox: true)
        MailServer.add_mailbox!("ann@dobase.test", "theirs")

        assert_no_difference -> { User.count } do
          post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com", user_template_id: @template.id } }
          post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com",
            mail_address: "ann@elsewhere.com", user_template_id: @template.id } }
        end

        assert_response :unprocessable_entity
        assert_select ".error-text", text: "must be an address at dobase.test"
        assert_equal 1, File.readlines(file).size
      end
    end

    test "nothing is made when the mail server's account file can't be written" do
      with_mail_server do
        @template.update!(mail: true, make_mailbox: true)
        Rails.application.config.x.mail_server.accounts_file = "/nonexistent/postfix-accounts.cf"

        assert_no_difference [ -> { User.count }, -> { Tool.count }, -> { Mails::Account.count } ] do
          post admin_users_path, params: { user_setup: { first_name: "Ann", last_name: "Lee", email_address: "ann@example.com", user_template_id: @template.id } }
        end

        assert_response :unprocessable_entity
        assert_select ".flash-error", text: /The mailbox couldn't be made/
      end
    end

    test "a person's page says which of their tools they use, and when they last opened each" do
      memberships = Collaborator.where(user: users(:two)).includes(:tool).order(:id).to_a
      assert memberships.many?
      memberships.each { |membership| membership.update_column(:last_seen_at, nil) }
      used = memberships.last
      used.update_column(:last_seen_at, 2.hours.ago)

      get admin_user_path(users(:two))

      assert_response :success
      rows = css_select("li").select { |row| memberships.any? { |membership| row.text.include?(membership.tool.name) } }
      assert_equal memberships.size, rows.size
      assert_equal used.tool.name, rows.first.at_css("p").text.strip, "the tool used last comes first"
      assert_match "In use", rows.first.text
      assert_match "Opened about 2 hours ago", rows.first.text
      assert rows.drop(1).all? { |row| row.text.include?("Never opened") && row.text.exclude?("In use") }
    end

    test "the console says how many tools each person uses" do
      Collaborator.where(user: users(:two)).update_all(last_seen_at: nil)
      Collaborator.where(user: users(:two)).first.update!(last_seen_at: 1.day.ago)
      count = Collaborator.where(user: users(:two)).count

      get admin_users_path

      assert_match "1 of #{count} tools in use", response.body
      assert_match "Active 1 day ago", response.body
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
