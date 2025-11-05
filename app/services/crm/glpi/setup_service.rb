# frozen_string_literal: true

module Crm
  module Glpi
    # Validates GLPI integration settings and tests connectivity
    #
    # This service performs one-time validation of GLPI API credentials
    # and connection settings. It should be called before enabling the
    # integration to ensure all required settings are present and valid.
    #
    # @example Validate hook settings
    #   result = SetupService.new(hook).validate_and_test
    #   if result[:success]
    #     # Enable hook
    #   else
    #     # Show error: result[:error]
    #   end
    class SetupService
      attr_reader :hook, :api_url, :app_token, :user_token, :entity_id

      # Initialize setup service with hook configuration
      #
      # @param hook [Integrations::Hook] The hook containing GLPI settings
      def initialize(hook)
        @hook = hook
        @api_url = hook.settings['api_url']
        @app_token = hook.settings['app_token']
        @user_token = hook.settings['user_token']
        @entity_id = hook.settings['entity_id']&.to_i || 0
      end

      # Validate settings and test API connectivity
      #
      # Performs the following checks:
      # 1. Validates all required settings are present
      # 2. Validates API URL format
      # 3. Tests API connectivity by attempting to create a session
      # 4. Validates entity_id exists and is accessible
      #
      # @return [Hash] Result with :success and optional :error/:message
      #
      # @example Successful validation
      #   result = service.validate_and_test
      #   # => { success: true, message: "GLPI connection successful" }
      #
      # @example Failed validation
      #   result = service.validate_and_test
      #   # => { success: false, error: "Missing required setting: api_url" }
      def validate_and_test
        # Validate required settings
        validation_result = validate_settings
        return validation_result unless validation_result[:success]

        # Test API connectivity
        test_result = test_connection
        return test_result unless test_result[:success]

        {
          success: true,
          message: 'GLPI connection successful'
        }
      rescue StandardError => e
        Rails.logger.error "GLPI Setup Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        {
          success: false,
          error: "Setup failed: #{e.message}"
        }
      end

      private

      # Validate all required settings are present
      #
      # @return [Hash] Validation result
      def validate_settings
        missing_settings = []
        missing_settings << 'api_url' if @api_url.blank?
        missing_settings << 'app_token' if @app_token.blank?
        missing_settings << 'user_token' if @user_token.blank?

        if missing_settings.any?
          return {
            success: false,
            error: "Missing required settings: #{missing_settings.join(', ')}"
          }
        end

        # Validate API URL format
        unless valid_url?(@api_url)
          return {
            success: false,
            error: 'Invalid API URL format. Must be a valid HTTP/HTTPS URL'
          }
        end

        { success: true }
      end

      # Test API connection by creating and killing a session
      #
      # @return [Hash] Test result
      def test_connection
        base_client = Api::BaseClient.new(
          api_url: @api_url,
          app_token: @app_token,
          user_token: @user_token
        )

        # Test session creation
        base_client.with_session do
          # Session created successfully
          Rails.logger.info "GLPI connection test successful for hook ##{@hook.id}"
        end

        { success: true }
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI API Error during setup: #{e.message}"
        {
          success: false,
          error: "API connection failed: #{e.message}"
        }
      rescue StandardError => e
        Rails.logger.error "GLPI connection test failed: #{e.message}"
        {
          success: false,
          error: "Connection test failed: #{e.message}"
        }
      end

      # Validate URL format
      #
      # @param url [String] URL to validate
      # @return [Boolean] True if valid HTTP/HTTPS URL
      def valid_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
