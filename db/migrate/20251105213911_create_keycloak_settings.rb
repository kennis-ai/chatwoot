# frozen_string_literal: true

class CreateKeycloakSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :keycloak_settings do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, default: false, null: false
      t.string :issuer, null: false
      t.string :client_id, null: false
      t.string :client_secret, null: false
      t.string :uid_field, default: 'preferred_username'
      t.text :scopes, default: 'openid profile email'

      t.timestamps
    end

    add_index :keycloak_settings, :enabled
  end
end
