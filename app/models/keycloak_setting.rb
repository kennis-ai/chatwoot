# frozen_string_literal: true

# == Schema Information
#
# Table name: keycloak_settings
#
#  id            :bigint           not null, primary key
#  account_id    :bigint           not null
#  enabled       :boolean          default(FALSE), not null
#  issuer        :string           not null
#  client_id     :string           not null
#  client_secret :string           not null
#  uid_field     :string           default("preferred_username")
#  scopes        :text             default("openid profile email")
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

class KeycloakSetting < ApplicationRecord
  belongs_to :account

  validates :issuer, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :client_id, presence: true
  validates :client_secret, presence: true
  validates :uid_field, presence: true
  validates :scopes, presence: true

  # Encrypt sensitive data
  encrypts :client_secret

  # Validate issuer URL format
  validate :validate_issuer_url

  # Return discovery URL for OIDC configuration
  def discovery_url
    "#{issuer}/.well-known/openid-configuration"
  end

  # Return redirect URI for this account
  def redirect_uri
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{frontend_url}/omniauth/keycloak_#{account_id}/callback"
  end

  # Return provider name for OmniAuth (unique per account)
  def provider_name
    "keycloak_#{account_id}".to_sym
  end

  # Return scopes as array
  def scopes_array
    scopes.split
  end

  # Test connection to Keycloak
  def test_connection
    require 'net/http'
    require 'json'

    uri = URI(discovery_url)
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      config = JSON.parse(response.body)
      {
        success: true,
        message: 'Keycloak connection successful',
        issuer: config['issuer'],
        endpoints: {
          authorization: config['authorization_endpoint'],
          token: config['token_endpoint'],
          userinfo: config['userinfo_endpoint']
        }
      }
    else
      {
        success: false,
        error: "Failed to connect to Keycloak: #{response.code} #{response.message}"
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: "Connection error: #{e.message}"
    }
  end

  private

  def validate_issuer_url
    return if issuer.blank?

    uri = URI.parse(issuer)
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      errors.add(:issuer, 'must be a valid HTTP or HTTPS URL')
    end
  rescue URI::InvalidURIError
    errors.add(:issuer, 'is not a valid URL')
  end
end
