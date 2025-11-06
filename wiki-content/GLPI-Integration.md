# GLPI Integration

Complete IT Service Management (ITSM) integration between Chatwoot and GLPI, enabling seamless synchronization of contacts, conversations, and tickets.

## 📋 Overview

The GLPI integration automatically synchronizes your Chatwoot conversations with GLPI tickets, contacts with GLPI users, and messages with ticket followups. This creates a unified workflow between your customer support platform and IT service management system.

### Key Features

✅ **Contact Synchronization** - Chatwoot contacts sync to GLPI Users or Contacts
✅ **Automatic Ticket Creation** - Conversations automatically create GLPI tickets
✅ **Message Sync** - Messages sync as ITILFollowups (when enabled)
✅ **Bi-directional Status Updates** - Conversation resolution updates ticket status
✅ **Duplicate Prevention** - Email/phone matching prevents duplicate records
✅ **Session Management** - Automatic reconnection and cleanup
✅ **Mutex Locking** - Race condition prevention for concurrent operations
✅ **Error Handling** - Robust error handling with logging

### Architecture

The integration follows Chatwoot's standard CRM integration pattern:

```
Chatwoot Event → HookListener → HookJob → GLPI ProcessorService
                                              ↓
                                    [Mappers + API Clients]
                                              ↓
                                         GLPI REST API
```

**Components**:
- **API Clients**: HTTP communication with GLPI REST API
- **Mappers**: Data transformation between Chatwoot and GLPI formats
- **Services**: Business logic for synchronization
- **Listeners/Jobs**: Event handling and background processing

## 🚀 Quick Start

### Prerequisites

1. **GLPI Instance**: GLPI 9.5+ or 10.x running and accessible
2. **GLPI API Enabled**: REST API must be enabled in GLPI settings
3. **API Credentials**: Application token and user token from GLPI
4. **Chatwoot**: This kennis-ai fork with GLPI integration

### Setup Steps

#### 1. Enable GLPI API

In your GLPI instance:

1. Go to **Setup → General → API**
2. Enable **Enable REST API**
3. Note the **API base URL**: `https://your-glpi-domain.com/apirest.php`

#### 2. Create API Tokens

**Application Token** (Admin):
1. Go to **Setup → General → API**
2. Click **Add API client**
3. Copy the generated **App Token**

**User Token**:
1. Go to **Administration → Users**
2. Select your API user
3. Go to **Remote access keys** tab
4. Generate a new **API token**
5. Copy the token

#### 3. Configure in Chatwoot

1. Log in to Chatwoot as administrator
2. Go to **Settings → Integrations → CRM**
3. Find **GLPI** and click **Connect**
4. Fill in the configuration:

```
API Base URL: https://your-glpi-domain.com/apirest.php
App Token: your_app_token_here
User Token: your_user_token_here
```

**Optional Settings**:
- **Sync Messages**: Enable to sync conversation messages as ticket followups
- **Default Entity**: GLPI entity ID (default: 0 for root entity)
- **Default Category**: GLPI ticket category ID (optional)

5. Click **Test Connection** to verify
6. Click **Save** to enable the integration

#### 4. Test the Integration

1. Create a new conversation in Chatwoot
2. Check GLPI for the created ticket
3. Send a message in the conversation
4. Check GLPI ticket for the followup (if message sync is enabled)
5. Resolve the conversation in Chatwoot
6. Verify the ticket status changed to "Solved" in GLPI

## 📖 User Guide

### How It Works

#### Contact Synchronization

When a conversation is created:

1. Chatwoot checks if contact exists in GLPI (by email or phone)
2. If not found:
   - Creates GLPI User (if contact has email)
   - OR creates GLPI Contact (if no email, phone only)
3. If found: Uses existing GLPI record
4. Stores GLPI ID in contact's `additional_attributes`

**Contact Mapping**:
- `name` → GLPI `realname` / `firstname`
- `email` → GLPI `email` (Users) or `email` (Contacts)
- `phone_number` → GLPI `phone` or `mobile`
- `additional_attributes.glpi_user_id` → Stores GLPI User ID
- `additional_attributes.glpi_contact_id` → Stores GLPI Contact ID

#### Conversation → Ticket

When a conversation is created:

1. Contact sync happens first (see above)
2. Ticket is created in GLPI with:
   - **Title**: First 50 chars of first message
   - **Description**: Full first message with HTML formatting
   - **Requester**: GLPI User/Contact from step 1
   - **Status**: New (1) or Assigned (2) if agent assigned
   - **Entity**: From hook settings
   - **Category**: From hook settings (optional)
3. Ticket ID stored in conversation's `additional_attributes.glpi_ticket_id`
4. Ticket URL stored for quick access

**Conversation Mapping**:
- `messages.first.content` → Ticket `name` (title) + `content` (description)
- `status` → Ticket `status` (pending=2, resolved=5, open=2)
- `assignee` → Ticket `assigned_to_users_id`
- `account_id` → Ticket `entities_id`
- `additional_attributes.glpi_ticket_id` → Stores ticket ID

#### Message → ITILFollowup

When a message is created (if sync enabled):

1. Finds associated GLPI ticket from conversation
2. Creates ITILFollowup with:
   - **Content**: Message content with HTML formatting
   - **Requester Type**: User (2) for incoming, System (1) for outgoing
   - **Is Private**: Based on message visibility
3. Followup ID stored in message's `external_source_ids`

**Message Mapping**:
- `content` → Followup `content`
- `message_type` (incoming=2, outgoing=1) → `requesttypes_id`
- `private` → `is_private`
- `sender.name` → Included in content as "From: {name}"

#### Conversation Resolution

When conversation is resolved:

1. Finds associated GLPI ticket
2. Updates ticket status to "Solved" (5)
3. Optionally adds resolution followup

### Configuration Options

#### Hook Settings

- **`api_base_url`** (required): GLPI API endpoint URL
- **`app_token`** (required): Application token from GLPI
- **`user_token`** (required): User token from GLPI
- **`sync_messages`** (optional, default: false): Sync messages as followups
- **`entities_id`** (optional, default: 0): GLPI entity ID
- **`itilcategories_id`** (optional): Default ticket category

#### Entity & Category IDs

Find these in GLPI:

**Entity ID**:
```sql
-- In GLPI database
SELECT id, name FROM glpi_entities;
```

**Category ID**:
```sql
-- In GLPI database
SELECT id, name FROM glpi_itilcategories;
```

Or use the GLPI API:
```bash
# Get entities
curl -X GET 'https://your-glpi/apirest.php/Entity/' \
  -H "App-Token: YOUR_APP_TOKEN" \
  -H "Session-Token: YOUR_SESSION_TOKEN"

# Get categories
curl -X GET 'https://your-glpi/apirest.php/ITILCategory/' \
  -H "App-Token: YOUR_APP_TOKEN" \
  -H "Session-Token: YOUR_SESSION_TOKEN"
```

### Troubleshooting

See [[GLPI Troubleshooting]] for common issues and solutions.

#### Quick Checks

**Integration not working?**

1. Check Chatwoot logs: `tail -f log/production.log | grep GLPI`
2. Verify GLPI API is enabled and accessible
3. Test connection in Chatwoot settings
4. Check GLPI API logs: Setup → General → Logs → API logs

**Tickets not creating?**

1. Verify hook is enabled: Settings → Integrations → CRM → GLPI
2. Check contact has email or phone
3. Verify entity ID exists in GLPI
4. Check category ID is valid (if set)

**Messages not syncing?**

1. Enable message sync in hook settings
2. Verify ticket ID is stored in conversation attributes
3. Check message content is not empty

## 🔧 Developer Guide

### Implementation Details

The GLPI integration is implemented in 6 phases:

1. **Phase 1**: API Clients - HTTP communication layer
2. **Phase 2**: Mappers - Data transformation
3. **Phase 3**: Services - Business logic
4. **Phase 4**: Integration - Wiring into Chatwoot
5. **Phase 5**: Testing - Comprehensive tests
6. **Phase 6**: Documentation - User & developer docs

See [[GLPI Implementation Plan]] for full technical details.

### Code Structure

```
app/services/crm/glpi/
├── api/
│   ├── base_client.rb         # Session management, HTTP methods
│   ├── user_client.rb          # User CRUD
│   ├── contact_client.rb       # Contact CRUD
│   ├── ticket_client.rb        # Ticket CRUD
│   └── followup_client.rb      # Followup CRUD
├── mappers/
│   ├── contact_mapper.rb       # Chatwoot Contact → GLPI User/Contact
│   ├── conversation_mapper.rb  # Chatwoot Conversation → GLPI Ticket
│   └── message_mapper.rb       # Chatwoot Message → GLPI ITILFollowup
├── setup_service.rb            # Validate and test configuration
├── user_finder_service.rb      # Find/create GLPI Users
├── contact_finder_service.rb   # Find/create GLPI Contacts
└── processor_service.rb        # Main event handler
```

### Key Classes

#### BaseClient

Manages GLPI API sessions and HTTP requests.

```ruby
client = Crm::Glpi::Api::BaseClient.new(hook)
client.with_session do
  # Session automatically managed
  users = client.get('/User')
end
# Session automatically closed
```

#### ProcessorService

Main event handler that orchestrates the sync process.

```ruby
service = Crm::Glpi::ProcessorService.new(hook, event_name, event_data)
service.perform
```

**Events Handled**:
- `contact_created` - Sync contact to GLPI
- `conversation_created` - Create ticket in GLPI
- `conversation_status_changed` - Update ticket status
- `message_created` - Create followup (if enabled)

### Testing

#### Unit Tests

```bash
# All GLPI tests
bundle exec rspec spec/services/crm/glpi/

# API clients
bundle exec rspec spec/services/crm/glpi/api/

# Mappers
bundle exec rspec spec/services/crm/glpi/mappers/

# Services
bundle exec rspec spec/services/crm/glpi/*_service_spec.rb
```

#### Integration Tests

```bash
# Start local GLPI instance
docker run -d --name glpi-test \
  -p 8080:80 \
  -e GLPI_INSTALL=true \
  diouxx/glpi:latest

# Access: http://localhost:8080
# Credentials: glpi/glpi

# Run integration tests
bundle exec rspec spec/services/crm/glpi/integration/
```

#### Test Coverage

Target: >90% coverage

```bash
# Generate coverage report
COVERAGE=true bundle exec rspec spec/services/crm/glpi/

# View report
open coverage/index.html
```

### API Reference

#### GLPI REST API Endpoints

**Session Management**:
- `POST /initSession` - Initialize session
- `GET /killSession` - Close session

**Resources**:
- `GET /User` - List users
- `GET /User/:id` - Get user
- `POST /User` - Create user
- `PUT /User/:id` - Update user
- `GET /Contact` - List contacts
- `POST /Contact` - Create contact
- `GET /Ticket` - List tickets
- `POST /Ticket` - Create ticket
- `PUT /Ticket/:id` - Update ticket
- `POST /Ticket/:id/ITILFollowup` - Add followup

**Authentication Headers**:
```
App-Token: {app_token}
Session-Token: {session_token}
Content-Type: application/json
```

### Extending the Integration

#### Adding New Mappings

1. Create mapper in `app/services/crm/glpi/mappers/`
2. Follow existing patterns (ContactMapper, ConversationMapper)
3. Add tests in `spec/services/crm/glpi/mappers/`

#### Handling New Events

1. Add event handler in `ProcessorService#perform`
2. Implement sync logic
3. Add tests

#### Custom Fields

GLPI custom fields can be mapped via hook settings:

```ruby
# In hook settings
{
  "custom_field_mappings": {
    "chatwoot_field": "glpi_field_id"
  }
}
```

## 📚 Additional Resources

- [[GLPI Implementation Plan]] - Complete technical specification
- [[GLPI Troubleshooting]] - Common issues and solutions
- [GLPI REST API Documentation](https://glpi-project.org/documentation/)
- [GLPI GitHub Repository](https://github.com/glpi-project/glpi)

## 🐛 Known Issues

1. **Session Timeout**: Long-running operations may timeout. The client auto-reconnects.
2. **Entity Permissions**: User token must have access to specified entity.
3. **Category Restrictions**: Category must be valid for tickets in the entity.

## 🔄 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-11-05 | Initial release - All 6 phases complete |

---

**Need Help?** See [[GLPI Troubleshooting]] or create an issue on [GitHub](https://github.com/kennis-ai/chatwoot/issues).
