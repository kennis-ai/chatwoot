# Krayin CRM Integration

## Overview

The Krayin CRM integration enables seamless synchronization between Chatwoot and your Krayin CRM instance, automatically syncing contacts, conversations, and activities in real-time.

## Features

### Core Capabilities
- ✅ **Automatic Contact Sync** - Creates and updates Person and Lead records
- ✅ **Organization Linking** - Links contacts to companies based on company information
- ✅ **Conversation Tracking** - Syncs conversations as activities in Krayin
- ✅ **Message History** - Individual messages synced as activities
- ✅ **Custom Attributes** - Rich data mapping through custom contact attributes
- ✅ **Real-time Sync** - Events processed immediately via webhooks
- ✅ **Stage Progression** - Automatic lead stage updates based on conversation lifecycle
- ✅ **Multi-Channel Support** - Intelligent activity type detection per channel

### Advanced Features
- **Retry Logic** - Automatic retry on transient failures with exponential backoff
- **Performance Optimized** - Database indexes and API call caching
- **Race Condition Protection** - Redis mutex prevents duplicate records
- **Error Handling** - Comprehensive error logging and recovery
- **Configurable Sync** - Enable/disable conversations, messages, organizations, and stage progression

## Prerequisites

Before setting up the integration, ensure you have:

1. **Krayin CRM**
   - Version 2.1.5 or higher
   - Krayin REST API Package v2.1.1 installed
   - Admin access to Krayin instance

2. **API Credentials**
   - Laravel Sanctum API token
   - API endpoint URL (e.g., `https://crm.example.com/api/admin`)

3. **Chatwoot**
   - Enterprise plan or `crm_integration` feature flag enabled
   - Admin access to Chatwoot account

## How It Works

### Data Flow

```
Chatwoot Event → Hook Listener → Hook Job → Processor Service → Krayin API
     ↓              ↓                ↓              ↓                ↓
  contact       Filter by       Queue with    Map Data to      Create/Update
  created       event type      Redis Lock    Krayin format    Person/Lead/Activity
```

### Entity Mapping

| Chatwoot | Krayin | Description |
|----------|--------|-------------|
| Contact | Person | Contact information (name, email, phone) |
| Contact | Lead | Sales opportunity with value and pipeline |
| Contact Attributes | Organization | Company information if present |
| Conversation | Activity (Note) | Conversation details and summary |
| Message | Activity (Email/Call/Note) | Individual message content |

### Event Processing

The integration processes these Chatwoot events:

| Event | Action | Krayin Entity |
|-------|--------|---------------|
| `contact.created` | Create Person + Lead | Person, Lead |
| `contact.updated` | Update Person + Lead | Person, Lead |
| `conversation.created` | Create Activity | Activity |
| `conversation.updated` | Update Activity | Activity |
| `message.created` | Create Activity | Activity |

## Configuration Options

### Basic Settings

| Setting | Type | Description | Required |
|---------|------|-------------|----------|
| **API URL** | String | Krayin API endpoint (including `/api/admin`) | Yes |
| **API Token** | String | Laravel Sanctum Bearer token | Yes |

### Sync Options

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| **Sync Conversations** | Boolean | false | Create activities for conversations |
| **Sync Messages** | Boolean | false | Create activities for each message |
| **Sync to Organizations** | Boolean | false | Create and link organizations from company data |

### Stage Progression

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| **Enable Stage Progression** | Boolean | false | Auto-update lead stages |
| **Stage on Conversation Created** | Integer | null | Stage ID when conversation starts |
| **Stage on First Response** | Integer | null | Stage ID when agent responds |
| **Stage on Conversation Resolved** | Integer | null | Stage ID when resolved |

## Setup Instructions

See the [Krayin Setup Guide](./Krayin-Setup-Guide) for detailed step-by-step instructions.

### Quick Setup

1. Navigate to **Settings** → **Integrations** in Chatwoot
2. Find **Krayin CRM** and click **Configure**
3. Enter your API URL: `https://your-krayin.com/api/admin`
4. Enter your API Token (from Krayin → Settings → API Tokens)
5. Enable desired sync options
6. Click **Connect**
7. Verify connection successful

## Field Mapping

### Contact → Person

| Chatwoot Field | Krayin Field | Notes |
|----------------|--------------|-------|
| `name` | `name` | Contact full name |
| `email` | `emails[].value` | Array format with label 'work' |
| `phone_number` | `contact_numbers[].value` | E.164 format, label 'work' |
| `additional_attributes.job_title` | `job_title` | Job title/position |

### Contact → Lead

| Chatwoot Field | Krayin Field | Notes |
|----------------|--------------|-------|
| `name` | `title` | Lead title |
| Person ID | `person_id` | Link to Person |
| `additional_attributes.lead_value` | `lead_value` | Numeric value |
| Description | `description` | Built from contact data |
| Configuration | `lead_pipeline_id` | From hook settings |
| Configuration | `lead_pipeline_stage_id` | From hook settings |
| Configuration | `lead_source_id` | From hook settings |
| Configuration | `lead_type_id` | From hook settings |

### Contact → Organization (Optional)

| Chatwoot Field | Krayin Field | Notes |
|----------------|--------------|-------|
| `additional_attributes.company_name` | `name` | Organization name |
| `additional_attributes.company_*` | `address` | Combined address fields |

### Conversation → Activity

| Chatwoot Field | Krayin Field | Notes |
|----------------|--------------|-------|
| Channel Type | `type` | email/call/note based on channel |
| Display ID | `title` | "Conversation #123" |
| Details | `comment` | Full conversation context |
| Person ID | `person_id` | Link to Person |
| Status | `is_done` | true if resolved |

### Message → Activity

| Chatwoot Field | Krayin Field | Notes |
|----------------|--------------|-------|
| Channel Type | `type` | email/call/note based on channel |
| Sender + ID | `title` | "Message from John - Conversation #123" |
| Content | `comment` | Message details with attachments |
| Person ID | `person_id` | Link to Person |
| Always | `is_done` | true (messages are complete) |

## Custom Attributes

The integration supports custom contact attributes for richer data:

### Contact Attributes

```ruby
contact.additional_attributes = {
  # Person fields
  job_title: 'VP of Engineering',

  # Organization fields
  company_name: 'Acme Corp',
  company_address: '123 Main St',
  company_city: 'San Francisco',
  company_state: 'CA',
  company_country: 'USA',
  company_zipcode: '94105',

  # Lead fields
  lead_value: 75000.00
}
```

See [Krayin Custom Attributes Guide](./Krayin-Custom-Attributes) for complete reference.

## Channel-Specific Activity Types

The integration intelligently maps channel types to Krayin activity types:

| Channel | Activity Type | Reason |
|---------|---------------|--------|
| Email | `email` | Email correspondence |
| SMS / Twilio | `call` | Phone communication |
| WhatsApp | `call` | Messaging communication |
| Web Widget | `note` | Chat conversation |
| API | `note` or detected | Based on message type |

## Stage Progression Rules

When **Enable Stage Progression** is active:

### Flow Example

```
1. Contact Created
   └─> Set to "New Lead" stage (if configured)

2. Conversation Created
   └─> Move to "Contacted" stage (if configured)

3. First Agent Response
   └─> Move to "Qualified" stage (if configured)

4. Conversation Resolved
   └─> Move to "Won" or "Closed" stage (if configured)
```

### Configuration Tips

1. **Map to your pipeline**: Use stage IDs from your actual Krayin pipeline
2. **Optional stages**: Leave blank to skip that transition
3. **Test first**: Try with one contact before enabling for all
4. **Monitor logs**: Check Rails logs for stage update confirmations

## Performance & Reliability

### Automatic Retry
- Failed API calls automatically retry up to 3 times
- Exponential backoff: 2^attempt seconds
- Rate limits handled with longer backoff

### Caching
- Pipeline/stage configuration cached for 1 hour
- Reduces API calls by ~90% during setup

### Database Optimization
- Indexed external ID lookups (10-100x faster)
- Optimized inbox-specific queries

### Race Condition Protection
- Redis mutex prevents duplicate records
- Safe for concurrent event processing

## Monitoring

### Check Sync Status

1. **Rails Logs**: `tail -f log/production.log | grep "Krayin ProcessorService"`
2. **External IDs**: Check `contact_inboxes.source_id` field
3. **Hook Status**: Settings → Integrations → Krayin status indicator

### External ID Format

```
krayin:person:123|krayin:lead:456|krayin:organization:789|krayin:activity:101
```

Each contact can have multiple Krayin IDs stored together.

## Troubleshooting

See [Krayin Troubleshooting Guide](./Krayin-Troubleshooting) for detailed solutions.

### Common Issues

**Connection Failed**
- Verify API URL includes `/api/admin`
- Check API token is valid and not expired
- Ensure Krayin REST API package is installed

**Contacts Not Syncing**
- Check `crm_integration` feature flag is enabled
- Verify hook is enabled (not disabled)
- Check Rails logs for errors

**Organizations Not Created**
- Enable "Sync to Organizations" option
- Ensure contact has `company_name` attribute
- Verify organization API permissions

## Security Considerations

### API Token Security
- Store tokens securely (encrypted in database)
- Use Sanctum tokens with limited scope
- Rotate tokens periodically
- Never expose tokens in logs

### Data Privacy
- Only syncs data you configure
- Respects Chatwoot privacy settings
- No data sent if integration disabled
- GDPR compliant (no automatic storage)

## Best Practices

### Configuration
1. **Start Small**: Enable contact sync first, then conversations
2. **Test Thoroughly**: Use test account before production
3. **Monitor Initially**: Watch logs for first 24 hours
4. **Set Stages Carefully**: Map to your actual sales process

### Data Quality
1. **Use Custom Attributes**: Enrich contacts with company data
2. **Set Lead Values**: Help with pipeline reporting
3. **Consistent Naming**: Use standard field names
4. **Clean Data**: Validate emails and phones

### Performance
1. **Batch Operations**: Use bulk contact updates when possible
2. **Monitor API Usage**: Watch for rate limits
3. **Cache Configuration**: Don't repeatedly reconnect
4. **Index Database**: Migration runs automatically

## API Rate Limits

Krayin CRM typically has these limits:
- **Default**: 60 requests per minute
- **Burst**: 100 requests per minute

The integration handles rate limits automatically:
- Retries with exponential backoff
- Respects `Retry-After` headers
- Logs rate limit events

## Support

### Resources
- [Krayin Setup Guide](./Krayin-Setup-Guide)
- [Krayin Troubleshooting](./Krayin-Troubleshooting)
- [Krayin FAQ](./Krayin-FAQ)
- [Custom Attributes Guide](./Krayin-Custom-Attributes)

### Getting Help
- **Chatwoot Community**: [chatwoot.com/community](https://chatwoot.com/community)
- **GitHub Issues**: [chatwoot/chatwoot](https://github.com/chatwoot/chatwoot)
- **Krayin Documentation**: [krayincrm.com/docs](https://krayincrm.com/docs)

## Updates & Changelog

### Version Compatibility

| Krayin Version | Chatwoot Version | Status |
|----------------|------------------|--------|
| 2.1.5+ | 4.0+ | ✅ Fully Supported |
| 2.0.x | 4.0+ | ⚠️ Limited Support |
| < 2.0 | Any | ❌ Not Supported |

### Recent Updates
- **v1.0.0** (2024-11): Initial release with full feature set
  - Contact sync (Person + Lead)
  - Organization linking
  - Conversation and message activities
  - Stage progression
  - Performance optimizations
  - Enhanced error handling

## Related Integrations

- [GLPI Integration](./GLPI-Integration) - IT Service Management
- [Keycloak Authentication](./Keycloak-Authentication) - SSO & Identity

---

**Next Steps**: Follow the [Krayin Setup Guide](./Krayin-Setup-Guide) to configure your integration.
