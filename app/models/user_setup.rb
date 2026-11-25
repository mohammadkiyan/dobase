# frozen_string_literal: true

# An account an admin makes for someone else: the person, the tools a template gives
# them, their mailbox, and the tools of the admin's they join. All of it is made, or
# none of it. The person chooses a password through the welcome link (User#welcome).
#
# The mailbox is one that exists, connected with the login the admin gives, or one
# made for them on this installation's mail server (UserTemplate#make_mailbox), with
# a password nobody sees: it is kept encrypted on the Mail tool, as any other. When
# the mail server has a calendar server too (MailServer.calendar?), the person's
# Calendar tools are connected to it with that same login.
class UserSetup
  include ActiveModel::Model
  include ActiveModel::Attributes
  include Translation::Methods

  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email_address, :string
  attribute :admin, :boolean, default: false
  attribute :user_template_id, :integer
  attribute :mail_address, :string
  attribute :mail_username, :string
  attribute :mail_password, :string

  attr_reader :user, :mail_account, :calendar_accounts, :skipped_tools
  attr_accessor :made_by

  validate :template_exists
  validate :mailbox_given, if: -> { mail? && !make_mailbox? }
  validate :mailbox_can_be_made, if: :make_mailbox?

  def template
    @template ||= UserTemplate.find_by(id: user_template_id) if user_template_id
  end

  def mail?
    template&.mail?
  end

  def make_mailbox?
    mail? && template.make_mailbox?
  end

  # The mailbox's address is the person's own unless another is given, and its login
  # is that address unless another is given. A mailbox made here is at the mail
  # server's domain: their own address when it is there, else its name at the domain.
  def mailbox_address
    return mail_address.presence || email_address.to_s.strip unless make_mailbox?

    address = mail_address.presence || email_address.to_s.strip
    address = "#{address.split("@").first}@#{MailServer.domain}" unless mail_address.present? || MailServer.in_domain?(address)
    address.strip.downcase
  end

  def mailbox_login = make_mailbox? ? mailbox_address : (mail_username.presence || mailbox_address)

  # The new mailbox didn't take its login in time; its mail shows once it does
  def mailbox_waiting? = @mailbox_waiting == true

  def save
    @user = User.new(first_name:, last_name:, email_address: email_address.to_s.strip.downcase,
      admin:, welcome_pending: true, password: SecureRandom.base58(32))
    @skipped_tools = []
    @calendar_accounts = []

    @user.validate
    validate
    @user.errors.each { |error| errors.add(error.attribute, error.message) }
    return false if errors.any?

    if make_mailbox?
      new_mailbox
    elsif mail?
      return false unless mailbox_connects?
    end

    ActiveRecord::Base.transaction do
      @user.save!
      make_own_tools
      make_mail_tool if mail?
      join_shared_tools
      # Last, so that nothing is left on the mail server when something above went wrong
      MailServer.add_mailbox!(mailbox_address, @mail_account.password) if make_mailbox?
    end
    sync_accounts if @mail_account
    true
  rescue ActiveRecord::RecordInvalid => invalid
    invalid.record.errors.each { |error| errors.add(:base, error.full_message) unless error.attribute == :tool }
    start_again
  rescue MailServer::Error => error
    errors.add(:base, _("The mailbox couldn't be made: %{problem}", problem: error.message))
    start_again
  end

  private

  def template_exists
    errors.add(:user_template_id, _("isn't a template")) if user_template_id && !template
  end

  def mailbox_given
    errors.add(:mail_password, _("is needed to connect the mailbox")) if mail_password.blank?
  end

  def mailbox_can_be_made
    return if mail_address.blank? && email_address.blank? # The user's own error says so

    address = mailbox_address
    if !MailServer.configured?
      errors.add(:base, _("This installation has no mail server to make mailboxes on."))
    elsif !address.match?(URI::MailTo::EMAIL_REGEXP) || !MailServer.in_domain?(address)
      errors.add(:mail_address, _("must be an address at %{domain}", domain: MailServer.domain))
    elsif MailServer.mailbox?(address)
      errors.add(:mail_address, _("%{address} has a mailbox already", address: address))
    end
  end

  def new_mailbox
    @mail_account = Mails::Account.new(template.mail_server_settings.merge(
      email_address: mailbox_address, username: mailbox_login, password: SecureRandom.base58(24)))
  end

  # A mailbox made here, and the calendars on its login, are synced once the mail server
  # takes that login: a login refused before then would hold the sync back for an hour
  def sync_accounts
    @mailbox_waiting = make_mailbox? && !MailServer.ready?(@mail_account)
    later = @mailbox_waiting ? { wait: 5.minutes } : {}

    SyncEmailsJob.set(later).perform_later(@mail_account.id)
    @calendar_accounts.each { |account| SyncCalendarsJob.set(later).perform_later(account.id, discover: true) }
  end

  def start_again
    @user = User.new(@user.attributes.slice("first_name", "last_name", "email_address", "admin"))
    false
  end

  # Both servers are asked to take the login before anything is made, as when someone
  # connects a mailbox themselves (Tools::Mails::AccountsController)
  def mailbox_connects?
    @mail_account = Mails::Account.new(template.mail_server_settings.merge(
      email_address: mailbox_address, username: mailbox_login, password: mail_password))
    problem = Mails::ConnectionCheck.new(@mail_account).problem
    errors.add(:base, _("The mailbox couldn't be connected: %{problem}", problem: problem)) if problem
    problem.nil?
  end

  def make_own_tools
    template.own_tools.each do |tool|
      type = ToolType.enabled.find_by(slug: tool["type"]) or next
      made = @user.owned_tools.create!(tool_type: type, name: tool["name"].presence || type.human_name)
      connect_calendar(made) if type.slug == "calendar"
    end if template
  end

  # On the calendar server that takes the logins of the mailbox made here (Radicale
  # makes their calendar at the first login)
  def connect_calendar(tool)
    return unless make_mailbox? && MailServer.calendar?

    @calendar_accounts << tool.create_calendar_account!(provider: "custom", caldav_url: MailServer.caldav_url,
      username: mailbox_login, password: @mail_account.password)
  end

  def make_mail_tool
    type = ToolType.find_by!(slug: "mail")
    tool = @user.owned_tools.create!(tool_type: type, name: template.mail_tool_name.presence || type.human_name)
    @mail_account.tool = tool
    @mail_account.save!
  end

  # Only a tool the admin making the account owns: owners are the ones who say who is on a tool
  def join_shared_tools
    return unless template

    template.shared_tools.each do |tool|
      next @skipped_tools << tool unless made_by && tool.owned_by?(made_by)
      tool.collaborators.find_or_create_by!(user: @user) { |collaborator| collaborator.role = "collaborator" }
    end
  end
end
