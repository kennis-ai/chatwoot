# frozen_string_literal: true

class Crm::Krayin::PersonFinderService
  attr_reader :person_client, :contact

  def initialize(person_client:, contact:)
    @person_client = person_client
    @contact = contact
  end

  def perform
    # Try to find existing person
    person = find_existing_person

    # Return existing person if found
    return person if person.present?

    # Create new person if not found
    create_person
  end

  private

  def find_existing_person
    # Try to find by email first
    if @contact.email.present?
      persons = @person_client.search_person(email: @contact.email)
      return persons.first if persons.present? && persons.any?
    end

    # Try to find by phone if email search failed
    if @contact.phone_number.present?
      persons = @person_client.search_person(phone: @contact.phone_number)
      return persons.first if persons.present? && persons.any?
    end

    nil
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin PersonFinderService - Search error: #{e.message}"
    nil
  end

  def create_person
    person_data = Crm::Krayin::Mappers::ContactMapper.map_to_person(@contact)

    # Create person in Krayin
    person_id = @person_client.create_person(person_data)

    # Fetch and return the created person
    @person_client.get_person(person_id)
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    Rails.logger.error "Krayin PersonFinderService - Create error: #{e.message}"
    raise e
  end
end
