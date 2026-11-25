# frozen_string_literal: true

# An admin makes accounts for others, from a template of the tools each one starts
# with, and hands them a link to choose their password.
class AddAdminConsole < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
    # Made by an admin, and the password not yet chosen through the welcome link
    add_column :users, :welcome_pending, :boolean, default: false, null: false

    create_table :user_templates do |t|
      t.string :name, null: false
      # The tools each new account gets of its own: [{ "type" => "boards", "name" => "Tasks" }]
      t.json :tools, default: [], null: false
      # Tools of the admin's that each new account joins as a collaborator
      t.json :shared_tool_ids, default: [], null: false

      # A Mail tool on the account's own mailbox, on these servers
      t.boolean :mail, default: false, null: false
      t.string :mail_tool_name
      t.string :mail_imap_host
      t.integer :mail_imap_port, default: 993
      t.boolean :mail_imap_ssl, default: true, null: false
      t.string :mail_smtp_host
      t.integer :mail_smtp_port, default: 587
      t.string :mail_smtp_auth, default: "plain", null: false
      t.boolean :mail_smtp_tls, default: true, null: false

      t.timestamps
    end

    # Whoever set up this installation is its admin
    reversible do |direction|
      direction.up { execute "UPDATE users SET admin = 1 WHERE id = (SELECT MIN(id) FROM users)" }
    end
  end
end
