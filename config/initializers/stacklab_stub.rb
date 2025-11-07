# frozen_string_literal: true

# Stacklab License Stub
#
# This initializer stubs the StackLab licensing service to allow Kanban functionality
# to work without requiring a valid StackLab license token.
#
# The original implementation from stacklabdigital/kanban:v2.8.7 requires:
# - Valid STACKLAB_TOKEN environment variable
# - PRO plan license verification via https://pulse.stacklab.digital/api/cw/licenses/verify
# - Firebase service account for real-time features
#
# This stub bypasses all license checks and returns success for all license-related queries.
#
# To use the real StackLab licensing service instead:
# 1. Delete or rename this file
# 2. Copy stacklab/licensing_service.rb from the Docker image
# 3. Set STACKLAB_TOKEN environment variable
# 4. Ensure lib/chatwoot_app.rb includes the StackLab integration code

Rails.application.config.after_initialize do
  # Only stub if StackLab licensing service is not already loaded
  # This allows the real service to take precedence if configured
  unless defined?(::Stacklab::LicensingService)
    Rails.logger.info '[StackLab Stub] StackLab licensing service not found. Using stub implementation.'

    # Create a stub module structure matching the expected API
    module Stacklab
      module LicensingService
        class << self
          def get_license_info(force_refresh: false)
            {
              token_provided: true,
              plan: 'pro',
              features: {
                kanban_pro: true,
                stacklab_modules: true,
                cloud_configs: true
              },
              message: 'Stubbed StackLab license - all features enabled',
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
            'Stubbed StackLab license - all features enabled'
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
            Rails.logger.info '[StackLab Stub] Cache clear requested (no-op in stub mode)'
          end
        end
      end
    end
  end

  # Stub the ChatwootApp.stacklab integration
  # This provides the interface that Kanban controllers expect
  module ChatwootApp
    class StacklabLicenseAccessor
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
        'Stubbed StackLab license - all features enabled'
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
          stacklab_modules: true,
          cloud_configs: true
        }.with_indifferent_access
      end

      def clear_cache!
        Rails.logger.info '[StackLab Stub] Cache clear requested (no-op in stub mode)'
      end
    end

    class << self
      # Override the stacklab method to return our stub accessor
      def stacklab
        @stacklab_accessor ||= StacklabLicenseAccessor.new(true)
      end

      # Override the stacklab? check to always return true
      def stacklab?
        true
      end
    end
  end

  Rails.logger.info '[StackLab Stub] Initialization complete. All Kanban features enabled without license validation.'
  Rails.logger.info '[StackLab Stub] To use real StackLab licensing, delete config/initializers/stacklab_stub.rb and configure STACKLAB_TOKEN'
end
