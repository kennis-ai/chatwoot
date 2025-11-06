# Krayin CRM Integration - Remaining Tasks

## Completed Phases

- ✅ **Phase 1**: Foundation & Setup (Commit: Multiple commits)
- ✅ **Phase 2**: Core Services & Mappers (Commit: c128a2122)
- ✅ **Phase 3**: Event Integration & Testing (Commits: 66dff2af4, b48f9d095)
- ✅ **Phase 4.1-4.3**: Organization Sync & Custom Attributes (Commit: be21dcfc5)

## Remaining Implementation Tasks

### Phase 4.4: Enhanced Error Handling

**Status**: Not started
**Priority**: High
**Estimated Effort**: 2-3 hours

#### Tasks
- [ ] Add retry logic for transient API failures
- [ ] Implement exponential backoff for rate limits
- [ ] Add detailed error logging with context
- [ ] Implement error notification system (email/slack)
- [ ] Add error recovery patterns

#### Files to Modify
- `app/services/crm/krayin/api/base_client.rb`
- `app/services/crm/krayin/processor_service.rb`

#### Implementation Notes
```ruby
# BaseClient retry logic example
def request_with_retry(method, endpoint, data = {}, retries = 3)
  attempt = 0
  begin
    attempt += 1
    send_request(method, endpoint, data)
  rescue ApiError => e
    if retriable_error?(e) && attempt < retries
      wait_time = 2 ** attempt # Exponential backoff
      sleep(wait_time)
      retry
    else
      raise
    end
  end
end

def retriable_error?(error)
  # Retry on 429 (rate limit), 502/503/504 (temporary server errors)
  [429, 502, 503, 504].include?(error.status_code)
end
```

---

### Phase 4.5: Performance Optimization

**Status**: Not started
**Priority**: Medium
**Estimated Effort**: 3-4 hours

#### Tasks
- [ ] Add database indexes for external ID lookups
- [ ] Optimize API calls (batch where possible)
- [ ] Add caching for pipeline/stage/source/type lookups
- [ ] Optimize mapper operations
- [ ] Profile and optimize slow paths

#### Files to Create/Modify
- `db/migrate/YYYYMMDDHHMMSS_optimize_krayin_lookups.rb`
- `app/services/crm/krayin/setup_service.rb`
- `app/services/crm/krayin/processor_service.rb`

#### Implementation Notes
```ruby
# Migration for indexes
class OptimizeKrayinLookups < ActiveRecord::Migration[7.0]
  def change
    add_index :contact_inboxes, :source_id,
      where: "source_id LIKE 'krayin:%'",
      name: 'index_contact_inboxes_on_krayin_source_id'
  end
end

# Caching example
class SetupService
  def fetch_default_configuration
    Rails.cache.fetch("krayin:config:#{api_url}", expires_in: 1.hour) do
      {
        default_pipeline_id: fetch_pipelines.first['id'],
        default_stage_id: fetch_stages.first['id'],
        # ...
      }
    end
  end
end
```

---

### Phase 4.6: Lead Stage Progression Logic

**Status**: Not started
**Priority**: Medium
**Estimated Effort**: 4-5 hours

#### Tasks
- [ ] Implement stage mapping configuration
- [ ] Add stage progression rules based on conversation status
- [ ] Handle stage transitions (new → contacted → qualified → won/lost)
- [ ] Add configuration for auto-qualify behavior
- [ ] Support custom stage mapping

#### Files to Modify
- `app/services/crm/krayin/processor_service.rb`
- `app/services/crm/krayin/mappers/conversation_mapper.rb`
- `config/integration/apps.yml`

#### Configuration Schema Addition
```yaml
# apps.yml additions
settings_json_schema:
  properties:
    stage_progression_enabled: { type: boolean }
    stage_mapping:
      type: object
      properties:
        on_conversation_created: { type: integer }  # stage_id
        on_first_response: { type: integer }
        on_conversation_resolved: { type: integer }
```

#### Implementation Notes
```ruby
# ProcessorService stage progression
def update_lead_stage(lead_id, conversation)
  return unless stage_progression_enabled?

  new_stage_id = determine_stage_from_conversation(conversation)
  return if new_stage_id.blank?

  lead_data = { lead_pipeline_stage_id: new_stage_id }
  lead_client.update_lead(lead_data, lead_id)
end

def determine_stage_from_conversation(conversation)
  mapping = @hook.settings['stage_mapping'] || {}

  case conversation.status
  when 'open'
    mapping['on_conversation_created'] || @hook.settings['default_stage_id']
  when 'resolved'
    mapping['on_conversation_resolved']
  else
    nil
  end
end
```

---

### Phase 4.7: Activity Enhancement

**Status**: Not started
**Priority**: Low
**Estimated Effort**: 2-3 hours

#### Tasks
- [ ] Support multiple activity types (call, meeting, chat, email)
- [ ] Add activity type detection from inbox type
- [ ] Support activity notes/comments from messages
- [ ] Add activity scheduling support
- [ ] Support activity location mapping

#### Files to Modify
- `app/services/crm/krayin/mappers/conversation_mapper.rb`
- `app/services/crm/krayin/mappers/message_mapper.rb`

#### Implementation Notes
```ruby
# MessageMapper enhanced activity type
def activity_type
  case inbox_type
  when 'Channel::WebWidget'
    'chat'
  when 'Channel::Email'
    'email'
  when 'Channel::TwilioSms', 'Channel::Whatsapp'
    'call' # or 'sms'
  when 'Channel::Api'
    detect_from_message_type
  else
    'note'
  end
end

def inbox_type
  @message.inbox&.channel&.class&.name
end
```

---

## Phase 5: Documentation & Release

### Phase 5.1: User Documentation (Wiki)

**Status**: Not started
**Priority**: High
**Estimated Effort**: 6-8 hours

#### Wiki Pages to Create
1. **Krayin-CRM-Integration.md** - Main integration guide
   - Overview and benefits
   - Prerequisites (Krayin v2.1.5+, Laravel Sanctum token)
   - Setup instructions
   - Configuration options
   - Field mappings
   - Troubleshooting

2. **Krayin-Setup-Guide.md** - Step-by-step tutorial
   - Obtaining API credentials
   - Configuring integration in Chatwoot
   - Testing the connection
   - Verifying sync
   - Screenshots and examples

3. **Krayin-Troubleshooting.md** - Common issues
   - Connection failures
   - Sync errors
   - Missing data
   - Performance issues
   - Log analysis

4. **Krayin-FAQ.md** - Frequently asked questions
   - How often does sync happen?
   - Can I sync existing contacts?
   - What happens if Krayin is down?
   - How do I map custom fields?

#### Templates
```markdown
# Krayin CRM Integration

## Overview
The Krayin CRM integration automatically syncs contacts, conversations, and activities from Chatwoot to your Krayin CRM instance.

## Features
- ✅ Automatic contact sync (Person + Lead)
- ✅ Organization linking
- ✅ Conversation tracking as activities
- ✅ Message history sync
- ✅ Custom attribute mapping
- ✅ Real-time bidirectional sync

## Prerequisites
- Krayin CRM v2.1.5 or higher
- Krayin REST API Package v2.1.1
- Laravel Sanctum API token
- Chatwoot Enterprise (or feature flag enabled)
...
```

### Phase 5.2: Developer Documentation

**Status**: Not started
**Priority**: Medium
**Estimated Effort**: 4-5 hours

#### Documents to Create

1. **krayin-architecture.md** - System design
   - Component overview
   - Data flow diagrams
   - API client architecture
   - Mapper pattern explanation
   - External ID management
   - Event system integration

2. **krayin-development-guide.md** - Developer guide
   - Local development setup
   - Running tests
   - Debugging integration
   - Adding new mappers
   - Extending processors
   - API client usage

3. **krayin-testing-guide.md** - Testing strategy
   - Unit test examples
   - Integration test patterns
   - Mocking API responses
   - WebMock usage
   - Test factories
   - Coverage requirements

### Phase 5.3: Code Documentation

**Status**: Partially complete
**Priority**: Medium
**Estimated Effort**: 2-3 hours

#### Tasks
- [ ] Add RDoc comments to all public methods
- [ ] Add inline documentation for complex logic
- [ ] Document configuration options
- [ ] Add examples in code comments
- [ ] Generate RDoc HTML documentation

---

## Summary

### Current Status
- **Implementation**: ~80% complete
- **Testing**: ~95% complete (Phase 4.4-4.7 tests needed)
- **Documentation**: ~40% complete (custom attributes done)

### Immediate Next Steps
1. Implement Phase 4.4: Enhanced Error Handling (HIGH PRIORITY)
2. Create Wiki documentation (Phase 5.1)
3. Implement Phase 4.6: Lead Stage Progression (if business logic defined)
4. Perform full E2E testing with real Krayin instance

### Optional Enhancements
- Phase 4.5: Performance optimization (if performance issues arise)
- Phase 4.7: Activity enhancement (if richer activity data needed)
- Bi-directional sync (sync FROM Krayin TO Chatwoot)
- Webhook support from Krayin
- Bulk sync tool for existing contacts

---

## Testing Checklist

Before marking integration as production-ready:

- [ ] Test with real Krayin v2.1.5 instance
- [ ] Verify all CRUD operations (Person, Lead, Organization, Activity)
- [ ] Test concurrent event handling with Redis locks
- [ ] Verify external ID storage and retrieval
- [ ] Test error scenarios (API down, invalid token, rate limits)
- [ ] Test with 1000+ contacts for performance
- [ ] Verify custom attribute mapping
- [ ] Test organization linking
- [ ] Verify conversation sync
- [ ] Verify message sync
- [ ] Test feature flag enforcement
- [ ] Test hook enable/disable behavior

---

## Deployment Checklist

- [ ] Run all RSpec tests (`bundle exec rspec spec/services/crm/krayin`)
- [ ] Run integration tests
- [ ] Review and approve all code changes
- [ ] Update CHANGELOG.md
- [ ] Create GitHub release notes
- [ ] Update version tag (e.g., v4.7.0-kennis-ai.1.1.0)
- [ ] Deploy to staging environment
- [ ] Perform smoke tests
- [ ] Deploy to production
- [ ] Monitor error logs for 24 hours
- [ ] Notify users via announcement

---

## Future Roadmap

### v2.0 Features (Future)
- Bi-directional sync (Krayin → Chatwoot)
- Webhook support from Krayin
- Bulk import tool
- Advanced field mapping UI
- Sync conflict resolution
- Custom sync schedules
- Sync analytics dashboard
- Multiple Krayin instance support
