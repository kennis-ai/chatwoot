# frozen_string_literal: true

class Api::V1::Accounts::KeycloakSettingsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_keycloak_settings

  def show; end

  def create
    @keycloak_settings = Current.account.build_keycloak_setting(keycloak_settings_params)
    if @keycloak_settings.save
      render :show
    else
      render json: { errors: @keycloak_settings.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @keycloak_settings.update(keycloak_settings_params)
      # Reload OmniAuth middleware to apply new settings
      reload_omniauth_middleware
      render :show
    else
      render json: { errors: @keycloak_settings.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @keycloak_settings.destroy!
    # Reload OmniAuth middleware to remove provider
    reload_omniauth_middleware
    head :no_content
  end

  # Test Keycloak connection
  def test
    result = @keycloak_settings.test_connection
    if result[:success]
      render json: result, status: :ok
    else
      render json: result, status: :unprocessable_entity
    end
  end

  private

  def set_keycloak_settings
    @keycloak_settings = Current.account.keycloak_setting ||
                         Current.account.build_keycloak_setting
  end

  def keycloak_settings_params
    params.require(:keycloak_settings).permit(
      :enabled,
      :issuer,
      :client_id,
      :client_secret,
      :uid_field,
      :scopes
    )
  end

  def check_authorization
    authorize(KeycloakSetting)
  end

  def reload_omniauth_middleware
    # This will be picked up on next authentication attempt
    # Full reload happens on app restart
    Rails.cache.delete('omniauth_keycloak_providers')
  end
end
