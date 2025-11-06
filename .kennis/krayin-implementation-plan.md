# Krayin CRM Integration - Implementation Plan

**Document Version:** 1.1  
**Date:** 2025-01-06  
**Based on:** LeadSquared Integration Pattern & CRM Integration Implementation Plan  
**Target Branch:** `feature/krayin-crm-integration`  
**Target Krayin Version:** v2.1.5+ (January 2025)  
**REST API Package Version:** v2.1.1+ (September 2025)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Summary](#architecture-summary)
3. [Phase 1: Foundation & API Clients](#phase-1-foundation--api-clients)
4. [Phase 2: Core Services & Mappers](#phase-2-core-services--mappers)
5. [Phase 3: Event Integration & Testing](#phase-3-event-integration--testing)
6. [Phase 4: Advanced Features & Polish](#phase-4-advanced-features--polish)
7. [Phase 5: Documentation & Release](#phase-5-documentation--release)
8. [Success Criteria](#success-criteria)
9. [Risk Mitigation](#risk-mitigation)

---

## Overview

### Prerequisites

**IMPORTANT:** Krayin CRM requires the separate `krayin/rest-api` package for API access:
- **Target Krayin Version:** v2.1.x (latest: v2.1.5 as of January 2025)
- **REST API Package:** `krayin/rest-api` v2.1.1+ (latest as of September 2025)
- **Installation:** `composer require krayin/rest-api`
- **Minimum Krayin Version:** v2.0.0 or later
- Uses Laravel Sanctum for authentication
- API documentation accessible at `/api/admin/documentation` (L5-Swagger)
- All API endpoints are under `/api/admin/*` prefix

**Environment Configuration Required:**
```bash
SANCTUM_STATEFUL_DOMAINS="${APP_URL}"
L5_SWAGGER_UI_PERSIST_AUTHORIZATION=true
```

### Goals
- Sync Chatwoot contacts to Krayin Leads/Persons
- Create Krayin Activities from conversations
- Track lead pipeline and sales stages
- Enable sales team workflows

### Timeline
**Total Duration:** 4-5 weeks

### Key Deliverables
1. Base API client with token authentication
2. Person and Lead management
3. Activity tracking from conversations
4. Pipeline stage progression
5. Comprehensive test coverage
6. User and developer documentation

### Technical Approach
- Follow LeadSquared integration pattern
- **Require krayin/rest-api package installation**
- Use Laravel Sanctum API token authentication
- Support dual entity creation (Person + Lead)
- Implement activity sync for conversation tracking
- Add organization sync for company contacts
- API endpoints are under `/api/admin/*` prefix
- Use L5-Swagger documentation for endpoint discovery

---

## Architecture Summary

### Component Structure

```
app/services/crm/krayin/
├── setup_service.rb              # Setup and validation
├── processor_service.rb          # Event processing orchestrator
├── lead_finder_service.rb        # Find/create leads
├── person_finder_service.rb      # Find/create persons
├── api/
│   ├── base_client.rb            # Base HTTP client with token auth
│   ├── lead_client.rb            # Lead CRUD operations
│   ├── person_client.rb          # Person CRUD operations
│   ├── organization_client.rb    # Organization CRUD operations
│   ├── activity_client.rb        # Activity CRUD operations
│   └── pipeline_client.rb        # Pipeline/Stage operations
└── mappers/
    ├── contact_mapper.rb         # Contact → Person + Lead
    ├── conversation_mapper.rb    # Conversation → Activity
    └── message_mapper.rb         # Messages → Activity notes

spec/services/crm/krayin/         # Mirror structure with specs
```

### Data Flow

```
Chatwoot Event → Hook Listener → Hook Job
                                    ↓
                          Krayin Processor Service
                                    ↓
                    ┌───────────────┴───────────────┐
                    ↓                               ↓
            Contact Handler                 Conversation Handler
                    ↓                               ↓
        Person + Lead Creation              Activity Creation
                    ↓                               ↓
            External ID Storage             Metadata Storage
```

### Key Mappings

**Contact → Krayin:**
- Contact → Person (basic info)
- Contact → Lead (sales data)
- Store both `person_id` and `lead_id`

**Conversation → Krayin:**
- Conversation → Activity (interaction record)
- Status → Lead Stage (pipeline progression)
- Messages → Activity comments

---

## Phase 1: Foundation & API Clients

**Duration:** Week 1  
**Goal:** Establish solid API foundation with all required clients

### Tasks

#### 1.1 Environment Setup
- [ ] Create feature branch: `feature/krayin-crm-integration`
- [ ] Set up Krayin development instance (Docker/local)
- [ ] **Install krayin/rest-api package: `composer require krayin/rest-api`**
- [ ] **Run `php artisan krayin-rest-api:install` for L5-Swagger setup**
- [ ] **Configure Sanctum in .env: `SANCTUM_STATEFUL_DOMAINS` and `L5_SWAGGER_UI_PERSIST_AUTHORIZATION`**
- [ ] Verify Krayin API endpoints at `/api/admin/documentation`
- [ ] Generate API token for test user
- [ ] Document API authentication flow with Bearer tokens
- [ ] Test API access with curl/Postman

**Deliverable:** Working Krayin instance with REST API package installed and accessible

#### 1.2 Base API Client
- [ ] Create `Crm::Krayin::Api::BaseClient`
- [ ] Implement **Bearer token authentication** (Laravel Sanctum)
- [ ] Set base URI to `/api/admin` prefix
- [ ] Add HTTP methods: GET, POST, PUT, DELETE
- [ ] Implement error handling with custom `ApiError` class
- [ ] Add response parsing and validation
- [ ] Handle 401 (unauthorized), 404 (not found), 422 (validation) errors specifically
- [ ] Add proper headers: `Authorization: Bearer {token}`, `Accept: application/json`

**Files:**
- `app/services/crm/krayin/api/base_client.rb`
- `spec/services/crm/krayin/api/base_client_spec.rb`

**Test Coverage:**
- Valid authentication
- Invalid token handling
- HTTP method operations
- Error response parsing
- Validation error extraction

#### 1.3 Person Client
- [ ] Create `Crm::Krayin::Api::PersonClient` extending `BaseClient`
- [ ] Implement `search_person(email:, phone:)` - searches via `/api/admin/contacts/persons`
- [ ] Implement `create_person(person_data)` - POST to `/api/admin/contacts/persons`
  - Required: `name`, `emails` (array format)
  - Optional: `contact_numbers` (array), `job_title`, `organization_id`
- [ ] Implement `update_person(person_data, person_id)` - PUT to `/api/admin/contacts/persons/{id}`
- [ ] Implement `get_person(person_id)` - GET from `/api/admin/contacts/persons/{id}`
- [ ] Add proper argument validation
- [ ] Handle array format for emails and contact_numbers

**Files:**
- `app/services/crm/krayin/api/person_client.rb`
- `spec/services/crm/krayin/api/person_client_spec.rb`

#### 1.4 Lead Client
- [ ] Create `Crm::Krayin::Api::LeadClient` extending `BaseClient`
- [ ] Implement `search_lead(email:, phone:)` - searches via `/api/admin/leads`
- [ ] Implement `create_lead(lead_data)` - POST to `/api/admin/leads`
  - Required: `title`, `lead_value`, `lead_source_id`, `lead_type_id`, `lead_pipeline_id`, `lead_pipeline_stage_id`
  - Optional: `person_id`, `description`, `expected_close_date`
- [ ] Implement `update_lead(lead_data, lead_id)` - PUT to `/api/admin/leads/{id}`
- [ ] Implement `get_lead(lead_id)` - GET from `/api/admin/leads/{id}`
- [ ] Implement `get_pipelines()` - GET from `/api/admin/leads/pipelines` (verify endpoint)
- [ ] Implement `get_stages(pipeline_id)` - GET stages for pipeline
- [ ] Handle lead stage updates separately if needed

**Files:**
- `app/services/crm/krayin/api/lead_client.rb`
- `spec/services/crm/krayin/api/lead_client_spec.rb`

#### 1.5 Activity Client
- [ ] Create `Crm::Krayin::Api::ActivityClient` extending `BaseClient`
- [ ] Implement `search_activity(params)` - searches via `/api/admin/activities`
- [ ] Implement `create_activity(activity_data)` - POST to `/api/admin/activities`
  - Required fields depend on `type`:
    - `note`: requires `type`, `comment`
    - `call`, `meeting`, `lunch`: require `type`, `title`, `schedule_from`, `schedule_to`
  - Optional: `location`, `participants` (array), `is_done`
- [ ] Implement `update_activity(activity_data, activity_id)` - PUT to `/api/admin/activities/{id}`
- [ ] Implement `get_activity(activity_id)` - GET from `/api/admin/activities/{id}`
- [ ] Handle activity-lead linking via pivot table
- [ ] Handle activity-person linking via pivot table

**Files:**
- `app/services/crm/krayin/api/activity_client.rb`
- `spec/services/crm/krayin/api/activity_client_spec.rb`

#### 1.6 Organization Client (Optional)
- [ ] Create `Crm::Krayin::Api::OrganizationClient` extending `BaseClient`
- [ ] Implement `search_organization(name)` - searches via `/api/admin/contacts/organizations`
- [ ] Implement `create_organization(org_data)` - POST to `/api/admin/contacts/organizations`
  - Required: `name`
  - Optional: `address` (array format)
- [ ] Implement `update_organization(org_data, org_id)` - PUT to `/api/admin/contacts/organizations/{id}`
- [ ] Implement `get_organization(org_id)` - GET from `/api/admin/contacts/organizations/{id}`

**Files:**
- `app/services/crm/krayin/api/organization_client.rb`
- `spec/services/crm/krayin/api/organization_client_spec.rb`

### Phase 1 Deliverables
- ✅ All API clients implemented and tested
- ✅ 90%+ test coverage for API layer
- ✅ Working Krayin development environment
- ✅ API documentation notes

### Phase 1 Exit Criteria
- [ ] All API client specs passing
- [ ] Manual API testing successful
- [ ] Error handling verified
- [ ] Code review completed

---

## Phase 2: Core Services & Mappers

**Duration:** Week 2  
**Goal:** Implement business logic for data transformation and synchronization

### Tasks

#### 2.1 Contact Mapper
- [ ] Create `Crm::Krayin::Mappers::ContactMapper`
- [ ] Implement `map_to_person(contact)` method
  - Map name (string)
  - **Map email to `emails` ARRAY format** (required, unique)
  - **Map phone to `contact_numbers` ARRAY format** (optional, unique)
  - Format: `{"value": "email@example.com", "label": "work"}` 
  - Map job title and additional attributes
- [ ] Implement `map_to_lead(contact, person_id, settings)` method
  - Map title from contact name
  - Link to person_id
  - Apply default pipeline/stage
  - Apply lead source
  - Map lead value if available
  - Map description from attributes
- [ ] Implement `map_organization(contact)` helper (if sync enabled)
  - Extract company name
  - Map address fields
  - Return nil if no company info

**Files:**
- `app/services/crm/krayin/mappers/contact_mapper.rb`
- `spec/services/crm/krayin/mappers/contact_mapper_spec.rb`

**Test Coverage:**
- Person mapping with all fields
- Person mapping with minimal fields
- Lead mapping with person reference
- Lead mapping with custom settings
- Organization extraction

#### 2.2 Conversation Mapper
- [ ] Create `Crm::Krayin::Mappers::ConversationMapper`
- [ ] Implement `map_to_activity(conversation, person_id, settings)` method
  - Map display_id to title
  - Map first message to comment
  - Map created_at to schedule_from
  - Map updated_at to schedule_to
  - Map inbox type to activity type
  - Map assignee to user_id
  - Add participants array with person_id
  - Map is_done based on status
  - Extract location if available

**Files:**
- `app/services/crm/krayin/mappers/conversation_mapper.rb`
- `spec/services/crm/krayin/mappers/conversation_mapper_spec.rb`

**Test Coverage:**
- Activity mapping from open conversation
- Activity mapping from resolved conversation
- Activity type determination from inbox
- Participant mapping
- Status to is_done mapping

#### 2.3 Message Mapper
- [ ] Create `Crm::Krayin::Mappers::MessageMapper`
- [ ] Implement methods for appending messages to activity comments
- [ ] Handle message formatting (sender, timestamp, content)

**Files:**
- `app/services/crm/krayin/mappers/message_mapper.rb`
- `spec/services/crm/krayin/mappers/message_mapper_spec.rb`

#### 2.4 Person Finder Service
- [ ] Create `Crm::Krayin::PersonFinderService`
- [ ] Implement `find_or_create(contact)` method
  - Search by email first
  - Fallback to phone if no email
  - Create new person if not found
  - Return person_id

**Files:**
- `app/services/crm/krayin/person_finder_service.rb`
- `spec/services/crm/krayin/person_finder_service_spec.rb`

#### 2.5 Lead Finder Service
- [ ] Create `Crm::Krayin::LeadFinderService`
- [ ] Implement `find_or_create(contact, person_id)` method
  - Search by person_id
  - Create new lead if not found
  - Return lead_id

**Files:**
- `app/services/crm/krayin/lead_finder_service.rb`
- `spec/services/crm/krayin/lead_finder_service_spec.rb`

#### 2.6 Setup Service
- [ ] Create `Crm::Krayin::SetupService`
- [ ] Implement `setup` method
  - Validate API connection
  - Fetch and validate pipelines
  - Set default pipeline/stage if not configured
  - Validate lead source
  - Store configuration in hook settings
- [ ] Add error handling with ChatwootExceptionTracker

**Files:**
- `app/services/crm/krayin/setup_service.rb`
- `spec/services/crm/krayin/setup_service_spec.rb`

**Test Coverage:**
- Successful setup with valid credentials
- Setup with invalid credentials
- Default pipeline/stage selection
- Configuration persistence

#### 2.7 Processor Service (Core Logic)
- [ ] Create `Crm::Krayin::ProcessorService` extending `Crm::BaseProcessorService`
- [ ] Implement `initialize(hook)` method
  - Extract settings
  - Initialize all API clients
  - Initialize finder services
  - Set feature flags (create_person, create_lead, enable_activity)
- [ ] Implement `handle_contact(contact)` method
  - Check if contact is identifiable
  - Create/update person if enabled
  - Create/update lead if enabled
  - Store external IDs (person_id, lead_id)
- [ ] Implement private `create_or_update_person(contact, person_id)`
- [ ] Implement private `create_or_update_lead(contact, person_id, lead_id)`
- [ ] Add comprehensive error handling

**Files:**
- `app/services/crm/krayin/processor_service.rb`
- `spec/services/crm/krayin/processor_service_spec.rb`

**Test Coverage:**
- Contact creation with person only
- Contact creation with person + lead
- Contact update scenarios
- External ID storage
- Error handling for API failures

### Phase 2 Deliverables
- ✅ All mappers implemented and tested
- ✅ Finder services working correctly
- ✅ Setup service validates connections
- ✅ Processor service handles contact sync
- ✅ 85%+ test coverage for business logic

### Phase 2 Exit Criteria
- [ ] All mapper specs passing
- [ ] All service specs passing
- [ ] Manual testing of contact sync
- [ ] Code review completed

---

## Phase 3: Event Integration & Testing

**Duration:** Week 3  
**Goal:** Integrate with Chatwoot event system and implement conversation handling

### Tasks

#### 3.1 Configuration Setup
- [ ] Add Krayin configuration to `config/integration/apps.yml`
  - Define settings JSON schema
  - Define settings form schema
  - Add visible properties
  - Configure feature flag: `crm_integration`
- [ ] Create logo asset: `public/assets/images/integrations/krayin.png`
- [ ] Update I18n keys in `config/locales/en.yml`

**Files:**
- `config/integration/apps.yml`
- `public/assets/images/integrations/krayin.png`
- `config/locales/en.yml`

#### 3.2 Hook Model Updates
- [ ] Update `app/models/integrations/hook.rb`
- [ ] Add `'krayin'` to `crm_integration?` method
- [ ] Verify hook validation logic

**Files:**
- `app/models/integrations/hook.rb`

#### 3.3 Hook Listener Updates
- [ ] Update `app/listeners/hook_listener.rb`
- [ ] Add Krayin to `supported_events_map`
  - Support: `contact.updated`, `conversation.created`, `conversation.resolved`
- [ ] Verify event filtering logic

**Files:**
- `app/listeners/hook_listener.rb`

#### 3.4 Hook Job Updates
- [ ] Update `app/jobs/hook_job.rb`
- [ ] Add `when 'krayin'` case to `perform` method
- [ ] Implement `process_krayin_integration_with_lock` method
- [ ] Implement `process_krayin_integration` method
  - Handle `contact.updated` event
  - Handle `conversation.created` event
  - Handle `conversation.resolved` event
- [ ] Use Redis mutex for concurrency control

**Files:**
- `app/jobs/hook_job.rb`

#### 3.5 Setup Job Updates
- [ ] Update `app/jobs/crm/setup_job.rb`
- [ ] Add `when 'krayin'` case to `create_setup_service` method
- [ ] Return `Crm::Krayin::SetupService.new(hook)`

**Files:**
- `app/jobs/crm/setup_job.rb`

#### 3.6 Conversation Handling in Processor
- [ ] Implement `handle_conversation_created(conversation)` in Processor
  - Check if activity sync enabled
  - Get or create person_id from contact
  - Map conversation to activity
  - Create activity in Krayin
  - Store activity_id in conversation metadata
- [ ] Implement `handle_conversation_resolved(conversation)` in Processor
  - Update lead stage if auto-qualify enabled
  - Mark activity as done if activity sync enabled
- [ ] Implement private helper methods:
  - `create_activity_from_conversation(conversation)`
  - `mark_activity_done(conversation)`
  - `update_lead_stage(contact, stage_name)`
  - `get_person_id(contact)`
  - `get_activity_id(conversation)`

**Files:**
- `app/services/crm/krayin/processor_service.rb` (update)
- `spec/services/crm/krayin/processor_service_spec.rb` (update)

**Test Coverage:**
- Conversation created with activity sync
- Conversation resolved marks activity done
- Conversation resolved updates lead stage
- Activity metadata storage
- Error handling

#### 3.7 Integration Testing
- [ ] Create integration test suite
- [ ] Test end-to-end contact sync flow
- [ ] Test end-to-end conversation sync flow
- [ ] Test event processing with Redis locks
- [ ] Test concurrent event handling
- [ ] Test error scenarios and recovery

**Files:**
- `spec/jobs/hook_job_spec.rb` (update for Krayin)
- `spec/listeners/hook_listener_spec.rb` (update for Krayin)
- `spec/integration/krayin_integration_spec.rb` (new)

### Phase 3 Deliverables
- ✅ Full event integration working
- ✅ Conversation handling implemented
- ✅ Activity sync functional
- ✅ Lead stage progression working
- ✅ Integration tests passing

### Phase 3 Exit Criteria
- [ ] All integration tests passing
- [ ] Manual E2E testing successful
- [ ] Event processing verified with real Krayin instance
- [ ] Code review completed

---

## Phase 4: Advanced Features & Polish

**Duration:** Week 4  
**Goal:** Implement advanced features and polish the integration

### Tasks

#### 4.1 Organization Sync
- [ ] Implement organization detection in ContactMapper
- [ ] Implement organization creation in Processor
- [ ] Add `create_or_update_organization(contact)` method
- [ ] Link persons to organizations
- [ ] Store organization_id in contact metadata
- [ ] Add configuration toggle: `sync_to_organization`

**Files:**
- `app/services/crm/krayin/processor_service.rb` (update)
- `app/services/crm/krayin/mappers/contact_mapper.rb` (update)

**Test Coverage:**
- Organization extraction from contact
- Organization creation
- Person-organization linking
- Organization updates

#### 4.2 External ID Management
- [ ] Implement multi-ID storage support
  - Override `get_external_id(contact, key)` method
  - Override `store_external_id(contact, id, key)` method
  - Support keys: `id`, `person_id`, `lead_id`, `organization_id`
- [ ] Add migration helpers if needed
- [ ] Add external ID indexes for performance

**Files:**
- `app/services/crm/krayin/processor_service.rb` (update)
- `db/migrate/YYYYMMDDHHMMSS_add_krayin_external_id_indexes.rb` (optional)

#### 4.3 Custom Attributes Setup
- [ ] Document custom attribute creation
- [ ] Create example script for custom attributes
- [ ] Add validation for custom attribute keys
- [ ] Document attribute mapping patterns

**Files:**
- `.kennis/krayin-custom-attributes.md` (new)

#### 4.4 Enhanced Error Handling
- [ ] Add retry logic for transient failures
- [ ] Implement exponential backoff for rate limits
- [ ] Add detailed error logging
- [ ] Implement error notification system
- [ ] Add error recovery patterns

**Files:**
- `app/services/crm/krayin/api/base_client.rb` (update)
- `app/services/crm/krayin/processor_service.rb` (update)

#### 4.5 Performance Optimization
- [ ] Add database indexes for external ID lookups
- [ ] Optimize API calls (batch where possible)
- [ ] Add caching for pipeline/stage lookups
- [ ] Optimize mapper operations
- [ ] Profile and optimize slow paths

**Files:**
- `db/migrate/YYYYMMDDHHMMSS_optimize_krayin_lookups.rb`

#### 4.6 Lead Stage Progression Logic
- [ ] Implement stage mapping configuration
- [ ] Add stage progression rules
- [ ] Handle stage transitions based on conversation status
- [ ] Add configuration for auto-qualify behavior
- [ ] Support custom stage mapping

**Files:**
- `app/services/crm/krayin/processor_service.rb` (update)
- `config/integration/apps.yml` (update)

#### 4.7 Activity Enhancement
- [ ] Support multiple activity types (call, meeting, chat)
- [ ] Add activity type detection from inbox type
- [ ] Support activity notes/comments from messages
- [ ] Add activity scheduling support
- [ ] Support activity location mapping

**Files:**
- `app/services/crm/krayin/mappers/conversation_mapper.rb` (update)
- `app/services/crm/krayin/mappers/message_mapper.rb` (update)

### Phase 4 Deliverables
- ✅ Organization sync working
- ✅ Enhanced error handling in place
- ✅ Performance optimized
- ✅ Advanced features documented
- ✅ Custom attributes guide created

### Phase 4 Exit Criteria
- [ ] All advanced features tested
- [ ] Performance benchmarks met
- [ ] Error handling verified
- [ ] Code review completed

---

## Phase 5: Documentation & Release

**Duration:** Week 5  
**Goal:** Complete documentation and prepare for release

### Tasks

#### 5.1 User Documentation (Wiki)
- [ ] Create main integration guide: "Krayin CRM Integration"
  - Overview and benefits
  - Prerequisites
  - Setup instructions
  - Configuration options
  - Field mappings
  - Troubleshooting
- [ ] Create setup tutorial with screenshots
- [ ] Create FAQ section
- [ ] Create video tutorial (optional)

**Wiki Pages:**
- `Krayin-CRM-Integration.md`
- `Krayin-Setup-Guide.md`
- `Krayin-Troubleshooting.md`
- `Krayin-FAQ.md`

#### 5.2 Developer Documentation
- [ ] Create architecture overview document
- [ ] Document API client usage
- [ ] Document mapper extension points
- [ ] Document event flow
- [ ] Create sequence diagrams
- [ ] Document testing strategies

**Files:**
- `.kennis/krayin-architecture.md`
- `.kennis/krayin-development-guide.md`
- `.kennis/krayin-testing-guide.md`

#### 5.3 Code Documentation
- [ ] Add RDoc comments to all public methods
- [ ] Add inline documentation for complex logic
- [ ] Document configuration options
- [ ] Add examples in comments

#### 5.4 Migration Guide
- [ ] Document upgrade path from no integration
- [ ] Document data migration strategies
- [ ] Create migration scripts if needed
- [ ] Document rollback procedures

**Files:**
- `.kennis/krayin-migration-guide.md`

#### 5.5 Testing Documentation
- [ ] Document test setup process
- [ ] Create test data fixtures
- [ ] Document VCR cassette usage
- [ ] Document manual testing checklist
- [ ] Create QA test plan

**Files:**
- `spec/fixtures/krayin/` (test data)
- `spec/cassettes/krayin/` (VCR recordings)
- `.kennis/krayin-test-plan.md`

#### 5.6 Release Preparation
- [ ] Update CHANGELOG.md
- [ ] Update version numbers
- [ ] Create release notes
- [ ] Prepare announcement
- [ ] Review all documentation
- [ ] Final code review
- [ ] Security review
- [ ] Performance review

#### 5.7 Demo & Training
- [ ] Create demo environment
- [ ] Prepare demo script
- [ ] Record demo video
- [ ] Create training materials
- [ ] Conduct team training session

### Phase 5 Deliverables
- ✅ Complete user documentation
- ✅ Complete developer documentation
- ✅ Migration guide ready
- ✅ Release notes prepared
- ✅ Demo environment ready

### Phase 5 Exit Criteria
- [ ] All documentation reviewed and approved
- [ ] Demo successful
- [ ] Team trained
- [ ] Ready for beta release

---

## Success Criteria

### Technical Metrics
- [ ] API success rate > 99%
- [ ] Average sync time < 2 seconds
- [ ] Error rate < 1%
- [ ] Test coverage > 85%
- [ ] All RuboCop checks passing
- [ ] No N+1 queries
- [ ] All specs passing

### Functional Requirements
- [ ] Contact → Person sync working
- [ ] Contact → Lead sync working
- [ ] Conversation → Activity sync working
- [ ] Lead stage progression working
- [ ] Organization sync working (optional)
- [ ] Custom attributes mappable
- [ ] Error handling graceful
- [ ] Concurrent operations safe

### Quality Standards
- [ ] Code follows Ruby style guide
- [ ] All public methods documented
- [ ] No security vulnerabilities
- [ ] Performance benchmarks met
- [ ] Accessibility standards met
- [ ] I18n complete for all strings

### Documentation Standards
- [ ] User guide complete
- [ ] Developer guide complete
- [ ] API documentation complete
- [ ] Troubleshooting guide complete
- [ ] FAQ comprehensive

---

## Risk Mitigation

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Krayin API incomplete/undocumented | High | Medium | Early API exploration, fallback to direct DB access if needed |
| API rate limiting | Medium | Low | Implement backoff, queue management |
| Data sync conflicts | High | Medium | Mutex locks, idempotency keys |
| Person-Lead relationship complexity | Medium | Medium | Clear mapping logic, comprehensive tests |
| Authentication token expiry | Medium | Low | Token refresh logic, error handling |

### Business Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Poor user adoption | Medium | Low | Clear documentation, demo videos |
| Complex setup process | Medium | Medium | Simplified configuration, setup wizard |
| Data privacy concerns | High | Low | Document data handling, provide controls |
| Integration breaks on Krayin updates | Medium | Medium | Version documentation, test suite |

### Critical Prerequisites

**⚠️ IMPORTANT: The Krayin REST API package must be installed on the target Krayin instance:**
- Package: `krayin/rest-api`
- Installation: `composer require krayin/rest-api`  
- Setup: `php artisan krayin-rest-api:install`
- Verification: Check `/api/admin/documentation` is accessible
- This is a HARD REQUIREMENT - integration will not work without it

### Mitigation Actions

1. **REST API Package:**
   - Document as prerequisite in all setup guides
   - Add setup service check to verify API accessibility
   - Provide installation instructions for clients
   - Test against demo instance first

2. **API Documentation Gaps:**
   - Explore Krayin codebase directly
   - Check Laravel routes: `php artisan route:list`
   - Review RestAPI package controllers
   - Create custom endpoints if needed

2. **Testing Challenges:**
   - Set up dedicated Krayin test instance
   - Use VCR for API mocking
   - Create comprehensive fixtures
   - Test with real data scenarios

3. **Performance Issues:**
   - Add database indexes early
   - Profile API calls frequently
   - Implement caching strategically
   - Monitor job queue performance

4. **User Experience:**
   - Beta test with friendly users
   - Gather feedback early and often
   - Iterate on configuration UI
   - Provide migration support

---

## Implementation Checklist

### Pre-Implementation
- [ ] Review and approve this plan
- [ ] Set up Krayin development instance
- [ ] Create feature branch
- [ ] Set up project board/tracker
- [ ] Assign team members

### Phase 1
- [ ] All API clients implemented
- [ ] All client specs passing
- [ ] Manual API testing completed
- [ ] Phase 1 review completed

### Phase 2
- [ ] All mappers implemented
- [ ] All services implemented
- [ ] All specs passing
- [ ] Phase 2 review completed

### Phase 3
- [ ] Event integration complete
- [ ] Integration tests passing
- [ ] E2E testing completed
- [ ] Phase 3 review completed

### Phase 4
- [ ] Advanced features implemented
- [ ] Performance optimized
- [ ] All features tested
- [ ] Phase 4 review completed

### Phase 5
- [ ] All documentation complete
- [ ] Demo prepared
- [ ] Release notes ready
- [ ] Ready for beta launch

### Post-Implementation
- [ ] Beta testing phase (1 week)
- [ ] Gather feedback
- [ ] Address critical issues
- [ ] General availability release
- [ ] Monitor adoption and issues

---

## Notes

### Key Differences from GLPI
- **Authentication:** Bearer token (Laravel Sanctum) vs. session-based (GLPI)
- **Data Model:** Dual entity (Person + Lead) vs. single entity
- **Focus:** Sales/CRM workflow vs. IT service management
- **Complexity:** Moderate vs. High (due to GLPI session management)
- **API Package:** Requires separate `krayin/rest-api` package installation
- **API Prefix:** All endpoints under `/api/admin/*` not just `/admin/*`
- **Documentation:** Auto-generated L5-Swagger docs at `/api/admin/documentation`

### Important API Discoveries
1. **REST API Package Required:**
   - Krayin core does NOT include REST API by default
   - Must install `krayin/rest-api` package separately
   - Customer/client must have this installed for integration to work

2. **Data Structure Specifics:**
   - Emails and phone numbers are stored as **arrays**, not strings
   - Person `emails` field is required and must be unique
   - Lead requires multiple IDs: `lead_source_id`, `lead_type_id`, `lead_pipeline_id`, `lead_pipeline_stage_id`
   - Activities use many-to-many relationships through pivot tables

3. **Activity Types:**
   - Supported: `note`, `call`, `meeting`, `lunch`, `file`, `email`, `system`
   - Different required fields based on type
   - `note` type best for conversation sync (only requires `comment`)

4. **Authentication:**
   - Uses Laravel Sanctum `HasApiTokens` trait
   - Bearer token in Authorization header
   - Token must be generated per user in Krayin

5. **Version Compatibility:**
   - Krayin v2.1.x introduces new features: IMAP integration, Events & Campaigns, Magic AI Lead Creation
   - REST API package v2.1.1 is compatible with Krayin v2.1.x
   - Mobile-responsive design available in v2.1+
   - Bulk upload support for data migration

### Learning from GLPI Implementation
- Start with solid API foundation
- Implement comprehensive error handling early
- Use finder services pattern (worked well)
- Add mutex locks from the beginning
- Test concurrency scenarios thoroughly

### Success Dependencies
1. Krayin instance accessibility
2. API endpoint availability
3. Clear API documentation or exploratory access
4. Team availability for reviews
5. Test environment stability

---

**Document Status:** Ready for Review  
**Next Step:** Review plan and approve to begin Phase 1  
**Estimated Start Date:** TBD  
**Estimated Completion Date:** 4-5 weeks from start
