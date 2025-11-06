# GLPI Integration Troubleshooting Guide

## Overview

This guide provides solutions to common issues with the GLPI integration in Chatwoot.

---

## Quick Diagnostics

### Health Check Checklist

Before diving into specific issues, run through this checklist:

- [ ] GLPI API is enabled (Setup → General → API)
- [ ] App Token and User Token are valid
- [ ] Feature flag `crm_integration` is enabled
- [ ] Hook status is "enabled" in Chatwoot
- [ ] Redis is running and accessible
- [ ] Sidekiq is processing jobs
- [ ] GLPI instance is accessible from Chatwoot server
- [ ] API URL includes `/apirest.php` at the end

### Quick Test Commands

```ruby
# Rails console

# 1. Check feature flag
account = Account.find(YOUR_ACCOUNT_ID)
account.enabled_features.include?('crm_integration')
# Should return: true

# 2. Find hook
hook = Integrations::Hook.find_by(app_id: 'glpi', account: account)
hook.present? && !hook.disabled?
# Should return: true

# 3. Test connectivity
service = Crm::Glpi::SetupService.new(hook)
result = service.validate_and_test
puts result
# Should return: { success: true, message: "GLPI connection successful" }

# 4. Check Redis
Redis.current.ping
# Should return: "PONG"

# 5. Check Sidekiq
Sidekiq::Queue.new('medium').size
# Should return: 0 or low number
```

---

## Connection Issues

### Problem: "API connection failed"

**Symptoms**:
- Integration setup fails
- Error message: "API connection failed"
- No records created in GLPI

**Causes**:
1. Incorrect API URL
2. Invalid App Token or User Token
3. GLPI API not enabled
4. Network/firewall blocking access
5. HTTPS certificate issues

**Solutions**:

#### 1. Verify API URL Format

**Correct Format**: `https://your-domain.com/apirest.php`

**Common Mistakes**:
```
❌ https://your-domain.com (missing /apirest.php)
❌ https://your-domain.com/glpi (missing /apirest.php)
❌ http://your-domain.com/apirest.php (http instead of https)
❌ https://your-domain.com/apirest.php/ (trailing slash)
```

**Fix in Rails Console**:
```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')
settings = hook.settings
settings['api_url'] = 'https://your-domain.com/apirest.php'
hook.update!(settings: settings)
```

#### 2. Verify Tokens

**Check App Token**:
```bash
# Test App Token via cURL
curl -X GET 'https://your-glpi.com/apirest.php/initSession' \
  -H 'Content-Type: application/json' \
  -H 'App-Token: YOUR_APP_TOKEN' \
  -H 'Authorization: user_token YOUR_USER_TOKEN'

# Expected response:
{"session_token":"abc123..."}

# Error response:
{"0":"ERROR_WRONG_APP_TOKEN_PARAMETER","1":"parameter app_token is missing or invalid"}
```

**Regenerate Tokens**:
1. **App Token**: GLPI → Setup → General → API → Regenerate
2. **User Token**: GLPI → User Preferences → Remote Access Keys → Regenerate

**Update Tokens in Chatwoot**:
```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')
settings = hook.settings
settings['app_token'] = 'NEW_APP_TOKEN'
settings['user_token'] = 'NEW_USER_TOKEN'
hook.update!(settings: settings)
```

#### 3. Enable GLPI API

**In GLPI Admin Panel**:
1. Navigate to **Setup → General → API**
2. Check **Enable REST API**: YES
3. Check **Enable login with external token**: YES
4. Check **Enable login with credentials**: NO (recommended)
5. Save

**Verify API Enabled**:
```bash
curl -I https://your-glpi.com/apirest.php
# Should return: HTTP/1.1 200 OK (not 404)
```

#### 4. Test Network Connectivity

**From Chatwoot Server**:
```bash
# Test DNS resolution
nslookup your-glpi.com

# Test HTTP connectivity
curl -I https://your-glpi.com

# Test GLPI API endpoint
curl -I https://your-glpi.com/apirest.php

# Test with full request
curl -X GET 'https://your-glpi.com/apirest.php/initSession' \
  -H 'App-Token: YOUR_APP_TOKEN' \
  -H 'Authorization: user_token YOUR_USER_TOKEN'
```

**Check Firewall Rules**:
- Allow outbound HTTPS (443) from Chatwoot to GLPI
- Check if GLPI has IP whitelisting enabled

#### 5. HTTPS Certificate Issues

**Problem**: SSL certificate verification fails

**Temporary Workaround** (development only):
```ruby
# In base_client.rb (NOT recommended for production)
class BaseClient
  include HTTParty
  default_options.update(verify: false)  # Disable SSL verification
end
```

**Proper Solution**:
- Install proper SSL certificate on GLPI server
- Add GLPI's CA certificate to Chatwoot server's trust store

---

## Contact Sync Issues

### Problem: Contacts Not Syncing to GLPI

**Symptoms**:
- Contacts created in Chatwoot
- No corresponding User/Contact in GLPI
- Missing `glpi_user_id` or `glpi_contact_id` in metadata

**Diagnostic Steps**:

```ruby
# 1. Find contact
contact = Contact.find(YOUR_CONTACT_ID)

# 2. Check metadata
contact.additional_attributes
# Look for 'external' → 'glpi_user_id' or 'glpi_contact_id'

# 3. Check if identifiable
contact.name.present? || contact.email.present? || contact.phone_number.present?
# Should return: true

# 4. Check Sidekiq jobs
Sidekiq::Queue.new('medium').select { |job|
  job.klass == 'HookJob' && job.args[0]['app_id'] == 'glpi'
}

# 5. Check for errors
Sidekiq::RetrySet.new.select { |job|
  job.klass == 'HookJob' && job.args[0]['app_id'] == 'glpi'
}.each { |job| puts job['error_message'] }
```

**Common Causes & Solutions**:

#### 1. Contact Not Identifiable

**Problem**: Contact has no name, email, or phone

**Check**:
```ruby
contact = Contact.find(YOUR_CONTACT_ID)
puts "Name: #{contact.name}"
puts "Email: #{contact.email}"
puts "Phone: #{contact.phone_number}"
```

**Solution**: Add at least one identifier
```ruby
contact.update!(email: 'user@example.com')
```

#### 2. Feature Flag Not Enabled

**Check**:
```ruby
account = Account.find(YOUR_ACCOUNT_ID)
account.enabled_features.include?('crm_integration')
```

**Solution**:
```ruby
account.enable_features('crm_integration')
```

#### 3. Hook Disabled

**Check**:
```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')
hook.disabled?
```

**Solution**:
```ruby
hook.update!(status: 'enabled')
```

#### 4. GLPI Permissions

**Problem**: GLPI user lacks permission to create Users/Contacts

**Check GLPI Permissions**:
1. Log in to GLPI as the user whose token is used
2. Try manually creating a User/Contact
3. If fails, contact GLPI admin to grant permissions

**Required Permissions**:
- **For User Sync**: Create User, Update User
- **For Contact Sync**: Create Contact, Update Contact

#### 5. Manual Trigger

**Manually trigger sync**:
```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')
contact = Contact.find(YOUR_CONTACT_ID)
processor = Crm::Glpi::ProcessorService.new(hook)
result = processor.process_event('contact.created', contact)
puts result
```

---

## Ticket Creation Issues

### Problem: Tickets Not Created in GLPI

**Symptoms**:
- Conversations created in Chatwoot
- No corresponding Ticket in GLPI
- Missing `ticket_id` in conversation metadata

**Diagnostic Steps**:

```ruby
# 1. Find conversation
conversation = Conversation.find(YOUR_CONVERSATION_ID)

# 2. Check ticket ID
conversation.additional_attributes.dig('glpi', 'ticket_id')
# Should return: integer (ticket ID)

# 3. Check contact sync
contact = conversation.contact
contact.additional_attributes.dig('external', 'glpi_user_id') ||
contact.additional_attributes.dig('external', 'glpi_contact_id')
# Should return: integer (user/contact ID)

# 4. Check messages
conversation.messages.count
# Should be > 0
```

**Common Causes & Solutions**:

#### 1. Contact Not Synced First

**Problem**: Contact must be synced before ticket creation

**Solution**: Ensure contact has `glpi_user_id` or `glpi_contact_id`
```ruby
# Manually sync contact first
hook = Integrations::Hook.find_by(app_id: 'glpi')
processor = Crm::Glpi::ProcessorService.new(hook)
processor.process_event('contact.created', conversation.contact)

# Then sync conversation
processor.process_event('conversation.created', conversation)
```

#### 2. Invalid Ticket Type

**Problem**: Ticket type not 1 or 2

**Check**:
```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')
hook.settings['ticket_type']
# Should be: '1' or '2'
```

**Solution**:
```ruby
settings = hook.settings
settings['ticket_type'] = '1'  # 1=Incident, 2=Request
hook.update!(settings: settings)
```

#### 3. Invalid Entity ID

**Problem**: Entity ID doesn't exist or user has no access

**Check in GLPI**:
1. Navigate to Administration → Entities
2. Note the entity IDs
3. Verify user has access to the entity

**Solution**:
```ruby
settings = hook.settings
settings['entity_id'] = '0'  # Root entity
hook.update!(settings: settings)
```

#### 4. Missing Requester

**Problem**: No requester ID found for contact

**Diagnostic**:
```ruby
contact = conversation.contact
requester_id = contact.additional_attributes.dig('external', 'glpi_user_id') ||
               contact.additional_attributes.dig('external', 'glpi_contact_id')
puts "Requester ID: #{requester_id}"
```

**Solution**: Re-sync contact
```ruby
processor.process_event('contact.created', contact)
```

---

## Message Sync Issues

### Problem: Messages Not Syncing as Followups

**Symptoms**:
- Messages created in Chatwoot
- No corresponding followups in GLPI ticket
- `last_synced_message_id` not updating

**Diagnostic Steps**:

```ruby
# 1. Find conversation
conversation = Conversation.find(YOUR_CONVERSATION_ID)

# 2. Check ticket ID
ticket_id = conversation.additional_attributes.dig('glpi', 'ticket_id')
puts "Ticket ID: #{ticket_id}"

# 3. Check last synced message
last_synced = conversation.additional_attributes.dig('glpi', 'last_synced_message_id')
puts "Last Synced: #{last_synced}"

# 4. Check messages
conversation.messages.order(:id).pluck(:id, :content, :created_at)
```

**Common Causes & Solutions**:

#### 1. No Ticket ID

**Problem**: Ticket wasn't created first

**Solution**: Create ticket first
```ruby
processor = Crm::Glpi::ProcessorService.new(hook)
processor.process_event('conversation.created', conversation)
```

#### 2. Messages Already Synced

**Problem**: All messages already have been synced

**Check**:
```ruby
last_id = conversation.additional_attributes.dig('glpi', 'last_synced_message_id')
latest_message = conversation.messages.last
puts "Last synced: #{last_id}, Latest message: #{latest_message.id}"
```

**Solution**: If `last_id >= latest_message.id`, messages are already synced

#### 3. GLPI Followup Permissions

**Problem**: User lacks permission to create followups

**Test Manually in GLPI**:
1. Open the ticket in GLPI
2. Try adding a followup
3. If fails, contact admin to grant permissions

**Required Permission**: Create ITILFollowup

#### 4. Force Re-sync

**Reset last synced ID**:
```ruby
conversation = Conversation.find(YOUR_CONVERSATION_ID)
attrs = conversation.additional_attributes
attrs['glpi']['last_synced_message_id'] = nil
conversation.update!(additional_attributes: attrs)

# Trigger sync
processor = Crm::Glpi::ProcessorService.new(hook)
processor.process_event('conversation.updated', conversation)
```

---

## Duplicate Records

### Problem: Multiple GLPI Users/Contacts for Same Chatwoot Contact

**Symptoms**:
- Multiple User/Contact records in GLPI with same email
- Different `glpi_user_id` values in contact metadata

**Root Causes**:
1. Race condition during concurrent events
2. Redis not running or not accessible
3. Mutex lock timeout
4. Manual record creation

**Prevention Check**:

```ruby
# Check Redis connectivity
Redis.current.ping
# Should return: "PONG"

# Check mutex lock configuration
Redis::Alfred::CRM_PROCESS_MUTEX
# Should return: "crm:process:hook:%{hook_id}"
```

**Solutions**:

#### 1. Clean Up Duplicates Manually

**In GLPI**:
1. Search for duplicate Users/Contacts by email
2. Identify the correct record to keep
3. Delete duplicate records
4. Note the correct User/Contact ID

**Update Chatwoot Metadata**:
```ruby
contact = Contact.find_by(email: 'user@example.com')
attrs = contact.additional_attributes || {}
attrs['external'] ||= {}
attrs['external']['glpi_user_id'] = CORRECT_USER_ID  # Use correct ID
contact.update!(additional_attributes: attrs)
```

#### 2. Ensure Redis is Working

```bash
# Check Redis status
redis-cli ping
# Should return: PONG

# Check Redis from Rails
rails console
Redis.current.ping
```

**If Redis not running**:
```bash
# Start Redis
redis-server

# Or via Docker
docker start redis
```

#### 3. Increase Mutex Timeout

**If seeing timeout errors**:
```ruby
# In hook_job.rb (if needed)
with_lock(key, ttl: 10.seconds, retry_count: 5) do
  process_glpi_integration(hook, event_name, event_data)
end
```

---

## Performance Issues

### Problem: Slow Sync or Timeouts

**Symptoms**:
- Sync takes > 10 seconds
- Timeout errors in logs
- High Sidekiq queue length

**Diagnostic Steps**:

```ruby
# Check Sidekiq queue
Sidekiq::Queue.new('medium').size
# Should be: < 100

# Check processing times
Sidekiq::Stats.new.processed
Sidekiq::Stats.new.failed

# Check for long-running jobs
Sidekiq::Workers.new.each do |process_id, thread_id, work|
  puts "#{work['queue']} - #{work['payload']['class']} - #{work['run_at']}"
end
```

**Common Causes & Solutions**:

#### 1. High Message Volume

**Problem**: Syncing hundreds of messages at once

**Check**:
```ruby
conversation = Conversation.find(YOUR_CONVERSATION_ID)
last_synced = conversation.additional_attributes.dig('glpi', 'last_synced_message_id') || 0
messages_to_sync = conversation.messages.where('id > ?', last_synced).count
puts "Messages to sync: #{messages_to_sync}"
```

**Solution**: Sync runs incrementally, but if backlog is large, it may take time
- Monitor `last_synced_message_id` progress
- Consider batching (future enhancement)

#### 2. GLPI Server Performance

**Test GLPI Response Time**:
```bash
time curl -X GET 'https://your-glpi.com/apirest.php/initSession' \
  -H 'App-Token: YOUR_APP_TOKEN' \
  -H 'Authorization: user_token YOUR_USER_TOKEN'
```

**If slow (> 2 seconds)**:
- Check GLPI server resources (CPU, memory, disk)
- Optimize GLPI database
- Scale GLPI infrastructure

#### 3. Network Latency

**Test Network Latency**:
```bash
ping your-glpi-domain.com
# Should be: < 100ms average
```

**If high latency**:
- Consider moving Chatwoot closer to GLPI (same region)
- Use VPN or dedicated connection
- Increase timeout settings

#### 4. Sidekiq Concurrency

**Check Concurrency**:
```bash
# Check Sidekiq process count
ps aux | grep sidekiq

# Check configuration
cat config/sidekiq.yml
```

**Increase if needed**:
```yaml
# config/sidekiq.yml
:concurrency: 25  # Increase from default 10
```

---

## Session Management Issues

### Problem: "Session token invalid" Errors

**Symptoms**:
- Random 401 errors
- Error: "Session token invalid"
- Sessions not being cleaned up

**Diagnostic Steps**:

```ruby
# Check active sessions in GLPI
# In GLPI: Administration → Sessions
# Look for many active API sessions

# Test session lifecycle
client = Crm::Glpi::Api::BaseClient.new(hook)
client.with_session do |token|
  puts "Session Token: #{token}"
end
# Session should be killed after block
```

**Common Causes & Solutions**:

#### 1. Session Leaks

**Problem**: Sessions not being killed due to exceptions

**Check GLPI Active Sessions**:
- GLPI → Administration → Sessions
- Look for many "API" sessions

**Solution**: Already handled by `ensure` blocks in BaseClient
```ruby
def with_session
  init_session
  yield @session_token
ensure
  kill_session
end
```

**If sessions still leak**:
```ruby
# Manually kill old sessions (GLPI admin)
# Or increase GLPI session timeout
# GLPI → Setup → General → Session → Session timeout
```

#### 2. Session Timeout

**Problem**: Long-running operations exceed session timeout

**Check GLPI Session Timeout**:
- GLPI → Setup → General → Session
- Note the timeout value

**Solution**:
- Increase GLPI session timeout if needed
- Operations typically complete in < 30 seconds

---

## Feature Flag Issues

### Problem: Integration Not Working After Setup

**Symptoms**:
- Integration configured correctly
- No errors in logs
- No records created in GLPI
- Events not being processed

**Diagnostic Steps**:

```ruby
# 1. Check if feature flag exists
account = Account.find(YOUR_ACCOUNT_ID)
account.enabled_features
# Should include: "crm_integration"

# 2. Check hook
hook = Integrations::Hook.find_by(app_id: 'glpi', account: account)
hook.feature_allowed?
# Should return: true

# 3. Manually check
account.enabled_features.include?('crm_integration')
# Should return: true
```

**Solution**:

```ruby
# Enable feature flag
account = Account.find(YOUR_ACCOUNT_ID)
account.enable_features('crm_integration')

# Verify
account.reload
account.enabled_features.include?('crm_integration')
# Should return: true
```

---

## Metadata Issues

### Problem: Metadata Not Being Stored

**Symptoms**:
- Records created in GLPI
- No corresponding IDs in Chatwoot metadata
- Missing `glpi_user_id`, `ticket_id`, etc.

**Diagnostic Steps**:

```ruby
# Check contact metadata
contact = Contact.find(YOUR_CONTACT_ID)
puts contact.additional_attributes.inspect

# Check conversation metadata
conversation = Conversation.find(YOUR_CONVERSATION_ID)
puts conversation.additional_attributes.inspect

# Expected structure:
# Contact: { "external" => { "glpi_user_id" => 123 } }
# Conversation: { "glpi" => { "ticket_id" => 456, "last_synced_message_id" => 789 } }
```

**Solutions**:

#### 1. Manually Store Metadata

**Contact**:
```ruby
contact = Contact.find(YOUR_CONTACT_ID)
attrs = contact.additional_attributes || {}
attrs['external'] ||= {}
attrs['external']['glpi_user_id'] = 123  # Use actual GLPI user ID
contact.update!(additional_attributes: attrs)
```

**Conversation**:
```ruby
conversation = Conversation.find(YOUR_CONVERSATION_ID)
attrs = conversation.additional_attributes || {}
attrs['glpi'] ||= {}
attrs['glpi']['ticket_id'] = 456  # Use actual GLPI ticket ID
conversation.update!(additional_attributes: attrs)
```

#### 2. Re-trigger Sync

```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')
processor = Crm::Glpi::ProcessorService.new(hook)

# For contact
result = processor.process_event('contact.created', contact)
puts result

# For conversation
result = processor.process_event('conversation.created', conversation)
puts result
```

---

## Logging and Debugging

### Enable Debug Logging

```ruby
# In Rails console
Rails.logger.level = Logger::DEBUG

# In production (temporarily)
# Edit config/environments/production.rb
config.log_level = :debug

# Restart Rails server
```

### Watch GLPI-Specific Logs

```bash
# Development
tail -f log/development.log | grep GLPI

# Production
tail -f log/production.log | grep GLPI

# Sidekiq
tail -f log/sidekiq.log | grep GLPI
```

### Check Exception Tracking

```ruby
# If using ChatwootExceptionTracker
# Check your exception tracking service (Sentry, Rollbar, etc.)

# Recent errors
ChatwootExceptionTracker.recent_errors.select { |e| e.message.include?('GLPI') }
```

---

## Emergency Procedures

### Disable Integration Temporarily

**Via UI**:
1. Settings → Integrations → GLPI
2. Edit
3. Status: Disabled
4. Save

**Via Rails Console**:
```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')
hook.update!(status: 'disabled')
```

### Clear Stuck Jobs

```ruby
# Clear medium queue (where HookJob runs)
Sidekiq::Queue.new('medium').clear

# Or selectively clear GLPI jobs
Sidekiq::Queue.new('medium').each do |job|
  job.delete if job.klass == 'HookJob' && job.args[0]['app_id'] == 'glpi'
end
```

### Reset Integration

**Complete reset**:
```ruby
hook = Integrations::Hook.find_by(app_id: 'glpi')

# 1. Disable hook
hook.update!(status: 'disabled')

# 2. Clear metadata (optional - only if needed)
Contact.where(account: hook.account).find_each do |contact|
  if contact.additional_attributes&.dig('external', 'glpi_user_id')
    attrs = contact.additional_attributes
    attrs['external'].delete('glpi_user_id')
    attrs['external'].delete('glpi_contact_id')
    contact.update!(additional_attributes: attrs)
  end
end

# 3. Reconfigure settings
settings = {
  'api_url' => 'https://your-glpi.com/apirest.php',
  'app_token' => 'NEW_APP_TOKEN',
  'user_token' => 'NEW_USER_TOKEN',
  'entity_id' => '0',
  'sync_type' => 'user',
  'ticket_type' => '1'
}
hook.update!(settings: settings)

# 4. Test
service = Crm::Glpi::SetupService.new(hook)
result = service.validate_and_test
puts result

# 5. Re-enable
hook.update!(status: 'enabled') if result[:success]
```

---

## Getting Help

### Information to Provide When Reporting Issues

1. **Environment**:
   - Chatwoot version
   - GLPI version
   - Ruby version
   - Rails environment (development/production)

2. **Configuration**:
   - Hook settings (sanitize tokens!)
   - Feature flags enabled
   - Sync type (user/contact)

3. **Logs**:
   - Rails logs (last 50 lines with GLPI errors)
   - Sidekiq logs
   - GLPI API logs (if accessible)

4. **Steps to Reproduce**:
   - Exact steps to trigger the issue
   - Expected behavior
   - Actual behavior

5. **Diagnostics**:
   - Output from quick test commands
   - Metadata inspection results
   - Sidekiq queue status

### Support Channels

1. **Documentation**: Check user guide and developer guide
2. **Community Forum**: https://community.chatwoot.com
3. **GitHub Issues**: https://github.com/chatwoot/chatwoot/issues
4. **Enterprise Support**: For paid support plans

---

**Version**: 1.0.0
**Last Updated**: 2025-11-05
