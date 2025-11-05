# frozen_string_literal: true

module Crm
  module Glpi
    module Mappers
      # Maps Chatwoot Message to GLPI ITILFollowup format
      #
      # This mapper transforms Chatwoot message data into the format expected
      # by the GLPI ITILFollowup API. Followups are comments or updates added
      # to tickets, and can be marked as private (internal notes) or public.
      #
      # @example Basic mapping
      #   message = Message.find(123)
      #   followup_data = MessageMapper.map_to_followup(
      #     message,
      #     ticket_id: 789,
      #     settings: { 'default_user_id' => 2 }
      #   )
      class MessageMapper
        class << self
          # Map Chatwoot Message to GLPI ITILFollowup format
          #
          # Followups represent comments or updates on a ticket. They include:
          # - Message content with sender and timestamp
          # - Privacy flag (private messages are internal notes)
          # - Attachment information (as URLs in content)
          #
          # @param message [Message] The Chatwoot message
          # @param ticket_id [Integer] The GLPI ticket ID to attach the followup to
          # @param settings [Hash] Integration settings from hook configuration
          # @option settings [Integer] 'default_user_id' Default GLPI user ID for followups
          #
          # @return [Hash] GLPI ITILFollowup attributes
          #
          # @example
          #   followup_data = MessageMapper.map_to_followup(
          #     message,
          #     ticket_id: 789,
          #     settings: { 'default_user_id' => 2 }
          #   )
          def map_to_followup(message, ticket_id, settings)
            {
              itemtype: 'Ticket',
              items_id: ticket_id,
              content: format_message_content(message),
              is_private: message.private? ? 1 : 0,
              date: message.created_at.iso8601,
              users_id: settings['default_user_id'] || 0
            }.compact
          end

          # Format message content with sender, timestamp, and attachments
          #
          # Creates a formatted string that includes:
          # - Timestamp in YYYY-MM-DD HH:MM:SS format
          # - Sender name (or 'Unknown' if not available)
          # - Message content
          # - List of attachments (if any)
          #
          # @param message [Message] The message to format
          # @return [String] Formatted message content
          #
          # @example Without attachments
          #   format_message_content(message)
          #   # => "[2025-01-05 14:30:00] John Doe:\nHello, I need help with my account."
          #
          # @example With attachments
          #   format_message_content(message)
          #   # => "[2025-01-05 14:30:00] John Doe:\nPlease see the screenshot.\n\nAttachments:\n- https://example.com/file.png"
          def format_message_content(message)
            sender = message.sender&.name || 'Unknown'
            timestamp = message.created_at.strftime('%Y-%m-%d %H:%M:%S')

            content = "[#{timestamp}] #{sender}:\n#{message.content}"

            if message.attachments.any?
              attachment_list = message.attachments.map { |a| "- #{a.file_url}" }.join("\n")
              content += "\n\nAttachments:\n#{attachment_list}"
            end

            content
          end
        end
      end
    end
  end
end
