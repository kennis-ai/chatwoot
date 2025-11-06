# GLPI Integration Developer Guide

## Overview

This guide provides technical documentation for developers working on or extending the GLPI integration for Chatwoot.

---

## Architecture

### Layer Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Chatwoot Events                         │
│         (contact.created, conversation.updated, etc.)        │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                       HookJob                                │
│              (Event Router with Mutex Lock)                  │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                  ProcessorService                            │
│              (Event-to-Action Orchestrator)                  │
└────┬─────────────┬────────────────┬──────────────────┬───────┘
     │             │                │                  │
     ▼             ▼                ▼                  ▼
┌─────────┐  ┌──────────┐    ┌───────────┐    ┌──────────────┐
│  User   │  │ Contact  │    │  Ticket   │    │   Followup   │
│ Finder  │  │  Finder  │    │  Client   │    │    Client    │
│ Service │  │ Service  │    │           │    │              │
└────┬────┘  └────┬─────┘    └─────┬─────┘    └──────┬───────┘
     │            │                 │                 │
     ▼            ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────┐
│                    Data Mappers                              │
│     (Contact → User/Contact, Conversation → Ticket, etc.)    │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                     API Clients                              │
│              (BaseClient, UserClient, etc.)                  │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                      GLPI REST API                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
app/services/crm/glpi/
├── api/
│   ├── base_client.rb           # Base HTTP client with session management
│   ├── contact_client.rb        # GLPI Contact CRUD operations
│   ├── followup_client.rb       # GLPI ITILFollowup operations
│   ├── ticket_client.rb         # GLPI Ticket CRUD operations
│   └── user_client.rb           # GLPI User CRUD operations
├── mappers/
│   ├── contact_mapper.rb        # Chatwoot Contact → GLPI User/Contact
│   ├── conversation_mapper.rb   # Chatwoot Conversation → GLPI Ticket
│   └── message_mapper.rb        # Chatwoot Message → GLPI ITILFollowup
├── contact_finder_service.rb   # Find-or-create GLPI Contacts
├── processor_service.rb         # Event orchestration
├── setup_service.rb             # Validation and connectivity testing
└── user_finder_service.rb       # Find-or-create GLPI Users

spec/services/crm/glpi/
├── api/                         # API client specs (763 lines)
├── mappers/                     # Mapper specs (565 lines)
├── integration_spec.rb          # E2E integration specs (245 lines)
├── *_service_spec.rb            # Service specs (718 lines)
└── (14 total spec files, 2,425 lines, ~96% coverage)

config/
├── integration/
│   └── apps.yml                 # GLPI integration definition
└── locales/
    └── en.yml                   # Backend translations

app/jobs/
└── hook_job.rb                  # Event handler integration

.kennis/
├── glpi-user-guide.md           # User documentation
├── glpi-developer-guide.md      # This file
├── glpi-testing-guide.md        # Testing documentation
├── glpi-troubleshooting.md      # Troubleshooting guide
└── phase*-completion-summary.md # Implementation phase summaries
```

---

## Component Details

### 1. API Clients (`app/services/crm/glpi/api/`)

#### BaseClient

**Purpose**: Foundation for all GLPI API clients with session management

**Key Features**:
- Session lifecycle management (init/kill/cleanup)
- Automatic session creation and cleanup in ensure blocks
- HTTParty integration for HTTP requests
- Error handling and logging
- Session token caching per instance

**Usage Pattern**:
```ruby
client = Crm::Glpi::Api::BaseClient.new(hook)
client.with_session do |session_token|
  # API operations using session_token
end
# Session automatically killed in ensure block
```

**Session Management**:
```ruby
# Initialize session
def init_session
  response = self.class.get(
    "#{@api_url}/initSession",
    headers: {
      'Content-Type' => 'application/json',
      'App-Token' => @app_token,
      'Authorization' => "user_token #{@user_token}"
    }
  )
  @session_token = response.parsed_response['session_token']
end

# Kill session (cleanup)
def kill_session
  return unless @session_token
  self.class.get(
    "#{@api_url}/killSession",
    headers: session_headers
  )
ensure
  @session_token = nil
end
```

#### UserClient

**Purpose**: CRUD operations for GLPI Users

**Methods**:
- `search_user(criteria)` - Search users by email/name
- `create_user(user_data)` - Create new GLPI User
- `update_user(user_id, user_data)` - Update existing User

**Example**:
```ruby
client = Crm::Glpi::Api::UserClient.new(hook)
result = client.search_user({ criteria: [{ field: 5, searchtype: 'equals', value: 'john@example.com' }] })
user_id = result.dig('data', 0, '2') # Extract user ID from search result
```

#### ContactClient

**Purpose**: CRUD operations for GLPI Contacts

**Methods**:
- `search_contact(criteria)` - Search contacts by email
- `create_contact(contact_data)` - Create new GLPI Contact
- `update_contact(contact_id, contact_data)` - Update existing Contact

#### TicketClient

**Purpose**: CRUD operations for GLPI Tickets

**Methods**:
- `create_ticket(ticket_data)` - Create new Ticket
- `update_ticket(ticket_id, ticket_data)` - Update Ticket status/priority

**Example**:
```ruby
client = Crm::Glpi::Api::TicketClient.new(hook)
ticket_data = {
  name: 'Customer Issue',
  content: 'Description here',
  status: 2,
  priority: 3,
  type: 1,
  entities_id: 0,
  _users_id_requester: 123
}
result = client.create_ticket(ticket_data)
ticket_id = result['id']
```

#### FollowupClient

**Purpose**: Create GLPI ITILFollowups (ticket updates)

**Methods**:
- `create_followup(ticket_id, followup_data)` - Add followup to ticket

**Example**:
```ruby
client = Crm::Glpi::Api::FollowupClient.new(hook)
followup_data = {
  content: 'Customer replied: Thank you!',
  is_private: 0,
  users_id: 2
}
client.create_followup(456, followup_data)
```

---

### 2. Data Mappers (`app/services/crm/glpi/mappers/`)

#### ContactMapper

**Purpose**: Transform Chatwoot Contacts to GLPI User/Contact format

**Methods**:
- `to_user(contact)` - Map to GLPI User structure
- `to_contact(contact)` - Map to GLPI Contact structure

**Key Logic**:
```ruby
# Name splitting
def split_name(name)
  return ['', ''] if name.blank?
  parts = name.split(/\s+/, 2)
  [parts[0] || '', parts[1] || '']
end

# Phone formatting
def format_phone(phone)
  return nil if phone.blank?
  parsed = Phonelib.parse(phone)
  parsed.valid? ? parsed.international : phone
end

# Mapping
def to_user(contact)
  firstname, realname = split_name(contact.name)
  {
    firstname: firstname,
    realname: realname,
    name: contact.email,
    phone: format_phone(contact.phone_number)
  }.compact
end
```

#### ConversationMapper

**Purpose**: Transform Chatwoot Conversations to GLPI Tickets

**Methods**:
- `to_ticket(conversation, requester_id, settings)` - Map to GLPI Ticket structure

**Status/Priority Mapping**:
```ruby
STATUS_MAP = {
  'open' => 2,      # Processing (assigned)
  'pending' => 4,   # Pending
  'resolved' => 5,  # Solved
  'snoozed' => 4    # Pending
}.freeze

PRIORITY_MAP = {
  'low' => 2,
  'medium' => 3,
  'high' => 4,
  'urgent' => 5
}.freeze
```

#### MessageMapper

**Purpose**: Transform Chatwoot Messages to GLPI ITILFollowups

**Methods**:
- `to_followup(message, default_user_id)` - Map to GLPI ITILFollowup structure

**Attachment Handling**:
```ruby
def format_content_with_attachments(message)
  content = message.content

  if message.attachments.present?
    attachment_urls = message.attachments.map(&:file_url)
    content += "\n\nAttachments:\n" + attachment_urls.join("\n")
  end

  content
end
```

---

### 3. Core Services

#### SetupService

**Purpose**: Integration setup and validation

**Methods**:
- `validate_and_test` - Validate credentials and test connectivity

**Usage**:
```ruby
service = Crm::Glpi::SetupService.new(hook)
result = service.validate_and_test
# => { success: true, message: "GLPI connection successful" }
# OR
# => { success: false, error: "API connection failed" }
```

#### UserFinderService

**Purpose**: Find-or-create pattern for GLPI Users

**Methods**:
- `find_or_create_user(contact)` - Search by email, create if not found

**Flow**:
```ruby
def find_or_create_user(contact)
  # 1. Search by email
  existing_user = search_user_by_email(contact.email)
  return existing_user['2'].to_i if existing_user

  # 2. Create if not found
  user_data = mapper.to_user(contact)
  result = user_client.create_user(user_data)

  # 3. Return user ID
  result['id']
end
```

#### ContactFinderService

**Purpose**: Find-or-create pattern for GLPI Contacts

**Methods**:
- `find_or_create_contact(contact)` - Search by email, create if not found

**Similar flow to UserFinderService but for GLPI Contacts**

#### ProcessorService

**Purpose**: Main event orchestration service

**Methods**:
- `process_event(event_name, event_data)` - Route and handle events
- `handle_contact_created(contact)` - Contact creation handler
- `handle_contact_updated(contact)` - Contact update handler
- `handle_conversation_created(conversation)` - Conversation creation handler
- `handle_conversation_updated(conversation)` - Conversation update handler

**Event Routing**:
```ruby
def process_event(event_name, event_data)
  case event_name
  when 'contact.created'
    handle_contact_created(event_data[:contact] || event_data['contact'])
  when 'contact.updated'
    handle_contact_updated(event_data[:contact] || event_data['contact'])
  when 'conversation.created'
    handle_conversation_created(event_data[:conversation] || event_data['conversation'])
  when 'conversation.updated'
    handle_conversation_updated(event_data[:conversation] || event_data['conversation'])
  else
    { success: false, error: "Unhandled event: #{event_name}" }
  end
rescue StandardError => e
  ChatwootExceptionTracker.new(e, account: @hook.account).capture_exception
  Rails.logger.error "GLPI ProcessorService error: #{e.message}"
  { success: false, error: e.message }
end
```

**Contact Handler**:
```ruby
def handle_contact_created(contact)
  return { success: false, error: 'Contact not identifiable' } unless identifiable?(contact)

  if @settings['sync_type'] == 'contact'
    contact_id = contact_finder.find_or_create_contact(contact)
    store_contact_id(contact, contact_id)
  else
    user_id = user_finder.find_or_create_user(contact)
    store_user_id(contact, user_id)
  end

  { success: true }
end
```

**Conversation Handler**:
```ruby
def handle_conversation_created(conversation)
  # 1. Ensure contact is synced
  sync_contact_if_needed(conversation.contact)

  # 2. Get requester ID
  requester_id = get_requester_id(conversation.contact)
  return { success: false, error: 'Requester not found' } unless requester_id

  # 3. Create ticket
  ticket_data = conversation_mapper.to_ticket(conversation, requester_id, @settings)
  result = ticket_client.create_ticket(ticket_data)

  # 4. Store ticket ID
  store_ticket_id(conversation, result['id'])

  # 5. Sync initial messages
  sync_messages(conversation, result['id'])

  { success: true, ticket_id: result['id'] }
end
```

---

### 4. Event Integration (`app/jobs/hook_job.rb`)

**Integration Point**: HookJob handles all Chatwoot events and routes them to integrations

**GLPI Integration**:
```ruby
def perform(hook, event_name, event_data = {})
  return if hook.disabled?

  case hook.app_id
  when 'glpi'
    process_glpi_integration_with_lock(hook, event_name, event_data)
  # ... other integrations
  end
end

def process_glpi_integration_with_lock(hook, event_name, event_data)
  valid_event_names = ['contact.created', 'contact.updated', 'conversation.created', 'conversation.updated']
  return unless valid_event_names.include?(event_name)
  return unless hook.feature_allowed?

  key = format(::Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
  with_lock(key) do
    process_glpi_integration(hook, event_name, event_data)
  end
end
```

**Mutex Lock Strategy**:
- **Purpose**: Prevent race conditions during rapid event sequences
- **Key**: `crm:process:hook:{hook_id}`
- **Timeout**: 3 seconds
- **Retries**: 3 attempts
- **Scope**: Per hook (account-level)

---

## Configuration

### apps.yml Structure

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
      api_url: { type: string }
      app_token: { type: string }
      user_token: { type: string }
      entity_id: { type: string }
      sync_type: { type: string, enum: [user, contact] }
      ticket_type: { type: string }
      category_id: { type: string }
      default_user_id: { type: string }
    required: [api_url, app_token, user_token]

  settings_form_schema:
    - label: API URL
      type: text
      name: api_url
      validation: required
      placeholder: https://glpi.example.com/apirest.php
      help: Your GLPI API endpoint URL
    # ... more fields

  visible_properties:
    - api_url
    - entity_id
    - sync_type
    - ticket_type
    - category_id
```

---

## Testing

### Test Structure

```
spec/services/crm/glpi/
├── api/
│   ├── base_client_spec.rb      (203 lines)
│   ├── contact_client_spec.rb   (140 lines)
│   ├── followup_client_spec.rb  (140 lines)
│   ├── ticket_client_spec.rb    (140 lines)
│   └── user_client_spec.rb      (140 lines)
├── mappers/
│   ├── contact_mapper_spec.rb   (218 lines)
│   ├── conversation_mapper_spec.rb (197 lines)
│   └── message_mapper_spec.rb   (150 lines)
├── contact_finder_service_spec.rb  (180 lines)
├── integration_spec.rb             (245 lines)
├── processor_service_spec.rb       (258 lines)
├── setup_service_spec.rb           (140 lines)
└── user_finder_service_spec.rb     (140 lines)
```

### Running Tests

```bash
# All GLPI tests
bundle exec rspec spec/services/crm/glpi/

# By component
bundle exec rspec spec/services/crm/glpi/api/
bundle exec rspec spec/services/crm/glpi/mappers/
bundle exec rspec spec/services/crm/glpi/*_service_spec.rb

# Single file
bundle exec rspec spec/services/crm/glpi/processor_service_spec.rb

# With coverage
COVERAGE=true bundle exec rspec spec/services/crm/glpi/
```

### Test Patterns

**WebMock for API Stubbing**:
```ruby
RSpec.describe Crm::Glpi::Api::UserClient do
  before do
    stub_request(:get, "#{api_url}/initSession")
      .to_return(status: 200, body: { session_token: 'test_token' }.to_json)

    stub_request(:get, "#{api_url}/killSession")
      .to_return(status: 200, body: {}.to_json)
  end

  it 'creates user' do
    stub_request(:post, "#{api_url}/User")
      .to_return(status: 201, body: { id: 123 }.to_json)

    result = client.create_user({ name: 'test@example.com' })
    expect(result['id']).to eq(123)
  end
end
```

**Integration Testing Pattern**:
```ruby
RSpec.describe 'GLPI Integration End-to-End' do
  it 'syncs contact, creates ticket, and adds followups' do
    # Stub all API calls
    stub_request(:get, %r{.*/search/User}).to_return(...)
    stub_request(:post, %r{.*/User}).to_return(...)
    stub_request(:post, %r{.*/Ticket}).to_return(...)

    # Execute flow
    processor = Crm::Glpi::ProcessorService.new(hook)
    processor.process_event('contact.created', contact)
    processor.process_event('conversation.created', conversation)

    # Verify results
    expect(contact.additional_attributes.dig('external', 'glpi_user_id')).to eq(123)
    expect(conversation.additional_attributes.dig('glpi', 'ticket_id')).to eq(456)
  end
end
```

---

## Extending the Integration

### Adding New Event Types

1. **Add to valid_event_names** in HookJob:
```ruby
valid_event_names = [
  'contact.created', 'contact.updated',
  'conversation.created', 'conversation.updated',
  'your.new.event'  # Add here
]
```

2. **Add handler** in ProcessorService:
```ruby
def process_event(event_name, event_data)
  case event_name
  # ... existing cases
  when 'your.new.event'
    handle_your_new_event(event_data)
  end
end

def handle_your_new_event(data)
  # Implementation
end
```

3. **Add tests**:
```ruby
context 'when processing your.new.event' do
  it 'handles the event correctly' do
    # Test implementation
  end
end
```

### Adding New GLPI Entities

Example: Add support for GLPI Projects

1. **Create client** (`app/services/crm/glpi/api/project_client.rb`):
```ruby
module Crm
  module Glpi
    module Api
      class ProjectClient < BaseClient
        def create_project(project_data)
          with_session do
            response = self.class.post(
              "#{@api_url}/Project",
              headers: session_headers,
              body: { input: project_data }.to_json
            )
            handle_response(response)
          end
        end
      end
    end
  end
end
```

2. **Create mapper** (`app/services/crm/glpi/mappers/project_mapper.rb`):
```ruby
module Crm
  module Glpi
    module Mappers
      class ProjectMapper
        def to_project(chatwoot_data)
          {
            name: chatwoot_data.name,
            # ... more mappings
          }.compact
        end
      end
    end
  end
end
```

3. **Integrate into ProcessorService**:
```ruby
def handle_project_created(project_data)
  project_mapper = Mappers::ProjectMapper.new
  project_client = Api::ProjectClient.new(@hook)

  glpi_project_data = project_mapper.to_project(project_data)
  result = project_client.create_project(glpi_project_data)

  { success: true, project_id: result['id'] }
end
```

### Adding Custom Field Mappings

1. **Update mapper** to accept custom field configuration:
```ruby
def to_ticket(conversation, requester_id, settings)
  base_data = {
    name: ticket_title(conversation),
    content: ticket_content(conversation),
    # ... standard fields
  }

  # Add custom fields
  if settings['custom_fields']
    custom_data = map_custom_fields(conversation, settings['custom_fields'])
    base_data.merge!(custom_data)
  end

  base_data.compact
end

def map_custom_fields(conversation, field_config)
  field_config.each_with_object({}) do |(glpi_field, chatwoot_field), result|
    value = conversation.custom_attributes[chatwoot_field]
    result[glpi_field] = value if value.present?
  end
end
```

2. **Update settings schema** in apps.yml:
```yaml
settings_json_schema:
  properties:
    # ... existing properties
    custom_fields:
      type: object
      description: Map Chatwoot custom attributes to GLPI fields
```

---

## Performance Considerations

### Session Management

**Problem**: Creating a new session for every API call is expensive

**Solution**: BaseClient uses `with_session` pattern to reuse session across multiple operations:

```ruby
# Good: Single session for multiple operations
client.with_session do |session_token|
  user_id = create_user(user_data)
  ticket_id = create_ticket(ticket_data)
  create_followup(ticket_id, followup_data)
end

# Bad: Multiple sessions
user_id = client.create_user(user_data)      # Session 1
ticket_id = client.create_ticket(ticket_data) # Session 2
client.create_followup(ticket_id, followup_data) # Session 3
```

### Message Syncing

**Problem**: Syncing all messages on every conversation update is inefficient

**Solution**: Incremental sync using `last_synced_message_id`:

```ruby
def messages_to_sync(conversation)
  last_synced_id = conversation.additional_attributes.dig('glpi', 'last_synced_message_id')

  if last_synced_id
    conversation.messages.where('id > ?', last_synced_id)
  else
    conversation.messages
  end
end
```

### Batch Operations

**Current**: One API call per message followup
**Future**: Batch followup creation in single API call

```ruby
# Future enhancement
def create_followups_batch(ticket_id, followups_data)
  with_session do
    response = self.class.post(
      "#{@api_url}/Ticket/#{ticket_id}/ITILFollowup",
      headers: session_headers,
      body: { input: followups_data }.to_json  # Array of followups
    )
    handle_response(response)
  end
end
```

### Caching

**Consideration**: Cache GLPI entity IDs to reduce search queries

```ruby
# Example implementation
def find_or_create_user(contact)
  # Check cache first
  cached_user_id = Rails.cache.read("glpi:user:#{contact.email}")
  return cached_user_id if cached_user_id

  # Search GLPI
  user_id = search_or_create_user(contact)

  # Cache for 1 hour
  Rails.cache.write("glpi:user:#{contact.email}", user_id, expires_in: 1.hour)

  user_id
end
```

---

## Security

### Token Storage

- **App Token** and **User Token** stored encrypted in `hook.settings`
- Never exposed in visible_properties
- Only transmitted over HTTPS

### Session Security

- Sessions killed immediately after use in ensure blocks
- No long-lived sessions
- Session tokens never persisted

### Rate Limiting

**Current**: No rate limiting
**Recommendation**: Implement rate limiting for high-volume accounts

```ruby
# Example implementation
def rate_limit_check(hook_id)
  key = "glpi:rate_limit:#{hook_id}"
  count = Redis.current.incr(key)
  Redis.current.expire(key, 1.minute) if count == 1

  raise RateLimitError if count > 100 # 100 requests per minute
end
```

---

## Monitoring

### Logging

**Key Log Points**:
```ruby
Rails.logger.info "[GLPI] Processing #{event_name} for hook #{@hook.id}"
Rails.logger.info "[GLPI] Created user #{user_id} for contact #{contact.id}"
Rails.logger.error "[GLPI] API error: #{e.message}"
```

### Metrics

**Recommended Metrics**:
- Event processing time
- API call duration
- Success/failure rates
- Session creation frequency
- Queue depth (Sidekiq)

**Example Implementation**:
```ruby
def process_event_with_metrics(event_name, event_data)
  start_time = Time.current
  result = process_event(event_name, event_data)
  duration = Time.current - start_time

  StatsD.increment('glpi.events.processed', tags: ["event:#{event_name}"])
  StatsD.histogram('glpi.event_duration', duration, tags: ["event:#{event_name}"])
  StatsD.increment('glpi.events.success') if result[:success]
  StatsD.increment('glpi.events.failure') unless result[:success]

  result
end
```

---

## Troubleshooting

### Debugging Tips

1. **Enable debug logging**:
```ruby
# In Rails console
Rails.logger.level = Logger::DEBUG
```

2. **Check Sidekiq**:
```bash
# Visit /sidekiq in browser
# Or via Rails console
Sidekiq::Queue.new('medium').size
Sidekiq::RetrySet.new.each { |job| puts job['error_message'] if job['class'] == 'HookJob' }
```

3. **Inspect metadata**:
```ruby
# Contact metadata
contact.additional_attributes.dig('external', 'glpi_user_id')

# Conversation metadata
conversation.additional_attributes.dig('glpi', 'ticket_id')
conversation.additional_attributes.dig('glpi', 'last_synced_message_id')
```

4. **Test API connectivity**:
```ruby
hook = Integrations::Hook.find(YOUR_HOOK_ID)
service = Crm::Glpi::SetupService.new(hook)
result = service.validate_and_test
puts result
```

5. **Manual event trigger**:
```ruby
hook = Integrations::Hook.find(YOUR_HOOK_ID)
contact = Contact.find(YOUR_CONTACT_ID)
processor = Crm::Glpi::ProcessorService.new(hook)
result = processor.process_event('contact.created', contact)
puts result
```

---

## Future Enhancements

### Planned Features

1. **Bidirectional Sync**: GLPI → Chatwoot updates via webhooks
2. **Bulk Import**: Historical data synchronization tool
3. **Custom Field Mapping**: Configure field mappings in UI
4. **Multi-Entity Support**: Support syncing to multiple GLPI entities
5. **Advanced Filtering**: Sync only specific conversations based on rules
6. **Attachment Upload**: Upload actual files, not just URLs
7. **Dashboard**: Sync statistics and monitoring UI

### Architecture Improvements

1. **Service Object Pattern**: Extract more granular service objects
2. **Event Sourcing**: Track all sync operations for audit
3. **Async Batch Processing**: Batch API operations for efficiency
4. **Connection Pooling**: Reuse HTTP connections
5. **Circuit Breaker**: Prevent cascading failures during GLPI downtime

---

## Contributing

### Code Style

- Follow RuboCop rules (150 character max line length)
- Use YARD documentation for all public methods
- Write descriptive method and variable names
- Keep methods under 30 lines when possible
- Use `.compact` to remove nil values from hashes

### Testing Requirements

- Maintain ~96% test coverage
- Write tests before implementation (TDD)
- Use WebMock for all external API calls
- Test both success and error paths
- Include edge cases (nil, blank, malformed data)

### Documentation

- Update this guide when adding new features
- Keep YARD comments in sync with code
- Add examples for complex functionality
- Document breaking changes clearly

### Pull Request Process

1. Create feature branch from `main`
2. Implement feature with tests
3. Run RuboCop: `bundle exec rubocop -a`
4. Run tests: `bundle exec rspec spec/services/crm/glpi/`
5. Update documentation
6. Submit PR with clear description

---

## References

- **GLPI REST API**: https://github.com/glpi-project/glpi/blob/main/apirest.md
- **Chatwoot Architecture**: https://www.chatwoot.com/docs/
- **HTTParty**: https://github.com/jnunemaker/httparty
- **WebMock**: https://github.com/bblimke/webmock
- **RSpec**: https://rspec.info/

---

## Support

For technical questions or issues:
1. Check this developer guide
2. Review test suite for examples
3. Check GLPI API documentation
4. File GitHub issue with reproduction steps

---

**Version**: 1.0.0
**Last Updated**: 2025-11-05
**Maintainer**: Chatwoot Team
