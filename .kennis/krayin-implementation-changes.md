# Krayin Implementation Plan - Key Changes from Research

**Date:** 2025-01-06  
**Status:** Updated based on DeepWiki and official documentation research  
**Target Krayin Version:** v2.1.5+ (January 2025)  
**REST API Package:** v2.1.1+ (September 2025)

---

## Critical Discovery: REST API Package Requirement

### Finding
Krayin CRM **does not include REST API functionality by default**. A separate package must be installed:

```bash
composer require krayin/rest-api
php artisan krayin-rest-api:install
```

### Impact
- **CRITICAL PREREQUISITE:** Clients must have `krayin/rest-api` package installed
- Integration will **completely fail** without this package
- Must be documented prominently in all setup guides
- Setup service should verify API accessibility during initialization

### Version Information
- **Krayin Core:** v2.1.5 (latest stable, released September 19, 2025)
- **REST API Package:** v2.1.1 (latest, released September 1, 2025)
- **Minimum Version:** Krayin v2.0.0
- **Laravel Version:** Based on Laravel 11.x

### New Features in Krayin 2.1
- IMAP Account Settings for email sync
- Events & Campaigns for marketing
- Magic AI Lead Creation (PDF/image extraction)
- Mobile-responsive design
- Bulk Upload (CSV, XLS, XLSX)
- Brazilian Portuguese language support

### Configuration Required
```bash
SANCTUM_STATEFUL_DOMAINS="${APP_URL}"
L5_SWAGGER_UI_PERSIST_AUTHORIZATION=true
```

---

## API Structure Changes

### Original Assumption vs. Reality

| Aspect | Original Plan | Actual Implementation |
|--------|--------------|----------------------|
| API Endpoints | Assumed `/admin/*` | Actually `/api/admin/*` |
| API Package | Assumed built-in | Requires separate `krayin/rest-api` package |
| Documentation | Unknown | L5-Swagger at `/api/admin/documentation` |
| Authentication | Generic token | Laravel Sanctum Bearer tokens |

---

## Data Format Requirements

### Email and Phone Numbers
**CRITICAL:** Krayin stores emails and phones as **arrays**, not strings:

```json
{
  "name": "John Doe",
  "emails": [
    {"value": "john@example.com", "label": "work"}
  ],
  "contact_numbers": [
    {"value": "+1234567890", "label": "work"}
  ]
}
```

**Mapper must convert:**
- Chatwoot `email` (string) → Krayin `emails` (array of objects)
- Chatwoot `phone_number` (string) → Krayin `contact_numbers` (array of objects)

---

## Lead Creation Requirements

### Required Fields for Lead

The original plan underestimated the required fields. Leads require:

**Required:**
- `title` - Lead title
- `lead_value` - Monetary value (numeric, required)
- `lead_source_id` - Source ID (required)
- `lead_type_id` - Type ID (required)  
- `lead_pipeline_id` - Pipeline ID (required)
- `lead_pipeline_stage_id` - Stage ID (required)

**Optional but Important:**
- `person_id` - Link to person (nullable)
- `description` - Lead description
- `expected_close_date` - Expected closing date

### Implications
- Setup service **must** fetch and store default IDs for:
  - Lead source
  - Lead type
  - Pipeline
  - Initial stage
- Cannot create leads without these reference IDs

---

## Activity Entity Details

### Activity Types Supported
- `note` - Text notes (simplest, best for conversation sync)
- `call` - Phone call records
- `meeting` - Meeting records
- `lunch` - Lunch appointments
- `file` - File attachments
- `email` - Email communications
- `system` - Automatic change logs

### Required Fields by Type

**For `note` type (recommended for conversations):**
- `type`: "note"
- `comment`: The note content

**For `call`, `meeting`, `lunch` types:**
- `type`: activity type
- `title`: Activity title
- `schedule_from`: Start datetime
- `schedule_to`: End datetime

### Activity Relationships
Activities use **many-to-many** relationships:
- `lead_activities` pivot table for lead associations
- `person_activities` pivot table for person associations

---

## API Client Implementation Changes

### Base URL Structure
```ruby
# Original plan
@api_url = "https://crm.example.com"

# Corrected implementation
@api_url = "https://crm.example.com/api/admin"
```

### Authentication Headers
```ruby
{
  'Content-Type' => 'application/json',
  'Accept' => 'application/json',
  'Authorization' => "Bearer #{@api_token}"  # Laravel Sanctum format
}
```

### No Session Management Needed
Unlike GLPI, Krayin uses stateless Bearer tokens:
- No `init_session` / `kill_session` methods needed
- Simpler client implementation
- Each request includes Bearer token in header

---

## Updated Phase 1 Tasks

### Additional Tasks Required

1. **Environment Setup:**
   - ✅ Document REST API package requirement
   - ✅ Provide installation instructions
   - ✅ Add verification step in setup service

2. **Base Client:**
   - ✅ Update base URL to include `/api/admin` prefix
   - ✅ Implement Bearer token authentication
   - ✅ Remove session management (not needed)

3. **Person Client:**
   - ✅ Handle array format for emails
   - ✅ Handle array format for contact_numbers
   - ✅ Convert single values to array format

4. **Lead Client:**
   - ✅ Add methods to fetch lead sources, types, pipelines, stages
   - ✅ Store reference IDs during setup
   - ✅ Handle all required fields in lead creation

5. **Activity Client:**
   - ✅ Support activity type selection
   - ✅ Use `note` type as default for conversations
   - ✅ Handle many-to-many pivot relationships

---

## Risk Assessment Updates

### New High-Priority Risk

**Risk:** Client Krayin instance does not have REST API package installed  
**Impact:** Critical - Integration completely non-functional  
**Probability:** High - Package not installed by default  
**Mitigation:**
1. Document as hard prerequisite in setup guide
2. Add automated check in setup service
3. Provide clear error message with installation instructions
4. Test against demo instance first

### Reduced Risks

**API Documentation:** Lower risk than expected
- L5-Swagger provides interactive API docs
- Official demo available for testing
- GitHub repository has examples

---

## Implementation Plan Updates Summary

### Modified Sections
1. ✅ Prerequisites section added with REST API package requirement
2. ✅ Technical Approach updated with correct API structure
3. ✅ Phase 1 Environment Setup expanded with installation steps
4. ✅ Base Client updated for Bearer token auth
5. ✅ Person Client updated for array format handling
6. ✅ Lead Client updated with required fields
7. ✅ Activity Client updated with type-specific requirements
8. ✅ Risk Mitigation updated with API package risk
9. ✅ Key Differences section updated with findings
10. ✅ Important API Discoveries section added

### Timeline Impact
- **No change to overall timeline**
- REST API package installation adds ~15 minutes to setup
- Simpler authentication (no session management) saves development time
- Array format handling adds minimal complexity to mappers

---

## Testing Implications

### Additional Test Cases Required

1. **API Package Verification:**
   - Test setup service behavior when API package missing
   - Test error message clarity
   - Test API endpoint accessibility check

2. **Data Format Conversion:**
   - Test email string → emails array conversion
   - Test phone string → contact_numbers array conversion
   - Test empty/nil handling for optional fields

3. **Lead Creation:**
   - Test with all required IDs
   - Test with missing required IDs (should fail gracefully)
   - Test pipeline/stage fetching during setup

4. **Activity Types:**
   - Test note creation (simplest path)
   - Test type-specific field requirements
   - Test pivot table relationships

---

## Documentation Updates Required

### User Documentation
1. ✅ Add REST API package as prerequisite
2. ✅ Provide installation command
3. Add troubleshooting for "API not accessible" error
4. Document Sanctum token generation

### Developer Documentation  
1. Document array format for emails/phones
2. Document lead required fields and reference IDs
3. Document activity type selection logic
4. Add sequence diagram for setup service checks

### Setup Guide
1. REST API package installation steps
2. Sanctum configuration steps
3. API token generation for test user
4. Verification steps for API accessibility

---

## Next Steps

1. ✅ Implementation plan updated with all findings
2. ⏭️ Begin Phase 1 implementation with updated requirements
3. ⏭️ Test against official Krayin demo instance
4. ⏭️ Create setup verification script
5. ⏭️ Document array format handling patterns

---

## References

- **Krayin REST API Repository:** https://github.com/krayin/rest-api
- **Developer Documentation:** https://devdocs.krayincrm.com/1.x/api/
- **API Documentation:** https://apidoc.krayincrm.com/api/documentation
- **Official Demo:** https://demo.krayincrm.com/krayin-rest-api/
- **DeepWiki Analysis:** https://deepwiki.com/search/krayin

---

**Review Status:** ✅ Complete  
**Implementation Plan Status:** ✅ Updated  
**Ready for Phase 1:** ✅ Yes
