# frozen_string_literal: true

class Crm::Krayin::LeadFinderService
  attr_reader :lead_client, :contact, :person_id, :settings

  def initialize(lead_client:, contact:, person_id:, settings:)
    @lead_client = lead_client
    @contact = contact
    @person_id = person_id
    @settings = settings
  end

  def perform
    # Try to find existing lead
    lead = find_existing_lead

    # Return existing lead if found
    return lead if lead.present?

    # Create new lead if not found
    create_lead
  end

  private

  def find_existing_lead
    # Try to find by email first
    if @contact.email.present?
      leads = @lead_client.search_lead(email: @contact.email)
      return leads.first if leads.present? && leads.any?
    end

    # Try to find by phone if email search failed
    if @contact.phone_number.present?
      leads = @lead_client.search_lead(phone: @contact.phone_number)
      return leads.first if leads.present? && leads.any?
    end

    nil
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin LeadFinderService - Search error: #{e.message}"
    nil
  end

  def create_lead
    lead_data = Crm::Krayin::Mappers::ContactMapper.map_to_lead(@contact, @person_id, @settings)

    # Create lead in Krayin
    lead_id = @lead_client.create_lead(lead_data)

    # Fetch and return the created lead
    @lead_client.get_lead(lead_id)
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin LeadFinderService - Create error: #{e.message}"
    raise e
  end
end
