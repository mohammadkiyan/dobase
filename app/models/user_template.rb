# frozen_string_literal: true

# What an account an admin makes starts with: tools of its own, a Mail tool on its
# own mailbox, and tools of the admin's it joins as a collaborator. The mailbox is
# made for it on this installation's mail server (make_mailbox, MailServer), or is
# one that exists on the servers named here, with the login given when the account
# is made.
class UserTemplate < ApplicationRecord
  # Mail is a tool of its own here: it needs a mailbox to be of use
  OWN_TOOL_TYPES = %w[todos boards docs files chat calendar room].freeze

  validates :name, presence: true
  validates :mail_imap_host, :mail_smtp_host, presence: true, if: -> { mail? && !make_mailbox? }
  validate :mail_server_configured, if: -> { mail? && make_mailbox? }
  validates :mail_smtp_auth, inclusion: { in: Mails::Account::SMTP_AUTH_METHODS }
  validate :tools_are_known

  before_validation :tidy

  # The tools a new account gets of its own, as { "type" => slug, "name" => name }
  def own_tools
    Array(tools)
  end

  def own_tool(slug)
    own_tools.find { |tool| tool["type"] == slug }
  end

  # The admin's tools a new account joins. A tool that has gone since is left out.
  def shared_tools
    Tool.where(id: shared_tool_ids).includes(:tool_type).order(:name)
  end

  # A mailbox made on this installation's mail server is reached the way that server says
  def mail_server_settings
    return MailServer.settings if make_mailbox?

    {
      imap_host: mail_imap_host, imap_port: mail_imap_port, imap_ssl: mail_imap_ssl,
      smtp_host: mail_smtp_host, smtp_port: mail_smtp_port, smtp_auth: mail_smtp_auth, smtp_tls: mail_smtp_tls
    }
  end

  # The form says which kinds are ticked and what each is called
  def chosen_tools=(chosen)
    self.tools = chosen.to_h.filter_map do |slug, settings|
      settings = settings.to_h.stringify_keys
      next unless ActiveModel::Type::Boolean.new.cast(settings["on"])

      { "type" => slug.to_s, "name" => settings["name"].to_s.strip.presence }
    end
  end

  private

  def tidy
    self.name = name.to_s.strip
    self.shared_tool_ids = Array(shared_tool_ids).compact_blank.map(&:to_i).uniq
    self.mail_imap_host = mail_imap_host.to_s.strip.presence
    self.mail_smtp_host = mail_smtp_host.to_s.strip.presence
  end

  def mail_server_configured
    errors.add(:base, _("This installation has no mail server to make mailboxes on.")) unless MailServer.configured?
  end

  def tools_are_known
    unknown = own_tools.map { |tool| tool["type"] } - OWN_TOOL_TYPES
    errors.add(:tools, :invalid) if unknown.any?
  end
end
