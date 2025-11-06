# GLPI Integration - Branch Strategy

## Overview

This document outlines the branch strategy for implementing the GLPI CRM integration following the plan in `glpi-integration-implementation-plan.md`.

## Branch Structure

All branches follow the naming convention: `feature/glpi-phase{N}-{description}`

### Phase 1: Foundation & API Clients
**Branch**: `feature/glpi-phase1-api-clients`

**Purpose**: Core HTTP client and API clients for GLPI resources

**Deliverables**:
- `app/services/crm/glpi/api/base_client.rb` - Core HTTP client with session management
- `app/services/crm/glpi/api/user_client.rb` - CRUD operations for GLPI Users
- `app/services/crm/glpi/api/contact_client.rb` - CRUD operations for GLPI Contacts
- `app/services/crm/glpi/api/ticket_client.rb` - CRUD operations for GLPI Tickets
- `app/services/crm/glpi/api/followup_client.rb` - CRUD operations for GLPI ITILFollowup
- Complete test coverage for all API clients

**Dependencies**: None

**Merge Target**: main (after code review)

---

### Phase 2: Data Mappers
**Branch**: `feature/glpi-phase2-mappers`

**Purpose**: Transform Chatwoot models to GLPI API formats

**Deliverables**:
- `app/services/crm/glpi/mappers/contact_mapper.rb` - Contact → User/Contact mapping
- `app/services/crm/glpi/mappers/conversation_mapper.rb` - Conversation → Ticket mapping
- `app/services/crm/glpi/mappers/message_mapper.rb` - Message → ITILFollowup mapping
- Complete test coverage for all mappers

**Dependencies**: Phase 1 (needs API client structure for context)

**Merge Target**: feature/glpi-phase1-api-clients (or main if Phase 1 is merged)

---

### Phase 3: Core Services
**Branch**: `feature/glpi-phase3-services`

**Purpose**: Business logic services for integration

**Deliverables**:
- `app/services/crm/glpi/setup_service.rb` - One-time setup/validation
- `app/services/crm/glpi/user_finder_service.rb` - Find/create GLPI Users
- `app/services/crm/glpi/contact_finder_service.rb` - Find/create GLPI Contacts
- `app/services/crm/glpi/processor_service.rb` - Main event handler
- Complete test coverage for all services

**Dependencies**: Phase 1 & Phase 2 (uses API clients and mappers)

**Merge Target**: main (after Phase 1 & 2 are merged)

---

### Phase 4: Configuration & Integration
**Branch**: `feature/glpi-phase4-integration`

**Purpose**: Wire up integration to Chatwoot core

**Deliverables**:
- `config/integration/apps.yml` - Add GLPI configuration
- `config/locales/en.yml` - Add i18n strings
- `app/models/integrations/hook.rb` - Add GLPI to crm_integration?
- `app/listeners/hook_listener.rb` - Add GLPI event mapping
- `app/jobs/hook_job.rb` - Add GLPI processing
- `app/jobs/crm/setup_job.rb` - Add GLPI setup case
- `public/integrations/glpi.png` - Add logo

**Dependencies**: Phase 3 (services must exist)

**Merge Target**: main (after Phase 3 is merged)

---

### Phase 5: Testing & Refinement
**Branch**: `feature/glpi-phase5-testing`

**Purpose**: Comprehensive testing and bug fixes

**Deliverables**:
- Integration tests with local GLPI instance
- Performance testing results
- Edge case handling
- Bug fixes from testing phase
- Test coverage report (>90%)

**Dependencies**: Phase 4 (full integration must be in place)

**Merge Target**: main (after Phase 4 is merged and testing complete)

---

### Phase 6: Documentation & Deployment
**Branch**: `feature/glpi-phase6-documentation`

**Purpose**: User and developer documentation

**Deliverables**:
- `docs/glpi-integration.md` - User-facing documentation
- `docs/development/crm-integrations/glpi.md` - Developer documentation
- YARD comments on all public methods
- Deployment checklist completion

**Dependencies**: Phase 5 (implementation must be complete)

**Merge Target**: main (after Phase 5 is merged)

---

## Workflow

### Sequential Development

Phases should be developed sequentially due to dependencies:

```
Phase 1 (API Clients)
    ↓
Phase 2 (Mappers)
    ↓
Phase 3 (Services)
    ↓
Phase 4 (Integration)
    ↓
Phase 5 (Testing)
    ↓
Phase 6 (Documentation)
```

### Merge Strategy

**Option A: Linear Merges (Recommended for first iteration)**
```bash
# Phase 1
git checkout feature/glpi-phase1-api-clients
# ... implement and test ...
git checkout main
git merge feature/glpi-phase1-api-clients

# Phase 2
git checkout feature/glpi-phase2-mappers
git merge main  # Get Phase 1 changes
# ... implement and test ...
git checkout main
git merge feature/glpi-phase2-mappers

# Continue pattern for remaining phases
```

**Option B: Stacked Branches (For parallel review)**
```bash
# Phase 1
git checkout feature/glpi-phase1-api-clients
# ... implement ...

# Phase 2 (based on Phase 1)
git checkout -b feature/glpi-phase2-mappers feature/glpi-phase1-api-clients
# ... implement ...

# Phase 3 (based on Phase 2)
git checkout -b feature/glpi-phase3-services feature/glpi-phase2-mappers
# ... implement ...

# Merge in order: 1 → 2 → 3 → 4 → 5 → 6
```

### Code Review Checkpoints

Each phase should have a code review before merging:

1. **Phase 1 Review**: API client architecture, session management, error handling
2. **Phase 2 Review**: Data mapping logic, field transformations
3. **Phase 3 Review**: Service patterns, business logic, finder services
4. **Phase 4 Review**: Integration points, configuration correctness
5. **Phase 5 Review**: Test results, performance metrics, edge cases
6. **Phase 6 Review**: Documentation completeness, clarity

---

## Branch Maintenance

### Keep Branches Updated

```bash
# Update branch with latest main
git checkout feature/glpi-phase{N}-{description}
git merge main

# Or rebase if preferred (no merge commits)
git checkout feature/glpi-phase{N}-{description}
git rebase main
```

### Delete After Merge

```bash
# After successful merge to main
git branch -d feature/glpi-phase{N}-{description}
git push origin --delete feature/glpi-phase{N}-{description}
```

---

## Commit Message Convention

Follow semantic commits for better changelog generation:

```
feat(glpi): add BaseClient with session management
fix(glpi): handle session expiration in API client
test(glpi): add unit tests for UserClient
refactor(glpi): simplify ContactMapper name splitting
docs(glpi): add YARD comments to ProcessorService
```

### Scope Tags
- `glpi-api`: API client changes
- `glpi-mapper`: Mapper changes
- `glpi-service`: Service changes
- `glpi-integration`: Integration wiring
- `glpi-test`: Testing changes
- `glpi-docs`: Documentation

---

## Pull Request Template

When creating PRs for each phase:

```markdown
## Phase X: [Description]

### Summary
Brief description of what this phase implements.

### Implementation Details
- Component 1
- Component 2
- Component 3

### Testing
- [ ] Unit tests passing (>90% coverage)
- [ ] Manual testing completed
- [ ] Edge cases covered

### Dependencies
- Phase X-1 must be merged first (if applicable)

### Checklist
- [ ] Code follows Chatwoot style guide
- [ ] RuboCop passes
- [ ] All tests passing
- [ ] Documentation updated
- [ ] No breaking changes to existing integrations

### Related
- Implementation Plan: `.kennis/glpi-integration-implementation-plan.md`
- Previous Phase: [Link if applicable]
```

---

## Feature Flags

The integration uses the existing `crm_integration` feature flag:

```ruby
# To enable during development
Account.find_by(id: YOUR_ACCOUNT_ID).enable_features('crm_integration')

# To disable
Account.find_by(id: YOUR_ACCOUNT_ID).disable_features('crm_integration')
```

---

## Rollback Strategy

If a phase needs to be rolled back:

```bash
# Revert the merge commit
git revert -m 1 <merge-commit-sha>

# Or reset to before merge (if not pushed)
git reset --hard <commit-before-merge>
```

---

## Timeline

Based on the implementation plan:

- **Phase 1**: Days 1-5 (Week 1)
- **Phase 2**: Days 1-5 (Week 2)
- **Phase 3**: Days 1-5 (Week 2-3)
- **Phase 4**: Days 1-2 (Week 3)
- **Phase 5**: Days 3-4 (Week 3)
- **Phase 6**: Day 5 (Week 3)

Total: ~3 weeks for full implementation

---

## Quick Reference

### Check Current Phase Branch
```bash
git branch --show-current
```

### List All GLPI Branches
```bash
git branch | grep glpi
```

### Switch to Phase Branch
```bash
git checkout feature/glpi-phase1-api-clients
git checkout feature/glpi-phase2-mappers
git checkout feature/glpi-phase3-services
git checkout feature/glpi-phase4-integration
git checkout feature/glpi-phase5-testing
git checkout feature/glpi-phase6-documentation
```

### Create PR from CLI (using gh)
```bash
gh pr create --base main --head feature/glpi-phase1-api-clients \
  --title "feat(glpi): Phase 1 - API Clients" \
  --body "Implementation of GLPI API clients with session management"
```

---

**Version**: 1.0
**Last Updated**: 2025-01-05
**Author**: Claude Code
**Related**: `glpi-integration-implementation-plan.md`
