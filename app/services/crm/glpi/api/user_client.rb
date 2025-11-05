# frozen_string_literal: true

module Crm
  module Glpi
    module Api
      # GLPI User API client
      #
      # Handles CRUD operations for GLPI User resources.
      # Users in GLPI represent internal users or external users with login access.
      #
      # @example Creating a user
      #   client = UserClient.new(
      #     api_url: 'https://glpi.example.com/apirest.php',
      #     app_token: 'token',
      #     user_token: 'token'
      #   )
      #
      #   user_data = {
      #     name: 'john.doe@example.com',
      #     firstname: 'John',
      #     realname: 'Doe',
      #     _useremails: ['john.doe@example.com']
      #   }
      #
      #   result = client.create_user(user_data)
      class UserClient < BaseClient
        # Search for users by email address
        #
        # Uses GLPI's search API with criteria to find users by email.
        # Field 5 represents the user email field in GLPI.
        #
        # @param email [String] The email address to search for
        # @return [Hash] Search results containing matching users
        # @raise [ApiError] If the search request fails
        #
        # @example
        #   results = client.search_user(email: 'john@example.com')
        #   if results['data'].present?
        #     user_id = results['data'].first['2'] # Field 2 is the ID
        #   end
        def search_user(email:)
          with_session do
            query = {
              criteria: [
                { field: 5, searchtype: 'equals', value: email }
              ].to_json
            }
            get('/search/User', query)
          end
        end

        # Get a specific user by ID
        #
        # @param user_id [Integer] The GLPI user ID
        # @return [Hash] User data
        # @raise [ApiError] If the user is not found or request fails
        def get_user(user_id)
          with_session do
            get("/User/#{user_id}")
          end
        end

        # Create a new user in GLPI
        #
        # @param user_data [Hash] User attributes
        # @option user_data [String] :name User login name (required)
        # @option user_data [String] :firstname First name
        # @option user_data [String] :realname Last name
        # @option user_data [String] :phone Phone number
        # @option user_data [String] :mobile Mobile number
        # @option user_data [Array<String>] :_useremails Email addresses
        # @option user_data [Integer] :entities_id Entity ID
        #
        # @return [Hash] Created user data with ID
        # @raise [ApiError] If user creation fails
        #
        # @example
        #   user_data = {
        #     name: 'john.doe',
        #     firstname: 'John',
        #     realname: 'Doe',
        #     _useremails: ['john@example.com'],
        #     entities_id: 0
        #   }
        #   result = client.create_user(user_data)
        #   user_id = result['id']
        def create_user(user_data)
          with_session do
            post('/User', { input: user_data })
          end
        end

        # Update an existing user in GLPI
        #
        # @param user_id [Integer] The GLPI user ID
        # @param user_data [Hash] User attributes to update
        # @return [Hash] Update result
        # @raise [ApiError] If the user is not found or update fails
        #
        # @example
        #   client.update_user(123, { phone: '+1234567890' })
        def update_user(user_id, user_data)
          with_session do
            put("/User/#{user_id}", { input: user_data })
          end
        end
      end
    end
  end
end
