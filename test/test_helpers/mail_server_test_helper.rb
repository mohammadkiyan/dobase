# frozen_string_literal: true

# This installation's own mail server (MailServer) for a test: its account file in a
# folder of its own, at the domain given, with a calendar server when one is given
module MailServerTestHelper
  def with_mail_server(domain: "dobase.test", caldav_url: nil)
    config = Rails.application.config.x.mail_server
    was = config.slice(:domain, :accounts_file, :ready_within, :caldav_url)

    Dir.mktmpdir do |dir|
      config.domain = domain
      config.accounts_file = File.join(dir, "postfix-accounts.cf")
      config.ready_within = 0.seconds
      config.caldav_url = caldav_url
      yield config.accounts_file
    end
  ensure
    config.merge!(was)
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include MailServerTestHelper
end
