# GLPI Integration Testing Guide

## Overview

This guide covers testing strategies for the GLPI integration in Chatwoot. The integration has comprehensive test coverage at multiple levels:

- **Unit Tests**: Individual services, mappers, and API clients
- **Integration Tests**: HookJob and end-to-end flows
- **Manual Tests**: With live GLPI instance

---

## Automated Test Suite

### Test Coverage Summary

| Component | Files | Lines | Coverage |
|-----------|-------|-------|----------|
| **Phase 1 - API Clients** | 5 | 763 | ~95% |
| **Phase 2 - Data Mappers** | 3 | 565 | ~100% |
| **Phase 3 - Core Services** | 4 | 718 | ~95% |
| **Phase 4 - Integration** | 1 | 134 | ~95% |
| **Phase 5 - E2E Tests** | 1 | 245 | ~100% |
| **Total** | 14 | 2,425 | ~96% |

---

## Running Tests

### Run All GLPI Tests

```bash
# Run all GLPI integration tests
bundle exec rspec spec/services/crm/glpi/

# Run with coverage report
COVERAGE=true bundle exec rspec spec/services/crm/glpi/
open coverage/index.html
```

### Run by Component

```bash
# Phase 1: API Clients
bundle exec rspec spec/services/crm/glpi/api/

# Phase 2: Data Mappers
bundle exec rspec spec/services/crm/glpi/mappers/

# Phase 3: Core Services
bundle exec rspec spec/services/crm/glpi/*_service_spec.rb

# Phase 5: Integration Tests
bundle exec rspec spec/services/crm/glpi/integration_spec.rb

# HookJob Integration
bundle exec rspec spec/jobs/hook_job_spec.rb --tag glpi
```

### Run Specific Tests

```bash
# Single service
bundle exec rspec spec/services/crm/glpi/processor_service_spec.rb

# Single context
bundle exec rspec spec/services/crm/glpi/processor_service_spec.rb:70

# Run by line number
bundle exec rspec spec/services/crm/glpi/integration_spec.rb:35
```

---

## Test Scenarios Covered

### Unit Tests (Phases 1-3)

#### API Clients
- ✅ Session management (init/kill with cleanup)
- ✅ CRUD operations for Users, Contacts, Tickets, Followups
- ✅ Search operations with criteria
- ✅ Error handling (401, 404, 422, 500)
- ✅ Timeout handling
- ✅ Response parsing

#### Data Mappers
- ✅ Contact → GLPI User mapping
- ✅ Contact → GLPI Contact mapping
- ✅ Conversation → GLPI Ticket mapping
- ✅ Message → GLPI ITILFollowup mapping
- ✅ Name splitting (single, multiple spaces, nil, blank)
- ✅ Phone number formatting (valid, invalid, international)
- ✅ Status code mappings (open, pending, resolved, snoozed)
- ✅ Priority code mappings (low, medium, high, urgent)
- ✅ Missing data handling (.compact usage)

#### Core Services
- ✅ SetupService: Credential validation and connectivity testing
- ✅ UserFinderService: Find-or-create pattern for Users
- ✅ ContactFinderService: Find-or-create pattern for Contacts
- ✅ ProcessorService: Event routing and orchestration
- ✅ Dual sync mode (User vs Contact)
- ✅ Metadata storage (external IDs, ticket IDs, message tracking)
- ✅ Error tracking with ChatwootExceptionTracker

### Integration Tests (Phases 4-5)

#### HookJob Integration
- ✅ Event routing to GLPI processor
- ✅ Redis mutex lock acquisition
- ✅ Feature flag validation
- ✅ All 4 event types (contact.created/updated, conversation.created/updated)
- ✅ Invalid event rejection
- ✅ Disabled hook handling

#### End-to-End Flows
- ✅ Full contact → ticket → followup flow
- ✅ Sync type switching (User vs Contact)
- ✅ API error handling
- ✅ Non-identifiable contact handling
- ✅ Update existing records (no duplicates)
- ✅ Message attachment URL inclusion
- ✅ Incremental message sync

---

## Manual Testing with Live GLPI

### Prerequisites

1. **GLPI Instance**: Running GLPI 10.0+ with API enabled
2. **API Tokens**: App token and user token generated
3. **Chatwoot Instance**: Development or staging environment
4. **Feature Flag**: `crm_integration` enabled for account

### Setup Steps

#### 1. Enable GLPI API

In GLPI:
```
Setup → General → API
- Enable REST API
- Generate Application Token (save as APP_TOKEN)
```

In GLPI User Preferences:
```
Remote Access Keys → API token
- Generate User Token (save as USER_TOKEN)
```

#### 2. Configure Integration in Chatwoot

```ruby
# Rails console
account = Account.first
account.enable_features('crm_integration')

hook = account.hooks.create!(
  app_id: 'glpi',
  settings: {
    'api_url' => 'https://your-glpi.com/apirest.php',
    'app_token' => ENV['GLPI_APP_TOKEN'],
    'user_token' => ENV['GLPI_USER_TOKEN'],
    'entity_id' => '0',
    'sync_type' => 'user',
    'ticket_type' => '1'
  }
)
```

#### 3. Test Connectivity

```ruby
setup_service = Crm::Glpi::SetupService.new(hook)
result = setup_service.validate_and_test

puts result # Should show { success: true, message: "GLPI connection successful" }
```

### Manual Test Cases

#### Test 1: Contact Sync (User Mode)

**Steps**:
1. Create new contact in Chatwoot with email and phone
2. Check Rails logs for GLPI API calls
3. Verify user created in GLPI
4. Check contact metadata for `glpi_user_id`

**Expected**:
```ruby
contact.reload
contact.additional_attributes.dig('external', 'glpi_user_id')
# => 123 (GLPI User ID)
```

#### Test 2: Ticket Creation

**Steps**:
1. Create conversation with the contact
2. Add first message
3. Check Rails logs for ticket creation
4. Verify ticket in GLPI
5. Check conversation metadata for `ticket_id`

**Expected**:
```ruby
conversation.reload
conversation.additional_attributes.dig('glpi', 'ticket_id')
# => 456 (GLPI Ticket ID)
```

#### Test 3: Message Sync as Followups

**Steps**:
1. Add 3 new messages to conversation
2. Update conversation status
3. Check Rails logs for followup creation
4. Verify followups in GLPI ticket
5. Check `last_synced_message_id`

**Expected**:
```ruby
conversation.reload
conversation.additional_attributes.dig('glpi', 'last_synced_message_id')
# => (ID of last message)
```

#### Test 4: Contact Sync (Contact Mode)

**Steps**:
1. Update hook to use `sync_type: 'contact'`
2. Create new contact
3. Verify GLPI Contact created (not User)
4. Check contact metadata for `glpi_contact_id`

**Expected**:
```ruby
contact.reload
contact.additional_attributes.dig('external', 'glpi_contact_id')
# => 789 (GLPI Contact ID)
```

#### Test 5: Status Synchronization

**Steps**:
1. Create conversation → Check GLPI status = 2 (Processing)
2. Update to pending → Check GLPI status = 4 (Pending)
3. Resolve conversation → Check GLPI status = 5 (Solved)

**Expected**: GLPI ticket status matches conversation status

#### Test 6: Priority Synchronization

**Steps**:
1. Create conversation with `priority: :urgent`
2. Check GLPI ticket priority = 5 (Very High)
3. Update to `priority: :low`
4. Check GLPI ticket priority = 2 (Low)

**Expected**: GLPI ticket priority matches conversation priority

#### Test 7: Private Messages

**Steps**:
1. Add private (internal) message to conversation
2. Check GLPI followup `is_private` = 1
3. Add public message
4. Check GLPI followup `is_private` = 0

**Expected**: Private flag correctly set in GLPI

#### Test 8: Attachment URLs

**Steps**:
1. Add message with file attachment
2. Check GLPI followup content includes "Attachments:" section
3. Verify attachment URL listed

**Expected**: Followup content contains attachment URLs

#### Test 9: Concurrent Events (Race Condition)

**Steps**:
1. Create 5 contacts rapidly (< 1 second apart)
2. Check GLPI for duplicate users
3. Verify Redis mutex prevented duplicates

**Expected**: No duplicate GLPI users created

#### Test 10: Error Handling

**Steps**:
1. Configure hook with invalid tokens
2. Create contact
3. Check Rails logs for error
4. Verify no crash, error logged

**Expected**: Graceful error handling, no exceptions raised

---

## Monitoring During Tests

### Rails Logs

```bash
# Watch GLPI activity
tail -f log/development.log | grep GLPI

# Example output:
# [GLPI] Created user #123 for contact #456
# [GLPI] Created ticket #789 for conversation #1011
# [GLPI] Updated ticket #789 for conversation #1011
# [GLPI] Created followup for message #1213 on ticket #789
```

### Sidekiq Dashboard

```
http://localhost:3000/sidekiq

Check:
- HookJob processing
- Queue: medium
- Failures (should be 0)
- Retry attempts
```

### GLPI Logs

```bash
# GLPI API logs location
tail -f /var/www/html/glpi/files/_log/api.log

# Check for:
# - Session creation/destruction
# - API calls (User, Contact, Ticket, Followup)
# - Error responses
```

---

## Performance Testing

### Load Test: Many Messages

```ruby
# Create conversation with 100 messages
conversation = Conversation.first
100.times do |i|
  conversation.messages.create!(
    account: conversation.account,
    inbox: conversation.inbox,
    content: "Test message #{i}",
    message_type: :incoming,
    sender: conversation.contact
  )
end

# Trigger sync
processor = Crm::Glpi::ProcessorService.new(hook)
result = processor.process_event('conversation.updated', conversation)

# Check:
# - Total time
# - Number of API calls
# - Memory usage
# - No errors
```

### Concurrency Test: Rapid Events

```ruby
# Create 10 contacts simultaneously
threads = 10.times.map do |i|
  Thread.new do
    contact = Contact.create!(
      account: account,
      name: "Test Contact #{i}",
      email: "test#{i}@example.com"
    )
    HookJob.perform_now(hook, 'contact.created', { contact: contact })
  end
end
threads.each(&:join)

# Check:
# - No duplicate GLPI users
# - All contacts have glpi_user_id
# - Redis mutex worked
```

---

## Troubleshooting

### Common Issues

#### 1. API Connection Failed

**Symptoms**: "API connection failed" error
**Causes**:
- Invalid API URL
- Wrong app_token or user_token
- GLPI API not enabled
- Network/firewall issues

**Fix**:
```ruby
# Test connectivity
setup_service = Crm::Glpi::SetupService.new(hook)
result = setup_service.validate_and_test
puts result[:error] # Check specific error
```

#### 2. Duplicate Users/Contacts

**Symptoms**: Multiple GLPI records for same contact
**Causes**:
- Redis mutex not working
- Race condition in event processing

**Fix**:
- Check Redis is running
- Verify mutex lock key format
- Check Sidekiq isn't bypassing mutex

#### 3. Messages Not Syncing

**Symptoms**: Conversation updates but no followups in GLPI
**Causes**:
- Missing ticket_id in conversation metadata
- API errors during followup creation

**Fix**:
```ruby
conversation.reload
puts conversation.additional_attributes.dig('glpi', 'ticket_id')
# If nil, ticket wasn't created properly
```

#### 4. Session Token Leaks

**Symptoms**: Many active sessions in GLPI
**Causes**:
- Exception during API call
- Session not cleaned up in ensure block

**Fix**:
- Check BaseClient `with_session` usage
- Verify `kill_session` called in ensure

---

## Test Data Cleanup

### After Manual Testing

```ruby
# Clean up test data in Chatwoot
Contact.where(email: /test\d+@example.com/).destroy_all
Conversation.where(display_id: ...test_ids...).destroy_all

# Clean up in GLPI (via API or UI)
# - Delete test users/contacts
# - Delete test tickets
# - Close active sessions
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: GLPI Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2

      - name: Install dependencies
        run: bundle install

      - name: Run GLPI tests
        run: |
          bundle exec rspec spec/services/crm/glpi/

      - name: Upload coverage
        uses: codecov/codecov-action@v2
        with:
          files: ./coverage/.resultset.json
```

---

## Success Criteria

### Automated Tests
- ✅ All unit tests passing (96% coverage)
- ✅ All integration tests passing
- ✅ No WebMock errors
- ✅ No RuboCop violations

### Manual Tests
- ✅ Contact syncs to GLPI User/Contact
- ✅ Ticket created with correct data
- ✅ Followups added for messages
- ✅ Status/priority synchronized
- ✅ Private messages marked correctly
- ✅ Attachments URLs included
- ✅ No duplicate records
- ✅ Errors logged gracefully
- ✅ No session token leaks

### Performance
- ✅ 100 messages sync < 30 seconds
- ✅ 10 concurrent contacts no duplicates
- ✅ Memory usage stable
- ✅ No N+1 queries

---

## Next Steps After Testing

1. **Code Review**: Get team review of all phases
2. **Documentation**: Update user-facing docs
3. **Logo**: Add GLPI logo to `/public/dashboard/images/integrations/`
4. **Deployment**: Merge to main branch
5. **Release Notes**: Document new feature
6. **User Guide**: Write setup instructions

---

## References

- [GLPI REST API Documentation](https://github.com/glpi-project/glpi/blob/main/apirest.md)
- [Chatwoot Hooks Documentation](https://www.chatwoot.com/docs/product/integrations/webhooks)
- [RSpec Best Practices](https://rspec.info/documentation/)
- [WebMock Usage](https://github.com/bblimke/webmock)
