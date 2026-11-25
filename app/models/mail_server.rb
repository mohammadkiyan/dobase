# frozen_string_literal: true

# This installation's own mail server, when it has one: docker-mailserver in
# docker-compose.yml, whose account file Dobase shares (the `mail-config` volume).
# A mailbox is a line in that file, "ann@example.com|{SHA512-CRYPT}$6$...", as the
# server's own `setup email add` writes it; the server reads the file again every few
# seconds and takes the new login from then on. Dobase reaches it inside the compose
# network, so without TLS, as the comments in docker-compose.yml say. Its calendar
# server, when it has one (Radicale, `caldav_url`), takes the same logins.
module MailServer
  class Error < StandardError; end

  module_function

  def config = Rails.application.config.x.mail_server

  def configured?
    config.domain.present? && config.accounts_file.present?
  end

  def domain = config.domain

  # What a Mail tool on one of its mailboxes connects with
  def settings
    { imap_host: config.host, imap_port: 143, imap_ssl: false,
      smtp_host: config.host, smtp_port: 587, smtp_auth: "plain", smtp_tls: false }
  end

  # A calendar server that takes this server's logins
  def calendar? = configured? && config.caldav_url.present?

  def caldav_url = config.caldav_url

  def in_domain?(address)
    address.to_s.downcase.end_with?("@#{domain}")
  end

  def mailbox?(address)
    address = address.to_s.downcase
    File.exist?(accounts_file) && File.foreach(accounts_file).any? { |line| address_of(line) == address }
  end

  # Adds the mailbox. The file is locked while it is read and written, so two accounts
  # made at once don't write over each other.
  def add_mailbox!(address, password)
    address = address.to_s.strip.downcase
    raise Error, "#{address} isn't an address at #{domain}" unless in_domain?(address)

    File.open(accounts_file, File::RDWR | File::CREAT | File::APPEND, 0o644) do |file|
      file.flock(File::LOCK_EX)
      existing = file.read
      raise Error, "#{address} has a mailbox already" if existing.each_line.any? { |line| address_of(line) == address }

      # Writes go to the end of the file whatever was read (APPEND)
      file.write("\n") unless existing.empty? || existing.end_with?("\n")
      file.write("#{address}|{SHA512-CRYPT}#{sha512_crypt(password)}\n")
    end
  rescue SystemCallError => error
    raise Error, error.message
  end

  # Waits until the server takes the new mailbox's login, so that the first sync doesn't
  # find it refused (a refused login is tried again only after an hour). True once it does.
  def ready?(account, within: config.ready_within)
    deadline = Time.current + within
    loop do
      return true if Mails::ConnectionCheck.new(account).problem.nil?
      return false if Time.current >= deadline

      sleep 1
    end
  end

  def accounts_file = config.accounts_file

  def address_of(line) = line.split("|", 2).first.to_s.strip.downcase

  def sha512_crypt(password)
    hash = password.crypt("$6$#{SecureRandom.alphanumeric(16)}")
    raise Error, "this system's crypt() can't make SHA512-CRYPT hashes" unless hash.start_with?("$6$")

    hash
  end
end
