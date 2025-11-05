# frozen_string_literal: true

module Crm
  module Glpi
    module Mappers
      # Maps Chatwoot Conversation to GLPI Ticket format
      #
      # This mapper transforms Chatwoot conversation data into the format expected
      # by the GLPI Ticket API. It handles status mapping, priority mapping, and
      # content generation from conversation messages.
      #
      # @example Basic mapping
      #   conversation = Conversation.find(123)
      #   ticket_data = ConversationMapper.map_to_ticket(
      #     conversation,
      #     requester_id: 456,
      #     entity_id: 0,
      #     settings: { 'ticket_type' => 1, 'category_id' => 10 }
      #   )
      class ConversationMapper
        # Chatwoot status to GLPI status code mapping
        #
        # Chatwoot statuses:
        # - open: Active conversation with an agent
        # - pending: Waiting for customer response
        # - resolved: Conversation closed/solved
        # - snoozed: Temporarily hidden (not used in GLPI)
        #
        # GLPI statuses:
        # - 1: New (incoming)
        # - 2: Processing (assigned)
        # - 4: Pending
        # - 5: Solved
        # - 6: Closed
        CHATWOOT_TO_GLPI_STATUS = {
          'open' => 2,      # Processing (assigned)
          'pending' => 4,   # Pending
          'resolved' => 5,  # Solved
          'snoozed' => 2    # Treat as Processing
        }.freeze

        # Chatwoot priority to GLPI priority code mapping
        #
        # Chatwoot priorities: low, medium, high, urgent
        # GLPI priorities: 1=Very Low, 2=Low, 3=Medium, 4=High, 5=Very High
        CHATWOOT_TO_GLPI_PRIORITY = {
          'low' => 2,       # Low
          'medium' => 3,    # Medium
          'high' => 4,      # High
          'urgent' => 5     # Very High
        }.freeze

        class << self
          # Map Chatwoot Conversation to GLPI Ticket format
          #
          # @param conversation [Conversation] The Chatwoot conversation
          # @param requester_id [Integer] The GLPI User/Contact ID who requested the ticket
          # @param entity_id [Integer] The GLPI entity ID to assign
          # @param settings [Hash] Integration settings from hook configuration
          # @option settings [Integer] 'ticket_type' Default ticket type (1=Incident, 2=Request)
          # @option settings [Integer] 'category_id' Default ticket category ID
          #
          # @return [Hash] GLPI Ticket attributes
          #
          # @example
          #   ticket_data = ConversationMapper.map_to_ticket(
          #     conversation,
          #     requester_id: 456,
          #     entity_id: 0,
          #     settings: { 'ticket_type' => 1, 'category_id' => 10 }
          #   )
          def map_to_ticket(conversation, requester_id, entity_id, settings)
            first_message = conversation.messages.order(:created_at).first

            {
              name: "Conversation ##{conversation.display_id}",
              content: generate_ticket_content(conversation, first_message),
              status: map_status(conversation.status),
              priority: map_priority(conversation),
              _users_id_requester: requester_id,
              entities_id: entity_id,
              type: settings['ticket_type'] || 1, # Default to Incident
              itilcategories_id: settings['category_id']
            }.compact
          end

          # Map Chatwoot conversation status to GLPI status code
          #
          # @param status [String] Chatwoot status ('open', 'pending', 'resolved', 'snoozed')
          # @return [Integer] GLPI status code
          #
          # @example
          #   ConversationMapper.map_status('open')
          #   # => 2 (Processing)
          def map_status(status)
            CHATWOOT_TO_GLPI_STATUS[status] || 1 # Default to New
          end

          # Map Chatwoot conversation priority to GLPI priority code
          #
          # @param conversation [Conversation] The Chatwoot conversation
          # @return [Integer] GLPI priority code (2-5)
          #
          # @example
          #   ConversationMapper.map_priority(conversation)
          #   # => 3 (Medium)
          def map_priority(conversation)
            priority_name = conversation.priority&.to_s || 'medium'
            CHATWOOT_TO_GLPI_PRIORITY[priority_name] || 3 # Default to Medium
          end

          private

          # Generate ticket content from conversation and first message
          #
          # If a first message exists, use its content. Otherwise, use a default message.
          # Includes sender information if available.
          #
          # @param conversation [Conversation] The Chatwoot conversation
          # @param first_message [Message, nil] The first message in the conversation
          # @return [String] Formatted ticket content
          def generate_ticket_content(conversation, first_message)
            if first_message.present?
              format_message_with_sender(first_message)
            else
              "New conversation from #{conversation.contact&.name || 'Unknown'}"
            end
          end

          # Format message content with sender information
          #
          # @param message [Message] The message to format
          # @return [String] Formatted message with sender and timestamp
          def format_message_with_sender(message)
            sender = message.sender&.name || 'Unknown'
            timestamp = message.created_at.strftime('%Y-%m-%d %H:%M:%S')

            "[#{timestamp}] #{sender}:\n#{message.content}"
          end
        end
      end
    end
  end
end
