# frozen_string_literal: true

# License License Stub
#
# This initializer stubs the ThirdParty licensing service to allow Kanban functionality
# to work without requiring a valid ThirdParty license token.
#
# The original implementation from licensedigital/kanban:v2.8.7 requires:
# - Valid LICENSE_TOKEN environment variable
# - PRO plan license verification via https://pulse.license.digital/api/cw/licenses/verify
# - Firebase service account for real-time features
#
# This stub bypasses all license checks and returns success for all license-related queries.
#
# To use the real ThirdParty licensing service instead:
# 1. Delete or rename this file
# 2. Copy license/licensing_service.rb from the Docker image
# 3. Set LICENSE_TOKEN environment variable
# 4. Ensure lib/chatwoot_app.rb includes the ThirdParty integration code

Rails.application.config.after_initialize do
  # Only stub if ThirdParty licensing service is not already loaded
  # This allows the real service to take precedence if configured
  unless defined?(::License::LicensingService)
    Rails.logger.info '[ThirdParty Stub] ThirdParty licensing service not found. Using stub implementation.'

    # Create a stub module structure matching the expected API
    module License
      module LicensingService
        class << self
          def get_license_info(force_refresh: false)
            {
              token_provided: true,
              plan: 'pro',
              features: {
                kanban_pro: true,
                license_modules: true,
                cloud_configs: true
              },
              message: 'Stubbed ThirdParty license - all features enabled',
              raw_response: { stubbed: true }
            }.with_indifferent_access
          end

          def feature_enabled?(feature_key)
            true # All features enabled in stub mode
          end

          def current_plan
            'pro'
          end

          def license_message
            'Stubbed ThirdParty license - all features enabled'
          end

          def token_configured_in_env?
            true
          end

          def token_valid?
            true
          end

          def pro_plan?
            true
          end

          def clear_cache!
            Rails.logger.info '[ThirdParty Stub] Cache clear requested (no-op in stub mode)'
          end
        end
      end
    end
  end

  # Stub the ChatwootApp.license integration
  # This provides the interface that Kanban controllers expect
  module ChatwootApp
    class LicenseLicenseAccessor
      def initialize(service_loaded = true)
        @service_loaded = service_loaded
      end

      def service_available?
        true
      end

      def kanban_pro_active?
        true
      end

      def feature_enabled?(feature_key)
        true # All features enabled
      end

      def plan
        'pro'
      end

      def message
        'Stubbed ThirdParty license - all features enabled'
      end

      def token_configured?
        true
      end

      def token_valid?
        true
      end

      def pro_plan?
        true
      end

      def all_features
        {
          kanban_pro: true,
          license_modules: true,
          cloud_configs: true
        }.with_indifferent_access
      end

      def clear_cache!
        Rails.logger.info '[ThirdParty Stub] Cache clear requested (no-op in stub mode)'
      end
    end

    class << self
      # Override the license method to return our stub accessor
      def license
        @license_accessor ||= LicenseLicenseAccessor.new(true)
      end

      # Override the license? check to always return true
      def license?
        true
      end
    end
  end

  Rails.logger.info '[ThirdParty Stub] Initialization complete. All Kanban features enabled without license validation.'
  Rails.logger.info '[ThirdParty Stub] To use real ThirdParty licensing, delete config/initializers/license_stub.rb and configure LICENSE_TOKEN'
end
