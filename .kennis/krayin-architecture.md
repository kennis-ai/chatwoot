# Krayin CRM Integration - Architecture Documentation

## Overview

This document describes the technical architecture of the Krayin CRM integration for Chatwoot.

## System Architecture

### High-Level Architecture

```
┌─────────────────┐
│   Chatwoot UI   │
│  (Vue.js SPA)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│  Rails Backend  │◄────►│  Redis (Mutex)   │
│   (Event Bus)   │      └──────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Hook Listener  │  Filters by event type
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Hook Job     │  Queue: medium, Redis lock
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Processor Service│  Business logic orchestration
└────────┬────────┘
         │
         ├──────┬──────┬──────────┐
         ▼      ▼      ▼          ▼
    ┌────────┬──────┬──────┬───────────┐
    │ Person │ Lead │ Org  │ Activity  │  Finder Services
    │ Finder │Finder│Finder│  Mapper   │
    └────┬───┴──┬───┴──┬───┴──────┬────┘
         │      │      │          │
         ▼      ▼      ▼          ▼
    ┌────────────────────────────────┐
    │      API Client Layer          │
    │  (PersonClient, LeadClient,    │
    │   OrganizationClient,          │
    │   ActivityClient)              │
    └───────────────┬────────────────┘
                    │ HTTPS + Bearer Token
                    ▼
        ┌──────────────────────┐
        │   Krayin CRM API     │
        │  (Laravel Sanctum)   │
        └──────────────────────┘
```

## Component Details

### 1. Event System

#### HookListener (`app/listeners/hook_listener.rb`)

**Purpose**: Listens to Chatwoot events and triggers appropriate hooks.

**Events Handled**:
- `contact.created`
- `contact.updated`
- `conversation.created`
- `conversation.updated`
- `message.created`

**Flow**:
```ruby
Event Triggered
  ↓
HookListener receives event
  ↓
Check if event supported for Krayin
  ↓
Find all hooks for account/inbox
  ↓
Filter by app_id = 'krayin'
  ↓
Enqueue HookJob for each hook
```

**Key Methods**:
- `supported_hook_event?(hook, event_name)`: Validates event/hook compatibility
- `execute_hooks(event, message)`: For message-based events
- `execute_account_hooks(event, account, event_data)`: For account-level events

### 2. Job Layer

#### HookJob (`app/jobs/hook_job.rb`)

**Purpose**: Asynchronous job processing with Redis mutex for race condition protection.

**Queue**: `medium` priority
**Retry**: 3 attempts on `LockAcquisitionError`

**Flow**:
```ruby
Job Enqueued
  ↓
Check if hook disabled → Exit if disabled
  ↓
Acquire Redis lock (CRM_PROCESS_MUTEX)
  ↓
Route to appropriate processor
  ↓
Process event → Krayin API calls
  ↓
Release lock
```

**Redis Mutex**:
- **Key Format**: `chatwoot:crm:process:mutex:hook_id:{hook_id}`
- **Purpose**: Prevents race conditions when rapid-fire events occur
- **Timeout**: Default 3 seconds per attempt

**Processing Methods**:
- `process_krayin_integration_with_lock`: Wrapper with mutex
- `process_krayin_integration`: Actual processing logic

### 3. Processor Service

#### ProcessorService (`app/services/crm/krayin/processor_service.rb`)

**Purpose**: Core orchestration service handling all Krayin sync logic.

**Initialization**:
```ruby
def initialize(inbox:, event_name:, event_data:)
  @inbox = inbox
  @hook = inbox.hooks.find_by(app_id: 'krayin')
  @event_name = event_name
  @event_data = event_data
end
```

**Event Routing**:
```ruby
case @event_name
when 'contact_created', 'contact_updated'
  process_contact  # → Person + Lead + Organization
when 'conversation_created', 'conversation_updated'
  process_conversation  # → Activity
when 'message_created'
  process_message  # → Activity
end
```

**Contact Processing Flow**:
```
1. Check if organization sync enabled
   └─> YES: Create/update organization
2. Find or create Person (PersonFinderService)
3. Store Person external ID
4. Link Person to Organization (if exists)
5. Find or create Lead (LeadFinderService)
6. Store Lead external ID
7. Update lead stage (if progression enabled)
```

**Conversation Processing Flow**:
```
1. Extract Person ID from contact external IDs
2. Map conversation data (ConversationMapper)
3. Check if activity exists (by external ID)
   └─> YES: Update existing activity
   └─> NO: Create new activity
4. Store Activity external ID
5. Update lead stage (if progression enabled)
```

**External ID Management**:
- **Format**: `krayin:person:123|krayin:lead:456|krayin:organization:789|krayin:activity:101`
- **Storage**: `contact_inboxes.source_id` field
- **Methods**:
  - `store_external_id(record, type, external_id)`: Store ID
  - `get_external_id(record, type)`: Retrieve ID
  - `extract_external_id(source_id, type)`: Parse ID
  - `parse_external_ids(source_id)`: Parse all IDs
  - `build_source_id_string(ids_hash)`: Build multi-ID format

### 4. Finder Services

#### PersonFinderService (`app/services/crm/krayin/person_finder_service.rb`)

**Purpose**: Find existing Person or create new one in Krayin.

**Search Strategy**:
1. Search by email (if present)
2. Search by phone (if email not found)
3. Create new Person if not found

**Flow**:
```ruby
Initialize with PersonClient + Contact
  ↓
Check for existing external ID
  ├─> Found: Get Person by ID
  └─> Not Found: Search by email/phone
      ├─> Found: Return existing Person
      └─> Not Found: Create new Person
```

#### LeadFinderService (`app/services/crm/krayin/lead_finder_service.rb`)

**Purpose**: Find existing Lead or create new one linked to Person.

**Search Strategy**:
1. Check for existing external ID
2. Search by email/phone (if no ID)
3. Create new Lead with Person link

**Flow**:
```ruby
Initialize with LeadClient + Contact + PersonID + Settings
  ↓
Check for existing external ID
  ├─> Found: Update existing Lead
  └─> Not Found: Search by email/phone
      ├─> Found: Update existing Lead
      └─> Not Found: Create new Lead
```

### 5. Mapper Layer

#### ContactMapper (`app/services/crm/krayin/mappers/contact_mapper.rb`)

**Purpose**: Transform Chatwoot Contact to Krayin Person/Lead/Organization format.

**Methods**:

```ruby
# Maps to Person entity
def map_to_person
  {
    name: contact.name,
    emails: [{value: contact.email, label: 'work'}],
    contact_numbers: [{value: format_phone(contact.phone_number), label: 'work'}],
    job_title: contact.additional_attributes&.dig('job_title')
  }
end

# Maps to Lead entity
def map_to_lead(person_id, settings)
  {
    title: contact.name,
    person_id: person_id,
    lead_value: extract_lead_value,
    description: build_description,
    lead_pipeline_id: settings['default_pipeline_id'],
    lead_pipeline_stage_id: settings['default_stage_id'],
    lead_source_id: settings['default_source_id'],
    lead_type_id: settings['default_lead_type_id']
  }
end

# Maps to Organization entity (optional)
def map_to_organization
  {
    name: extract_company_name,
    address: extract_company_address
  }
end
```

**Phone Formatting**:
- Uses `TelephoneNumber` gem
- Converts to E.164 format: `+1234567890`
- Fallback to original on parse error

#### ConversationMapper (`app/services/crm/krayin/mappers/conversation_mapper.rb`)

**Purpose**: Transform Conversation to Krayin Activity format.

**Activity Type Detection**:
```ruby
def determine_activity_type
  case inbox_channel_type
  when 'Channel::Email' then 'email'
  when 'Channel::TwilioSms', 'Channel::Sms' then 'call'
  when 'Channel::Whatsapp' then 'call'
  else 'note'
  end
end
```

**Activity Mapping**:
```ruby
{
  type: determine_activity_type,
  title: "Conversation ##{conversation.display_id}",
  comment: build_activity_comment,  # Rich markdown with details
  person_id: person_id,
  is_done: conversation.status == 'resolved'
}
```

#### MessageMapper (`app/services/crm/krayin/mappers/message_mapper.rb`)

**Purpose**: Transform Message to Krayin Activity format.

**Activity Type Detection**:
- Inbox channel-based (same as ConversationMapper)
- Fallback to message type (outgoing→email, incoming→note)

**Activity Mapping**:
```ruby
{
  type: activity_type,
  title: "Message from #{sender_name} - Conversation ##{conversation_id}",
  comment: build_activity_comment,  # Message content + attachments + context
  person_id: person_id,
  is_done: true  # Messages are always complete
}
```

### 6. API Client Layer

#### BaseClient (`app/services/crm/krayin/api/base_client.rb`)

**Purpose**: Base HTTP client with retry logic and error handling.

**Features**:
- HTTParty-based REST client
- Bearer token authentication
- Automatic retry with exponential backoff
- Rate limit handling
- Comprehensive error messages

**HTTP Methods**:
```ruby
get(path, params = {})
post(path, body = {}, params = {})
put(path, body = {}, params = {})
delete(path, params = {})
```

**Retry Logic**:
```ruby
MAX_RETRIES = 3
INITIAL_BACKOFF = 1 second

Retriable Errors: 429, 502, 503, 504
Backoff: 2^attempt for errors, 3^attempt for rate limits
```

**Error Handling**:
- 401: Unauthorized (invalid token)
- 403: Forbidden (insufficient permissions)
- 404: Not Found
- 422: Validation Failed
- 429: Rate Limit (respects Retry-After header)
- 500: Internal Server Error
- 502/503/504: Service Unavailable (retriable)

#### PersonClient (`app/services/crm/krayin/api/person_client.rb`)

**Endpoints**:
- `search_person(email:, phone:)`: POST `/persons/search`
- `create_person(person_data)`: POST `/persons`
- `update_person(person_data, person_id)`: PUT `/persons/{id}`
- `get_person(person_id)`: GET `/persons/{id}`

#### LeadClient (`app/services/crm/krayin/api/lead_client.rb`)

**Endpoints**:
- `search_lead(email:, phone:)`: POST `/leads/search`
- `create_lead(lead_data)`: POST `/leads`
- `update_lead(lead_data, lead_id)`: PUT `/leads/{id}`
- `get_lead(lead_id)`: GET `/leads/{id}`
- `get_pipelines()`: GET `/settings/pipelines`
- `get_stages(pipeline_id)`: GET `/settings/stages`
- `get_sources()`: GET `/settings/sources`
- `get_types()`: GET `/settings/types`

#### OrganizationClient (`app/services/crm/krayin/api/organization_client.rb`)

**Endpoints**:
- `search_organization(name)`: GET `/contacts/organizations?name={name}`
- `create_organization(org_data)`: POST `/contacts/organizations`
- `update_organization(org_data, org_id)`: PUT `/contacts/organizations/{id}`
- `get_organization(org_id)`: GET `/contacts/organizations/{id}`

#### ActivityClient (`app/services/crm/krayin/api/activity_client.rb`)

**Endpoints**:
- `create_activity(activity_data)`: POST `/activities`
- `update_activity(activity_data, activity_id)`: PUT `/activities/{id}`
- `get_activity(activity_id)`: GET `/activities/{id}`

### 7. Setup Service

#### SetupService (`app/services/crm/krayin/setup_service.rb`)

**Purpose**: Initial integration setup and configuration fetch.

**Triggered**: When hook is created via `after_create :trigger_setup_if_crm` callback.

**Process**:
1. Validate API connection (test pipelines endpoint)
2. Fetch default configuration:
   - Pipelines (select first/default)
   - Stages (select first stage of pipeline)
   - Sources (prefer 'Website'/'Web', otherwise first)
   - Types (select first)
3. Cache configuration (1 hour TTL)
4. Store in hook settings

**Configuration Keys**:
```ruby
{
  'api_url' => 'https://crm.example.com/api/admin',
  'api_token' => '1|...',
  'default_pipeline_id' => 1,
  'default_pipeline_name' => 'Sales Pipeline',
  'default_stage_id' => 1,
  'default_stage_name' => 'New',
  'default_source_id' => 2,
  'default_source_name' => 'Website',
  'default_lead_type_id' => 1,
  'default_lead_type_name' => 'Customer'
}
```

## Data Flow Diagrams

### Contact Creation Flow

```
Contact Created in Chatwoot
  ↓
Event: contact.created
  ↓
HookListener.contact_created
  ├─> Filter by hook.app_id == 'krayin'
  └─> HookJob.perform_later(hook, 'contact.created', contact: contact)
      ↓
HookJob (Redis Lock Acquired)
  ├─> process_krayin_integration_with_lock
  └─> ProcessorService.perform
      ├─> Organization Sync (if enabled)
      │   ├─> Search organization by name
      │   └─> Create if not found
      │       └─> Store external ID: krayin:organization:789
      │
      ├─> Person Sync
      │   ├─> PersonFinderService
      │   │   ├─> Search by email
      │   │   └─> Create if not found
      │   └─> Store external ID: krayin:person:123
      │       └─> Link to Organization (if exists)
      │
      └─> Lead Sync
          ├─> LeadFinderService
          │   ├─> Search by email
          │   └─> Create if not found
          └─> Store external ID: krayin:lead:456
              └─> Update stage (if progression enabled)

Result: contact_inboxes.source_id = "krayin:person:123|krayin:lead:456|krayin:organization:789"
```

### Conversation Sync Flow

```
Conversation Created in Chatwoot
  ↓
Event: conversation.created
  ↓
HookListener.conversation_created
  └─> HookJob.perform_later(hook, 'conversation.created', conversation: conversation)
      ↓
HookJob (Redis Lock Acquired)
  └─> ProcessorService.process_conversation
      ├─> Get Person ID from contact external IDs
      ├─> ConversationMapper.map_to_activity
      │   ├─> Determine activity type (email/call/note)
      │   ├─> Build title: "Conversation #123"
      │   └─> Build comment with details
      │
      ├─> Check existing activity ID
      │   ├─> Found: Update activity
      │   └─> Not Found: Create activity
      │
      ├─> Store external ID: krayin:activity:101
      │
      └─> Update lead stage (if progression enabled)
          └─> Determine stage based on conversation status

Result: Additional attributes: { krayin_activity_id: 101 }
```

## Database Schema

### contact_inboxes

```sql
CREATE TABLE contact_inboxes (
  id BIGINT PRIMARY KEY,
  contact_id BIGINT NOT NULL,
  inbox_id BIGINT NOT NULL,
  source_id VARCHAR,  -- Krayin external IDs stored here
  created_at TIMESTAMP,
  updated_at TIMESTAMP,

  -- Indexes for performance
  INDEX idx_contact_inboxes_krayin (source_id) WHERE source_id LIKE 'krayin:%',
  INDEX idx_contact_inboxes_inbox_krayin (inbox_id, source_id) WHERE source_id LIKE 'krayin:%'
);

-- Example source_id value:
-- "krayin:person:123|krayin:lead:456|krayin:organization:789|krayin:activity:101"
```

### integrations_hooks

```sql
CREATE TABLE integrations_hooks (
  id BIGINT PRIMARY KEY,
  account_id BIGINT,
  inbox_id BIGINT,
  app_id VARCHAR,  -- 'krayin'
  hook_type INTEGER,  -- 0=account, 1=inbox
  status INTEGER,  -- 0=disabled, 1=enabled
  settings JSONB,  -- Configuration
  access_token VARCHAR ENCRYPTED,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Example settings JSONB:
{
  "api_url": "https://crm.example.com/api/admin",
  "api_token": "1|...",
  "default_pipeline_id": 1,
  "default_stage_id": 1,
  "default_source_id": 2,
  "default_lead_type_id": 1,
  "sync_conversations": true,
  "sync_messages": false,
  "sync_to_organization": true,
  "stage_progression_enabled": true,
  "stage_on_conversation_created": 2,
  "stage_on_first_response": 3,
  "stage_on_conversation_resolved": 4
}
```

## Configuration Management

### Hook Settings Schema

```ruby
{
  # Required - Basic Auth
  api_url: String,
  api_token: String,

  # Auto-fetched - Defaults
  default_pipeline_id: Integer,
  default_pipeline_name: String,
  default_stage_id: Integer,
  default_stage_name: String,
  default_source_id: Integer,
  default_source_name: String,
  default_lead_type_id: Integer,
  default_lead_type_name: String,

  # Optional - Manual Override
  lead_pipeline_id: Integer,
  lead_pipeline_stage_id: Integer,
  lead_source_id: Integer,
  lead_type_id: Integer,

  # Sync Options
  sync_conversations: Boolean,  # default: false
  sync_messages: Boolean,  # default: false
  sync_to_organization: Boolean,  # default: false

  # Stage Progression
  stage_progression_enabled: Boolean,  # default: false
  stage_on_conversation_created: Integer,
  stage_on_first_response: Integer,
  stage_on_conversation_resolved: Integer
}
```

## Performance Considerations

### Database Optimization

1. **Partial Indexes**:
   ```sql
   CREATE INDEX idx_krayin_source_id
   ON contact_inboxes(source_id)
   WHERE source_id LIKE 'krayin:%';
   ```
   - **Benefit**: 10-100x faster lookups
   - **Size**: Much smaller than full index

2. **Composite Indexes**:
   ```sql
   CREATE INDEX idx_inbox_krayin
   ON contact_inboxes(inbox_id, source_id)
   WHERE source_id LIKE 'krayin:%';
   ```
   - **Benefit**: Fast inbox-specific queries

### API Optimization

1. **Configuration Caching**:
   - **TTL**: 1 hour
   - **Key**: MD5(api_url)
   - **Benefit**: ~90% reduction in setup API calls

2. **Retry with Backoff**:
   - **Max Retries**: 3
   - **Backoff**: Exponential (2^attempt)
   - **Rate Limit Backoff**: 3^attempt
   - **Benefit**: Automatic recovery from transient failures

### Concurrency Protection

1. **Redis Mutex**:
   - **Lock Key**: `chatwoot:crm:process:mutex:hook_id:{id}`
   - **Purpose**: Prevent race conditions on rapid events
   - **Example**: contact.created → contact.updated → conversation.created in <1 second

## Error Handling Strategy

### Error Types

1. **Retriable Errors** (Auto-retry):
   - 429: Rate Limit Exceeded
   - 502: Bad Gateway
   - 503: Service Unavailable
   - 504: Gateway Timeout

2. **Non-Retriable Errors** (Fail immediately):
   - 401: Unauthorized (invalid token)
   - 403: Forbidden (insufficient permissions)
   - 404: Not Found
   - 422: Validation Failed
   - 500: Internal Server Error

### Error Recovery

```
API Request → Failure
  ↓
Is error retriable?
  ├─> YES: Calculate backoff → Wait → Retry (up to 3 times)
  └─> NO: Log error → Raise exception → Sidekiq retry (3 times)
```

### Logging

All operations logged with context:
```
INFO: Krayin ProcessorService - Processing contact 123
INFO: Krayin ProcessorService - Contact 123 synced. Person: 456, Lead: 789
ERROR: Krayin ProcessorService - Failed to process contact 123: API Error
WARN: Krayin API GET /leads/pipelines failed (attempt 2/3): Rate limit. Retrying in 4s...
```

## Testing Strategy

### Unit Tests

- **Location**: `spec/services/crm/krayin/`
- **Coverage**: All service classes
- **Mocking**: WebMock for HTTP calls
- **Pattern**: RSpec with describe/context/it

### Integration Tests

- **Location**: `spec/integration/krayin_integration_spec.rb`
- **Coverage**: End-to-end flows
- **Scenarios**:
  - Complete contact sync
  - Complete conversation sync
  - Concurrent event handling
  - Error scenarios
  - Feature flag enforcement

### Test Execution

```bash
# All Krayin tests
rspec spec/services/crm/krayin/

# Integration tests
rspec spec/integration/krayin_integration_spec.rb

# Specific service
rspec spec/services/crm/krayin/processor_service_spec.rb
```

## Deployment Considerations

### Prerequisites

1. **Database Migration**:
   ```bash
   rails db:migrate
   ```
   Creates performance indexes

2. **Feature Flag**:
   ```ruby
   account.enable_features(:crm_integration)
   ```

3. **Redis**:
   - Running for mutex locks
   - Running for cache (optional but recommended)

4. **Sidekiq**:
   - Medium queue workers
   - Minimum 2 workers recommended

### Monitoring

1. **Key Metrics**:
   - Sync success rate
   - API response times
   - Error rate
   - Queue depth

2. **Log Patterns**:
   - `"Krayin ProcessorService"`: Sync operations
   - `"Krayin API error"`: API failures
   - `"Rate limit"`: Rate limit hits
   - `"Updated lead.*stage"`: Stage progression

3. **Health Checks**:
   - Hook status: enabled/disabled
   - External ID format validation
   - API connectivity tests

## Security Considerations

### API Token Storage

- Encrypted at rest (if encryption configured)
- Never logged in plain text
- Transmitted over HTTPS only
- Rotatable without data loss

### Data Access

- Only syncs configured data
- Respects feature flags
- Respects hook enabled/disabled status
- No automatic data deletion

### Network Security

- HTTPS required for API calls
- Bearer token authentication
- SSL certificate validation
- No data caching of sensitive info

## Future Enhancements

### Planned Features

1. **Bi-directional Sync**: Krayin → Chatwoot
2. **Webhook Support**: Real-time updates from Krayin
3. **Bulk Sync Tool**: Batch import existing contacts
4. **Custom Field Mapping UI**: Configure mappings without code
5. **Sync Analytics**: Dashboard for sync metrics
6. **Advanced Stage Rules**: Label/assignment-based progression
7. **Multiple Krayin Instances**: Support multiple CRMs per account

### Extension Points

1. **Custom Mappers**: Extend mapper classes for custom fields
2. **Custom Processors**: Override processor methods for custom logic
3. **Event Hooks**: Add custom event handlers
4. **API Clients**: Extend for additional Krayin endpoints

## References

- [Krayin REST API Documentation](https://devdocs.krayincrm.com/api/)
- [Laravel Sanctum Documentation](https://laravel.com/docs/sanctum)
- [HTTParty Documentation](https://github.com/jnunemaker/httparty)
- [Sidekiq Documentation](https://github.com/mperham/sidekiq)

---

For implementation guides, see:
- [Development Guide](./krayin-development-guide.md)
- [Testing Guide](./krayin-testing-guide.md)
- [Custom Attributes Guide](./krayin-custom-attributes.md)
