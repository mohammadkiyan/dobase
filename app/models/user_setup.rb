# frozen_string_literal: true

# An account an admin makes for someone else: the person, the tools a template gives
# them, their mailbox, and the tools of the admin's they join. All of it is made, or
# none of it. The person chooses a password through the welcome link (User#welcome).
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

  attr_reader :user, :mail_account, :skipped_tools
  attr_accessor :made_by

  validate :template_exists
  validate :mailbox_given, if: :mail?

  def template
    @template ||= UserTemplate.find_by(id: user_template_id) if user_template_id
  end

  def mail?
    template&.mail?
  end

  # The mailbox's address is the person's own unless another is given, and its login
  # is that address unless another is given
  def mailbox_address = mail_address.presence || email_address.to_s.strip
  def mailbox_login = mail_username.presence || mailbox_address

  def save
    @user = User.new(first_name:, last_name:, email_address: email_address.to_s.strip.downcase,
      admin:, welcome_pending: true, password: SecureRandom.base58(32))
    @skipped_tools = []

    @user.validate
    validate
    @user.errors.each { |error| errors.add(error.attribute, error.message) }
    return false if errors.any?
    return false if mail? && !mailbox_connects?

    ActiveRecord::Base.transaction do
      @user.save!
      make_own_tools
      make_mail_tool if mail?
      join_shared_tools
    end
    SyncEmailsJob.perform_later(@mail_account.id) if @mail_account
    true
  rescue ActiveRecord::RecordInvalid => invalid
    invalid.record.errors.each { |error| errors.add(:base, error.full_message) unless error.attribute == :tool }
    @user = User.new(@user.attributes.slice("first_name", "last_name", "email_address", "admin"))
    false
  end

  private

  def template_exists
    errors.add(:user_template_id, _("isn't a template")) if user_template_id && !template
  end

  def mailbox_given
    errors.add(:mail_password, _("is needed to connect the mailbox")) if mail_password.blank?
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
      @user.owned_tools.create!(tool_type: type, name: tool["name"].presence || type.human_name)
    end if template
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
