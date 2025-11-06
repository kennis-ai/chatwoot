# OmniAuth configuration
# Sets the full host URL for callbacks and proper redirect handling
OmniAuth.config.full_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }

  # Keycloak OpenID Connect provider - Global (Environment Variable)
  if ENV['KEYCLOAK_ENABLED'] == 'true'
    provider :openid_connect, {
      name: :keycloak,
      scope: [:openid, :profile, :email],
      response_type: :code,
      issuer: ENV.fetch('KEYCLOAK_ISSUER', nil),
      discovery: true,
      client_auth_method: :basic,
      uid_field: ENV.fetch('KEYCLOAK_UID_FIELD', 'preferred_username'),
      client_options: {
        identifier: ENV.fetch('KEYCLOAK_CLIENT_ID', nil),
        secret: ENV.fetch('KEYCLOAK_CLIENT_SECRET', nil),
        redirect_uri: "#{ENV.fetch('FRONTEND_URL', nil)}/omniauth/keycloak/callback"
      }
    }
  end

  # Keycloak OpenID Connect provider - Per-Account (Database)
  # Load Keycloak providers from database for each enabled account
  if defined?(KeycloakSetting) && ActiveRecord::Base.connection.table_exists?('keycloak_settings')
    KeycloakSetting.where(enabled: true).find_each do |setting|
      provider :openid_connect, {
        name: setting.provider_name,
        scope: setting.scopes_array.map(&:to_sym),
        response_type: :code,
        issuer: setting.issuer,
        discovery: true,
        client_auth_method: :basic,
        uid_field: setting.uid_field,
        client_options: {
          identifier: setting.client_id,
          secret: setting.client_secret,
          redirect_uri: setting.redirect_uri
        }
      }
    end
  end
end
