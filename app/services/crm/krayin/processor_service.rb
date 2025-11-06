# frozen_string_literal: true

# Krayin CRM Integration - Main Processor Service
#
# This service orchestrates the synchronization of Chatwoot data to Krayin CRM.
# It handles contacts, conversations, and messages, mapping them to Krayin entities
# (Person, Lead, Organization, Activity) and managing external ID tracking.
#
# @example Process a contact creation event
#   processor = Crm::Krayin::ProcessorService.new(
#     inbox: inbox,
#     event_name: 'contact.created',
#     event_data: { contact: contact }
#   )
#   processor.perform
#
# @example Process a conversation update event
#   processor = Crm::Krayin::ProcessorService.new(
#     inbox: inbox,
#     event_name: 'conversation.updated',
#     event_data: { conversation: conversation }
#   )
#   processor.perform
#
# @see Crm::Krayin::Mappers::ContactMapper
# @see Crm::Krayin::Mappers::ConversationMapper
# @see Crm::Krayin::Mappers::MessageMapper
# @see Crm::Krayin::Api::PersonClient
# @see Crm::Krayin::Api::LeadClient
class Crm::Krayin::ProcessorService
  attr_reader :inbox, :hook, :event_name, :event_data

  # Initialize the processor with event data
  #
  # @param inbox [Inbox] The Chatwoot inbox this event belongs to
  # @param event_name [String] The name of the event (e.g., 'contact.created')
  # @param event_data [Hash] Event-specific data containing the relevant record
  # @option event_data [Contact] :contact The contact record for contact events
  # @option event_data [Conversation] :conversation The conversation record for conversation events
  # @option event_data [Message] :message The message record for message events
  def initialize(inbox:, event_name:, event_data:)
    @inbox = inbox
    @hook = inbox.hooks.find_by(app_id: 'krayin')
    @event_name = event_name
    @event_data = event_data
  end

  # Process the event and sync data to Krayin CRM
  #
  # This is the main entry point that routes events to appropriate handlers.
  # Events are processed only if the hook is enabled and properly configured.
  #
  # Supported events:
  # - contact.created, contact.updated → Creates/updates Person and Lead
  # - conversation.created, conversation.updated → Creates/updates Activity
  # - message.created → Creates Activity for individual message
  #
  # @return [void]
  # @raise [Crm::Krayin::Api::BaseClient::ApiError] If API request fails after retries
  def perform
    return unless should_process?

    case @event_name
    when 'contact_created', 'contact_updated'
      process_contact
    when 'conversation_created', 'conversation_updated'
      process_conversation
    when 'message_created'
      process_message
    else
      Rails.logger.warn "Krayin ProcessorService - Unknown event: #{@event_name}"
    end
  end

  private

  # Check if event should be processed
  #
  # Events are only processed when:
  # - Hook exists for this inbox
  # - Hook status is 'enabled'
  # - Hook has valid settings (API URL, token, etc.)
  #
  # @return [Boolean] true if event should be processed
  def should_process?
    return false if @hook.blank?
    return false unless @hook.status == 'enabled'
    return false if @hook.settings.blank?

    true
  end

  # Process contact creation or update event
  #
  # This method:
  # 1. Creates/updates Organization (if enabled and contact has company data)
  # 2. Creates/updates Person in Krayin
  # 3. Links Person to Organization (if both exist)
  # 4. Creates/updates Lead for the Person
  # 5. Updates lead stage (if stage progression enabled)
  # 6. Stores all external IDs for future reference
  #
  # External IDs are stored in format: "krayin:person:123|krayin:lead:456|krayin:organization:789"
  #
  # @return [void]
  # @raise [Crm::Krayin::Api::BaseClient::ApiError] If any API request fails
  def process_contact
    contact = @event_data[:contact]
    return if contact.blank?

    Rails.logger.info "Krayin ProcessorService - Processing contact #{contact.id}"

    # Initialize API clients
    person_client = Crm::Krayin::Api::PersonClient.new(api_url, api_token)
    lead_client = Crm::Krayin::Api::LeadClient.new(api_url, api_token)
    
    # Sync organization if enabled and contact has company
    organization_id = nil
    if sync_organizations? && Crm::Krayin::Mappers::ContactMapper.new(contact).has_organization?
      organization_id = create_or_update_organization(contact)
    end

    # Find or create person
    person = Crm::Krayin::PersonFinderService.new(
      person_client: person_client,
      contact: contact
    ).perform

    return if person.blank?

    # Store person external ID
    store_external_id(contact, 'person', person['id'])
    
    # Link person to organization if both exist
    if organization_id.present? && person['id'].present?
      link_person_to_organization(person['id'], organization_id, person_client)
    end

    # Find or create lead
    lead = Crm::Krayin::LeadFinderService.new(
      lead_client: lead_client,
      contact: contact,
      person_id: person['id'],
      settings: @hook.settings
    ).perform

    return if lead.blank?

    # Store lead external ID
    store_external_id(contact, 'lead', lead['id'])

    # Update lead stage based on initial contact creation if enabled
    if stage_progression_enabled? && @event_name == 'contact_created'
      update_lead_stage_on_creation(lead_client, lead['id'])
    end

    Rails.logger.info "Krayin ProcessorService - Contact #{contact.id} synced. Person: #{person['id']}, Lead: #{lead['id']}"
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin ProcessorService - Failed to process contact #{contact&.id}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Krayin ProcessorService - Unexpected error processing contact #{contact&.id}: #{e.message}"
  end

  def process_conversation
    conversation = @event_data[:conversation]
    return if conversation.blank?

    contact = conversation.contact
    return if contact.blank?

    Rails.logger.info "Krayin ProcessorService - Processing conversation #{conversation.display_id}"

    # Get person ID from contact
    person_external_id = contact.contact_inboxes.find_by(inbox: @inbox)&.source_id
    return if person_external_id.blank?

    # Parse person ID (format: "krayin:person:123")
    person_id = extract_external_id(person_external_id, 'person')
    return if person_id.blank?

    # Initialize API client
    activity_client = Crm::Krayin::Api::ActivityClient.new(api_url, api_token)

    # Map conversation to activity
    activity_data = Crm::Krayin::Mappers::ConversationMapper.map_to_activity(
      conversation,
      person_id,
      @hook.settings
    )

    # Check if activity already exists
    existing_activity_id = get_external_id(conversation, 'activity')

    if existing_activity_id.present?
      # Update existing activity
      activity_client.update_activity(activity_data, existing_activity_id)
      Rails.logger.info "Krayin ProcessorService - Updated activity #{existing_activity_id} for conversation #{conversation.display_id}"
    else
      # Create new activity
      activity_id = activity_client.create_activity(activity_data)
      store_external_id(conversation, 'activity', activity_id)
      Rails.logger.info "Krayin ProcessorService - Created activity #{activity_id} for conversation #{conversation.display_id}"
    end

    # Update lead stage based on conversation status if enabled
    if stage_progression_enabled?
      lead_id = extract_external_id(person_external_id, 'lead')
      if lead_id.present?
        update_lead_stage_on_conversation(conversation, lead_id)
      end
    end
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin ProcessorService - Failed to process conversation #{conversation&.display_id}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Krayin ProcessorService - Unexpected error processing conversation #{conversation&.display_id}: #{e.message}"
  end

  def process_message
    message = @event_data[:message]
    return if message.blank?
    return if message.private? # Don't sync private notes

    conversation = message.conversation
    contact = conversation&.contact
    return if contact.blank?

    Rails.logger.info "Krayin ProcessorService - Processing message #{message.id}"

    # Get person ID from contact
    person_external_id = contact.contact_inboxes.find_by(inbox: @inbox)&.source_id
    return if person_external_id.blank?

    # Parse person ID
    person_id = extract_external_id(person_external_id, 'person')
    return if person_id.blank?

    # Initialize API client
    activity_client = Crm::Krayin::Api::ActivityClient.new(api_url, api_token)

    # Map message to activity
    activity_data = Crm::Krayin::Mappers::MessageMapper.map_to_activity(
      message,
      person_id,
      @hook.settings
    )

    # Create activity for message
    activity_id = activity_client.create_activity(activity_data)
    Rails.logger.info "Krayin ProcessorService - Created activity #{activity_id} for message #{message.id}"
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin ProcessorService - Failed to process message #{message&.id}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Krayin ProcessorService - Unexpected error processing message #{message&.id}: #{e.message}"
  end

  # Store external ID for a Krayin entity
  #
  # External IDs are stored in the contact_inboxes.source_id field using a multi-ID format:
  # "krayin:person:123|krayin:lead:456|krayin:organization:789|krayin:activity:101"
  #
  # This allows tracking multiple related Krayin entities for a single Chatwoot contact.
  #
  # @param record [Contact, Conversation] The Chatwoot record to store the ID for
  # @param type [String] The entity type ('person', 'lead', 'organization', 'activity')
  # @param external_id [String, Integer] The Krayin entity ID
  # @return [void]
  #
  # @example Store a person ID
  #   store_external_id(contact, 'person', 123)
  #   # Results in: "krayin:person:123"
  #
  # @example Store multiple IDs
  #   store_external_id(contact, 'person', 123)
  #   store_external_id(contact, 'lead', 456)
  #   # Results in: "krayin:person:123|krayin:lead:456"
  def store_external_id(record, type, external_id)
    # Store external ID in contact_inboxes source_id field
    # Enhanced format supports multiple IDs: "krayin:person:123|krayin:lead:456|krayin:organization:789"
    contact_inbox = record.contact_inboxes.find_or_initialize_by(inbox: @inbox)

    # Parse existing IDs
    existing_ids = parse_external_ids(contact_inbox.source_id)

    # Update or add the new ID
    existing_ids[type] = external_id

    # Rebuild source_id string
    contact_inbox.source_id = build_source_id_string(existing_ids)
    contact_inbox.save!
  end

  # Retrieve external ID for a specific entity type
  #
  # @param record [Contact, Conversation] The Chatwoot record
  # @param type [String] The entity type to retrieve ('person', 'lead', etc.)
  # @return [String, nil] The external ID or nil if not found
  #
  # @example Get person ID
  #   get_external_id(contact, 'person')
  #   # => "123"
  def get_external_id(record, type)
    contact_inbox = record.contact_inboxes.find_by(inbox: @inbox)
    return nil if contact_inbox.blank?

    extract_external_id(contact_inbox.source_id, type)
  end

  # Extract a specific entity ID from source_id string
  #
  # @param source_id [String] The full source_id string
  # @param type [String] The entity type to extract
  # @return [String, nil] The extracted ID or nil if not found
  #
  # @example Extract person ID
  #   extract_external_id("krayin:person:123|krayin:lead:456", "person")
  #   # => "123"
  def extract_external_id(source_id, type)
    return nil if source_id.blank?

    # Parse enhanced format: "krayin:person:123|krayin:lead:456|krayin:organization:789"
    ids = parse_external_ids(source_id)
    ids[type]
  end

  # Parse source_id string into a hash of entity types and IDs
  #
  # @param source_id [String] The source_id string to parse
  # @return [Hash] Hash mapping entity type to ID (e.g., {"person" => "123", "lead" => "456"})
  #
  # @example Parse multiple IDs
  #   parse_external_ids("krayin:person:123|krayin:lead:456")
  #   # => {"person" => "123", "lead" => "456"}
  def parse_external_ids(source_id)
    return {} if source_id.blank?

    ids = {}
    # Split by pipe to get individual ID entries
    source_id.split('|').each do |entry|
      parts = entry.split(':')
      next unless parts.length == 3 && parts[0] == 'krayin'

      ids[parts[1]] = parts[2]
    end
    ids
  end

  # Build source_id string from hash of entity types and IDs
  #
  # @param ids_hash [Hash] Hash mapping entity type to ID
  # @return [String] Formatted source_id string
  #
  # @example Build source_id from hash
  #   build_source_id_string({"person" => "123", "lead" => "456"})
  #   # => "krayin:person:123|krayin:lead:456"
  def build_source_id_string(ids_hash)
    # Build format: "krayin:person:123|krayin:lead:456|krayin:organization:789"
    ids_hash.map { |type, id| "krayin:#{type}:#{id}" }.join('|')
  end

  def create_or_update_organization(contact)
    org_client = Crm::Krayin::Api::OrganizationClient.new(api_url, api_token)
    mapper = Crm::Krayin::Mappers::ContactMapper.new(contact)
    
    org_data = mapper.map_to_organization
    return nil if org_data.blank?

    # Check if organization already exists
    existing_org_id = get_external_id(contact, 'organization')
    
    if existing_org_id.present?
      # Update existing organization
      org_client.update_organization(org_data, existing_org_id)
      Rails.logger.info "Krayin ProcessorService - Updated organization #{existing_org_id}"
      existing_org_id
    else
      # Search for existing organization by name
      existing_orgs = org_client.search_organization(org_data[:name])
      
      if existing_orgs.present? && existing_orgs.any?
        org_id = existing_orgs.first['id']
        store_external_id(contact, 'organization', org_id)
        Rails.logger.info "Krayin ProcessorService - Found existing organization #{org_id}"
        org_id
      else
        # Create new organization
        org_id = org_client.create_organization(org_data)
        store_external_id(contact, 'organization', org_id)
        Rails.logger.info "Krayin ProcessorService - Created organization #{org_id}"
        org_id
      end
    end
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin ProcessorService - Failed to sync organization: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "Krayin ProcessorService - Unexpected error syncing organization: #{e.message}"
    nil
  end

  def link_person_to_organization(person_id, organization_id, person_client)
    # Update person with organization_id
    person_client.update_person({ organization_id: organization_id }, person_id)
    Rails.logger.info "Krayin ProcessorService - Linked person #{person_id} to organization #{organization_id}"
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin ProcessorService - Failed to link person to organization: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Krayin ProcessorService - Unexpected error linking person to organization: #{e.message}"
  end

  # Check if organization sync is enabled
  #
  # @return [Boolean] true if organizations should be synced
  def sync_organizations?
    @hook.settings['sync_to_organization'] == true
  end

  # Check if lead stage progression is enabled
  #
  # When enabled, lead stages are automatically updated based on conversation lifecycle.
  #
  # @return [Boolean] true if stage progression is enabled
  # @see #determine_stage_from_conversation
  def stage_progression_enabled?
    @hook.settings['stage_progression_enabled'] == true
  end

  # Update lead stage when contact is first created
  #
  # Uses the 'stage_on_conversation_created' setting to determine target stage.
  #
  # @param lead_client [Crm::Krayin::Api::LeadClient] The lead API client
  # @param lead_id [String, Integer] The Krayin lead ID to update
  # @return [void]
  def update_lead_stage_on_creation(lead_client, lead_id)
    stage_id = @hook.settings['stage_on_conversation_created']
    return if stage_id.blank?

    lead_data = { lead_pipeline_stage_id: stage_id }
    lead_client.update_lead(lead_data, lead_id)
    Rails.logger.info "Krayin ProcessorService - Updated lead #{lead_id} stage to #{stage_id} on creation"
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin ProcessorService - Failed to update lead stage: #{e.message}"
  end

  # Update lead stage based on conversation status
  #
  # Automatically updates lead stage when conversation status changes.
  #
  # @param conversation [Conversation] The conversation to check
  # @param lead_id [String, Integer] The Krayin lead ID to update
  # @return [void]
  # @see #determine_stage_from_conversation
  def update_lead_stage_on_conversation(conversation, lead_id)
    stage_id = determine_stage_from_conversation(conversation)
    return if stage_id.blank?

    lead_client = Crm::Krayin::Api::LeadClient.new(api_url, api_token)
    lead_data = { lead_pipeline_stage_id: stage_id }
    lead_client.update_lead(lead_data, lead_id)
    Rails.logger.info "Krayin ProcessorService - Updated lead #{lead_id} stage to #{stage_id} based on conversation #{conversation.display_id}"
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin ProcessorService - Failed to update lead stage: #{e.message}"
  end

  # Determine appropriate lead stage based on conversation status
  #
  # Stage progression logic:
  # - Open conversation (no agent response) → stage_on_conversation_created
  # - Open conversation (has agent response) → stage_on_first_response
  # - Resolved conversation → stage_on_conversation_resolved
  #
  # @param conversation [Conversation] The conversation to check
  # @return [Integer, nil] The stage ID to set, or nil if no stage should be set
  #
  # @example Determine stage for new conversation
  #   determine_stage_from_conversation(conversation)
  #   # => 2 (stage_on_conversation_created)
  #
  # @example Determine stage for conversation with agent response
  #   conversation.messages.outgoing.create!(...)
  #   determine_stage_from_conversation(conversation)
  #   # => 3 (stage_on_first_response)
  def determine_stage_from_conversation(conversation)
    case conversation.status
    when 'open'
      # Check if this is first agent response
      if conversation.messages.outgoing.any?
        @hook.settings['stage_on_first_response']
      else
        @hook.settings['stage_on_conversation_created']
      end
    when 'resolved'
      @hook.settings['stage_on_conversation_resolved']
    else
      nil
    end
  end

  # Get Krayin API URL from hook settings
  #
  # @return [String] The API URL (e.g., "https://crm.example.com/api/admin")
  def api_url
    @hook.settings['api_url']
  end

  # Get Krayin API token from hook settings
  #
  # @return [String] The API Bearer token
  def api_token
    @hook.settings['api_token']
  end
end
