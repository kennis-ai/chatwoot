# Krayin CRM Integration - Frequently Asked Questions

## General Questions

### What is the Krayin CRM integration?

The Krayin integration automatically synchronizes contacts, conversations, and activities from Chatwoot to your Krayin CRM instance in real-time, enabling seamless customer relationship management.

### Which Krayin versions are supported?

- **Supported**: Krayin CRM v2.1.5 and higher with REST API Package v2.1.1
- **Limited Support**: Krayin v2.0.x
- **Not Supported**: Versions below 2.0

### Do I need Chatwoot Enterprise?

You need either:
- Chatwoot Enterprise plan, OR
- Self-hosted Chatwoot with `crm_integration` feature flag enabled

Contact your Chatwoot administrator to check feature availability.

### Is the integration bi-directional?

Currently **one-way**: Chatwoot → Krayin

Bi-directional sync (Krayin → Chatwoot) is planned for future versions.

### How much does it cost?

The integration itself is free and included with Chatwoot. You only need:
- Valid Krayin CRM license
- Chatwoot plan that includes CRM integrations

## Setup & Configuration

### How do I get a Krayin API token?

See the [Setup Guide - Step 2](./Krayin-Setup-Guide#step-2-generate-api-token) for detailed instructions.

Quick method via Tinker:
```bash
php artisan tinker
$user = \Webkul\User\Models\Admin::first();
$token = $user->createToken('Chatwoot')->plainTextToken;
echo $token;
```

### What API permissions are needed?

The API user needs permissions to:
- View, Create, Edit Persons
- View, Create, Edit Leads
- View, Create, Edit Organizations
- View, Create, Edit Activities
- View Settings (Pipelines, Stages, Sources, Types)

We recommend using an Admin role or creating a custom role with these specific permissions.

### Can I use multiple inboxes?

Yes! Each inbox can have its own Krayin configuration with different:
- API endpoints (different Krayin instances)
- Pipeline settings
- Sync options
- Stage progression rules

Configure per inbox at: **Settings** → **Inboxes** → [Select Inbox] → **Integrations**

### How do I test without affecting production?

1. Create a test Krayin instance
2. Configure integration with test API credentials
3. Create test contacts in separate inbox
4. Verify sync works correctly
5. Swap to production credentials when ready

## Sync Behavior

### When does sync happen?

Sync occurs **immediately** when these events happen:
- Contact created or updated
- Conversation created or updated
- Message created (if message sync enabled)

Events are processed asynchronously via background jobs (usually within seconds).

### What if Krayin is down?

The integration includes automatic retry logic:
- Retries up to 3 times with exponential backoff
- Rate limits handled automatically
- Failed syncs logged for review
- No data loss - events queued for retry

### Do existing contacts sync?

Yes, when you:
- Update an existing contact
- Create a conversation with existing contact
- Manually trigger sync via Rails console

To bulk sync existing contacts:
```ruby
# Rails console - use with caution!
Contact.find_in_batches(batch_size: 100) do |batch|
  batch.each do |contact|
    contact.touch # Triggers contact.updated event
  end
end
```

### Can I sync selectively?

Yes, through configuration:
- **Sync Conversations**: Enable/disable conversation activities
- **Sync Messages**: Enable/disable message activities
- **Sync Organizations**: Enable/disable organization creation
- **Stage Progression**: Enable/disable automatic stage updates

Configure at: **Settings** → **Integrations** → **Krayin CRM** → **Configure**

### How often does it sync?

Real-time on event triggers. No scheduled/batch sync.

For performance, configuration data is cached for 1 hour.

## Data & Mapping

### What contact data is synced?

| Chatwoot Field | Synced | Krayin Entity |
|----------------|--------|---------------|
| Name | ✅ | Person, Lead |
| Email | ✅ | Person |
| Phone | ✅ | Person |
| Custom Attributes | ✅ | Person (job_title), Lead (lead_value), Organization (company_*) |
| Profile Picture | ❌ | Not synced |
| Tags | ❌ | Not synced |
| Labels | ✅ | In conversation activities |

### Can I map custom fields?

Yes! Use custom attributes in Chatwoot:

```ruby
contact.additional_attributes = {
  job_title: 'VP Sales',           # → Person.job_title
  company_name: 'Acme Corp',       # → Organization.name
  lead_value: 50000,               # → Lead.lead_value
  custom_field: 'value'            # → Included in descriptions
}
```

See [Custom Attributes Guide](./Krayin-Custom-Attributes) for complete reference.

### What if a contact has no email?

- **Person Creation**: Requires at least email OR phone number
- **No email/phone**: Person creation skipped, logged as warning
- **Best Practice**: Always collect email or phone

### How are phone numbers formatted?

Phone numbers are automatically formatted to E.164 international format:
- Input: `(555) 123-4567`
- Stored: `+15551234567`

Invalid formats are preserved as-is with a warning logged.

### Do attachments sync?

Attachments are **referenced** in activity comments but not uploaded to Krayin:
- Filename included
- File size included
- File type included
- Download link not included (Chatwoot-only)

## Organizations

### How do organizations work?

When "Sync to Organizations" is enabled:

1. Contact must have one of these custom attributes:
   - `company_name`
   - `company`
   - `organization`

2. Integration searches for existing organization by name

3. If found: Links Person to existing organization

4. If not found: Creates new organization, then links

### Can multiple contacts link to same organization?

Yes! Multiple Persons can link to the same Organization in Krayin.

The integration searches by company name and reuses existing organizations.

### What organization data syncs?

| Chatwoot Attribute | Krayin Field |
|--------------------|--------------|
| `company_name` | `name` |
| `company_address` | `address` (part) |
| `company_city` | `address` (part) |
| `company_state` | `address` (part) |
| `company_country` | `address` (part) |
| `company_zipcode` | `address` (part) |

Address fields are combined into a single address string.

## Stage Progression

### How does stage progression work?

When enabled, lead stages update based on conversation lifecycle:

```
Contact Created → Initial Stage (configured)
   ↓
Conversation Created → "Contacted" Stage (configured)
   ↓
First Agent Response → "Qualified" Stage (configured)
   ↓
Conversation Resolved → "Won/Closed" Stage (configured)
```

### Which stage IDs should I use?

1. Log into Krayin
2. Navigate to **Settings** → **Lead Pipelines**
3. Click on your pipeline
4. Note the Stage IDs (usually 1, 2, 3, etc.)
5. Use these IDs in Chatwoot integration settings

### Can I customize stage rules?

Currently supports these transitions:
- Conversation created
- First agent response
- Conversation resolved

Custom rules (based on labels, assignments, etc.) planned for future versions.

### What if I don't want stage progression?

Leave "Enable Stage Progression" unchecked. Leads remain in manually set stages.

## Activity Types

### What activity types are used?

Automatically determined by channel:

| Channel | Activity Type | Reason |
|---------|---------------|--------|
| Email | `email` | Email correspondence |
| SMS | `call` | Phone/SMS communication |
| WhatsApp | `call` | Messaging app |
| Web Widget | `note` | Chat conversation |
| API | `note` or `email` | Based on message type |

### Can I change activity types?

Not through configuration. Activity type is intelligently detected based on:
1. Inbox channel type
2. Message direction (incoming/outgoing)

Custom type mapping planned for future versions.

### Why are WhatsApp messages marked as "call"?

Krayin's default activity types are:
- Email
- Call
- Meeting
- Lunch
- Note

WhatsApp/SMS fit best under "Call" as they're real-time communication, not async like email.

## Performance & Limits

### How fast is the sync?

- **Database Lookup**: <10ms (indexed)
- **API Call**: 100-500ms (depends on Krayin server)
- **Total Sync Time**: Usually <1 second per contact

Large batches may take longer due to:
- API rate limits
- Network latency
- Server load

### Are there API rate limits?

Yes, Krayin typically limits:
- **60 requests per minute** (default)
- **100 requests per minute** (burst)

The integration handles this automatically:
- Retries with exponential backoff
- Respects `Retry-After` headers
- Queues requests if needed

### How many contacts can I sync?

No hard limit. Tested with:
- ✅ 1,000 contacts: <1 minute
- ✅ 10,000 contacts: <10 minutes
- ✅ 100,000+ contacts: Batch in chunks

For very large imports, use off-peak hours.

### Does sync affect Chatwoot performance?

Minimal impact:
- Events processed asynchronously (background jobs)
- No blocking of user interactions
- Redis mutex prevents database locks
- Indexed lookups are fast

## Troubleshooting

### How do I check if sync is working?

1. **Create test contact** in Chatwoot
2. **Check Rails logs**: `tail -f log/production.log | grep Krayin`
3. **Check Krayin**: Search for contact by email
4. **Check external ID**: Rails console → `contact.contact_inboxes.first.source_id`

Expected: `"krayin:person:123|krayin:lead:456"`

### Why isn't my contact syncing?

Common reasons:
- Feature flag not enabled
- Hook disabled
- No email/phone on contact
- API connection issue
- Permission issue

See [Troubleshooting Guide](./Krayin-Troubleshooting) for solutions.

### Where are errors logged?

- **Rails Logs**: `log/production.log` or `log/development.log`
- **Sidekiq Logs**: Check Sidekiq web UI for failed jobs
- **Chatwoot UI**: Some errors shown in integration status

Search logs for: `"Krayin ProcessorService"` or `"Krayin API error"`

### Can I manually trigger a sync?

Yes, via Rails console:

```ruby
# For specific contact
contact = Contact.find(123)
contact.touch # Triggers contact.updated event

# For conversation
conversation = Conversation.find(456)
conversation.touch # Triggers conversation.updated event
```

## Security & Privacy

### Is my API token secure?

Yes:
- Stored encrypted in database (if encryption configured)
- Never exposed in logs
- Transmitted over HTTPS only
- Can be rotated anytime

### What data is sent to Krayin?

Only what you configure:
- Contact information (name, email, phone)
- Custom attributes you set
- Conversation details (if enabled)
- Message content (if enabled)

No Chatwoot internal data, agent passwords, or sensitive system info is sent.

### Is it GDPR compliant?

Yes, the integration:
- Syncs only explicitly configured data
- Can be disabled per inbox
- Allows data deletion (delete contact in both systems)
- Provides audit trail via logs

### Can I delete synced data?

1. **In Chatwoot**: Delete contact (doesn't auto-delete from Krayin)
2. **In Krayin**: Delete Person/Lead manually
3. **Unlink**: Remove external IDs from `contact_inboxes.source_id`

No automatic cascade delete (by design, for data safety).

## Advanced

### Can I modify the sync logic?

Yes, for self-hosted installations:
- Mapper classes: `app/services/crm/krayin/mappers/`
- Processor service: `app/services/crm/krayin/processor_service.rb`
- Custom attributes: Extend ContactMapper

Changes require Ruby/Rails knowledge.

### Can I add custom Krayin fields?

Yes, by customizing mappers:

```ruby
# app/services/crm/krayin/mappers/contact_mapper.rb
def map_to_person
  {
    name: contact.name,
    emails: format_emails,
    # Add custom field
    custom_field: contact.additional_attributes&.dig('custom_value')
  }.compact
end
```

### Can I sync to multiple Krayin instances?

Not directly, but you can:
1. Use different inboxes for different Krayin instances
2. Route contacts to appropriate inbox
3. Each inbox configured with different API credentials

### How do I migrate from another CRM?

See [Setup Guide - Migration](./Krayin-Setup-Guide#migration-from-other-crms) section.

Key steps:
1. Export from old CRM
2. Import to Krayin
3. Map external IDs
4. Enable integration
5. Verify no duplicates

## Support & Resources

### Where can I get help?

- **Documentation**: This Wiki
- **Community**: [chatwoot.com/community](https://chatwoot.com/community)
- **GitHub**: [github.com/chatwoot/chatwoot](https://github.com/chatwoot/chatwoot)
- **Krayin Docs**: [krayincrm.com/docs](https://krayincrm.com/docs)

### How do I report a bug?

1. **Check logs**: Gather error messages
2. **Test in isolation**: Reproduce with minimal setup
3. **Create GitHub issue**: [New Issue](https://github.com/chatwoot/chatwoot/issues/new)
4. **Include**:
   - Chatwoot version
   - Krayin version
   - Steps to reproduce
   - Error logs
   - Expected vs actual behavior

### How can I request a feature?

Open a GitHub issue with:
- **Title**: `[Krayin Integration] Feature: Your Feature Name`
- **Description**: What you want and why
- **Use Case**: Real-world scenario
- **Examples**: How it should work

### Where's the source code?

- **Integration Code**: `app/services/crm/krayin/`
- **API Clients**: `app/services/crm/krayin/api/`
- **Mappers**: `app/services/crm/krayin/mappers/`
- **Jobs**: `app/jobs/hook_job.rb`, `app/jobs/crm/setup_job.rb`
- **Tests**: `spec/services/crm/krayin/`, `spec/integration/krayin_integration_spec.rb`

## Related Documentation

- [Krayin CRM Integration](./Krayin-CRM-Integration) - Overview and features
- [Krayin Setup Guide](./Krayin-Setup-Guide) - Step-by-step setup
- [Krayin Troubleshooting](./Krayin-Troubleshooting) - Problem solving
- [Krayin Custom Attributes](./Krayin-Custom-Attributes) - Data mapping guide

---

**Have a question not answered here?** Ask in the [Chatwoot Community](https://chatwoot.com/community)!
