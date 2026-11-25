# frozen_string_literal: true

require "test_helper"

module Admin
  class UserTemplatesControllerTest < ActionDispatch::IntegrationTest
    setup do
      users(:one).update!(admin: true)
      sign_in_as users(:one)
    end

    test "a template keeps the tools ticked, with their names, and the admin's tools to join" do
      get new_admin_user_template_path
      assert_response :success
      assert_select "input[name='user_template[shared_tool_ids][]'][value=?]", tools(:project_board).id.to_s
      assert_select "input[name='user_template[shared_tool_ids][]'][value=?]", tools(:other_todos).id.to_s, count: 0

      post admin_user_templates_path, params: { user_template: {
        name: "Sales",
        chosen_tools: { "boards" => { on: "1", name: "Pipeline" }, "chat" => { on: "0", name: "" }, "todos" => { on: "1", name: "" } },
        shared_tool_ids: [ "", tools(:project_board).id.to_s ]
      } }

      template = UserTemplate.find_by!(name: "Sales")
      assert_redirected_to admin_user_templates_path
      assert_equal [ { "type" => "todos", "name" => nil }, { "type" => "boards", "name" => "Pipeline" } ], template.own_tools
      assert_equal [ tools(:project_board).id ], template.shared_tool_ids
    end

    test "unticking every tool takes them all off" do
      template = UserTemplate.create!(name: "Sales", chosen_tools: { "boards" => { on: "1" } })

      patch admin_user_template_path(template), params: { user_template: { name: "Sales", chosen_tools: { "boards" => { on: "0" } } } }

      assert_empty template.reload.own_tools
    end

    test "a template with a mailbox needs its servers" do
      post admin_user_templates_path, params: { user_template: { name: "Mail", mail: "1" } }

      assert_response :unprocessable_entity
      assert_not UserTemplate.exists?(name: "Mail")
    end

    test "a template that makes the mailbox needs no servers, only the installation's mail server" do
      post admin_user_templates_path, params: { user_template: { name: "Mail", mail: "1", make_mailbox: "1" } }
      assert_response :unprocessable_entity
      assert_select ".flash-error", text: /no mail server to make mailboxes on/

      with_mail_server do
        get new_admin_user_template_path
        assert_select "input[type=checkbox][name='user_template[make_mailbox]'][checked]"

        post admin_user_templates_path, params: { user_template: { name: "Mail", mail: "1", make_mailbox: "1" } }
      end

      assert UserTemplate.find_by!(name: "Mail").make_mailbox?
    end

    test "only an admin gets in" do
      sign_in_as users(:two)
      get admin_user_templates_path
      assert_response :not_found
    end
  end
end
