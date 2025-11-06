# Krayin CRM Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the Krayin CRM integration.

## Table of Contents

1. [Connection Issues](#connection-issues)
2. [Sync Issues](#sync-issues)
3. [Organization Issues](#organization-issues)
4. [Stage Progression Issues](#stage-progression-issues)
5. [Performance Issues](#performance-issues)
6. [Data Issues](#data-issues)
7. [Debugging Tools](#debugging-tools)

## Connection Issues

### Cannot Connect to Krayin API

**Symptoms**:
- Error: "Unable to connect to Krayin API"
- Integration shows "Disconnected" status
- Setup fails immediately

**Diagnostic Steps**:

1. **Verify API URL Format**
   ```
   ✅ Correct: https://crm.example.com/api/admin
   ❌ Wrong: https://crm.example.com/api/admin/
   ❌ Wrong: https://crm.example.com/api
   ❌ Wrong: https://crm.example.com
   ```

2. **Test API Connection**
   ```bash
   curl -X GET https://your-krayin.com/api/admin/settings/pipelines \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/json"
   ```

3. **Check Response**:
   - **200 OK**: Connection works, check token permissions
   - **401 Unauthorized**: Invalid or expired token
   - **404 Not Found**: API endpoint incorrect or REST API not installed
   - **500 Error**: Krayin server issue
   - **Connection refused**: Network/firewall issue

**Solutions**:

- **Fix URL**: Ensure `/api/admin` path is included
- **Regenerate Token**: Create new API token in Krayin
- **Install REST API**: `composer require krayin/rest-api`
- **Check Firewall**: Allow Chatwoot server IP
- **Verify SSL**: Use valid SSL certificate

### Unauthorized: Invalid API Token

**Symptoms**:
- Error: "Unauthorized: Invalid API token"
- 401 HTTP response
- Token appears correct

**Diagnostic Steps**:

1. **Check Token Format**:
   - Should start with number and pipe: `1|aBc...`
   - Should be long (~100 characters)
   - No extra spaces or newlines

2. **Verify Token in Database**:
   ```sql
   SELECT * FROM personal_access_tokens
   WHERE tokenable_type = 'Webkul\\User\\Models\\Admin';
   ```

3. **Test Token Directly**:
   ```bash
   curl -X GET https://your-krayin.com/api/admin/auth/user \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/json"
   ```

**Solutions**:

- **Generate New Token**: Use Tinker or Krayin UI
- **Check Permissions**: Ensure API user has admin role
- **Verify Expiration**: Tokens may expire based on configuration
- **Clear Cache**: `php artisan optimize:clear` in Krayin

### API Rate Limit Exceeded

**Symptoms**:
- Error: "Rate limit exceeded"
- 429 HTTP response
- Sync pauses temporarily

**Diagnostic Steps**:

1. **Check Rate Limit**:
   ```bash
   # Response headers show limits
   X-RateLimit-Limit: 60
   X-RateLimit-Remaining: 0
   Retry-After: 45
   ```

2. **Review Sync Frequency**:
   ```bash
   # Rails logs
   tail -f log/production.log | grep "Rate limit"
   ```

**Solutions**:

- **Wait**: Integration automatically retries after backoff period
- **Reduce Sync**: Disable message-level sync if not needed
- **Increase Limit**: Configure higher rate limit in Krayin
- **Batch Operations**: Avoid bulk contact updates

## Sync Issues

### Contact Not Syncing

**Symptoms**:
- Contact created in Chatwoot
- No Person or Lead in Krayin
- No errors visible in UI

**Diagnostic Steps**:

1. **Check Feature Flag**:
   ```ruby
   # Rails console
   account.feature_enabled?(:crm_integration)
   # Should return: true
   ```

2. **Check Hook Status**:
   ```ruby
   # Rails console
   hook = Integrations::Hook.find_by(app_id: 'krayin')
   hook.status # Should be: "enabled"
   hook.disabled? # Should be: false
   ```

3. **Check Rails Logs**:
   ```bash
   tail -f log/production.log | grep "Krayin ProcessorService"
   ```

4. **Check External ID**:
   ```ruby
   contact = Contact.find(123)
   contact.contact_inboxes.first&.source_id
   # Should show: "krayin:person:456|krayin:lead:789"
   ```

**Solutions**:

- **Enable Feature**: `account.enable_features(:crm_integration)`
- **Enable Hook**: In Chatwoot UI, re-configure integration
- **Check Logs**: Look for specific error messages
- **Manually Trigger**: Update contact to trigger sync

### Person Created But No Lead

**Symptoms**:
- Person exists in Krayin
- Lead is missing
- External ID shows only Person

**Diagnostic Steps**:

1. **Check Pipeline Configuration**:
   ```ruby
   hook = Integrations::Hook.find_by(app_id: 'krayin')
   hook.settings['default_pipeline_id'] # Should have value
   hook.settings['default_stage_id'] # Should have value
   ```

2. **Check Krayin Permissions**:
   - Test lead creation manually in Krayin UI
   - Verify API user can create leads

3. **Check Rails Logs**:
   ```bash
   grep "Failed to process contact" log/production.log
   ```

**Solutions**:

- **Reconnect Integration**: Re-run setup to fetch configuration
- **Verify Pipelines**: Check pipelines exist in Krayin
- **Check Permissions**: Ensure API user has lead creation rights
- **Manual Creation**: Create lead manually and note any errors

### Conversation Not Creating Activity

**Symptoms**:
- Conversation exists in Chatwoot
- No activity in Krayin
- Person and Lead exist

**Diagnostic Steps**:

1. **Check Sync Setting**:
   ```ruby
   hook.settings['sync_conversations'] # Should be: true
   ```

2. **Check Person ID**:
   ```ruby
   contact_inbox = contact.contact_inboxes.first
   source_id = contact_inbox.source_id
   # Should contain: "krayin:person:XXX"
   ```

3. **Check Activity Client**:
   ```bash
   # Test activity API
   curl -X POST https://your-krayin.com/api/admin/activities \
     -H "Authorization: Bearer TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"type":"note","title":"Test","person_id":123}'
   ```

**Solutions**:

- **Enable Sync**: Turn on "Sync Conversations" in settings
- **Verify Person**: Ensure Person ID exists
- **Check Permissions**: Verify API user can create activities
- **Retry**: Update conversation to trigger re-sync

## Organization Issues

### Organization Not Created

**Symptoms**:
- Contact has company_name attribute
- No organization in Krayin
- Person created without organization link

**Diagnostic Steps**:

1. **Check Sync Setting**:
   ```ruby
   hook.settings['sync_to_organization'] # Should be: true
   ```

2. **Check Company Attribute**:
   ```ruby
   contact.additional_attributes['company_name'] # Should have value
   # OR
   contact.additional_attributes['company']
   # OR
   contact.additional_attributes['organization']
   ```

3. **Check Rails Logs**:
   ```bash
   grep "organization" log/production.log
   ```

**Solutions**:

- **Enable Setting**: Turn on "Sync to Organizations"
- **Add Attribute**: Ensure contact has company_name
- **Check Permissions**: Verify organization creation rights
- **Retry**: Update contact to re-trigger sync

### Person Not Linked to Organization

**Symptoms**:
- Organization exists in Krayin
- Person exists but not linked
- External ID shows organization ID

**Diagnostic Steps**:

1. **Check External IDs**:
   ```ruby
   source_id = contact.contact_inboxes.first.source_id
   # Should include: "krayin:organization:XXX"
   ```

2. **Check Person in Krayin**:
   - Open Person record
   - Check "Organization" field
   - Should show organization name

**Solutions**:

- **Update Contact**: Trigger re-sync by updating contact
- **Manual Link**: Link manually in Krayin UI
- **Check API**: Verify person update endpoint works

## Stage Progression Issues

### Lead Stage Not Updating

**Symptoms**:
- Stage progression enabled
- Conversation created/resolved
- Lead stage unchanged in Krayin

**Diagnostic Steps**:

1. **Check Configuration**:
   ```ruby
   hook.settings['stage_progression_enabled'] # Should be: true
   hook.settings['stage_on_conversation_created'] # Should have stage ID
   ```

2. **Verify Stage IDs**:
   - Log into Krayin
   - Navigate to Settings → Pipelines
   - Check stage IDs match configuration

3. **Check Lead ID**:
   ```ruby
   source_id = contact.contact_inboxes.first.source_id
   # Should include: "krayin:lead:XXX"
   ```

4. **Check Rails Logs**:
   ```bash
   grep "Updated lead.*stage" log/production.log
   ```

**Solutions**:

- **Enable Feature**: Turn on stage progression
- **Correct Stage IDs**: Use actual IDs from Krayin
- **Check Permissions**: Verify lead update rights
- **Retry**: Create new conversation to test

### Wrong Stage Applied

**Symptoms**:
- Stage updates but to wrong stage
- Logic doesn't match configuration

**Diagnostic Steps**:

1. **Review Configuration**:
   ```ruby
   settings = hook.settings
   settings['stage_on_conversation_created']
   settings['stage_on_first_response']
   settings['stage_on_conversation_resolved']
   ```

2. **Check Conversation Status**:
   ```ruby
   conversation.status # 'open' or 'resolved'
   conversation.messages.outgoing.any? # Check for agent response
   ```

**Solutions**:

- **Verify Mapping**: Ensure stage IDs match desired stages
- **Test Logic**: Create test conversations with different statuses
- **Review Logs**: Check which stage was applied

## Performance Issues

### Slow Sync

**Symptoms**:
- Contacts take minutes to sync
- UI feels sluggish
- High API response times

**Diagnostic Steps**:

1. **Check Database Indexes**:
   ```sql
   -- Check if migration ran
   SELECT * FROM schema_migrations
   WHERE version LIKE '%optimize_krayin%';
   ```

2. **Check API Response Times**:
   ```bash
   # Test API speed
   time curl -X GET https://your-krayin.com/api/admin/leads/pipelines \
     -H "Authorization: Bearer TOKEN"
   ```

3. **Check Cache**:
   ```ruby
   # Rails console
   Rails.cache.read("krayin:setup:...")
   ```

**Solutions**:

- **Run Migration**: `rails db:migrate`
- **Check Network**: Ensure good connection to Krayin
- **Optimize Krayin**: Check Krayin server performance
- **Reduce Sync**: Disable message-level sync

### High Memory Usage

**Symptoms**:
- Sidekiq workers using lots of memory
- Server running out of RAM

**Diagnostic Steps**:

1. **Check Job Queue**:
   ```bash
   # Check Sidekiq queue size
   redis-cli LLEN queue:medium
   ```

2. **Monitor Memory**:
   ```bash
   top -p $(pidof sidekiq)
   ```

**Solutions**:

- **Batch Processing**: Process contacts in smaller batches
- **Increase Workers**: Add more Sidekiq workers with less concurrency
- **Optimize Queries**: Ensure ActiveRecord queries use includes

## Data Issues

### Duplicate Records

**Symptoms**:
- Multiple Person records for same contact
- Multiple Leads for same person

**Diagnostic Steps**:

1. **Check Redis Locks**:
   ```bash
   redis-cli KEYS "*krayin*mutex*"
   ```

2. **Search Krayin**:
   - Search by email in Persons
   - Count results

**Solutions**:

- **Manual Cleanup**: Merge duplicates in Krayin
- **Check Redis**: Ensure Redis is running
- **Race Condition**: Should be prevented by mutex

### Missing Data

**Symptoms**:
- Person/Lead created but missing fields
- Custom attributes not syncing

**Diagnostic Steps**:

1. **Check Source Data**:
   ```ruby
   contact.name
   contact.email
   contact.phone_number
   contact.additional_attributes
   ```

2. **Check Mapper Output**:
   ```ruby
   # Rails console
   mapper = Crm::Krayin::Mappers::ContactMapper.new(contact)
   mapper.map_to_person
   mapper.map_to_lead(123, hook.settings)
   ```

**Solutions**:

- **Add Data**: Ensure contact has required fields
- **Check Mapping**: Verify mapper includes field
- **Update Contact**: Trigger re-sync

### Incorrect Phone Format

**Symptoms**:
- Phone number not syncing
- Format error in Krayin

**Diagnostic Steps**:

1. **Check Phone Format**:
   ```ruby
   contact.phone_number
   # Should be E.164: +1234567890
   ```

2. **Test Formatting**:
   ```ruby
   phone = contact.phone_number
   parsed = TelephoneNumber.parse(phone)
   parsed.valid?
   parsed.e164_number
   ```

**Solutions**:

- **Use E.164 Format**: Always use international format
- **Update Contact**: Correct phone number format
- **Validation**: Add phone validation in Chatwoot

## Debugging Tools

### Rails Console

```ruby
# Access Rails console
rails console production

# Find contact
contact = Contact.find_by(email: 'user@example.com')

# Check external IDs
contact.contact_inboxes.first&.source_id

# Check hook configuration
hook = Integrations::Hook.find_by(app_id: 'krayin')
hook.settings

# Manually trigger sync
processor = Crm::Krayin::ProcessorService.new(
  inbox: contact.inbox,
  event_name: 'contact.updated',
  event_data: { contact: contact }
)
processor.perform
```

### Logs Analysis

```bash
# Watch real-time logs
tail -f log/production.log | grep "Krayin"

# Search for errors
grep "Krayin.*error" log/production.log

# Count sync events
grep -c "Contact.*synced" log/production.log

# Check specific contact
grep "Contact 123" log/production.log
```

### API Testing

```bash
# Test connection
curl -X GET https://your-krayin.com/api/admin/auth/user \
  -H "Authorization: Bearer TOKEN" \
  -H "Accept: application/json"

# Test person creation
curl -X POST https://your-krayin.com/api/admin/persons \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "emails": [{"value": "test@example.com", "label": "work"}]
  }'

# Test lead creation
curl -X POST https://your-krayin.com/api/admin/leads \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Lead",
    "person_id": 123,
    "lead_pipeline_id": 1,
    "lead_pipeline_stage_id": 1
  }'
```

### Database Queries

```sql
-- Check external IDs
SELECT * FROM contact_inboxes
WHERE source_id LIKE 'krayin:%';

-- Check hook configuration
SELECT * FROM integrations_hooks
WHERE app_id = 'krayin';

-- Check contacts without sync
SELECT c.* FROM contacts c
LEFT JOIN contact_inboxes ci ON c.id = ci.contact_id
WHERE ci.source_id IS NULL OR ci.source_id NOT LIKE 'krayin:%';
```

## Getting Help

If these troubleshooting steps don't resolve your issue:

1. **Check Logs**: Collect relevant log entries
2. **Document Steps**: Note exactly what you did
3. **Gather Info**:
   - Chatwoot version
   - Krayin version
   - Error messages
   - Configuration settings

4. **Get Support**:
   - [Chatwoot Community](https://chatwoot.com/community)
   - [GitHub Issues](https://github.com/chatwoot/chatwoot/issues)
   - [Krayin Community](https://forums.krayincrm.com)

## Related Guides

- [Krayin Setup Guide](./Krayin-Setup-Guide)
- [Krayin FAQ](./Krayin-FAQ)
- [Krayin Custom Attributes](./Krayin-Custom-Attributes)

---

**Still need help?** Visit the [Chatwoot Community](https://chatwoot.com/community) for support!
