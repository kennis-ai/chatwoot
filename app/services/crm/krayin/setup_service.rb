# frozen_string_literal: true

class Crm::Krayin::SetupService
  attr_reader :inbox, :api_url, :api_token

  def initialize(inbox:, api_url:, api_token:)
    @inbox = inbox
    @api_url = api_url
    @api_token = api_token
  end

  def perform
    # Validate API connection
    validate_api_connection

    # Fetch default configuration
    config = fetch_default_configuration

    # Store hook configuration
    store_hook_configuration(config)

    config
  end

  private

  def validate_api_connection
    # Test API connection by fetching pipelines
    lead_client = Crm::Krayin::Api::LeadClient.new(@api_url, @api_token)
    pipelines = lead_client.get_pipelines

    raise StandardError, 'Unable to connect to Krayin API' if pipelines.blank?

    Rails.logger.info "Krayin SetupService - Successfully connected to API at #{@api_url}"
    true
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin SetupService - API connection failed: #{e.message}"
    raise StandardError, "Failed to connect to Krayin API: #{e.message}"
  end

  def fetch_default_configuration
    lead_client = Crm::Krayin::Api::LeadClient.new(@api_url, @api_token)

    config = {
      'api_url' => @api_url,
      'api_token' => @api_token
    }

    # Fetch pipelines and get default pipeline
    pipelines = lead_client.get_pipelines
    if pipelines.present? && pipelines.any?
      default_pipeline = pipelines.first
      config['default_pipeline_id'] = default_pipeline['id']
      config['default_pipeline_name'] = default_pipeline['name']

      # Fetch stages for default pipeline
      stages = lead_client.get_stages(default_pipeline['id'])
      if stages.present? && stages.any?
        default_stage = stages.first
        config['default_stage_id'] = default_stage['id']
        config['default_stage_name'] = default_stage['name']
      end
    end

    # Fetch lead sources
    sources = lead_client.get_sources
    if sources.present? && sources.any?
      # Try to find a 'Website' or 'Web' source, otherwise use first
      default_source = sources.find { |s| s['name']&.match?(/web/i) } || sources.first
      config['default_source_id'] = default_source['id']
      config['default_source_name'] = default_source['name']
    end

    # Fetch lead types
    types = lead_client.get_types
    if types.present? && types.any?
      default_type = types.first
      config['default_lead_type_id'] = default_type['id']
      config['default_lead_type_name'] = default_type['name']
    end

    config
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin SetupService - Failed to fetch configuration: #{e.message}"
    raise StandardError, "Failed to fetch Krayin configuration: #{e.message}"
  end

  def store_hook_configuration(config)
    # Find or create the Krayin CRM hook
    hook = @inbox.hooks.find_or_initialize_by(app_id: 'krayin')

    hook.settings = config
    hook.status = 'enabled'
    hook.hook_type = 'inbox'
    hook.save!

    Rails.logger.info "Krayin SetupService - Configuration saved for inbox #{@inbox.id}"
    hook
  rescue StandardError => e
    Rails.logger.error "Krayin SetupService - Failed to store configuration: #{e.message}"
    raise e
  end
end
