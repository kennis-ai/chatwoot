# frozen_string_literal: true

module Crm
  module Glpi
    module Api
      # GLPI Ticket API client
      #
      # Handles CRUD operations for GLPI Ticket resources.
      # Tickets are the primary entity for tracking support requests and incidents.
      #
      # @example Creating a ticket
      #   client = TicketClient.new(
      #     api_url: 'https://glpi.example.com/apirest.php',
      #     app_token: 'token',
      #     user_token: 'token'
      #   )
      #
      #   ticket_data = {
      #     name: 'Customer inquiry',
      #     content: 'Customer needs help with login',
      #     status: 2, # Processing
      #     priority: 3, # Medium
      #     _users_id_requester: 123,
      #     entities_id: 0
      #   }
      #
      #   result = client.create_ticket(ticket_data)
      class TicketClient < BaseClient
        # Create a new ticket in GLPI
        #
        # @param ticket_data [Hash] Ticket attributes
        # @option ticket_data [String] :name Ticket title (required)
        # @option ticket_data [String] :content Ticket description (required)
        # @option ticket_data [Integer] :status Status code (1=New, 2=Processing, 4=Pending, 5=Solved, 6=Closed)
        # @option ticket_data [Integer] :priority Priority code (1=Very Low, 2=Low, 3=Medium, 4=High, 5=Very High)
        # @option ticket_data [Integer] :type Type code (1=Incident, 2=Request)
        # @option ticket_data [Integer] :_users_id_requester Requester user ID
        # @option ticket_data [Integer] :entities_id Entity ID
        # @option ticket_data [Integer] :itilcategories_id Category ID
        #
        # @return [Hash] Created ticket data with ID
        # @raise [ApiError] If ticket creation fails
        #
        # @example
        #   ticket_data = {
        #     name: 'Conversation #123',
        #     content: 'Customer inquiry about billing',
        #     status: 2,
        #     priority: 3,
        #     _users_id_requester: 456,
        #     entities_id: 0,
        #     type: 1
        #   }
        #   result = client.create_ticket(ticket_data)
        #   ticket_id = result['id']
        def create_ticket(ticket_data)
          with_session do
            post('/Ticket', { input: ticket_data })
          end
        end

        # Update an existing ticket in GLPI
        #
        # Commonly used to update ticket status when conversations are resolved.
        #
        # @param ticket_id [Integer] The GLPI ticket ID
        # @param ticket_data [Hash] Ticket attributes to update
        # @return [Hash] Update result
        # @raise [ApiError] If the ticket is not found or update fails
        #
        # @example Update ticket status to Solved
        #   client.update_ticket(123, { status: 5 })
        #
        # @example Update ticket priority
        #   client.update_ticket(123, { priority: 5 })
        def update_ticket(ticket_id, ticket_data)
          with_session do
            put("/Ticket/#{ticket_id}", { input: ticket_data })
          end
        end

        # Get a specific ticket by ID
        #
        # @param ticket_id [Integer] The GLPI ticket ID
        # @return [Hash] Ticket data
        # @raise [ApiError] If the ticket is not found or request fails
        def get_ticket(ticket_id)
          with_session do
            get("/Ticket/#{ticket_id}")
          end
        end

        # Add a document to a ticket
        #
        # This method can be used to attach files or documents to tickets.
        #
        # @param ticket_id [Integer] The GLPI ticket ID
        # @param document_data [Hash] Document attributes
        # @option document_data [String] :name Document name
        # @option document_data [String] :filename File name
        # @option document_data [String] :filepath File path or base64 content
        #
        # @return [Hash] Document link result
        # @raise [ApiError] If document attachment fails
        def add_document(ticket_id, document_data)
          with_session do
            post("/Ticket/#{ticket_id}/Document_Item", { input: document_data })
          end
        end
      end
    end
  end
end
