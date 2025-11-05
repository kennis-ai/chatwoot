# frozen_string_literal: true

module Crm
  module Glpi
    # Find or create GLPI Contacts from Chatwoot Contacts
    #
    # This service implements the find-or-create pattern for GLPI Contacts.
    # Contacts in GLPI are distinct from Users - they represent external
    # entities (customers, suppliers) while Users are internal. This service
    # is used when the integration is configured to sync to Contacts instead
    # of Users.
    #
    # @example Find or create contact
    #   finder = ContactFinderService.new(contact_client, entity_id)
    #   contact_id = finder.find_or_create(contact)
    class ContactFinderService
      attr_reader :contact_client, :entity_id

      # Initialize finder service
      #
      # @param contact_client [Api::ContactClient] GLPI Contact API client
      # @param entity_id [Integer] GLPI entity ID (default: 0)
      def initialize(contact_client, entity_id = 0)
        @contact_client = contact_client
        @entity_id = entity_id
      end

      # Find or create GLPI Contact from Chatwoot Contact
      #
      # Search order:
      # 1. Check if contact has stored GLPI contact_id
      # 2. Search by email
      # 3. Search by phone number
      # 4. Create new contact if not found
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI contact ID, or nil if failed
      #
      # @example
      #   contact_id = finder.find_or_create(contact)
      #   # => 456
      def find_or_create(contact)
        contact_id = get_stored_contact_id(contact)
        return contact_id if contact_id.present?

        contact_id = find_by_contact(contact)
        return contact_id if contact_id.present?

        create_contact(contact)
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI API error finding/creating contact: #{e.message}"
        nil
      rescue StandardError => e
        Rails.logger.error "Error finding/creating GLPI contact: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        nil
      end

      private

      # Find contact by contact attributes (email or phone)
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI contact ID if found
      def find_by_contact(contact)
        contact_id = find_by_email(contact)
        contact_id = find_by_phone(contact) if contact_id.blank?

        contact_id
      end

      # Find contact by email address
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI contact ID if found
      def find_by_email(contact)
        return nil if contact.email.blank?

        contacts = @contact_client.search_contact(email: contact.email)
        return nil unless contacts.is_a?(Array) && contacts.any?

        contacts.first['id']
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI search contact by email failed: #{e.message}"
        nil
      end

      # Find contact by phone number
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI contact ID if found
      def find_by_phone(contact)
        return nil if contact.phone_number.blank?

        # Format phone number for search
        formatted_phone = Mappers::ContactMapper.format_phone_number(contact.phone_number)
        return nil if formatted_phone.blank?

        # GLPI doesn't have phone search, so we can't find by phone
        # We'll need to create a new contact
        nil
      rescue StandardError => e
        Rails.logger.error "Error searching contact by phone: #{e.message}"
        nil
      end

      # Create new GLPI contact from contact
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI contact ID if created
      def create_contact(contact)
        contact_data = Mappers::ContactMapper.map_to_contact(contact, @entity_id)

        result = @contact_client.create_contact(contact_data)
        return nil unless result.is_a?(Hash)

        contact_id = result['id']
        raise StandardError, 'Failed to create contact - no ID returned' if contact_id.blank?

        Rails.logger.info "Created GLPI contact ##{contact_id} for contact ##{contact.id}"
        contact_id
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI API error creating contact: #{e.message}"
        nil
      rescue StandardError => e
        Rails.logger.error "Error creating GLPI contact: #{e.message}"
        nil
      end

      # Get stored GLPI contact ID from contact metadata
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] Stored GLPI contact ID
      def get_stored_contact_id(contact)
        return nil if contact.additional_attributes.blank?
        return nil if contact.additional_attributes['external'].blank?

        contact.additional_attributes.dig('external', 'glpi_contact_id')
      end
    end
  end
end
