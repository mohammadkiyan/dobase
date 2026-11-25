# frozen_string_literal: true

require "test_helper"

class MailServerTest < ActiveSupport::TestCase
  test "it is there only with a domain and an account file" do
    with_mail_server do
      assert MailServer.configured?
      Rails.application.config.x.mail_server.accounts_file = nil
      assert_not MailServer.configured?
    end
  end

  test "it has a calendar server only when it has a CalDAV address too" do
    with_mail_server { assert_not MailServer.calendar? }
    with_mail_server(caldav_url: "http://calendar:5232/") do
      assert MailServer.calendar?
      Rails.application.config.x.mail_server.accounts_file = nil
      assert_not MailServer.calendar?
    end
  end

  test "a mailbox is a line the server reads, with a SHA512-CRYPT hash of its password" do
    with_mail_server do |file|
      File.write(file, "postmaster@dobase.test|{SHA512-CRYPT}$6$x$y") # the server's own, without a newline at its end

      MailServer.add_mailbox!("Ann@Dobase.test", "secret")

      lines = File.readlines(file, chomp: true)
      assert_equal "postmaster@dobase.test|{SHA512-CRYPT}$6$x$y", lines.first
      address, hash = lines.second.split("|{SHA512-CRYPT}")
      assert_equal "ann@dobase.test", address
      assert hash.start_with?("$6$")
      assert_equal hash, "secret".crypt(hash)
      assert MailServer.mailbox?("ann@dobase.test")
    end
  end

  test "a mailbox that is there already, or at another domain, isn't added" do
    with_mail_server do |file|
      MailServer.add_mailbox!("ann@dobase.test", "secret")

      assert_raises(MailServer::Error) { MailServer.add_mailbox!("ANN@dobase.test", "other") }
      assert_raises(MailServer::Error) { MailServer.add_mailbox!("ann@example.com", "other") }
      assert_equal 1, File.readlines(file).size
    end
  end

  test "an account file it can't write says so" do
    with_mail_server do |file|
      Rails.application.config.x.mail_server.accounts_file = File.join(file, "missing", "postfix-accounts.cf")

      assert_raises(MailServer::Error) { MailServer.add_mailbox!("ann@dobase.test", "secret") }
    end
  end
end
