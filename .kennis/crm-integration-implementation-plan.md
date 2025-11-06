# CRM Integration Implementation Plan
## GLPI and Krayin CRM Integration for Chatwoot

**Document Version:** 1.0
**Date:** 2025-11-05
**Based on:** LeadSquared Integration Pattern

---

## Table of Contents

1. [Overview](#overview)
2. [GLPI Integration](#glpi-integration)
3. [Krayin CRM Integration](#krayin-crm-integration)
4. [Custom Attributes for Chatwoot](#custom-attributes-for-chatwoot)
5. [Implementation Timeline](#implementation-timeline)
6. [Testing Strategy](#testing-strategy)

---

## Overview

### Reference Implementation
The LeadSquared integration (`app/services/crm/leadsquared/`) serves as the blueprint for both GLPI and Krayin CRM integrations.

### Core Architecture Pattern

```
Components:
├── Configuration (config/integration/apps.yml)
├── Hook Model (app/models/integrations/hook.rb)
├── Setup Service (app/services/crm/{crm}/setup_service.rb)
├── Processor Service (app/services/crm/{crm}/processor_service.rb)
├── API Clients (app/services/crm/{crm}/api/)
├── Mappers (app/services/crm/{crm}/mappers/)
├── Event Listeners (app/listeners/hook_listener.rb)
└── Background Jobs (app/jobs/hook_job.rb, app/jobs/crm/setup_job.rb)
```

### Supported Events
- `contact.created`
- `contact.updated`
- `conversation.created`
- `conversation.resolved`

---

## GLPI Integration

### 1. Business Requirements

**Primary Goals:**
- Sync Chatwoot contacts to GLPI Users/Contacts
- Create GLPI Tickets from Chatwoot conversations
- Sync conversation messages as ticket followups
- Bidirectional sync for ticket status updates

**Use Cases:**
1. **IT Support Integration**: Convert support conversations into ITIL tickets
2. **Asset Management**: Link conversations to GLPI assets/computers
3. **User Management**: Keep contact information synchronized
4. **SLA Tracking**: Leverage GLPI's SLA features for conversations

---

### 2. GLPI API Overview

**Authentication:**
- Session-based authentication
- Requires: `app_token` and `user_token`
- Must initialize session before requests: `POST /initSession`
- Must kill session after requests: `GET /killSession`

**Key Endpoints:**
```
POST   /initSession              - Initialize API session
GET    /killSession              - Terminate API session
GET    /getFullSession           - Get session info
GET    /getActiveProfile         - Get active profile

GET    /User                     - List users
GET    /User/:id                 - Get user
POST   /User                     - Create user
PUT    /User/:id                 - Update user

GET    /Ticket                   - List tickets
GET    /Ticket/:id               - Get ticket
POST   /Ticket                   - Create ticket
PUT    /Ticket/:id               - Update ticket

GET    /ITILFollowup             - List followups
POST   /ITILFollowup             - Create followup
GET    /TicketTask               - List ticket tasks
POST   /TicketTask               - Create ticket task

GET    /Entity                   - List entities
```

---

### 3. Data Mapping

#### Contact → GLPI User/Contact

| Chatwoot Contact | GLPI User Field | GLPI Contact Field | Notes |
|------------------|-----------------|-------------------|-------|
| `name` | `realname` | `firstname` | Split name if needed |
| `email` | `email` (unique) | `email` | Primary identifier |
| `phone_number` | `phone` | `phone` | Format as needed |
| `phone_number` | `mobile` | `mobile` | Mobile number |
| `additional_attributes` | `comment` | `comment` | JSON serialized |
| N/A | `name` (username) | N/A | Generated from email |
| N/A | `is_active` = 1 | `is_deleted` = 0 | Active by default |

**Decision Point:** User vs Contact
- **Use Contact** if: Only need basic info, no login required
- **Use User** if: Need to assign tickets, track activity

#### Conversation → GLPI Ticket

| Chatwoot Conversation | GLPI Ticket Field | Notes |
|----------------------|-------------------|-------|
| `display_id` | `name` | e.g., "Chatwoot #1234" |
| First message content | `content` | Ticket description |
| `inbox.name` | `itilcategories_id` | Map to category |
| `created_at` | `date` | Creation timestamp |
| `status` (open/resolved) | `status` (1-6) | Map statuses |
| `priority` | `priority` (1-6) | Map priorities |
| `contact` | `users_id_recipient` | Requester |
| `assignee` | `users_id_tech` | Technician assigned |
| N/A | `type` | 1=Incident, 2=Request |
| N/A | `entities_id` | Default entity ID |

**Status Mapping:**
```ruby
CHATWOOT_TO_GLPI_STATUS = {
  'open' => 2,      # Processing (assigned)
  'pending' => 4,   # Pending
  'resolved' => 5,  # Solved
  'bot' => 1        # New
}.freeze

GLPI_TO_CHATWOOT_STATUS = {
  1 => 'open',      # New
  2 => 'open',      # Processing (assigned)
  3 => 'open',      # Processing (planned)
  4 => 'pending',   # Pending
  5 => 'resolved',  # Solved
  6 => 'resolved'   # Closed
}.freeze
```

**Priority Mapping:**
```ruby
CHATWOOT_TO_GLPI_PRIORITY = {
  'urgent' => 5,    # Very high
  'high' => 4,      # High
  'medium' => 3,    # Medium
  'low' => 2,       # Low
  nil => 3          # Default: Medium
}.freeze
```

#### Messages → GLPI ITILFollowup

| Chatwoot Message | GLPI ITILFollowup Field | Notes |
|------------------|------------------------|-------|
| `content` | `content` | Message text |
| `created_at` | `date` | Timestamp |
| `sender.name` | `users_id` | Map to GLPI user |
| `message_type` (incoming/outgoing) | `is_private` | 0=public, 1=private |
| N/A | `tickets_id` | Parent ticket ID |
| N/A | `requesttypes_id` | Request source (e.g., Chat=10) |

---

### 4. File Structure

```
app/services/crm/glpi/
├── setup_service.rb
├── processor_service.rb
├── ticket_finder_service.rb
├── user_finder_service.rb
├── api/
│   ├── base_client.rb           # Session management, auth
│   ├── user_client.rb            # User CRUD operations
│   ├── contact_client.rb         # Contact CRUD operations
│   ├── ticket_client.rb          # Ticket CRUD operations
│   ├── followup_client.rb        # Followup CRUD operations
│   └── entity_client.rb          # Entity operations
└── mappers/
    ├── contact_mapper.rb         # Contact → GLPI User/Contact
    ├── conversation_mapper.rb    # Conversation → GLPI Ticket
    └── message_mapper.rb         # Message → GLPI Followup

spec/services/crm/glpi/
├── setup_service_spec.rb
├── processor_service_spec.rb
├── ticket_finder_service_spec.rb
├── user_finder_service_spec.rb
├── api/
│   ├── base_client_spec.rb
│   ├── user_client_spec.rb
│   ├── ticket_client_spec.rb
│   └── followup_client_spec.rb
└── mappers/
    ├── contact_mapper_spec.rb
    ├── conversation_mapper_spec.rb
    └── message_mapper_spec.rb
```

---

### 5. Configuration

#### `config/integration/apps.yml`

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
    {
      'type': 'object',
      'properties':
        {
          'api_url': { 'type': 'string', 'format': 'uri' },
          'app_token': { 'type': 'string' },
          'user_token': { 'type': 'string' },
          'entity_id': { 'type': 'integer' },
          'use_contact': { 'type': 'boolean' },
          'default_ticket_type': { 'type': 'integer', 'enum': [1, 2] },
          'default_category_id': { 'type': 'integer' },
          'request_source_id': { 'type': 'integer' },
          'enable_ticket_sync': { 'type': 'boolean' },
          'enable_followup_sync': { 'type': 'boolean' },
          'enable_bidirectional_sync': { 'type': 'boolean' },
          'sync_interval_minutes': { 'type': 'integer', 'minimum': 5 }
        },
      'required': ['api_url', 'app_token', 'user_token']
    }
  settings_form_schema:
    [
      {
        'label': 'GLPI URL',
        'type': 'text',
        'name': 'api_url',
        'placeholder': 'https://glpi.example.com/apirest.php',
        'validation': 'required|url',
        'help': 'Your GLPI instance API URL (must end with /apirest.php)'
      },
      {
        'label': 'App Token',
        'type': 'text',
        'name': 'app_token',
        'validation': 'required',
        'help': 'GLPI Application Token (Setup > General > API)'
      },
      {
        'label': 'User Token',
        'type': 'password',
        'name': 'user_token',
        'validation': 'required',
        'help': 'GLPI User Token (My Settings > Remote access keys)'
      },
      {
        'label': 'Entity ID',
        'type': 'number',
        'name': 'entity_id',
        'help': 'Default GLPI Entity ID (leave empty for root entity)'
      },
      {
        'label': 'Use GLPI Contact instead of User',
        'type': 'checkbox',
        'name': 'use_contact',
        'help': 'Enable to sync to Contact entity instead of User'
      },
      {
        'label': 'Default Ticket Type',
        'type': 'select',
        'name': 'default_ticket_type',
        'default': 1,
        'options': [
          { 'label': 'Incident', 'value': 1 },
          { 'label': 'Request', 'value': 2 }
        ]
      },
      {
        'label': 'Default Category ID',
        'type': 'number',
        'name': 'default_category_id',
        'help': 'GLPI ITIL Category ID for new tickets'
      },
      {
        'label': 'Request Source ID',
        'type': 'number',
        'name': 'request_source_id',
        'default': 10,
        'help': 'Request source (10=Chat by default)'
      },
      {
        'label': 'Enable Ticket Sync',
        'type': 'checkbox',
        'name': 'enable_ticket_sync',
        'help': 'Create GLPI tickets from conversations'
      },
      {
        'label': 'Enable Followup Sync',
        'type': 'checkbox',
        'name': 'enable_followup_sync',
        'help': 'Sync messages as ticket followups'
      },
      {
        'label': 'Enable Bidirectional Sync',
        'type': 'checkbox',
        'name': 'enable_bidirectional_sync',
        'help': 'Sync GLPI ticket updates back to Chatwoot'
      },
      {
        'label': 'Sync Interval (minutes)',
        'type': 'number',
        'name': 'sync_interval_minutes',
        'default': 15,
        'help': 'Interval for pulling GLPI updates (min: 5 minutes)'
      }
    ]
  visible_properties:
    [
      'api_url',
      'entity_id',
      'use_contact',
      'default_ticket_type',
      'enable_ticket_sync',
      'enable_followup_sync',
      'enable_bidirectional_sync'
    ]
```

---

### 6. Implementation Details

#### 6.1 Base Client (`app/services/crm/glpi/api/base_client.rb`)

```ruby
class Crm::Glpi::Api::BaseClient
  include HTTParty

  class ApiError < StandardError
    attr_reader :code, :response

    def initialize(message = nil, code = nil, response = nil)
      @code = code
      @response = response
      super(message)
    end
  end

  def initialize(api_url, app_token, user_token)
    @api_url = api_url.chomp('/')
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

  def get(path, params = {})
    with_session do
      response = self.class.get(
        "#{@api_url}/#{path}",
        query: params,
        headers: headers
      )
      handle_response(response)
    end
  end

  def post(path, body = {}, params = {})
    with_session do
      response = self.class.post(
        "#{@api_url}/#{path}",
        query: params,
        body: body.to_json,
        headers: headers
      )
      handle_response(response)
    end
  end

  def put(path, body = {}, params = {})
    with_session do
      response = self.class.put(
        "#{@api_url}/#{path}",
        query: params,
        body: body.to_json,
        headers: headers
      )
      handle_response(response)
    end
  end

  private

  def init_session
    response = self.class.get(
      "#{@api_url}/initSession",
      headers: {
        'Content-Type' => 'application/json',
        'App-Token' => @app_token,
        'Authorization' => "user_token #{@user_token}"
      }
    )

    if response.success?
      @session_token = response.parsed_response['session_token']
    else
      raise ApiError.new("Failed to initialize GLPI session: #{response.body}", response.code, response)
    end
  end

  def kill_session
    return unless @session_token

    self.class.get(
      "#{@api_url}/killSession",
      headers: headers
    )
    @session_token = nil
  rescue StandardError => e
    Rails.logger.warn "Failed to kill GLPI session: #{e.message}"
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'App-Token' => @app_token,
      'Session-Token' => @session_token
    }
  end

  def handle_response(response)
    case response.code
    when 200..299
      response.parsed_response
    else
      error_message = "GLPI API error: #{response.code} - #{response.body}"
      Rails.logger.error error_message
      raise ApiError.new(error_message, response.code, response)
    end
  end
end
```

#### 6.2 Setup Service (`app/services/crm/glpi/setup_service.rb`)

```ruby
class Crm::Glpi::SetupService
  def initialize(hook)
    @hook = hook
    @api_url = hook.settings['api_url']
    @app_token = hook.settings['app_token']
    @user_token = hook.settings['user_token']

    @client = Crm::Glpi::Api::BaseClient.new(@api_url, @app_token, @user_token)
  end

  def setup
    validate_connection
    fetch_entity_info
    setup_custom_fields if needed
  rescue Crm::Glpi::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
    Rails.logger.error "GLPI API error in setup: #{e.message}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
    Rails.logger.error "Error during GLPI setup: #{e.message}"
  end

  private

  def validate_connection
    # Test connection and get active profile
    profile = @client.get('getActiveProfile')
    raise StandardError, 'No active profile found' if profile.blank?

    # Store profile info
    update_hook_settings({ glpi_profile: profile })
  end

  def fetch_entity_info
    entity_id = @hook.settings['entity_id'] || 0
    entities = @client.get('Entity')

    # Find or validate entity
    entity = entities.find { |e| e['id'] == entity_id }

    if entity.nil?
      Rails.logger.warn "Entity ID #{entity_id} not found, using root entity"
      entity_id = 0
    end

    update_hook_settings({ entity_id: entity_id })
  end

  def update_hook_settings(params)
    @hook.settings = @hook.settings.merge(params)
    @hook.save!
  end
end
```

#### 6.3 Processor Service (`app/services/crm/glpi/processor_service.rb`)

```ruby
class Crm::Glpi::ProcessorService < Crm::BaseProcessorService
  def self.crm_name
    'glpi'
  end

  def initialize(hook)
    super(hook)
    @api_url = hook.settings['api_url']
    @app_token = hook.settings['app_token']
    @user_token = hook.settings['user_token']
    @entity_id = hook.settings['entity_id'] || 0
    @use_contact = hook.settings['use_contact'] || false

    @allow_ticket = hook.settings['enable_ticket_sync']
    @allow_followup = hook.settings['enable_followup_sync']

    # Initialize API clients
    @base_client = Crm::Glpi::Api::BaseClient.new(@api_url, @app_token, @user_token)

    if @use_contact
      @contact_client = Crm::Glpi::Api::ContactClient.new(@api_url, @app_token, @user_token)
      @contact_finder = Crm::Glpi::ContactFinderService.new(@contact_client)
    else
      @user_client = Crm::Glpi::Api::UserClient.new(@api_url, @app_token, @user_token)
      @user_finder = Crm::Glpi::UserFinderService.new(@user_client)
    end

    @ticket_client = Crm::Glpi::Api::TicketClient.new(@api_url, @app_token, @user_token)
    @followup_client = Crm::Glpi::Api::FollowupClient.new(@api_url, @app_token, @user_token)
  end

  def handle_contact(contact)
    contact.reload
    unless identifiable_contact?(contact)
      Rails.logger.info("Contact not identifiable. Skipping handle_contact for ##{contact.id}")
      return
    end

    stored_id = get_external_id(contact)
    create_or_update_contact(contact, stored_id)
  end

  def handle_conversation_created(conversation)
    return unless @allow_ticket

    create_ticket_from_conversation(conversation)
  end

  def handle_conversation_resolved(conversation)
    return unless @allow_ticket

    update_ticket_status(conversation, 'resolved')
  end

  private

  def create_or_update_contact(contact, external_id)
    if @use_contact
      contact_data = Crm::Glpi::Mappers::ContactMapper.map_to_contact(contact, @entity_id)

      if external_id.present?
        @contact_client.update_contact(contact_data, external_id)
      else
        new_id = @contact_client.create_contact(contact_data)
        store_external_id(contact, new_id)
      end
    else
      user_data = Crm::Glpi::Mappers::ContactMapper.map_to_user(contact, @entity_id)

      if external_id.present?
        @user_client.update_user(user_data, external_id)
      else
        new_id = @user_client.create_user(user_data)
        store_external_id(contact, new_id)
      end
    end
  rescue Crm::Glpi::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "GLPI API error processing contact: #{e.message}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "Error processing contact in GLPI: #{e.message}"
  end

  def create_ticket_from_conversation(conversation)
    contact_id = get_contact_id(conversation.contact)
    return if contact_id.blank?

    ticket_data = Crm::Glpi::Mappers::ConversationMapper.map_to_ticket(
      conversation,
      contact_id,
      @entity_id,
      @hook.settings
    )

    ticket_id = @ticket_client.create_ticket(ticket_data)
    return if ticket_id.blank?

    metadata = { 'ticket_id' => ticket_id }
    store_conversation_metadata(conversation, metadata)

    # Create initial followup with first message if enabled
    if @allow_followup && conversation.messages.any?
      create_followup_from_messages(conversation, ticket_id)
    end
  rescue Crm::Glpi::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "GLPI API error creating ticket: #{e.message}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "Error creating ticket in GLPI: #{e.message}"
  end

  def create_followup_from_messages(conversation, ticket_id)
    conversation.messages.chat.each do |message|
      followup_data = Crm::Glpi::Mappers::MessageMapper.map_to_followup(
        message,
        ticket_id,
        @hook.settings
      )

      @followup_client.create_followup(followup_data)
    end
  end

  def update_ticket_status(conversation, status)
    ticket_id = get_ticket_id(conversation)
    return if ticket_id.blank?

    glpi_status = status_to_glpi(status)
    @ticket_client.update_ticket({ 'status' => glpi_status }, ticket_id)
  rescue Crm::Glpi::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "GLPI API error updating ticket status: #{e.message}"
  end

  def get_contact_id(contact)
    contact.reload

    unless identifiable_contact?(contact)
      Rails.logger.info("Contact not identifiable. Skipping for ##{contact.id}")
      return nil
    end

    contact_id = if @use_contact
                   @contact_finder.find_or_create(contact, @entity_id)
                 else
                   @user_finder.find_or_create(contact, @entity_id)
                 end

    return nil if contact_id.blank?

    store_external_id(contact, contact_id) unless get_external_id(contact)

    contact_id
  end

  def get_ticket_id(conversation)
    conversation.reload
    conversation.additional_attributes&.dig('glpi', 'ticket_id')
  end

  def status_to_glpi(status)
    {
      'open' => 2,
      'pending' => 4,
      'resolved' => 5,
      'bot' => 1
    }[status] || 2
  end
end
```

---

### 7. Custom Attributes for Chatwoot (GLPI)

#### Contact Attributes

```ruby
# Migration: Add GLPI-specific custom attributes
class AddGlpiContactAttributes < ActiveRecord::Migration[7.0]
  def change
    # These would be stored in contact.custom_attributes JSONB field

    # Example custom attributes:
    # {
    #   "glpi_user_id": 123,
    #   "glpi_contact_id": 456,
    #   "glpi_entity_id": 0,
    #   "glpi_location": "Building A, Floor 3",
    #   "glpi_department": "IT Support",
    #   "glpi_user_category": "Technician",
    #   "glpi_phone2": "+1234567890",
    #   "glpi_registration_number": "EMP-001",
    #   "glpi_sync_enabled": true,
    #   "glpi_last_sync_at": "2025-11-05T10:00:00Z"
    # }
  end
end
```

**Suggested Custom Attribute Definitions:**

```yaml
# config/custom_attributes/glpi_contact.yml
glpi_contact_attributes:
  - attribute_key: glpi_user_id
    attribute_display_name: GLPI User ID
    attribute_display_type: number
    attribute_description: Linked GLPI User ID
    attribute_model: contact_attribute

  - attribute_key: glpi_entity_id
    attribute_display_name: GLPI Entity
    attribute_display_type: number
    attribute_description: GLPI Entity ID
    attribute_model: contact_attribute

  - attribute_key: glpi_location
    attribute_display_name: GLPI Location
    attribute_display_type: text
    attribute_description: Physical location in GLPI
    attribute_model: contact_attribute

  - attribute_key: glpi_department
    attribute_display_name: Department
    attribute_display_type: text
    attribute_description: Department/Group in GLPI
    attribute_model: contact_attribute

  - attribute_key: glpi_user_category
    attribute_display_name: User Category
    attribute_display_type: list
    attribute_values: ["End User", "Technician", "Administrator", "VIP"]
    attribute_model: contact_attribute

  - attribute_key: glpi_registration_number
    attribute_display_name: Employee/Registration Number
    attribute_display_type: text
    attribute_description: GLPI registration number
    attribute_model: contact_attribute
```

#### Conversation Attributes

```yaml
# config/custom_attributes/glpi_conversation.yml
glpi_conversation_attributes:
  - attribute_key: glpi_ticket_id
    attribute_display_name: GLPI Ticket ID
    attribute_display_type: number
    attribute_description: Linked GLPI Ticket ID
    attribute_model: conversation_attribute

  - attribute_key: glpi_ticket_url
    attribute_display_name: GLPI Ticket URL
    attribute_display_type: link
    attribute_description: Direct link to GLPI ticket
    attribute_model: conversation_attribute

  - attribute_key: glpi_ticket_type
    attribute_display_name: Ticket Type
    attribute_display_type: list
    attribute_values: ["Incident", "Request"]
    attribute_model: conversation_attribute

  - attribute_key: glpi_category
    attribute_display_name: ITIL Category
    attribute_display_type: text
    attribute_description: GLPI ticket category
    attribute_model: conversation_attribute

  - attribute_key: glpi_urgency
    attribute_display_name: Urgency
    attribute_display_type: list
    attribute_values: ["Very Low", "Low", "Medium", "High", "Very High"]
    attribute_model: conversation_attribute

  - attribute_key: glpi_impact
    attribute_display_name: Impact
    attribute_display_type: list
    attribute_values: ["Very Low", "Low", "Medium", "High", "Very High"]
    attribute_model: conversation_attribute

  - attribute_key: glpi_sla_ttr
    attribute_display_name: SLA Time to Resolve
    attribute_display_type: date
    attribute_description: GLPI SLA deadline
    attribute_model: conversation_attribute

  - attribute_key: glpi_linked_assets
    attribute_display_name: Linked Assets
    attribute_display_type: text
    attribute_description: Comma-separated asset IDs
    attribute_model: conversation_attribute
```

---

### 8. Event Handling

#### Update `app/listeners/hook_listener.rb`

```ruby
# Add to supported_events_map
def supported_hook_event?(hook, event_name)
  # ... existing code ...

  supported_events_map = {
    # ... existing mappings ...
    'glpi' => ['contact.updated', 'conversation.created', 'conversation.resolved']
  }

  # ... rest of method ...
end
```

#### Update `app/jobs/hook_job.rb`

```ruby
def perform(hook, event_name, event_data = {})
  # ... existing code ...

  case hook.app_id
  # ... existing cases ...
  when 'glpi'
    process_glpi_integration_with_lock(hook, event_name, event_data)
  end
end

private

def process_glpi_integration_with_lock(hook, event_name, event_data)
  valid_event_names = ['contact.updated', 'conversation.created', 'conversation.resolved']
  return unless valid_event_names.include?(event_name)
  return unless hook.feature_allowed?

  key = format(::Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
  with_lock(key) do
    process_glpi_integration(hook, event_name, event_data)
  end
end

def process_glpi_integration(hook, event_name, event_data)
  processor = Crm::Glpi::ProcessorService.new(hook)

  case event_name
  when 'contact.updated'
    processor.handle_contact(event_data[:contact])
  when 'conversation.created'
    processor.handle_conversation_created(event_data[:conversation])
  when 'conversation.resolved'
    processor.handle_conversation_resolved(event_data[:conversation])
  end
end
```

#### Update `app/jobs/crm/setup_job.rb`

```ruby
def create_setup_service(hook)
  case hook.app_id
  # ... existing cases ...
  when 'glpi'
    Crm::Glpi::SetupService.new(hook)
  # ... rest of cases ...
  end
end
```

#### Update `app/models/integrations/hook.rb`

```ruby
def crm_integration?
  %w[leadsquared glpi].include?(app_id)
end
```

---

### 9. Bidirectional Sync (Optional Advanced Feature)

For syncing GLPI updates back to Chatwoot:

```ruby
# app/jobs/crm/glpi/sync_job.rb
class Crm::Glpi::SyncJob < ApplicationJob
  queue_as :low

  def perform(hook_id)
    hook = Integrations::Hook.find_by(id: hook_id)
    return unless hook&.enabled?
    return unless hook.settings['enable_bidirectional_sync']

    Crm::Glpi::BidirectionalSyncService.new(hook).sync_updates
  end
end

# Schedule with whenever gem or sidekiq-scheduler
# Every 15 minutes for each GLPI hook
```

---

### 10. Testing Checklist

- [ ] Unit tests for all API clients
- [ ] Unit tests for mappers
- [ ] Integration tests for setup service
- [ ] Integration tests for processor service
- [ ] Test session management (init/kill)
- [ ] Test error handling and retries
- [ ] Test mutex locks for race conditions
- [ ] Test bidirectional sync
- [ ] Manual E2E testing with real GLPI instance

---

## Krayin CRM Integration

### 1. Business Requirements

**Primary Goals:**
- Sync Chatwoot contacts to Krayin Leads/Persons
- Create Krayin Activities from conversations
- Track lead pipeline and sales stages
- Enable sales team workflows

**Use Cases:**
1. **Lead Management**: Convert conversations into qualified leads
2. **Sales Pipeline**: Track conversation-to-sale journey
3. **Activity Tracking**: Log all customer interactions
4. **Person/Organization Management**: Sync contact hierarchy

---

### 2. Krayin API Overview

**Authentication:**
- Token-based authentication (simpler than GLPI)
- Header: `Authorization: Bearer {token}`
- No session management required

**Key Endpoints:**
```
# Authentication
POST   /api/v1/login             - Get auth token

# Leads
GET    /api/v1/leads             - List leads
GET    /api/v1/leads/:id         - Get lead
POST   /api/v1/leads             - Create lead
PUT    /api/v1/leads/:id         - Update lead
DELETE /api/v1/leads/:id         - Delete lead

# Persons
GET    /api/v1/persons           - List persons
GET    /api/v1/persons/:id       - Get person
POST   /api/v1/persons           - Create person
PUT    /api/v1/persons/:id       - Update person

# Organizations
GET    /api/v1/organizations     - List organizations
POST   /api/v1/organizations     - Create organization

# Activities
GET    /api/v1/activities        - List activities
GET    /api/v1/activities/:id    - Get activity
POST   /api/v1/activities        - Create activity
PUT    /api/v1/activities/:id    - Update activity

# Products (optional)
GET    /api/v1/products          - List products

# Pipelines & Stages
GET    /api/v1/pipelines         - List pipelines
GET    /api/v1/stages            - List stages
```

**Note:** Krayin API documentation may be limited. You might need to:
1. Check Laravel routes: `php artisan route:list --path=api`
2. Review controller code in `packages/Webkul/RestApi/`
3. Create custom endpoints via Krayin package if needed

---

### 3. Data Mapping

#### Contact → Krayin Person/Lead

| Chatwoot Contact | Krayin Person | Krayin Lead | Notes |
|------------------|---------------|-------------|-------|
| `name` | `name` | `title` | Person name / Lead title |
| `email` | `emails[0].value` | `person.emails[0].value` | Primary email |
| `phone_number` | `contact_numbers[0].value` | `person.contact_numbers[0].value` | Primary phone |
| `additional_attributes.company` | `organization_id` | `organization_id` | Link to org |
| `additional_attributes.job_title` | `job_title` | N/A | Person's role |
| `additional_attributes` | `description` | `description` | JSON or formatted text |
| N/A | N/A | `lead_value` | Potential value |
| N/A | N/A | `lead_pipeline_id` | Pipeline assignment |
| N/A | N/A | `lead_pipeline_stage_id` | Current stage |
| N/A | N/A | `lead_source_id` | Source = Chatwoot |

**Strategy:**
- Create **Person** first (contains contact info)
- Create **Lead** linked to Person (contains sales data)
- Store both `person_id` and `lead_id` in contact's external IDs

#### Conversation → Krayin Activity

| Chatwoot Conversation | Krayin Activity | Notes |
|----------------------|-----------------|-------|
| `display_id` | `title` | e.g., "Conversation #1234" |
| First message | `comment` | Activity description |
| `created_at` | `schedule_from` | Start time |
| `updated_at` | `schedule_to` | End time |
| `inbox.name` | `type` | Call/Meeting/Chat |
| `assignee` | `user_id` | Assigned user |
| `contact` | `participants` | Link to persons |
| N/A | `is_done` | Sync with resolved status |
| N/A | `location` | Optional |

**Activity Types:**
- Chat (for messaging conversations)
- Call (for voice channels)
- Meeting (for scheduled interactions)

#### Conversation → Krayin Lead Stage Update

When conversation status changes, update lead stage:

```ruby
CONVERSATION_STATUS_TO_LEAD_STAGE = {
  'open' => 'Contact Made',      # or first stage
  'pending' => 'Follow Up',       # waiting on customer
  'resolved' => 'Qualified'       # or appropriate stage
}.freeze
```

---

### 4. File Structure

```
app/services/crm/krayin/
├── setup_service.rb
├── processor_service.rb
├── lead_finder_service.rb
├── person_finder_service.rb
├── api/
│   ├── base_client.rb           # Token auth, base requests
│   ├── lead_client.rb            # Lead CRUD
│   ├── person_client.rb          # Person CRUD
│   ├── organization_client.rb    # Organization CRUD
│   ├── activity_client.rb        # Activity CRUD
│   └── pipeline_client.rb        # Pipeline/Stage operations
└── mappers/
    ├── contact_mapper.rb         # Contact → Person + Lead
    ├── conversation_mapper.rb    # Conversation → Activity
    └── message_mapper.rb         # Messages → Activity comments

spec/services/crm/krayin/
├── setup_service_spec.rb
├── processor_service_spec.rb
├── lead_finder_service_spec.rb
├── person_finder_service_spec.rb
├── api/
│   ├── base_client_spec.rb
│   ├── lead_client_spec.rb
│   ├── person_client_spec.rb
│   └── activity_client_spec.rb
└── mappers/
    ├── contact_mapper_spec.rb
    ├── conversation_mapper_spec.rb
    └── message_mapper_spec.rb
```

---

### 5. Configuration

#### `config/integration/apps.yml`

```yaml
krayin:
  id: krayin
  feature_flag: crm_integration
  logo: krayin.png
  i18n_key: krayin
  action: /krayin
  hook_type: account
  allow_multiple_hooks: false
  settings_json_schema:
    {
      'type': 'object',
      'properties':
        {
          'api_url': { 'type': 'string', 'format': 'uri' },
          'api_token': { 'type': 'string' },
          'default_pipeline_id': { 'type': 'integer' },
          'default_stage_id': { 'type': 'integer' },
          'lead_source_id': { 'type': 'integer' },
          'create_person': { 'type': 'boolean' },
          'create_lead': { 'type': 'boolean' },
          'enable_activity_sync': { 'type': 'boolean' },
          'activity_type': { 'type': 'string', 'enum': ['call', 'meeting', 'lunch', 'chat'] },
          'default_lead_value': { 'type': 'number' },
          'auto_qualify_on_resolved': { 'type': 'boolean' },
          'sync_to_organization': { 'type': 'boolean' }
        },
      'required': ['api_url', 'api_token']
    }
  settings_form_schema:
    [
      {
        'label': 'Krayin API URL',
        'type': 'text',
        'name': 'api_url',
        'placeholder': 'https://crm.example.com/api/v1',
        'validation': 'required|url',
        'help': 'Your Krayin CRM API base URL'
      },
      {
        'label': 'API Token',
        'type': 'password',
        'name': 'api_token',
        'validation': 'required',
        'help': 'Krayin API authentication token'
      },
      {
        'label': 'Default Pipeline ID',
        'type': 'number',
        'name': 'default_pipeline_id',
        'help': 'Pipeline ID for new leads (leave empty for default)'
      },
      {
        'label': 'Default Stage ID',
        'type': 'number',
        'name': 'default_stage_id',
        'help': 'Initial stage for new leads'
      },
      {
        'label': 'Lead Source ID',
        'type': 'number',
        'name': 'lead_source_id',
        'help': 'Source ID representing Chatwoot'
      },
      {
        'label': 'Create Person Records',
        'type': 'checkbox',
        'name': 'create_person',
        'default': true,
        'help': 'Create Person records in Krayin'
      },
      {
        'label': 'Create Lead Records',
        'type': 'checkbox',
        'name': 'create_lead',
        'default': true,
        'help': 'Create Lead records in Krayin'
      },
      {
        'label': 'Sync Activities',
        'type': 'checkbox',
        'name': 'enable_activity_sync',
        'help': 'Create activities from conversations'
      },
      {
        'label': 'Activity Type',
        'type': 'select',
        'name': 'activity_type',
        'default': 'chat',
        'options': [
          { 'label': 'Call', 'value': 'call' },
          { 'label': 'Meeting', 'value': 'meeting' },
          { 'label': 'Chat', 'value': 'chat' },
          { 'label': 'Lunch', 'value': 'lunch' }
        ]
      },
      {
        'label': 'Default Lead Value',
        'type': 'number',
        'name': 'default_lead_value',
        'placeholder': '0.00',
        'help': 'Default potential value for new leads'
      },
      {
        'label': 'Auto-qualify on Resolved',
        'type': 'checkbox',
        'name': 'auto_qualify_on_resolved',
        'help': 'Move lead to qualified stage when conversation resolves'
      },
      {
        'label': 'Sync to Organization',
        'type': 'checkbox',
        'name': 'sync_to_organization',
        'help': 'Create/link to organization if company name provided'
      }
    ]
  visible_properties:
    [
      'api_url',
      'default_pipeline_id',
      'create_person',
      'create_lead',
      'enable_activity_sync',
      'activity_type',
      'auto_qualify_on_resolved'
    ]
```

---

### 6. Implementation Details

#### 6.1 Base Client (`app/services/crm/krayin/api/base_client.rb`)

```ruby
class Crm::Krayin::Api::BaseClient
  include HTTParty

  class ApiError < StandardError
    attr_reader :code, :response

    def initialize(message = nil, code = nil, response = nil)
      @code = code
      @response = response
      super(message)
    end
  end

  def initialize(api_url, api_token)
    @api_url = api_url.chomp('/')
    @api_token = api_token
    self.class.base_uri @api_url
  end

  def get(path, params = {})
    response = self.class.get(
      "/#{path}",
      query: params,
      headers: headers
    )
    handle_response(response)
  end

  def post(path, body = {}, params = {})
    response = self.class.post(
      "/#{path}",
      query: params,
      body: body.to_json,
      headers: headers
    )
    handle_response(response)
  end

  def put(path, body = {}, params = {})
    response = self.class.put(
      "/#{path}",
      query: params,
      body: body.to_json,
      headers: headers
    )
    handle_response(response)
  end

  def delete(path, params = {})
    response = self.class.delete(
      "/#{path}",
      query: params,
      headers: headers
    )
    handle_response(response)
  end

  private

  def headers
    {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'Authorization' => "Bearer #{@api_token}"
    }
  end

  def handle_response(response)
    case response.code
    when 200..299
      response.parsed_response
    when 401
      raise ApiError.new('Unauthorized: Invalid API token', response.code, response)
    when 404
      raise ApiError.new('Resource not found', response.code, response)
    when 422
      errors = extract_validation_errors(response)
      raise ApiError.new("Validation failed: #{errors}", response.code, response)
    else
      error_message = "Krayin API error: #{response.code} - #{response.body}"
      Rails.logger.error error_message
      raise ApiError.new(error_message, response.code, response)
    end
  end

  def extract_validation_errors(response)
    body = response.parsed_response
    return body['message'] if body['message']
    return body['errors'].to_s if body['errors']

    response.body
  end
end
```

#### 6.2 Lead Client (`app/services/crm/krayin/api/lead_client.rb`)

```ruby
class Crm::Krayin::Api::LeadClient < Crm::Krayin::Api::BaseClient
  def search_lead(email: nil, phone: nil)
    raise ArgumentError, 'Email or phone required' if email.blank? && phone.blank?

    # Krayin may not have direct search - might need to filter on list
    params = {}
    params[:email] = email if email.present?
    params[:phone] = phone if phone.present?

    leads = get('leads', params)
    leads.is_a?(Array) ? leads : leads['data']
  end

  def create_lead(lead_data)
    raise ArgumentError, 'Lead data is required' if lead_data.blank?

    response = post('leads', lead_data)
    response['data']['id'] || response['id']
  end

  def update_lead(lead_data, lead_id)
    raise ArgumentError, 'Lead ID is required' if lead_id.blank?
    raise ArgumentError, 'Lead data is required' if lead_data.blank?

    response = put("leads/#{lead_id}", lead_data)
    response['data'] || response
  end

  def get_lead(lead_id)
    raise ArgumentError, 'Lead ID is required' if lead_id.blank?

    response = get("leads/#{lead_id}")
    response['data'] || response
  end

  def get_pipelines
    response = get('pipelines')
    response['data'] || response
  end

  def get_stages(pipeline_id = nil)
    path = pipeline_id ? "pipelines/#{pipeline_id}/stages" : 'stages'
    response = get(path)
    response['data'] || response
  end
end
```

#### 6.3 Person Client (`app/services/crm/krayin/api/person_client.rb`)

```ruby
class Crm::Krayin::Api::PersonClient < Crm::Krayin::Api::BaseClient
  def search_person(email: nil, phone: nil)
    raise ArgumentError, 'Email or phone required' if email.blank? && phone.blank?

    params = {}
    params[:email] = email if email.present?
    params[:phone] = phone if phone.present?

    persons = get('persons', params)
    persons.is_a?(Array) ? persons : persons['data']
  end

  def create_person(person_data)
    raise ArgumentError, 'Person data is required' if person_data.blank?

    response = post('persons', person_data)
    response['data']['id'] || response['id']
  end

  def update_person(person_data, person_id)
    raise ArgumentError, 'Person ID is required' if person_id.blank?
    raise ArgumentError, 'Person data is required' if person_data.blank?

    response = put("persons/#{person_id}", person_data)
    response['data'] || response
  end

  def get_person(person_id)
    raise ArgumentError, 'Person ID is required' if person_id.blank?

    response = get("persons/#{person_id}")
    response['data'] || response
  end
end
```

#### 6.4 Setup Service (`app/services/crm/krayin/setup_service.rb`)

```ruby
class Crm::Krayin::SetupService
  def initialize(hook)
    @hook = hook
    @api_url = hook.settings['api_url']
    @api_token = hook.settings['api_token']

    @client = Crm::Krayin::Api::BaseClient.new(@api_url, @api_token)
    @lead_client = Crm::Krayin::Api::LeadClient.new(@api_url, @api_token)
  end

  def setup
    validate_connection
    setup_pipelines
    setup_lead_source
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
    Rails.logger.error "Krayin API error in setup: #{e.message}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
    Rails.logger.error "Error during Krayin setup: #{e.message}"
  end

  private

  def validate_connection
    # Test connection by fetching current user or pipelines
    pipelines = @lead_client.get_pipelines
    raise StandardError, 'No pipelines found' if pipelines.blank?

    Rails.logger.info "Krayin connection validated. Found #{pipelines.count} pipelines"
  end

  def setup_pipelines
    return if @hook.settings['default_pipeline_id'].present?

    pipelines = @lead_client.get_pipelines
    default_pipeline = pipelines.first

    if default_pipeline
      stages = @lead_client.get_stages(default_pipeline['id'])
      default_stage = stages.first

      update_hook_settings({
        default_pipeline_id: default_pipeline['id'],
        default_stage_id: default_stage['id']
      })
    end
  end

  def setup_lead_source
    # In future: Create custom lead source "Chatwoot" if API supports it
    # For now, just store the provided source ID
    update_hook_settings({ lead_source_id: @hook.settings['lead_source_id'] || 1 })
  end

  def update_hook_settings(params)
    @hook.settings = @hook.settings.merge(params.stringify_keys)
    @hook.save!
  end
end
```

#### 6.5 Processor Service (`app/services/crm/krayin/processor_service.rb`)

```ruby
class Crm::Krayin::ProcessorService < Crm::BaseProcessorService
  def self.crm_name
    'krayin'
  end

  def initialize(hook)
    super(hook)
    @api_url = hook.settings['api_url']
    @api_token = hook.settings['api_token']

    @create_person = hook.settings['create_person'] != false # default true
    @create_lead = hook.settings['create_lead'] != false # default true
    @enable_activity = hook.settings['enable_activity_sync']

    # Initialize API clients
    @base_client = Crm::Krayin::Api::BaseClient.new(@api_url, @api_token)
    @person_client = Crm::Krayin::Api::PersonClient.new(@api_url, @api_token)
    @lead_client = Crm::Krayin::Api::LeadClient.new(@api_url, @api_token)
    @activity_client = Crm::Krayin::Api::ActivityClient.new(@api_url, @api_token)

    @person_finder = Crm::Krayin::PersonFinderService.new(@person_client)
    @lead_finder = Crm::Krayin::LeadFinderService.new(@lead_client)
  end

  def handle_contact(contact)
    contact.reload
    unless identifiable_contact?(contact)
      Rails.logger.info("Contact not identifiable. Skipping handle_contact for ##{contact.id}")
      return
    end

    person_id = nil
    lead_id = nil

    # Create/update person
    if @create_person
      stored_person_id = get_external_id(contact, 'person_id')
      person_id = create_or_update_person(contact, stored_person_id)
    end

    # Create/update lead
    if @create_lead
      stored_lead_id = get_external_id(contact, 'lead_id')
      lead_id = create_or_update_lead(contact, person_id, stored_lead_id)
    end
  end

  def handle_conversation_created(conversation)
    return unless @enable_activity

    create_activity_from_conversation(conversation)
  end

  def handle_conversation_resolved(conversation)
    # Update lead stage if auto-qualify enabled
    if @hook.settings['auto_qualify_on_resolved']
      update_lead_stage(conversation.contact, 'qualified')
    end

    # Mark activity as done
    mark_activity_done(conversation) if @enable_activity
  end

  private

  def create_or_update_person(contact, person_id)
    person_data = Crm::Krayin::Mappers::ContactMapper.map_to_person(contact)

    if person_id.present?
      @person_client.update_person(person_data, person_id)
      person_id
    else
      new_person_id = @person_client.create_person(person_data)
      store_external_id(contact, new_person_id, 'person_id')
      new_person_id
    end
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "Krayin API error processing person: #{e.message}"
    nil
  end

  def create_or_update_lead(contact, person_id, lead_id)
    lead_data = Crm::Krayin::Mappers::ContactMapper.map_to_lead(
      contact,
      person_id,
      @hook.settings
    )

    if lead_id.present?
      @lead_client.update_lead(lead_data, lead_id)
      lead_id
    else
      new_lead_id = @lead_client.create_lead(lead_data)
      store_external_id(contact, new_lead_id, 'lead_id')
      new_lead_id
    end
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "Krayin API error processing lead: #{e.message}"
    nil
  end

  def create_activity_from_conversation(conversation)
    person_id = get_person_id(conversation.contact)
    return if person_id.blank?

    activity_data = Crm::Krayin::Mappers::ConversationMapper.map_to_activity(
      conversation,
      person_id,
      @hook.settings
    )

    activity_id = @activity_client.create_activity(activity_data)
    return if activity_id.blank?

    metadata = { 'activity_id' => activity_id }
    store_conversation_metadata(conversation, metadata)
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "Krayin API error creating activity: #{e.message}"
  end

  def mark_activity_done(conversation)
    activity_id = get_activity_id(conversation)
    return if activity_id.blank?

    @activity_client.update_activity({ is_done: true }, activity_id)
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "Krayin API error marking activity done: #{e.message}"
  end

  def update_lead_stage(contact, stage_name)
    lead_id = get_external_id(contact, 'lead_id')
    return if lead_id.blank?

    # Find qualified stage
    stages = @lead_client.get_stages
    qualified_stage = stages.find { |s| s['name'].downcase.include?('qualified') }
    return unless qualified_stage

    @lead_client.update_lead({ lead_pipeline_stage_id: qualified_stage['id'] }, lead_id)
  rescue Crm::Krayin::Api::BaseClient::ApiError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "Krayin API error updating lead stage: #{e.message}"
  end

  def get_person_id(contact)
    contact.reload

    unless identifiable_contact?(contact)
      Rails.logger.info("Contact not identifiable. Skipping for ##{contact.id}")
      return nil
    end

    person_id = @person_finder.find_or_create(contact)
    return nil if person_id.blank?

    store_external_id(contact, person_id, 'person_id') unless get_external_id(contact, 'person_id')

    person_id
  end

  def get_activity_id(conversation)
    conversation.reload
    conversation.additional_attributes&.dig('krayin', 'activity_id')
  end

  # Override base method to support multiple external IDs (person_id, lead_id)
  def get_external_id(contact, key = 'id')
    return nil if contact.additional_attributes.blank?
    return nil if contact.additional_attributes['external'].blank?

    contact.additional_attributes.dig('external', "krayin_#{key}")
  end

  def store_external_id(contact, external_id, key = 'id')
    contact.additional_attributes = {} if contact.additional_attributes.nil?
    contact.additional_attributes['external'] = {} if contact.additional_attributes['external'].blank?

    contact.additional_attributes['external']["krayin_#{key}"] = external_id
    contact.save!
  end
end
```

---

### 7. Custom Attributes for Chatwoot (Krayin)

#### Contact Attributes

```yaml
# config/custom_attributes/krayin_contact.yml
krayin_contact_attributes:
  - attribute_key: krayin_person_id
    attribute_display_name: Krayin Person ID
    attribute_display_type: number
    attribute_description: Linked Krayin Person ID
    attribute_model: contact_attribute

  - attribute_key: krayin_lead_id
    attribute_display_name: Krayin Lead ID
    attribute_display_type: number
    attribute_description: Linked Krayin Lead ID
    attribute_model: contact_attribute

  - attribute_key: krayin_organization_id
    attribute_display_name: Krayin Organization
    attribute_display_type: number
    attribute_description: Linked Organization ID
    attribute_model: contact_attribute

  - attribute_key: krayin_lead_value
    attribute_display_name: Lead Value
    attribute_display_type: number
    attribute_description: Potential deal value
    attribute_model: contact_attribute

  - attribute_key: krayin_lead_stage
    attribute_display_name: Lead Stage
    attribute_display_type: text
    attribute_description: Current pipeline stage
    attribute_model: contact_attribute

  - attribute_key: krayin_lead_source
    attribute_display_name: Lead Source
    attribute_display_type: text
    attribute_description: How lead was acquired
    attribute_model: contact_attribute

  - attribute_key: krayin_person_type
    attribute_display_name: Person Type
    attribute_display_type: list
    attribute_values: ["Customer", "Prospect", "Partner", "Vendor"]
    attribute_model: contact_attribute

  - attribute_key: krayin_job_title
    attribute_display_name: Job Title
    attribute_display_type: text
    attribute_description: Professional title
    attribute_model: contact_attribute
```

#### Conversation Attributes

```yaml
# config/custom_attributes/krayin_conversation.yml
krayin_conversation_attributes:
  - attribute_key: krayin_activity_id
    attribute_display_name: Krayin Activity ID
    attribute_display_type: number
    attribute_description: Linked Krayin Activity ID
    attribute_model: conversation_attribute

  - attribute_key: krayin_activity_url
    attribute_display_name: Krayin Activity URL
    attribute_display_type: link
    attribute_description: Direct link to activity
    attribute_model: conversation_attribute

  - attribute_key: krayin_activity_type
    attribute_display_name: Activity Type
    attribute_display_type: list
    attribute_values: ["Call", "Meeting", "Chat", "Lunch", "Email"]
    attribute_model: conversation_attribute

  - attribute_key: krayin_is_done
    attribute_display_name: Activity Completed
    attribute_display_type: checkbox
    attribute_description: Activity completion status
    attribute_model: conversation_attribute

  - attribute_key: krayin_expected_value
    attribute_display_name: Expected Deal Value
    attribute_display_type: number
    attribute_description: Potential revenue from this conversation
    attribute_model: conversation_attribute

  - attribute_key: krayin_related_quote_id
    attribute_display_name: Related Quote
    attribute_display_type: number
    attribute_description: Linked quote ID
    attribute_model: conversation_attribute
```

---

### 8. Event Handling

#### Update `app/listeners/hook_listener.rb`

```ruby
def supported_hook_event?(hook, event_name)
  # ... existing code ...

  supported_events_map = {
    # ... existing mappings ...
    'krayin' => ['contact.updated', 'conversation.created', 'conversation.resolved']
  }

  # ... rest of method ...
end
```

#### Update `app/jobs/hook_job.rb`

```ruby
def perform(hook, event_name, event_data = {})
  # ... existing code ...

  case hook.app_id
  # ... existing cases ...
  when 'krayin'
    process_krayin_integration_with_lock(hook, event_name, event_data)
  end
end

private

def process_krayin_integration_with_lock(hook, event_name, event_data)
  valid_event_names = ['contact.updated', 'conversation.created', 'conversation.resolved']
  return unless valid_event_names.include?(event_name)
  return unless hook.feature_allowed?

  key = format(::Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
  with_lock(key) do
    process_krayin_integration(hook, event_name, event_data)
  end
end

def process_krayin_integration(hook, event_name, event_data)
  processor = Crm::Krayin::ProcessorService.new(hook)

  case event_name
  when 'contact.updated'
    processor.handle_contact(event_data[:contact])
  when 'conversation.created'
    processor.handle_conversation_created(event_data[:conversation])
  when 'conversation.resolved'
    processor.handle_conversation_resolved(event_data[:conversation])
  end
end
```

#### Update `app/jobs/crm/setup_job.rb`

```ruby
def create_setup_service(hook)
  case hook.app_id
  # ... existing cases ...
  when 'krayin'
    Crm::Krayin::SetupService.new(hook)
  # ... rest of cases ...
  end
end
```

#### Update `app/models/integrations/hook.rb`

```ruby
def crm_integration?
  %w[leadsquared glpi krayin].include?(app_id)
end
```

---

### 9. Advanced Features (Krayin-Specific)

#### 9.1 Organization Sync

If contact has company information, create/link to Krayin Organization:

```ruby
# In ContactMapper
def map_organization
  return nil unless contact.additional_attributes['company'].present?

  {
    name: contact.additional_attributes['company'],
    address: {
      address: contact.additional_attributes['address'],
      city: contact.additional_attributes['city'],
      state: contact.additional_attributes['state'],
      postcode: contact.additional_attributes['postal_code'],
      country: contact.additional_attributes['country']
    }
  }
end
```

#### 9.2 Product/Quote Integration

Track products discussed in conversations:

```ruby
# Store in conversation metadata
{
  'krayin': {
    'products_mentioned': [123, 456],
    'quote_id': 789,
    'estimated_value': 5000.00
  }
}
```

#### 9.3 Email Sync

If Krayin supports email activities, sync email conversations:

```ruby
def create_email_activity(conversation)
  return unless conversation.inbox.email?

  activity_data = {
    type: 'email',
    subject: conversation.additional_attributes['mail_subject'],
    comment: conversation.messages.first&.content,
    # ... other fields
  }

  @activity_client.create_activity(activity_data)
end
```

---

### 10. Testing Checklist

- [ ] Unit tests for all API clients
- [ ] Unit tests for mappers
- [ ] Integration tests for setup service
- [ ] Integration tests for processor service
- [ ] Test person and lead creation/update
- [ ] Test activity sync
- [ ] Test stage progression logic
- [ ] Test mutex locks for race conditions
- [ ] Test organization sync
- [ ] Manual E2E testing with real Krayin instance

---

## Implementation Timeline

### Phase 1: GLPI Integration (Weeks 1-3)

**Week 1: Foundation**
- [ ] Setup GLPI development instance
- [ ] Create base API clients with session management
- [ ] Implement and test BaseClient
- [ ] Write unit tests for API clients

**Week 2: Core Features**
- [ ] Implement User/Contact mappers
- [ ] Implement Ticket/Followup mappers
- [ ] Create SetupService
- [ ] Create ProcessorService
- [ ] Implement contact sync

**Week 3: Advanced & Polish**
- [ ] Implement ticket sync
- [ ] Implement followup sync
- [ ] Add bidirectional sync (optional)
- [ ] Integration testing
- [ ] Documentation

### Phase 2: Krayin CRM Integration (Weeks 4-6)

**Week 4: Foundation**
- [ ] Setup Krayin development instance
- [ ] Verify Krayin API endpoints
- [ ] Create base API clients
- [ ] Implement and test BaseClient
- [ ] Write unit tests for API clients

**Week 5: Core Features**
- [ ] Implement Person mapper
- [ ] Implement Lead mapper
- [ ] Implement Activity mapper
- [ ] Create SetupService
- [ ] Create ProcessorService
- [ ] Implement person/lead sync

**Week 6: Advanced & Polish**
- [ ] Implement activity sync
- [ ] Implement organization sync
- [ ] Implement stage progression
- [ ] Integration testing
- [ ] Documentation

### Phase 3: Testing & Deployment (Week 7)

- [ ] End-to-end testing both integrations
- [ ] Performance testing
- [ ] Security audit
- [ ] Code review
- [ ] Create migration scripts
- [ ] Deploy to staging
- [ ] User acceptance testing
- [ ] Production deployment

---

## Testing Strategy

### Unit Tests

```ruby
# Example: spec/services/crm/glpi/api/base_client_spec.rb
RSpec.describe Crm::Glpi::Api::BaseClient do
  let(:api_url) { 'https://glpi.example.com/apirest.php' }
  let(:app_token) { 'test_app_token' }
  let(:user_token) { 'test_user_token' }
  let(:client) { described_class.new(api_url, app_token, user_token) }

  describe '#init_session' do
    it 'initializes session with valid credentials' do
      stub_request(:get, "#{api_url}/initSession")
        .to_return(
          status: 200,
          body: { session_token: 'abc123' }.to_json
        )

      expect { client.send(:init_session) }.not_to raise_error
    end

    it 'raises error with invalid credentials' do
      stub_request(:get, "#{api_url}/initSession")
        .to_return(status: 401)

      expect { client.send(:init_session) }.to raise_error(
        Crm::Glpi::Api::BaseClient::ApiError
      )
    end
  end

  # ... more tests
end
```

### Integration Tests

```ruby
# Example: spec/services/crm/glpi/processor_service_spec.rb
RSpec.describe Crm::Glpi::ProcessorService do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :glpi, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:processor) { described_class.new(hook) }

  describe '#handle_contact' do
    context 'when contact is new' do
      it 'creates GLPI user' do
        VCR.use_cassette('glpi/create_user') do
          expect { processor.handle_contact(contact) }
            .to change { contact.reload.additional_attributes.dig('external', 'glpi_id') }
            .from(nil).to(be_present)
        end
      end
    end

    context 'when contact exists' do
      before do
        contact.additional_attributes = {
          'external' => { 'glpi_id' => 123 }
        }
        contact.save!
      end

      it 'updates GLPI user' do
        VCR.use_cassette('glpi/update_user') do
          contact.name = 'Updated Name'
          expect { processor.handle_contact(contact) }
            .not_to raise_error
        end
      end
    end
  end

  # ... more tests
end
```

### Manual Testing Checklist

**GLPI:**
- [ ] Contact sync creates GLPI User
- [ ] Contact sync creates GLPI Contact (if configured)
- [ ] Contact update syncs to GLPI
- [ ] Conversation creates GLPI Ticket
- [ ] Messages sync as ITILFollowups
- [ ] Conversation resolved updates ticket status
- [ ] Bidirectional sync works (if enabled)
- [ ] Error handling works gracefully
- [ ] Session management is reliable

**Krayin:**
- [ ] Contact sync creates Krayin Person
- [ ] Contact sync creates Krayin Lead
- [ ] Contact update syncs to Krayin
- [ ] Conversation creates Activity
- [ ] Resolved conversation marks activity done
- [ ] Lead stage progression works
- [ ] Organization sync works (if enabled)
- [ ] Multiple conversations link correctly
- [ ] Error handling works gracefully

---

## Migration & Rollout Plan

### Database Migrations

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_crm_integration_support.rb
class AddCrmIntegrationSupport < ActiveRecord::Migration[7.0]
  def change
    # Ensure contacts.additional_attributes exists (likely already present)
    # Ensure conversations.additional_attributes exists (likely already present)

    # Add indexes for faster external ID lookups
    add_index :contacts,
      "(additional_attributes -> 'external' ->> 'glpi_id')",
      name: 'index_contacts_on_glpi_id',
      using: :gin

    add_index :contacts,
      "(additional_attributes -> 'external' ->> 'krayin_person_id')",
      name: 'index_contacts_on_krayin_person_id',
      using: :gin

    add_index :contacts,
      "(additional_attributes -> 'external' ->> 'krayin_lead_id')",
      name: 'index_contacts_on_krayin_lead_id',
      using: :gin
  end
end
```

### Feature Flag Strategy

```ruby
# Enable for specific accounts first
account.enable_feature!('crm_integration')

# Or globally
Rails.configuration.x.features.crm_integration = true
```

### Rollout Phases

1. **Internal Testing** (Week 7)
   - Enable for internal account
   - Test with real GLPI/Krayin instances
   - Monitor errors and performance

2. **Beta Users** (Week 8)
   - Select 3-5 beta customers
   - Provide detailed documentation
   - Gather feedback

3. **General Availability** (Week 9+)
   - Enable feature flag globally
   - Announce in changelog
   - Monitor adoption and issues

---

## Documentation Requirements

### User Documentation

1. **Setup Guides:**
   - How to get GLPI API tokens
   - How to get Krayin API tokens
   - Configuration screenshots
   - Troubleshooting common issues

2. **Feature Documentation:**
   - What data syncs
   - When sync happens
   - Field mappings
   - Limitations

3. **FAQ:**
   - Can I sync existing contacts?
   - How to handle duplicates?
   - What happens if CRM is down?
   - Can I customize field mappings?

### Developer Documentation

1. **Architecture Overview:**
   - Component diagram
   - Data flow diagram
   - Sequence diagrams

2. **API Client Documentation:**
   - Available methods
   - Error handling
   - Rate limiting

3. **Extension Guide:**
   - How to add new CRM
   - How to customize mappers
   - How to add new sync events

---

## Success Metrics

### Technical Metrics

- [ ] API success rate > 99%
- [ ] Average sync time < 2 seconds
- [ ] Error rate < 1%
- [ ] Test coverage > 90%

### Business Metrics

- [ ] Number of active integrations
- [ ] Customer satisfaction score
- [ ] Support ticket volume
- [ ] Feature adoption rate

---

## Risk Assessment & Mitigation

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| GLPI session timeouts | High | Medium | Implement retry logic, session pooling |
| API rate limiting | Medium | Low | Implement backoff, queue management |
| Data sync conflicts | High | Medium | Mutex locks, conflict resolution |
| Large data volumes | Medium | Medium | Pagination, batch processing |
| Network failures | High | Low | Retry logic, fallback queues |

### Business Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Poor user adoption | Medium | Low | Clear documentation, beta program |
| Support overhead | Medium | Medium | Comprehensive docs, self-service tools |
| Customer data issues | High | Low | Thorough testing, rollback plan |
| Integration complexity | Medium | Medium | Phased rollout, feature flags |

---

## Appendix

### A. GLPI API Reference

- **Documentation:** https://github.com/glpi-project/glpi/blob/main/apirest.md
- **API Version:** 9.5+
- **Authentication:** Session tokens
- **Rate Limits:** None (self-hosted)

### B. Krayin API Reference

- **Documentation:** Check `packages/Webkul/RestApi/` in Krayin repo
- **API Version:** 1.x
- **Authentication:** Bearer tokens
- **Rate Limits:** Configurable

### C. LeadSquared Reference Files

- Setup: `app/services/crm/leadsquared/setup_service.rb`
- Processor: `app/services/crm/leadsquared/processor_service.rb`
- Base Client: `app/services/crm/leadsquared/api/base_client.rb`
- Hook Model: `app/models/integrations/hook.rb`
- Hook Listener: `app/listeners/hook_listener.rb`
- Hook Job: `app/jobs/hook_job.rb`

### D. Custom Attribute Creation

```ruby
# To create custom attributes via Rails console:

# GLPI Contact Attributes
account = Account.find(YOUR_ACCOUNT_ID)

account.custom_attribute_definitions.create!(
  attribute_display_name: 'GLPI User ID',
  attribute_key: 'glpi_user_id',
  attribute_display_type: 'number',
  attribute_model: 'contact_attribute'
)

# Krayin Contact Attributes
account.custom_attribute_definitions.create!(
  attribute_display_name: 'Krayin Lead ID',
  attribute_key: 'krayin_lead_id',
  attribute_display_type: 'number',
  attribute_model: 'contact_attribute'
)

# Add more as needed...
```

---

## Conclusion

This implementation plan provides a comprehensive roadmap for integrating both GLPI and Krayin CRM with Chatwoot. The plan leverages the proven LeadSquared integration pattern and adapts it to the specific requirements of each CRM system.

**Recommended Approach:**
1. Start with **GLPI** integration (more complex, good learning experience)
2. Follow with **Krayin** integration (simpler, faster implementation)
3. Gather feedback and iterate

**Estimated Total Time:** 7-8 weeks for both integrations

**Next Steps:**
1. Review and approve this plan
2. Set up development environments (GLPI + Krayin instances)
3. Create feature branch: `feature/crm-integration-glpi-krayin`
4. Begin Phase 1: GLPI Integration

---

**Document Status:** Draft for Review
**Last Updated:** 2025-11-05
**Author:** Development Team
**Reviewers:** TBD
