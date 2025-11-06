# GLPI Integration Implementation Plan

## Overview

Implement GLPI CRM integration for Chatwoot following the proven LeadSquared architecture pattern. This integration will sync contacts to GLPI Users/Contacts and create GLPI Tickets from conversations with automatic followup synchronization.

## Architecture Reference

This implementation follows the same patterns established by the LeadSquared CRM integration in Chatwoot:
- Session-based authentication (vs. LeadSquared's key-based auth)
- Event-driven synchronization via hook listeners
- Background job processing with Redis mutex locks
- Modular service architecture with API clients, mappers, and processors
- Flexible configuration via JSON schema validation

## Key Differences: GLPI vs. LeadSquared

| Aspect | LeadSquared | GLPI |
|--------|-------------|------|
| **Authentication** | Static access_key + secret_key | Session-based (app_token + user_token) |
| **Primary Entity** | Lead | Ticket |
| **Secondary Entity** | Activity | ITILFollowup |
| **Contact Storage** | Lead only | User OR Contact (configurable) |
| **Setup Phase** | Create activity types | Validate session + entity |
| **Session Management** | N/A | Required for each API call batch |

## Implementation Phases

### Phase 1: Foundation & API Clients (Week 1)

#### 1.1 Create Base Client with Session Management

**File**: `app/services/crm/glpi/api/base_client.rb`

**Purpose**: Core HTTP client with GLPI session lifecycle management

**Key Features**:
- Initialize with `api_url`, `app_token`, `user_token`
- `init_session` - POST to `/initSession` with tokens in headers
- `kill_session` - GET to `/killSession` to cleanup
- `with_session(&block)` - Wrapper that ensures session cleanup
- GET/POST/PUT methods with proper headers (`Session-Token`, `App-Token`)
- Custom `ApiError` exception class with code and response
- `handle_response` - Check HTTP status codes
- `parse_response` - Parse JSON and detect GLPI errors

**Error Handling**:
- 401: Invalid credentials → raise ApiError
- 404: Resource not found → raise ApiError
- 422: Validation error → raise ApiError with details
- 500: Server error → raise ApiError
- Session expiration → reinitialize session

**Example Structure**:
```ruby
module Crm
  module Glpi
    module Api
      class ApiError < StandardError
        attr_reader :code, :response

        def initialize(code, response)
          @code = code
          @response = response
          super("GLPI API Error: #{code} - #{response}")
        end
      end

      class BaseClient
        include HTTParty

        attr_reader :api_url, :app_token, :user_token, :session_token

        def initialize(api_url:, app_token:, user_token:)
          @api_url = api_url
          @app_token = app_token
          @user_token = user_token
          @session_token = nil
        end

        def with_session(&block)
          init_session
          result = yield
          result
        ensure
          kill_session
        end

        def init_session
          # POST /initSession with Authorization header
        end

        def kill_session
          # GET /killSession
        end

        def get(endpoint, query_params = {})
          # GET with session token
        end

        def post(endpoint, body = {})
          # POST with session token
        end

        def put(endpoint, body = {})
          # PUT with session token
        end

        private

        def headers
          {
            'Session-Token' => @session_token,
            'App-Token' => @app_token,
            'Content-Type' => 'application/json'
          }.compact
        end

        def handle_response(response)
          # Check status codes, raise ApiError
        end

        def parse_response(response)
          # Parse JSON, detect errors
        end
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/api/base_client_spec.rb`
- Test session initialization success
- Test session initialization failure (invalid credentials)
- Test session cleanup
- Test `with_session` wrapper (success and error paths)
- Test GET/POST/PUT methods
- Test error handling for each status code
- Mock GLPI API responses using WebMock

---

#### 1.2 Create User Client

**File**: `app/services/crm/glpi/api/user_client.rb`

**Purpose**: CRUD operations for GLPI Users

**Methods**:
- `search_user(email:)` - Search by email using searchOptions
- `get_user(user_id)` - Get user by ID
- `create_user(user_data)` - Create new user
- `update_user(user_id, user_data)` - Update existing user

**Example**:
```ruby
module Crm
  module Glpi
    module Api
      class UserClient < BaseClient
        def search_user(email:)
          with_session do
            query = {
              criteria: [
                { field: 5, searchtype: 'equals', value: email }
              ]
            }
            get('/search/User', query)
          end
        end

        def create_user(user_data)
          with_session do
            post('/User', { input: user_data })
          end
        end

        def update_user(user_id, user_data)
          with_session do
            put("/User/#{user_id}", { input: user_data })
          end
        end
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/api/user_client_spec.rb`
- Test search by email (found/not found)
- Test create user (success/validation error)
- Test update user (success/not found)

---

#### 1.3 Create Contact Client

**File**: `app/services/crm/glpi/api/contact_client.rb`

**Purpose**: CRUD operations for GLPI Contacts

**Methods**:
- `search_contact(email:)` - Search by email
- `get_contact(contact_id)` - Get contact by ID
- `create_contact(contact_data)` - Create new contact
- `update_contact(contact_id, contact_data)` - Update existing contact

**Structure**: Similar to UserClient but for Contact itemtype

**Tests**: `spec/services/crm/glpi/api/contact_client_spec.rb`

---

#### 1.4 Create Ticket Client

**File**: `app/services/crm/glpi/api/ticket_client.rb`

**Purpose**: CRUD operations for GLPI Tickets

**Methods**:
- `create_ticket(ticket_data)` - Create new ticket
- `update_ticket(ticket_id, ticket_data)` - Update ticket (e.g., status)
- `get_ticket(ticket_id)` - Get ticket details
- `add_document(ticket_id, document_data)` - Attach document

**Example**:
```ruby
module Crm
  module Glpi
    module Api
      class TicketClient < BaseClient
        def create_ticket(ticket_data)
          with_session do
            post('/Ticket', { input: ticket_data })
          end
        end

        def update_ticket(ticket_id, ticket_data)
          with_session do
            put("/Ticket/#{ticket_id}", { input: ticket_data })
          end
        end
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/api/ticket_client_spec.rb`
- Test create ticket
- Test update ticket status
- Test ticket not found error

---

#### 1.5 Create Followup Client

**File**: `app/services/crm/glpi/api/followup_client.rb`

**Purpose**: CRUD operations for GLPI ITILFollowup (ticket comments)

**Methods**:
- `create_followup(followup_data)` - Create followup on ticket
- `update_followup(followup_id, followup_data)` - Update followup
- `get_ticket_followups(ticket_id)` - List followups for ticket

**Example**:
```ruby
module Crm
  module Glpi
    module Api
      class FollowupClient < BaseClient
        def create_followup(followup_data)
          with_session do
            post('/ITILFollowup', { input: followup_data })
          end
        end

        def get_ticket_followups(ticket_id)
          with_session do
            get("/Ticket/#{ticket_id}/ITILFollowup")
          end
        end
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/api/followup_client_spec.rb`
- Test create followup
- Test get ticket followups

---

### Phase 2: Data Mappers (Week 2)

#### 2.1 Contact Mapper

**File**: `app/services/crm/glpi/mappers/contact_mapper.rb`

**Purpose**: Transform Chatwoot Contact → GLPI User/Contact

**Methods**:

1. `map_to_user(contact, entity_id)` - Returns GLPI User hash
   - Maps to: `name`, `firstname`, `realname`, `phone`, `mobile`, `_useremails`
   - Splits contact.name into firstname/realname
   - Uses `entities_id` for entity assignment
   - Returns hash ready for API

2. `map_to_contact(contact, entity_id)` - Returns GLPI Contact hash
   - Maps to: `name`, `firstname`, `email`, `phone`, `phone2`, `entities_id`
   - Similar structure to User but different fields

3. `format_phone_number(phone_number)` - Normalize phone format
   - Use TelephoneNumber gem for parsing
   - Format as international: `+XX XXXXXXXXX`

**Example**:
```ruby
module Crm
  module Glpi
    module Mappers
      class ContactMapper
        def self.map_to_user(contact, entity_id)
          first_name, last_name = split_name(contact.name)

          {
            name: contact.email || contact.phone_number,
            firstname: first_name,
            realname: last_name,
            phone: format_phone_number(contact.phone_number),
            mobile: format_phone_number(contact.phone_number),
            _useremails: [contact.email].compact,
            entities_id: entity_id
          }.compact
        end

        def self.map_to_contact(contact, entity_id)
          first_name, last_name = split_name(contact.name)

          {
            name: contact.name,
            firstname: first_name,
            email: contact.email,
            phone: format_phone_number(contact.phone_number),
            entities_id: entity_id
          }.compact
        end

        def self.split_name(full_name)
          return [nil, nil] if full_name.blank?

          parts = full_name.split(' ', 2)
          [parts[0], parts[1]]
        end

        def self.format_phone_number(phone_number)
          return nil if phone_number.blank?

          parsed = TelephoneNumber.parse(phone_number)
          parsed.international_string
        rescue TelephoneNumber::InvalidNumberError
          phone_number
        end
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/mappers/contact_mapper_spec.rb`
- Test map_to_user with full data
- Test map_to_user with missing fields
- Test map_to_contact with full data
- Test split_name edge cases
- Test format_phone_number (valid/invalid)

---

#### 2.2 Conversation Mapper

**File**: `app/services/crm/glpi/mappers/conversation_mapper.rb`

**Purpose**: Transform Chatwoot Conversation → GLPI Ticket

**Methods**:

1. `map_to_ticket(conversation, requester_id, entity_id, settings)` - Returns GLPI Ticket hash
   - Maps conversation status to GLPI status codes
   - Maps conversation priority to GLPI priority codes
   - Generates ticket name from display_id
   - Sets content from first message or description
   - Sets requester (users_id_recipient or _users_id_requester)
   - Sets type, category, urgency based on settings

**Status Mapping**:
```ruby
CHATWOOT_TO_GLPI_STATUS = {
  'open' => 2,      # Processing (assigned)
  'pending' => 4,   # Pending
  'resolved' => 5,  # Solved
  'bot' => 1        # New (incoming)
}.freeze
```

**Priority Mapping**:
```ruby
CHATWOOT_TO_GLPI_PRIORITY = {
  'low' => 2,       # Low
  'medium' => 3,    # Medium
  'high' => 4,      # High
  'urgent' => 5     # Very High
}.freeze
```

**Example**:
```ruby
module Crm
  module Glpi
    module Mappers
      class ConversationMapper
        CHATWOOT_TO_GLPI_STATUS = {
          'open' => 2,
          'pending' => 4,
          'resolved' => 5,
          'bot' => 1
        }.freeze

        CHATWOOT_TO_GLPI_PRIORITY = {
          'urgent' => 5,
          'high' => 4,
          'medium' => 3,
          'low' => 2
        }.freeze

        def self.map_to_ticket(conversation, requester_id, entity_id, settings)
          first_message = conversation.messages.order(:created_at).first

          {
            name: "Conversation ##{conversation.display_id}",
            content: first_message&.content || 'New conversation',
            status: CHATWOOT_TO_GLPI_STATUS[conversation.status] || 1,
            priority: map_priority(conversation),
            _users_id_requester: requester_id,
            entities_id: entity_id,
            type: settings.dig('ticket_type') || 1, # Incident
            itilcategories_id: settings.dig('category_id')
          }.compact
        end

        def self.map_priority(conversation)
          priority = conversation.priority || 'medium'
          CHATWOOT_TO_GLPI_PRIORITY[priority] || 3
        end
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/mappers/conversation_mapper_spec.rb`
- Test map_to_ticket with all fields
- Test status mapping for each status
- Test priority mapping for each priority
- Test with missing first message
- Test with custom settings

---

#### 2.3 Message Mapper

**File**: `app/services/crm/glpi/mappers/message_mapper.rb`

**Purpose**: Transform Chatwoot Message → GLPI ITILFollowup

**Methods**:

1. `map_to_followup(message, ticket_id, settings)` - Returns GLPI ITILFollowup hash
   - Maps message content
   - Sets tickets_id linkage
   - Determines is_private based on message type
   - Includes sender information
   - Formats timestamps

**Example**:
```ruby
module Crm
  module Glpi
    module Mappers
      class MessageMapper
        def self.map_to_followup(message, ticket_id, settings)
          {
            itemtype: 'Ticket',
            items_id: ticket_id,
            content: format_message_content(message),
            is_private: message.private? ? 1 : 0,
            date: message.created_at.iso8601,
            users_id: settings.dig('default_user_id') || 0
          }.compact
        end

        def self.format_message_content(message)
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
```

**Tests**: `spec/services/crm/glpi/mappers/message_mapper_spec.rb`
- Test map_to_followup with basic message
- Test private vs public messages
- Test with attachments
- Test content formatting

---

### Phase 3: Core Services (Week 2-3)

#### 3.1 Setup Service

**File**: `app/services/crm/glpi/setup_service.rb`

**Purpose**: One-time initialization when integration is created

**Methods**:

1. `setup` - Main entry point
   - Validates API credentials by initializing session
   - Fetches and validates entity information
   - Stores configuration in hook settings
   - Returns success/failure

2. `validate_connection` - Test API connectivity
   - Attempts to init session
   - Fetches user info
   - Returns true/false

3. `fetch_entity_info` - Get entity details
   - If entity_id provided: validate it exists
   - If not provided: get default entity
   - Store entity info in settings

**Example**:
```ruby
module Crm
  module Glpi
    class SetupService
      def initialize(hook)
        @hook = hook
      end

      def setup
        validate_connection
        fetch_entity_info
        @hook.save!
        true
      rescue Api::ApiError => e
        Rails.logger.error("GLPI Setup Error: #{e.message}")
        ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
        false
      rescue StandardError => e
        Rails.logger.error("GLPI Setup Error: #{e.message}")
        ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
        false
      end

      private

      def validate_connection
        client = Api::BaseClient.new(
          api_url: @hook.settings['api_url'],
          app_token: @hook.settings['app_token'],
          user_token: @hook.settings['user_token']
        )

        client.with_session do
          # Session init success = valid credentials
          true
        end
      end

      def fetch_entity_info
        entity_id = @hook.settings['entity_id']

        if entity_id.blank?
          # Get default entity from user profile
          # Store in settings
        else
          # Validate provided entity_id exists
        end
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/setup_service_spec.rb`
- Test successful setup
- Test with invalid credentials
- Test with invalid entity_id
- Test entity_id auto-detection

---

#### 3.2 User Finder Service

**File**: `app/services/crm/glpi/user_finder_service.rb`

**Purpose**: Find or create GLPI User from Chatwoot Contact

**Methods**:

1. `find_or_create(contact, entity_id)` - Returns user_id
   - Check if external ID stored in contact
   - If yes: return stored ID
   - If no: search by email
   - If found: store ID and return
   - If not found: create user, store ID, return

**Example**:
```ruby
module Crm
  module Glpi
    class UserFinderService
      def initialize(user_client)
        @user_client = user_client
      end

      def find_or_create(contact, entity_id)
        # Check stored ID
        stored_id = contact.additional_attributes.dig('external', 'glpi_id')
        return stored_id if stored_id.present?

        # Search by email
        if contact.email.present?
          search_result = @user_client.search_user(email: contact.email)

          if search_result['data'].present?
            user_id = search_result['data'].first['2'] # ID field
            store_external_id(contact, user_id)
            return user_id
          end
        end

        # Create user
        user_data = Mappers::ContactMapper.map_to_user(contact, entity_id)
        response = @user_client.create_user(user_data)
        user_id = response['id']

        store_external_id(contact, user_id)
        user_id
      end

      private

      def store_external_id(contact, user_id)
        contact.additional_attributes ||= {}
        contact.additional_attributes['external'] ||= {}
        contact.additional_attributes['external']['glpi_id'] = user_id
        contact.save!
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/user_finder_service_spec.rb`
- Test with stored ID (returns immediately)
- Test search by email (found)
- Test search by email (not found, creates user)
- Test without email (creates user directly)

---

#### 3.3 Contact Finder Service

**File**: `app/services/crm/glpi/contact_finder_service.rb`

**Purpose**: Find or create GLPI Contact from Chatwoot Contact

**Structure**: Similar to UserFinderService but uses ContactClient and ContactMapper

**Tests**: `spec/services/crm/glpi/contact_finder_service_spec.rb`

---

#### 3.4 Processor Service

**File**: `app/services/crm/glpi/processor_service.rb`

**Purpose**: Main service that handles all CRM events

**Extends**: `Crm::BaseProcessorService`

**Initialization**:
```ruby
def initialize(hook)
  super(hook)
  @settings = hook.settings
  @entity_id = @settings['entity_id']

  # Initialize API clients
  @user_client = Api::UserClient.new(
    api_url: @settings['api_url'],
    app_token: @settings['app_token'],
    user_token: @settings['user_token']
  )

  @contact_client = Api::ContactClient.new(...)
  @ticket_client = Api::TicketClient.new(...)
  @followup_client = Api::FollowupClient.new(...)

  # Initialize finder services
  @user_finder = UserFinderService.new(@user_client)
  @contact_finder = ContactFinderService.new(@contact_client)
end
```

**Class Method**:
```ruby
def self.crm_name
  'glpi'
end
```

**Public Methods** (implement BaseProcessorService abstract methods):

1. `handle_contact_created(contact)` - Sync new contact to GLPI
2. `handle_contact_updated(contact)` - Update existing GLPI user/contact
3. `handle_conversation_created(conversation)` - Create GLPI ticket
4. `handle_conversation_resolved(conversation)` - Update ticket status to solved

**Private Methods**:

1. `create_or_update_contact(contact)` - Main contact sync logic
   - Check if contact is identifiable (has email or phone)
   - Determine if using User or Contact based on settings
   - Find or create in GLPI
   - Store external ID

2. `create_ticket_from_conversation(conversation)` - Ticket creation logic
   - Get contact from conversation
   - Ensure GLPI user/contact exists (find_or_create)
   - Map conversation to ticket data
   - Create ticket via API
   - Store ticket_id in conversation.additional_attributes['glpi']['ticket_id']
   - Optionally sync initial messages as followups

3. `update_ticket_status(conversation, new_status)` - Update ticket
   - Get stored ticket_id from conversation
   - Map Chatwoot status to GLPI status code
   - Update ticket via API

4. `sync_message_as_followup(message, ticket_id)` - Create followup
   - Map message to followup data
   - Create via API
   - Only if enable_followup_sync is true

**Example Structure**:
```ruby
module Crm
  module Glpi
    class ProcessorService < Crm::BaseProcessorService
      def self.crm_name
        'glpi'
      end

      def initialize(hook)
        super(hook)
        # Initialize clients and finders
      end

      # Public event handlers

      def handle_contact_created(contact)
        return unless identifiable_contact?(contact)
        create_or_update_contact(contact)
      end

      def handle_contact_updated(contact)
        return unless identifiable_contact?(contact)
        create_or_update_contact(contact)
      end

      def handle_conversation_created(conversation)
        return unless @settings['enable_ticket_sync']
        create_ticket_from_conversation(conversation)
      end

      def handle_conversation_resolved(conversation)
        return unless @settings['enable_ticket_sync']
        ticket_id = get_ticket_id(conversation)
        return unless ticket_id

        update_ticket_status(conversation, 'resolved')
      end

      private

      def create_or_update_contact(contact)
        if @settings['use_contact']
          @contact_finder.find_or_create(contact, @entity_id)
        else
          @user_finder.find_or_create(contact, @entity_id)
        end
      rescue Api::ApiError => e
        Rails.logger.error("GLPI Contact Sync Error: #{e.message}")
        ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
      end

      def create_ticket_from_conversation(conversation)
        contact = conversation.contact
        return unless contact

        # Ensure GLPI user/contact exists
        requester_id = if @settings['use_contact']
                         @contact_finder.find_or_create(contact, @entity_id)
                       else
                         @user_finder.find_or_create(contact, @entity_id)
                       end

        # Map and create ticket
        ticket_data = Mappers::ConversationMapper.map_to_ticket(
          conversation,
          requester_id,
          @entity_id,
          @settings
        )

        response = @ticket_client.create_ticket(ticket_data)
        ticket_id = response['id']

        # Store ticket ID
        store_conversation_metadata(conversation, 'ticket_id', ticket_id)

        # Optionally sync messages as followups
        sync_initial_messages(conversation, ticket_id) if @settings['enable_followup_sync']

        ticket_id
      rescue Api::ApiError => e
        Rails.logger.error("GLPI Ticket Creation Error: #{e.message}")
        ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
      end

      def update_ticket_status(conversation, new_status)
        ticket_id = get_ticket_id(conversation)
        return unless ticket_id

        status_code = Mappers::ConversationMapper::CHATWOOT_TO_GLPI_STATUS[new_status]
        @ticket_client.update_ticket(ticket_id, { status: status_code })
      rescue Api::ApiError => e
        Rails.logger.error("GLPI Ticket Update Error: #{e.message}")
        ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
      end

      def sync_initial_messages(conversation, ticket_id)
        conversation.messages.order(:created_at).each do |message|
          followup_data = Mappers::MessageMapper.map_to_followup(
            message,
            ticket_id,
            @settings
          )
          @followup_client.create_followup(followup_data)
        end
      end

      def get_ticket_id(conversation)
        conversation.additional_attributes.dig('glpi', 'ticket_id')
      end

      def store_conversation_metadata(conversation, key, value)
        conversation.additional_attributes ||= {}
        conversation.additional_attributes['glpi'] ||= {}
        conversation.additional_attributes['glpi'][key] = value
        conversation.save!
      end
    end
  end
end
```

**Tests**: `spec/services/crm/glpi/processor_service_spec.rb`
- Test handle_contact_created (success)
- Test handle_contact_updated (success)
- Test handle_conversation_created (creates ticket)
- Test handle_conversation_created with followup sync
- Test handle_conversation_resolved (updates status)
- Test error handling for each method
- Mock API responses with VCR or WebMock

---

### Phase 4: Configuration & Integration (Week 3)

#### 4.1 Update Integration Apps Configuration

**File**: `config/integration/apps.yml`

**Location**: Add after LeadSquared configuration block

**Configuration**:
```yaml
glpi:
  id: glpi
  feature_flag: crm_integration
  logo: glpi.png
  i18n_key: glpi
  action: /glpi
  hook_type: account
  allow_multiple_hooks: false
  settings_json_schema:
    type: object
    properties:
      api_url:
        type: string
        format: uri
        description: GLPI API base URL (e.g., https://glpi.example.com/apirest.php)
      app_token:
        type: string
        description: GLPI Application Token
      user_token:
        type: string
        description: GLPI User Token
      entity_id:
        type: integer
        description: GLPI Entity ID (optional, will use default if not provided)
      use_contact:
        type: boolean
        default: false
        description: Use GLPI Contact instead of User for contact sync
      enable_ticket_sync:
        type: boolean
        default: true
        description: Create GLPI tickets from conversations
      enable_followup_sync:
        type: boolean
        default: false
        description: Sync conversation messages as ticket followups
      ticket_type:
        type: integer
        default: 1
        description: Default ticket type (1=Incident, 2=Request)
      category_id:
        type: integer
        description: Default ticket category ID (optional)
    required:
      - api_url
      - app_token
      - user_token
  settings_form_schema:
    - label: API URL
      type: text
      name: api_url
      placeholder: https://glpi.example.com/apirest.php
      help_text: Your GLPI API endpoint URL
    - label: Application Token
      type: text
      name: app_token
      placeholder: Enter GLPI app token
      help_text: Generate from Setup > General > API
    - label: User Token
      type: text
      name: user_token
      placeholder: Enter GLPI user token
      help_text: Generate from User Preferences > Remote Access Keys
    - label: Entity ID
      type: number
      name: entity_id
      placeholder: Leave blank for default entity
      help_text: Specific GLPI entity to use (optional)
    - label: Use Contact Instead of User
      type: toggle
      name: use_contact
      default: false
      help_text: Sync Chatwoot contacts as GLPI Contacts instead of Users
    - label: Enable Ticket Sync
      type: toggle
      name: enable_ticket_sync
      default: true
      help_text: Create GLPI tickets from conversations
    - label: Enable Followup Sync
      type: toggle
      name: enable_followup_sync
      default: false
      help_text: Sync conversation messages as ticket followups
    - label: Default Ticket Type
      type: select
      name: ticket_type
      default: 1
      options:
        - label: Incident
          value: 1
        - label: Request
          value: 2
      help_text: Type for new tickets
    - label: Default Category ID
      type: number
      name: category_id
      placeholder: Leave blank for no category
      help_text: Default ticket category (optional)
  visible_properties:
    - api_url
    - enable_ticket_sync
    - enable_followup_sync
    - use_contact
```

---

#### 4.2 Update Localization Files

**File**: `config/locales/en.yml`

**Location**: Under `integration_apps` section

**Add**:
```yaml
en:
  integration_apps:
    glpi:
      name: "GLPI"
      description: "Sync contacts and conversations with GLPI ticketing system"
      help_text: "Connect Chatwoot to your GLPI instance to automatically create tickets from conversations and sync contact information."
      fields:
        api_url:
          label: "API URL"
          placeholder: "https://glpi.example.com/apirest.php"
          help_text: "Your GLPI API endpoint URL"
        app_token:
          label: "Application Token"
          placeholder: "Enter GLPI app token"
          help_text: "Generate from Setup > General > API in GLPI"
        user_token:
          label: "User Token"
          placeholder: "Enter GLPI user token"
          help_text: "Generate from User Preferences > Remote Access Keys"
        entity_id:
          label: "Entity ID"
          placeholder: "Leave blank for default"
          help_text: "Specific GLPI entity to use (optional)"
        use_contact:
          label: "Use Contact Instead of User"
          help_text: "Sync as GLPI Contacts instead of Users"
        enable_ticket_sync:
          label: "Enable Ticket Sync"
          help_text: "Create GLPI tickets from conversations"
        enable_followup_sync:
          label: "Enable Followup Sync"
          help_text: "Sync messages as ticket followups"
        ticket_type:
          label: "Default Ticket Type"
          help_text: "Type for new tickets"
        category_id:
          label: "Default Category ID"
          help_text: "Default ticket category (optional)"
      errors:
        invalid_credentials: "Invalid GLPI credentials"
        connection_failed: "Could not connect to GLPI API"
        session_expired: "GLPI session expired"
        entity_not_found: "Entity ID not found in GLPI"
        ticket_creation_failed: "Failed to create GLPI ticket"
```

---

#### 4.3 Update Hook Model

**File**: `app/models/integrations/hook.rb`

**Location**: Line ~110, method `crm_integration?`

**Change**:
```ruby
def crm_integration?
  ['leadsquared', 'glpi'].include?(app_id)
end
```

---

#### 4.4 Update Hook Listener

**File**: `app/listeners/hook_listener.rb`

**Location**: Line ~58, method `supported_hook_event?`

**Update** `supported_events_map`:
```ruby
def supported_events_map
  {
    'leadsquared' => ['contact.updated', 'conversation.created', 'conversation.resolved'],
    'glpi' => ['contact.updated', 'conversation.created', 'conversation.resolved']
  }
end
```

---

#### 4.5 Update Hook Job

**File**: `app/jobs/hook_job.rb`

**Location**: Add GLPI processing after LeadSquared section

**Add** (around line 40):
```ruby
when 'glpi'
  process_glpi_integration_with_lock(hook, event_name, event_data)
```

**Add** at end of class (around line 100):
```ruby
def process_glpi_integration_with_lock(hook, event_name, event_data)
  key = format(::Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
  with_lock(key) do
    process_glpi_integration(hook, event_name, event_data)
  end
end

def process_glpi_integration(hook, event_name, event_data)
  processor = Crm::Glpi::ProcessorService.new(hook)

  case event_name
  when 'contact.updated'
    processor.handle_contact_updated(event_data[:contact])
  when 'conversation.created'
    processor.handle_conversation_created(event_data[:conversation])
  when 'conversation.resolved'
    processor.handle_conversation_resolved(event_data[:conversation])
  end
end
```

---

#### 4.6 Update Setup Job

**File**: `app/jobs/crm/setup_job.rb`

**Location**: Method `create_setup_service` (around line 22)

**Add** GLPI case:
```ruby
def create_setup_service(hook)
  case hook.app_id
  when 'leadsquared'
    Crm::Leadsquared::SetupService.new(hook)
  when 'glpi'
    Crm::Glpi::SetupService.new(hook)
  else
    raise "Unknown CRM integration: #{hook.app_id}"
  end
end
```

---

#### 4.7 Add GLPI Logo

**File**: `public/integrations/glpi.png`

**Action**: Add GLPI logo image (200x200px recommended)

---

### Phase 5: Testing & Refinement (Week 3)

#### 5.1 Unit Tests

**Coverage Target**: > 90%

**Test Files** (all created in previous phases):
- `spec/services/crm/glpi/api/*_spec.rb` - API client tests
- `spec/services/crm/glpi/mappers/*_spec.rb` - Mapper tests
- `spec/services/crm/glpi/*_service_spec.rb` - Service tests

**Run Tests**:
```bash
bundle exec rspec spec/services/crm/glpi/
```

---

#### 5.2 Integration Testing

**Setup Local GLPI**:
```bash
docker run -d --name glpi \
  -p 8080:80 \
  -e GLPI_INSTALL=true \
  diouxx/glpi:latest
```

**Access**: http://localhost:8080
**Default credentials**: glpi/glpi

**Configure GLPI**:
1. Enable API: Setup > General > API
2. Generate App Token
3. Create test user
4. Generate User Token: User Preferences > Remote Access Keys
5. Note Entity ID

**Test Flow**:
1. Create GLPI integration in Chatwoot (via admin UI)
2. Configure with local GLPI credentials
3. Verify setup job runs successfully
4. Create test contact in Chatwoot
5. Verify GLPI User/Contact created
6. Create conversation with contact
7. Verify GLPI Ticket created
8. Add message to conversation
9. Verify followup created (if enabled)
10. Resolve conversation
11. Verify ticket status updated to "Solved"

**Manual Test Checklist**:
- [ ] Integration creation triggers setup job
- [ ] Setup validates credentials
- [ ] Contact sync creates GLPI User
- [ ] Contact sync creates GLPI Contact (when use_contact=true)
- [ ] Duplicate contact detection works
- [ ] Conversation creates ticket with correct requester
- [ ] Ticket name includes conversation display_id
- [ ] Ticket content includes first message
- [ ] Status mapping works for all statuses
- [ ] Priority mapping works
- [ ] Message sync creates followups (when enabled)
- [ ] Conversation resolution updates ticket status
- [ ] Error handling shows user-friendly messages
- [ ] Concurrent contact updates don't create duplicates (mutex test)

---

#### 5.3 Performance Testing

**Scenarios**:

1. **Bulk Contact Sync**
   - Import 100 contacts simultaneously
   - Monitor job queue
   - Verify no duplicate GLPI users created
   - Check processing time per contact

2. **High Conversation Volume**
   - Create 50 conversations simultaneously
   - Verify all tickets created
   - Check for race conditions
   - Monitor Redis mutex usage

3. **Message Throughput**
   - Send 100 messages rapidly
   - Verify followup creation (if enabled)
   - Check for dropped messages

**Performance Metrics**:
- Contact sync: < 2 seconds per contact
- Ticket creation: < 3 seconds per conversation
- Followup creation: < 1 second per message
- Setup job: < 5 seconds

**Load Testing** (optional):
```bash
# Use Sidekiq stats
bundle exec rails console
> Sidekiq::Stats.new

# Monitor Redis
redis-cli monitor | grep CRM_PROCESS_MUTEX
```

---

#### 5.4 Edge Cases & Error Handling

**Test Scenarios**:

1. **Invalid Credentials**
   - Use wrong app_token
   - Expected: Setup fails with user-friendly error
   - Error logged to ChatwootExceptionTracker

2. **Session Expiration During Request**
   - Mock session expiration
   - Expected: Automatic session reinit and retry

3. **Contact Without Email or Phone**
   - Create contact with only name
   - Expected: Skip sync, log warning

4. **GLPI API Timeout**
   - Mock slow response
   - Expected: Timeout after 30s, log error, retry later

5. **Invalid Entity ID**
   - Configure with non-existent entity_id
   - Expected: Setup fails with clear error message

6. **Duplicate Contact Creation**
   - Fire contact.created and contact.updated rapidly
   - Expected: Mutex prevents duplicate GLPI users

7. **Missing Required Fields**
   - Try to create ticket without requester
   - Expected: Error handled, ticket creation retried

8. **GLPI Server Down**
   - Stop GLPI container
   - Expected: Connection error caught, job retries

**Error Logging**:
- All API errors logged with full response
- Stack traces sent to ChatwootExceptionTracker
- User sees generic "sync failed" message (no technical details)

---

### Phase 6: Documentation & Deployment (Week 3)

#### 6.1 Code Documentation

**YARD Comments** for all public methods:

**Example**:
```ruby
# Initializes a GLPI API client with session management
#
# @param api_url [String] The GLPI API base URL (e.g., https://glpi.example.com/apirest.php)
# @param app_token [String] The GLPI application token
# @param user_token [String] The GLPI user token
# @raise [ApiError] If credentials are invalid
# @return [BaseClient] A new GLPI API client instance
def initialize(api_url:, app_token:, user_token:)
  # ...
end
```

**Add to all**:
- API clients
- Mappers
- Services
- Key methods in processor

**Generate Documentation**:
```bash
yard doc app/services/crm/glpi/
```

---

#### 6.2 User Documentation

**Create**: `docs/glpi-integration.md`

**Contents**:

```markdown
# GLPI Integration

## Overview

Connect Chatwoot to your GLPI ticketing system to automatically sync contacts and create tickets from conversations.

## Features

- ✅ Sync Chatwoot contacts to GLPI Users or Contacts
- ✅ Automatically create GLPI tickets from conversations
- ✅ Sync conversation messages as ticket followups
- ✅ Update ticket status when conversations are resolved
- ✅ Bidirectional contact identification

## Prerequisites

- GLPI instance (version 9.5 or higher)
- GLPI API enabled
- Application Token (admin access)
- User Token (for the user who will own tickets)

## Setup Instructions

### 1. Enable GLPI API

1. Log in to GLPI as administrator
2. Navigate to **Setup > General > API**
3. Enable "Enable Rest API"
4. Generate an **Application Token** and save it

### 2. Generate User Token

1. Log in as the user who will own tickets
2. Go to **User Preferences > Remote Access Keys**
3. Click **Add** to generate a new API token
4. Copy the token (shown only once)

### 3. Configure in Chatwoot

1. Go to **Settings > Integrations**
2. Click **GLPI**
3. Fill in the configuration:
   - **API URL**: Your GLPI API endpoint (e.g., `https://glpi.example.com/apirest.php`)
   - **Application Token**: Token from step 1
   - **User Token**: Token from step 2
   - **Entity ID**: (Optional) Leave blank to use default entity
4. Configure options:
   - **Use Contact Instead of User**: Toggle on to sync as GLPI Contacts (off = Users)
   - **Enable Ticket Sync**: Toggle on to create tickets from conversations
   - **Enable Followup Sync**: Toggle on to sync messages as followups
5. Click **Save**

### 4. Verify Connection

After saving, Chatwoot will:
- Validate your credentials
- Test API connectivity
- Fetch entity information

If successful, you'll see "Integration configured successfully."

## How It Works

### Contact Sync

When a contact is created or updated in Chatwoot:
1. Contact syncs to GLPI as User (or Contact if configured)
2. Email and phone number are matched first
3. If not found, a new User/Contact is created
4. GLPI ID is stored in Chatwoot for future updates

### Ticket Creation

When a conversation is created:
1. Contact is synced to GLPI (if not already synced)
2. A new ticket is created with:
   - Name: "Conversation #[display_id]"
   - Content: First message in conversation
   - Requester: The synced GLPI User/Contact
   - Status: New (or Processing if assigned)
   - Priority: Based on conversation priority
3. Ticket ID is stored in conversation metadata

### Message Sync (Optional)

When **Enable Followup Sync** is on:
- Each new message creates a followup on the ticket
- Followup includes sender name and timestamp
- Private messages are marked as private in GLPI

### Status Updates

When a conversation is resolved:
- GLPI ticket status updates to "Solved"

## Field Mapping

### Contact → GLPI User

| Chatwoot | GLPI | Notes |
|----------|------|-------|
| email | \_useremails | Primary identifier |
| phone_number | phone, mobile | Formatted internationally |
| name (first part) | firstname | Split on first space |
| name (last part) | realname | Split on first space |

### Contact → GLPI Contact

| Chatwoot | GLPI | Notes |
|----------|------|-------|
| name | name | Full name |
| name (first part) | firstname | Split on first space |
| email | email | Primary identifier |
| phone_number | phone | Formatted internationally |

### Conversation → GLPI Ticket

| Chatwoot | GLPI | Notes |
|----------|------|-------|
| display_id | name | As "Conversation #123" |
| first message | content | Ticket description |
| status | status | See status mapping below |
| priority | priority | See priority mapping below |
| contact | \_users_id_requester | Linked GLPI User/Contact |

### Status Mapping

| Chatwoot Status | GLPI Status |
|-----------------|-------------|
| open | Processing (2) |
| pending | Pending (4) |
| resolved | Solved (5) |
| bot | New (1) |

### Priority Mapping

| Chatwoot Priority | GLPI Priority |
|-------------------|---------------|
| urgent | Very High (5) |
| high | High (4) |
| medium | Medium (3) |
| low | Low (2) |

## Configuration Options

### Entity ID

- **What**: The GLPI entity to assign tickets to
- **When to use**: Multi-entity GLPI setups
- **Default**: User's default entity

### Use Contact Instead of User

- **What**: Sync Chatwoot contacts as GLPI Contacts instead of Users
- **When to use**: When your workflow uses Contacts for external users
- **Default**: Off (uses Users)

### Enable Ticket Sync

- **What**: Create GLPI tickets from conversations
- **When to use**: Always (core feature)
- **Default**: On

### Enable Followup Sync

- **What**: Sync conversation messages as ticket followups
- **When to use**: When you want full message history in GLPI
- **Caution**: Can create many API calls for long conversations
- **Default**: Off

### Default Ticket Type

- **Options**: Incident (1) or Request (2)
- **Default**: Incident (1)

### Default Category ID

- **What**: Ticket category to assign by default
- **How to find**: Check GLPI Categories setup
- **Default**: None (no category)

## Troubleshooting

### "Invalid credentials" error

- Verify Application Token is correct
- Verify User Token is correct
- Ensure API is enabled in GLPI (Setup > General > API)
- Check tokens haven't expired

### Contacts not syncing

- Check contact has email or phone number
- Check logs: `rails logs | grep GLPI`
- Verify entity permissions

### Tickets not created

- Ensure "Enable Ticket Sync" is on
- Check contact was synced first
- Verify user has permission to create tickets in entity
- Check logs for API errors

### Session expired errors

- Normal behavior - sessions are temporary
- Client automatically reconnects
- If persistent, check GLPI API configuration

### Duplicate contacts

- Should not happen due to mutex locks
- If occurs, check Redis is running
- Verify `CRM_PROCESS_MUTEX` key in Redis

## API Rate Limits

GLPI does not enforce rate limits by default, but:
- Each conversation creates 1-2 API calls (contact + ticket)
- Each message creates 1 API call (if followup sync enabled)
- Sessions are created/destroyed per operation batch

For high-volume usage:
- Consider disabling followup sync
- Monitor GLPI server load

## Security Considerations

- Tokens are encrypted in database
- Session tokens are temporary (destroyed after use)
- API calls use HTTPS (ensure GLPI has valid SSL)
- Tokens have same permissions as user who created them

## Support

For issues:
1. Check Chatwoot logs: `tail -f log/production.log | grep GLPI`
2. Check GLPI API logs: `glpi/files/_log/api.log`
3. Report bug with logs to Chatwoot support
```

---

#### 6.3 Internal Developer Documentation

**Create**: `docs/development/crm-integrations/glpi.md`

**Contents**:
- Architecture overview
- Code structure
- Adding new features guide
- Testing guide
- Debugging guide

---

#### 6.4 Deployment Preparation

**Pre-deployment Checklist**:
- [ ] All tests passing
- [ ] Test coverage > 90%
- [ ] Code reviewed
- [ ] Documentation complete
- [ ] Feature flag ready (`crm_integration`)
- [ ] Logo added
- [ ] Translations added
- [ ] Integration tested on staging

**Rollout Plan**:

**Phase 1: Internal Beta (Week 1)**
- Enable for internal account only
- Test with real GLPI instance
- Monitor logs and performance
- Gather feedback

**Phase 2: Private Beta (Week 2)**
- Enable for 5-10 selected customers
- Provide setup support
- Monitor error rates
- Fix issues

**Phase 3: Public Beta (Week 3)**
- Announce in changelog
- Enable for all accounts (behind feature flag)
- Monitor adoption rate
- Collect feedback

**Phase 4: General Availability (Week 4+)**
- Remove feature flag (or keep for enterprise)
- Add to integration marketplace
- Announce publicly

**Monitoring**:
- Track job success/failure rates
- Monitor API error rates
- Track performance metrics
- Monitor user feedback

---

## File Structure Summary

```
app/
├── services/crm/glpi/
│   ├── setup_service.rb
│   ├── processor_service.rb
│   ├── user_finder_service.rb
│   ├── contact_finder_service.rb
│   ├── api/
│   │   ├── base_client.rb
│   │   ├── user_client.rb
│   │   ├── contact_client.rb
│   │   ├── ticket_client.rb
│   │   └── followup_client.rb
│   └── mappers/
│       ├── contact_mapper.rb
│       ├── conversation_mapper.rb
│       └── message_mapper.rb
├── models/integrations/
│   └── hook.rb (update line ~110)
├── listeners/
│   └── hook_listener.rb (update line ~58)
└── jobs/
    ├── hook_job.rb (update line ~40, add methods ~100)
    └── crm/setup_job.rb (update line ~22)

spec/
└── services/crm/glpi/
    ├── setup_service_spec.rb
    ├── processor_service_spec.rb
    ├── user_finder_service_spec.rb
    ├── contact_finder_service_spec.rb
    ├── api/
    │   ├── base_client_spec.rb
    │   ├── user_client_spec.rb
    │   ├── contact_client_spec.rb
    │   ├── ticket_client_spec.rb
    │   └── followup_client_spec.rb
    └── mappers/
        ├── contact_mapper_spec.rb
        ├── conversation_mapper_spec.rb
        └── message_mapper_spec.rb

config/
├── integration/
│   └── apps.yml (add glpi block)
└── locales/
    └── en.yml (add integration_apps.glpi)

public/
└── integrations/
    └── glpi.png

docs/
├── glpi-integration.md
└── development/crm-integrations/
    └── glpi.md
```

## Success Criteria

- ✅ Contact sync creates/updates GLPI Users or Contacts
- ✅ Email/phone matching prevents duplicates
- ✅ Conversation creation generates GLPI Tickets
- ✅ Messages sync as ITILFollowups (when enabled)
- ✅ Conversation resolution updates ticket status to Solved
- ✅ No race conditions (mutex locks working)
- ✅ Session management reliable (no token leaks)
- ✅ Proper error handling and logging
- ✅ Test coverage > 90%
- ✅ User documentation complete
- ✅ Successfully tested with real GLPI instance

## Risk Mitigation

### Risk: Session Token Leaks
**Mitigation**: Always use `with_session` wrapper, ensure cleanup in `ensure` block

### Risk: Race Conditions on Contact Sync
**Mitigation**: Redis mutex locks (exact pattern from LeadSquared)

### Risk: API Rate Limiting
**Mitigation**: Background jobs, batch operations, optional followup sync

### Risk: GLPI Version Compatibility
**Mitigation**: Test with GLPI 9.5, 10.0, document minimum version

### Risk: Network Timeouts
**Mitigation**: Configure HTTParty timeouts, implement retry logic

### Risk: Invalid Data Mapping
**Mitigation**: Comprehensive mapper tests, `.compact` to remove nil values

## Timeline Summary

### Week 1: Foundation
- Days 1-2: API clients (base, user, contact, ticket, followup)
- Days 3-4: Unit tests for API clients
- Day 5: Code review and refinement

### Week 2: Core Logic
- Days 1-2: Mappers (contact, conversation, message)
- Days 2-3: Services (setup, finders, processor)
- Days 4-5: Service tests

### Week 3: Integration
- Days 1-2: Configuration updates (apps.yml, models, listeners, jobs)
- Day 3: Integration testing with local GLPI
- Day 4: Performance testing and edge cases
- Day 5: Documentation and deployment prep

## Next Steps

1. ✅ Review and approve this implementation plan
2. Set up development environment with GLPI Docker instance
3. Create feature branch: `feature/crm-integration-glpi`
4. Begin Phase 1: Implement BaseClient
5. Follow phases sequentially with tests at each step
6. Request code reviews at end of each phase
7. Deploy to staging after Phase 5
8. Begin beta rollout after Phase 6

## Dependencies

- Ruby gems: `httparty`, `telephone_number` (already in Gemfile)
- Redis: For mutex locks (already available)
- Sidekiq: For background jobs (already available)
- GLPI API: Version 9.5+ recommended

## References

- GLPI API Documentation: https://glpi-project.org/documentation/
- LeadSquared Integration: `app/services/crm/leadsquared/`
- Base Processor Service: `app/services/crm/base_processor_service.rb`
- Hook Model: `app/models/integrations/hook.rb`
- Integration Apps Config: `config/integration/apps.yml`

---

**Plan Version**: 1.0
**Last Updated**: 2025-01-05
**Author**: Claude Code
**Status**: Ready for Implementation
