# frozen_string_literal: true

module Crm
  module Glpi
    module Api
      # GLPI Contact API client
      #
      # Handles CRUD operations for GLPI Contact resources.
      # Contacts in GLPI represent external contacts (customers, suppliers, etc.)
      # without login access to the system.
      #
      # @example Creating a contact
      #   client = ContactClient.new(
      #     api_url: 'https://glpi.example.com/apirest.php',
      #     app_token: 'token',
      #     user_token: 'token'
      #   )
      #
      #   contact_data = {
      #     name: 'John Doe',
      #     firstname: 'John',
      #     email: 'john.doe@example.com',
      #     phone: '+1234567890'
      #   }
      #
      #   result = client.create_contact(contact_data)
      class ContactClient < BaseClient
        # Search for contacts by email address
        #
        # Uses GLPI's search API with criteria to find contacts by email.
        # Field 6 represents the contact email field in GLPI.
        #
        # @param email [String] The email address to search for
        # @return [Hash] Search results containing matching contacts
        # @raise [ApiError] If the search request fails
        #
        # @example
        #   results = client.search_contact(email: 'john@example.com')
        #   if results['data'].present?
        #     contact_id = results['data'].first['2'] # Field 2 is the ID
        #   end
        def search_contact(email:)
          with_session do
            query = {
              criteria: [
                { field: 6, searchtype: 'equals', value: email }
              ].to_json
            }
            get('/search/Contact', query)
          end
        end

        # Get a specific contact by ID
        #
        # @param contact_id [Integer] The GLPI contact ID
        # @return [Hash] Contact data
        # @raise [ApiError] If the contact is not found or request fails
        def get_contact(contact_id)
          with_session do
            get("/Contact/#{contact_id}")
          end
        end

        # Create a new contact in GLPI
        #
        # @param contact_data [Hash] Contact attributes
        # @option contact_data [String] :name Full name (required)
        # @option contact_data [String] :firstname First name
        # @option contact_data [String] :email Email address
        # @option contact_data [String] :phone Primary phone number
        # @option contact_data [String] :phone2 Secondary phone number
        # @option contact_data [Integer] :entities_id Entity ID
        #
        # @return [Hash] Created contact data with ID
        # @raise [ApiError] If contact creation fails
        #
        # @example
        #   contact_data = {
        #     name: 'John Doe',
        #     firstname: 'John',
        #     email: 'john@example.com',
        #     phone: '+1234567890',
        #     entities_id: 0
        #   }
        #   result = client.create_contact(contact_data)
        #   contact_id = result['id']
        def create_contact(contact_data)
          with_session do
            post('/Contact', { input: contact_data })
          end
        end

        # Update an existing contact in GLPI
        #
        # @param contact_id [Integer] The GLPI contact ID
        # @param contact_data [Hash] Contact attributes to update
        # @return [Hash] Update result
        # @raise [ApiError] If the contact is not found or update fails
        #
        # @example
        #   client.update_contact(123, { phone: '+1234567890' })
        def update_contact(contact_id, contact_data)
          with_session do
            put("/Contact/#{contact_id}", { input: contact_data })
          end
        end
      end
    end
  end
end
