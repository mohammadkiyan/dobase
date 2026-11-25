# frozen_string_literal: true

require "test_helper"

class UserAdminTest < ActiveSupport::TestCase
  test "the first account of an installation is its admin, and no other" do
    # Fixtures hang off the users: the check waits for a commit, which a test never makes
    ActiveRecord::Base.connection.disable_referential_integrity { User.delete_all }

    first = User.create!(first_name: "A", last_name: "B", email_address: "first@example.com", password: "password")
    second = User.create!(first_name: "C", last_name: "D", email_address: "second@example.com", password: "password")

    assert first.admin?
    assert_not second.admin?
  end
end
