# frozen_string_literal: true

module Crm
  module Glpi
    module Api
      # GLPI ITILFollowup API client
      #
      # Handles CRUD operations for GLPI ITILFollowup resources.
      # Followups are comments/updates added to tickets, problems, or changes.
      #
      # @example Creating a followup
      #   client = FollowupClient.new(
      #     api_url: 'https://glpi.example.com/apirest.php',
      #     app_token: 'token',
      #     user_token: 'token'
      #   )
      #
      #   followup_data = {
      #     itemtype: 'Ticket',
      #     items_id: 123,
      #     content: 'Customer replied with additional information',
      #     is_private: 0
      #   }
      #
      #   result = client.create_followup(followup_data)
      class FollowupClient < BaseClient
        # Create a new followup on a ticket
        #
        # Followups are used to add comments, updates, or notes to tickets.
        # They can be marked as private (visible only to technicians) or public.
        #
        # @param followup_data [Hash] Followup attributes
        # @option followup_data [String] :itemtype The parent item type (usually 'Ticket')
        # @option followup_data [Integer] :items_id The parent item ID (ticket ID)
        # @option followup_data [String] :content Followup text content (required)
        # @option followup_data [Integer] :is_private 1 for private, 0 for public (default: 0)
        # @option followup_data [String] :date Followup date in ISO8601 format
        # @option followup_data [Integer] :users_id User ID who created the followup
        #
        # @return [Hash] Created followup data with ID
        # @raise [ApiError] If followup creation fails
        #
        # @example Create a public followup
        #   followup_data = {
        #     itemtype: 'Ticket',
        #     items_id: 123,
        #     content: '[2025-01-05 10:30] Agent: Customer issue resolved',
        #     is_private: 0
        #   }
        #   result = client.create_followup(followup_data)
        #   followup_id = result['id']
        #
        # @example Create a private followup (internal note)
        #   followup_data = {
        #     itemtype: 'Ticket',
        #     items_id: 123,
        #     content: 'Internal note: Need to follow up with billing dept',
        #     is_private: 1
        #   }
        #   result = client.create_followup(followup_data)
        def create_followup(followup_data)
          with_session do
            post('/ITILFollowup', { input: followup_data })
          end
        end

        # Update an existing followup
        #
        # @param followup_id [Integer] The GLPI followup ID
        # @param followup_data [Hash] Followup attributes to update
        # @return [Hash] Update result
        # @raise [ApiError] If the followup is not found or update fails
        #
        # @example
        #   client.update_followup(456, { content: 'Updated content' })
        def update_followup(followup_id, followup_data)
          with_session do
            put("/ITILFollowup/#{followup_id}", { input: followup_data })
          end
        end

        # Get all followups for a ticket
        #
        # Retrieves all ITILFollowup items associated with a specific ticket.
        #
        # @param ticket_id [Integer] The GLPI ticket ID
        # @return [Array<Hash>] Array of followup data
        # @raise [ApiError] If the request fails
        #
        # @example
        #   followups = client.get_ticket_followups(123)
        #   followups.each do |followup|
        #     puts followup['content']
        #   end
        def get_ticket_followups(ticket_id)
          with_session do
            get("/Ticket/#{ticket_id}/ITILFollowup")
          end
        end

        # Get a specific followup by ID
        #
        # @param followup_id [Integer] The GLPI followup ID
        # @return [Hash] Followup data
        # @raise [ApiError] If the followup is not found or request fails
        def get_followup(followup_id)
          with_session do
            get("/ITILFollowup/#{followup_id}")
          end
        end
      end
    end
  end
end
