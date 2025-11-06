# frozen_string_literal: true

module Crm
  module Glpi
    # Find or create GLPI Users from Chatwoot Contacts
    #
    # This service implements the find-or-create pattern for GLPI Users.
    # It searches for existing users by email or phone, and creates new
    # users if not found. Users are the primary entity in GLPI for
    # authentication and ticket requesters.
    #
    # @example Find or create user
    #   finder = UserFinderService.new(user_client, entity_id)
    #   user_id = finder.find_or_create(contact)
    class UserFinderService
      attr_reader :user_client, :entity_id

      # Initialize finder service
      #
      # @param user_client [Api::UserClient] GLPI User API client
      # @param entity_id [Integer] GLPI entity ID (default: 0)
      def initialize(user_client, entity_id = 0)
        @user_client = user_client
        @entity_id = entity_id
      end

      # Find or create GLPI User from Chatwoot Contact
      #
      # Search order:
      # 1. Check if contact has stored GLPI user_id
      # 2. Search by email
      # 3. Search by phone number
      # 4. Create new user if not found
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI user ID, or nil if failed
      #
      # @example
      #   user_id = finder.find_or_create(contact)
      #   # => 123
      def find_or_create(contact)
        user_id = get_stored_user_id(contact)
        return user_id if user_id.present?

        user_id = find_by_contact(contact)
        return user_id if user_id.present?

        create_user(contact)
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI API error finding/creating user: #{e.message}"
        nil
      rescue StandardError => e
        Rails.logger.error "Error finding/creating GLPI user: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        nil
      end

      private

      # Find user by contact attributes (email or phone)
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI user ID if found
      def find_by_contact(contact)
        user_id = find_by_email(contact)
        user_id = find_by_phone(contact) if user_id.blank?

        user_id
      end

      # Find user by email address
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI user ID if found
      def find_by_email(contact)
        return nil if contact.email.blank?

        users = @user_client.search_user(email: contact.email)
        return nil unless users.is_a?(Array) && users.any?

        users.first['id']
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI search user by email failed: #{e.message}"
        nil
      end

      # Find user by phone number
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI user ID if found
      def find_by_phone(contact)
        return nil if contact.phone_number.blank?

        # Format phone number for search
        formatted_phone = Mappers::ContactMapper.format_phone_number(contact.phone_number)
        return nil if formatted_phone.blank?

        # GLPI doesn't have phone search, so we can't find by phone
        # We'll need to create a new user
        nil
      rescue StandardError => e
        Rails.logger.error "Error searching user by phone: #{e.message}"
        nil
      end

      # Create new GLPI user from contact
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI user ID if created
      def create_user(contact)
        user_data = Mappers::ContactMapper.map_to_user(contact, @entity_id)

        result = @user_client.create_user(user_data)
        return nil unless result.is_a?(Hash)

        user_id = result['id']
        raise StandardError, 'Failed to create user - no ID returned' if user_id.blank?

        Rails.logger.info "Created GLPI user ##{user_id} for contact ##{contact.id}"
        user_id
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI API error creating user: #{e.message}"
        nil
      rescue StandardError => e
        Rails.logger.error "Error creating GLPI user: #{e.message}"
        nil
      end

      # Get stored GLPI user ID from contact metadata
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] Stored GLPI user ID
      def get_stored_user_id(contact)
        return nil if contact.additional_attributes.blank?
        return nil if contact.additional_attributes['external'].blank?

        contact.additional_attributes.dig('external', 'glpi_user_id')
      end
    end
  end
end
