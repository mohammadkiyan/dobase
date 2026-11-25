# frozen_string_literal: true

Rails.application.config.x.app = ActiveSupport::OrderedOptions.new
Rails.application.config.x.app.name = ENV.fetch("APP_NAME", "Dobase")
Rails.application.config.x.app.logo_path = ENV.fetch("APP_LOGO_PATH", "/icon.svg")
Rails.application.config.x.app.host = ENV.fetch("APP_HOST", "localhost:3000")
# MAILER_FROM_ADDRESS is what ONCE calls the sender set on its email settings screen
Rails.application.config.x.app.from_email = ENV["APP_FROM_EMAIL"].presence || ENV["MAILER_FROM_ADDRESS"].presence || "notifications@dobase.co"

# This installation's own mail server (docker-mailserver in docker-compose.yml), on which
# the admin console makes a mailbox for each new account (MailServer). Off unless both the
# domain and the server's account file are given.
Rails.application.config.x.mail_server = ActiveSupport::OrderedOptions.new
Rails.application.config.x.mail_server.domain = ENV["MAIL_DOMAIN"].to_s.strip.downcase.presence
Rails.application.config.x.mail_server.accounts_file = ENV["MAILSERVER_ACCOUNTS_FILE"].presence
Rails.application.config.x.mail_server.host = ENV.fetch("MAILSERVER_HOST", "mailserver")
# The calendar server whose logins are the mail server's (Radicale in docker-compose.yml)
Rails.application.config.x.mail_server.caldav_url = ENV["MAILSERVER_CALDAV_URL"].to_s.strip.presence
# How long a new mailbox may take before the server takes its login: the server reads
# its account file every few seconds
Rails.application.config.x.mail_server.ready_within = 30.seconds
