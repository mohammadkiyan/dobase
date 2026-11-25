# frozen_string_literal: true

# A template can make each new account a mailbox of its own on this installation's
# mail server (MailServer), instead of connecting one that exists
class AddMakeMailboxToUserTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :user_templates, :make_mailbox, :boolean, default: false, null: false
  end
end
