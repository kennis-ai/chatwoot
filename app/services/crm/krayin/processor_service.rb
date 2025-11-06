# frozen_string_literal: true

class Crm::Krayin::ProcessorService
  attr_reader :inbox, :hook, :event_name, :event_data

  def initialize(inbox:, event_name:, event_data:)
    @inbox = inbox
    @hook = inbox.hooks.find_by(app_id: 'krayin')
    @event_name = event_name
    @event_data = event_data
  end

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

  def should_process?
    return false if @hook.blank?
    return false unless @hook.status == 'enabled'
    return false if @hook.settings.blank?

    true
  end

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

  def get_external_id(record, type)
    contact_inbox = record.contact_inboxes.find_by(inbox: @inbox)
    return nil if contact_inbox.blank?

    extract_external_id(contact_inbox.source_id, type)
  end

  def extract_external_id(source_id, type)
    return nil if source_id.blank?

    # Parse enhanced format: "krayin:person:123|krayin:lead:456|krayin:organization:789"
    ids = parse_external_ids(source_id)
    ids[type]
  end

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

  def sync_organizations?
    @hook.settings['sync_to_organization'] == true
  end

  def api_url
    @hook.settings['api_url']
  end

  def api_token
    @hook.settings['api_token']
  end
end
