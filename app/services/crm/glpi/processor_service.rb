# frozen_string_literal: true

module Crm
  module Glpi
    # Main processor service for GLPI CRM integration
    #
    # This service orchestrates all GLPI synchronization operations.
    # It receives events from Chatwoot hooks and coordinates the API
    # clients, mappers, and finder services to sync data to GLPI.
    #
    # Key responsibilities:
    # - Handle contact.created/updated events → sync to GLPI Users/Contacts
    # - Handle conversation.created events → create GLPI Tickets
    # - Handle conversation.updated events → update ticket status/add followups
    # - Manage session lifecycle via BaseClient
    # - Store external IDs in contact/conversation metadata
    #
    # @example Process an event
    #   processor = ProcessorService.new(hook)
    #   result = processor.process_event('contact.created', contact)
    #   # => { success: true }
    class ProcessorService < Crm::BaseProcessorService
      # CRM name for this integration
      #
      # @return [String] The CRM identifier
      def self.crm_name
        'glpi'
      end

      # Initialize processor with hook configuration
      #
      # @param hook [Integrations::Hook] The hook containing GLPI settings
      def initialize(hook)
        super(hook)

        # Extract settings
        @api_url = hook.settings['api_url']
        @app_token = hook.settings['app_token']
        @user_token = hook.settings['user_token']
        @entity_id = hook.settings['entity_id']&.to_i || 0
        @sync_type = hook.settings['sync_type'] || 'user' # 'user' or 'contact'

        # Optional settings
        @ticket_type = hook.settings['ticket_type']&.to_i
        @category_id = hook.settings['category_id']&.to_i
        @default_user_id = hook.settings['default_user_id']&.to_i

        # Initialize base client (used by other clients)
        @base_client = Api::BaseClient.new(
          api_url: @api_url,
          app_token: @app_token,
          user_token: @user_token
        )

        # Initialize API clients
        @user_client = Api::UserClient.new(
          api_url: @api_url,
          app_token: @app_token,
          user_token: @user_token
        )

        @contact_client = Api::ContactClient.new(
          api_url: @api_url,
          app_token: @app_token,
          user_token: @user_token
        )

        @ticket_client = Api::TicketClient.new(
          api_url: @api_url,
          app_token: @app_token,
          user_token: @user_token
        )

        @followup_client = Api::FollowupClient.new(
          api_url: @api_url,
          app_token: @app_token,
          user_token: @user_token
        )

        # Initialize finder services
        @user_finder = UserFinderService.new(@user_client, @entity_id)
        @contact_finder = ContactFinderService.new(@contact_client, @entity_id)
      end

      # Handle contact created event
      #
      # Creates or updates GLPI User or Contact based on sync_type setting
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Hash] Result with :success key
      def handle_contact_created(contact)
        handle_contact(contact)
      end

      # Handle contact updated event
      #
      # Updates existing GLPI User or Contact
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Hash] Result with :success key
      def handle_contact_updated(contact)
        handle_contact(contact)
      end

      # Handle conversation created event
      #
      # Creates GLPI Ticket from conversation
      #
      # @param conversation [Conversation] Chatwoot conversation
      # @return [Hash] Result with :success key
      def handle_conversation_created(conversation)
        @base_client.with_session do
          create_ticket(conversation)
        end

        { success: true }
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
        Rails.logger.error "Error creating GLPI ticket: #{e.message}"
        { success: false, error: e.message }
      end

      # Handle conversation updated event
      #
      # Updates ticket status or adds followup messages
      #
      # @param conversation [Conversation] Chatwoot conversation
      # @return [Hash] Result with :success key
      def handle_conversation_updated(conversation)
        @base_client.with_session do
          update_ticket(conversation)
        end

        { success: true }
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
        Rails.logger.error "Error updating GLPI ticket: #{e.message}"
        { success: false, error: e.message }
      end

      # Handle conversation resolved (not used, handled by updated)
      def handle_conversation_resolved(conversation)
        handle_conversation_updated(conversation)
      end

      private

      # Handle contact synchronization (create or update)
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Hash] Result with :success key
      def handle_contact(contact)
        contact.reload
        unless identifiable_contact?(contact)
          Rails.logger.info("Contact not identifiable. Skipping handle_contact for ##{contact.id}")
          return { success: false, error: 'Contact not identifiable' }
        end

        @base_client.with_session do
          if @sync_type == 'contact'
            sync_to_glpi_contact(contact)
          else
            sync_to_glpi_user(contact)
          end
        end

        { success: true }
      rescue Api::BaseClient::ApiError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
        Rails.logger.error "GLPI API error processing contact: #{e.message}"
        { success: false, error: e.message }
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
        Rails.logger.error "Error processing contact in GLPI: #{e.message}"
        { success: false, error: e.message }
      end

      # Sync Chatwoot contact to GLPI User
      #
      # @param contact [Contact] Chatwoot contact
      def sync_to_glpi_user(contact)
        stored_user_id = get_external_id(contact)

        if stored_user_id.present?
          # Update existing user
          user_data = Mappers::ContactMapper.map_to_user(contact, @entity_id)
          @user_client.update_user(stored_user_id, user_data)
          Rails.logger.info "Updated GLPI user ##{stored_user_id} for contact ##{contact.id}"
        else
          # Find or create user
          user_id = @user_finder.find_or_create(contact)
          return unless user_id.present?

          store_external_id(contact, user_id)
          Rails.logger.info "Linked GLPI user ##{user_id} to contact ##{contact.id}"
        end
      end

      # Sync Chatwoot contact to GLPI Contact
      #
      # @param contact [Contact] Chatwoot contact
      def sync_to_glpi_contact(contact)
        stored_contact_id = get_stored_contact_id(contact)

        if stored_contact_id.present?
          # Update existing contact
          contact_data = Mappers::ContactMapper.map_to_contact(contact, @entity_id)
          @contact_client.update_contact(stored_contact_id, contact_data)
          Rails.logger.info "Updated GLPI contact ##{stored_contact_id} for contact ##{contact.id}"
        else
          # Find or create contact
          contact_id = @contact_finder.find_or_create(contact)
          return unless contact_id.present?

          store_contact_id(contact, contact_id)
          Rails.logger.info "Linked GLPI contact ##{contact_id} to contact ##{contact.id}"
        end
      end

      # Create GLPI Ticket from conversation
      #
      # @param conversation [Conversation] Chatwoot conversation
      def create_ticket(conversation)
        # Get or create requester
        requester_id = get_requester_id(conversation.contact)
        return unless requester_id.present?

        # Map conversation to ticket
        settings = {
          'ticket_type' => @ticket_type,
          'category_id' => @category_id
        }.compact

        ticket_data = Mappers::ConversationMapper.map_to_ticket(
          conversation,
          requester_id,
          @entity_id,
          settings
        )

        # Create ticket
        result = @ticket_client.create_ticket(ticket_data)
        return unless result.is_a?(Hash)

        ticket_id = result['id']
        return if ticket_id.blank?

        # Store ticket ID in conversation metadata
        metadata = { 'ticket_id' => ticket_id }
        store_conversation_metadata(conversation, metadata)

        Rails.logger.info "Created GLPI ticket ##{ticket_id} for conversation ##{conversation.display_id}"
      end

      # Update GLPI Ticket from conversation
      #
      # @param conversation [Conversation] Chatwoot conversation
      def update_ticket(conversation)
        ticket_id = get_ticket_id(conversation)
        return unless ticket_id.present?

        # Update ticket status
        settings = {}
        ticket_data = {
          status: Mappers::ConversationMapper.map_status(conversation.status),
          priority: Mappers::ConversationMapper.map_priority(conversation)
        }.compact

        @ticket_client.update_ticket(ticket_id, ticket_data)

        # Sync recent messages as followups
        sync_followups(conversation, ticket_id)

        Rails.logger.info "Updated GLPI ticket ##{ticket_id} for conversation ##{conversation.display_id}"
      end

      # Sync conversation messages as GLPI followups
      #
      # @param conversation [Conversation] Chatwoot conversation
      # @param ticket_id [Integer] GLPI ticket ID
      def sync_followups(conversation, ticket_id)
        # Get last synced message ID from metadata
        last_synced_id = get_last_synced_message_id(conversation)

        # Get messages after last synced
        messages = if last_synced_id.present?
                     conversation.messages.where('id > ?', last_synced_id).order(:created_at)
                   else
                     conversation.messages.order(:created_at).limit(50) # Sync last 50 on first update
                   end

        return if messages.empty?

        # Create followup for each message
        messages.each do |message|
          create_followup(message, ticket_id)
        end

        # Update last synced message ID
        update_last_synced_message_id(conversation, messages.last.id)
      end

      # Create GLPI followup from message
      #
      # @param message [Message] Chatwoot message
      # @param ticket_id [Integer] GLPI ticket ID
      def create_followup(message, ticket_id)
        settings = { 'default_user_id' => @default_user_id }.compact
        followup_data = Mappers::MessageMapper.map_to_followup(message, ticket_id, settings)

        @followup_client.create_followup(followup_data)
        Rails.logger.info "Created GLPI followup for message ##{message.id} on ticket ##{ticket_id}"
      rescue Api::BaseClient::ApiError => e
        Rails.logger.error "GLPI API error creating followup: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Error creating GLPI followup: #{e.message}"
      end

      # Get GLPI requester ID (User or Contact) for contact
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI requester ID
      def get_requester_id(contact)
        unless identifiable_contact?(contact)
          Rails.logger.info("Contact not identifiable. Cannot create ticket for ##{contact.id}")
          return nil
        end

        if @sync_type == 'contact'
          contact_id = @contact_finder.find_or_create(contact)
          store_contact_id(contact, contact_id) if contact_id.present? && get_stored_contact_id(contact).blank?
          contact_id
        else
          user_id = @user_finder.find_or_create(contact)
          store_external_id(contact, user_id) if user_id.present? && get_external_id(contact).blank?
          user_id
        end
      end

      # Get stored GLPI contact ID
      #
      # @param contact [Contact] Chatwoot contact
      # @return [Integer, nil] GLPI contact ID
      def get_stored_contact_id(contact)
        return nil if contact.additional_attributes.blank?
        return nil if contact.additional_attributes['external'].blank?

        contact.additional_attributes.dig('external', 'glpi_contact_id')
      end

      # Store GLPI contact ID in contact metadata
      #
      # @param contact [Contact] Chatwoot contact
      # @param contact_id [Integer] GLPI contact ID
      def store_contact_id(contact, contact_id)
        contact.additional_attributes = {} if contact.additional_attributes.nil?
        contact.additional_attributes['external'] = {} if contact.additional_attributes['external'].blank?
        contact.additional_attributes['external']['glpi_contact_id'] = contact_id
        contact.save!
      end

      # Get stored GLPI ticket ID from conversation metadata
      #
      # @param conversation [Conversation] Chatwoot conversation
      # @return [Integer, nil] GLPI ticket ID
      def get_ticket_id(conversation)
        return nil if conversation.additional_attributes.blank?
        return nil if conversation.additional_attributes['glpi'].blank?

        conversation.additional_attributes.dig('glpi', 'ticket_id')
      end

      # Get last synced message ID from conversation metadata
      #
      # @param conversation [Conversation] Chatwoot conversation
      # @return [Integer, nil] Last synced message ID
      def get_last_synced_message_id(conversation)
        return nil if conversation.additional_attributes.blank?
        return nil if conversation.additional_attributes['glpi'].blank?

        conversation.additional_attributes.dig('glpi', 'last_synced_message_id')
      end

      # Update last synced message ID in conversation metadata
      #
      # @param conversation [Conversation] Chatwoot conversation
      # @param message_id [Integer] Last synced message ID
      def update_last_synced_message_id(conversation, message_id)
        conversation.additional_attributes = {} if conversation.additional_attributes.nil?
        conversation.additional_attributes['glpi'] = {} if conversation.additional_attributes['glpi'].blank?
        conversation.additional_attributes['glpi']['last_synced_message_id'] = message_id
        conversation.save!
      end
    end
  end
end
