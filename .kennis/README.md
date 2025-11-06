# Kennis Development Documentation

This directory contains technical documentation, implementation plans, and status reports for the Kennis fork of Chatwoot.

---

## 📋 Quick Links

### GitHub Actions & CI/CD Status
🎉 **All workflows passing!** [View Action Plan](./github-actions-action-plan.md)

### Integration Projects
- 🔧 [GLPI Integration](#glpi-integration-implementation)
- 🔑 [Keycloak Integration](#keycloak-integration)
- 💼 [Krayin CRM Integration](#krayin-crm-integration)

---

## 🚦 GitHub Actions Status

**Current Status**: ✅ ALL PASSING (as of 2025-11-06)

| Document | Purpose |
|----------|---------|
| [📋 Action Plan](./github-actions-action-plan.md) | **START HERE** - Quick reference & next steps |
| [📊 Status Report](./github-actions-status-2025-11-06.md) | Detailed analysis & recommendations |
| [🔧 Fix Plan](./github-actions-fix-plan.md) | Historical: omniauth dependency fix |

**Quick Check**:
```bash
gh run list --limit 10
```

---

## 🔧 GLPI Integration Implementation

This directory contains the complete implementation plan and branch strategy for the GLPI CRM integration.

## 📋 Documents

1. **glpi-integration-implementation-plan.md** (1,817 lines)
   - Complete technical specification
   - 6 implementation phases
   - Detailed code examples
   - Testing strategies
   - Timeline and dependencies

2. **glpi-branch-strategy.md**
   - Branch structure and naming conventions
   - Merge strategies and workflow
   - Code review checkpoints
   - Commit message conventions
   - Rollback procedures

3. **glpi-quick-start.md**
   - Getting started guide
   - Phase-by-phase instructions
   - Common commands reference
   - Troubleshooting tips

4. **glpi-branch-overview.txt**
   - Visual branch structure
   - Timeline overview
   - Quick command reference

## 🌳 Branch Status

All branches are created and ready:

| Branch | Status | Duration | Dependencies |
|--------|--------|----------|--------------|
| `feature/glpi-phase1-api-clients` | ✅ Ready | Week 1 | None |
| `feature/glpi-phase2-mappers` | ⏭️ Next | Week 2 (1-2) | Phase 1 |
| `feature/glpi-phase3-services` | ⏭️ Queued | Week 2-3 (3-5) | Phase 1 & 2 |
| `feature/glpi-phase4-integration` | ⏭️ Queued | Week 3 (1-2) | Phase 3 |
| `feature/glpi-phase5-testing` | ⏭️ Queued | Week 3 (3-4) | Phase 4 |
| `feature/glpi-phase6-documentation` | ⏭️ Queued | Week 3 (5) | Phase 5 |

## 🚀 Quick Start

```bash
# Start Phase 1 implementation
git checkout feature/glpi-phase1-api-clients

# View all GLPI branches
git branch | grep glpi

# Read the implementation plan
cat .kennis/glpi-integration-implementation-plan.md

# Read quick start guide
cat .kennis/glpi-quick-start.md
```

## 📚 Phase Overview

### Phase 1: API Clients (Week 1)
Foundation layer with HTTP client and resource clients for GLPI API.

**Deliverables:**
- BaseClient with session management
- UserClient, ContactClient, TicketClient, FollowupClient
- Complete test coverage

### Phase 2: Mappers (Week 2, Days 1-2)
Data transformation layer between Chatwoot and GLPI.

**Deliverables:**
- ContactMapper (Chatwoot → GLPI User/Contact)
- ConversationMapper (Chatwoot → GLPI Ticket)
- MessageMapper (Chatwoot → GLPI ITILFollowup)

### Phase 3: Services (Week 2-3, Days 3-5)
Business logic layer for integration.

**Deliverables:**
- SetupService (validation, initialization)
- UserFinderService, ContactFinderService
- ProcessorService (main event handler)

### Phase 4: Integration (Week 3, Days 1-2)
Wire integration into Chatwoot core.

**Deliverables:**
- Configuration files (apps.yml, en.yml)
- Model, listener, and job updates
- GLPI logo

### Phase 5: Testing (Week 3, Days 3-4)
Comprehensive testing and bug fixes.

**Deliverables:**
- Integration tests with local GLPI
- Performance tests
- Edge case handling

### Phase 6: Documentation (Week 3, Day 5)
User and developer documentation.

**Deliverables:**
- User documentation
- Developer documentation
- YARD comments

## 🎯 Success Criteria

- ✅ Contact sync creates/updates GLPI Users or Contacts
- ✅ Email/phone matching prevents duplicates
- ✅ Conversation creation generates GLPI Tickets
- ✅ Messages sync as ITILFollowups (when enabled)
- ✅ Conversation resolution updates ticket status to Solved
- ✅ No race conditions (mutex locks working)
- ✅ Session management reliable (no token leaks)
- ✅ Proper error handling and logging
- ✅ Test coverage > 90%
- ✅ User documentation complete
- ✅ Successfully tested with real GLPI instance

## 📖 Key References

- **GLPI API Documentation**: https://glpi-project.org/documentation/
- **LeadSquared Reference**: `app/services/crm/leadsquared/`
- **Base Processor Service**: `app/services/crm/base_processor_service.rb`
- **Hook Model**: `app/models/integrations/hook.rb`
- **Integration Apps Config**: `config/integration/apps.yml`

## 🔧 Development Setup

```bash
# Install dependencies
bundle install

# Ensure Redis is running (for mutex locks)
redis-cli ping

# Run development server
overmind start -f Procfile.dev

# Run tests
bundle exec rspec spec/services/crm/glpi/

# Run linter
bundle exec rubocop app/services/crm/glpi/
```

## 🐳 Local GLPI for Testing

```bash
# Start GLPI container
docker run -d --name glpi \
  -p 8080:80 \
  -e GLPI_INSTALL=true \
  diouxx/glpi:latest

# Access: http://localhost:8080
# Default credentials: glpi/glpi
```

## 📝 Commit Convention

```bash
# Format
git commit -m "feat(glpi-{scope}): {description}"

# Examples
git commit -m "feat(glpi-api): add BaseClient with session management"
git commit -m "test(glpi-api): add unit tests for UserClient"
git commit -m "fix(glpi-mapper): handle null phone numbers"
git commit -m "docs(glpi): add user documentation"
```

## 🔄 Workflow

1. Checkout phase branch
2. Implement features
3. Write tests (>90% coverage)
4. Run linter (RuboCop)
5. Create PR
6. Code review
7. Merge to main
8. Move to next phase

## 📊 Timeline

**Total Duration**: 3 weeks (~15 working days)

- Week 1: Phase 1 (Foundation)
- Week 2: Phases 2-3 (Mappers & Services)
- Week 3: Phases 4-6 (Integration, Testing, Documentation)

## 🎉 Current Status

✅ **All branches created and ready for implementation!**

**Next Step**: Start Phase 1 implementation
```bash
git checkout feature/glpi-phase1-api-clients
```

---

## 🔑 Keycloak Integration

Single Sign-On (SSO) integration with Keycloak for enterprise authentication.

### 📋 Documents

1. **keycloak-setup-guide.md**
   - Complete setup and configuration
   - Environment variable configuration
   - Troubleshooting guide

### 🚀 Quick Start

```bash
# View setup guide
cat .kennis/keycloak-setup-guide.md

# Example environment configuration
cat .kennis/keycloak-env-example.txt
```

---

## 💼 Krayin CRM Integration

CRM integration with Krayin for contact and lead management.

### 📋 Documents

1. **krayin-implementation-plan.md** - Complete implementation plan
2. **krayin-architecture.md** - Technical architecture
3. **krayin-development-guide.md** - Developer guide
4. **krayin-testing-guide.md** - Testing strategies
5. **krayin-custom-attributes.md** - Custom attribute mapping
6. **krayin-version-info.md** - Version information

### 📊 Phase Status

| Phase | Status | Document |
|-------|--------|----------|
| Phase 1 | ✅ Complete | [phase1-completion-summary.md](./phase1-completion-summary.md) |
| Phase 2 | ✅ Complete | [phase2-completion-summary.md](./phase2-completion-summary.md) |
| Phase 3 | ✅ Complete | [phase3-completion-summary.md](./phase3-completion-summary.md) |
| Phase 4 | ✅ Complete | [phase4-completion-summary.md](./phase4-completion-summary.md) |
| Phase 5 | ✅ Complete | [phase5-completion-summary.md](./phase5-completion-summary.md) |
| Phase 6 | ✅ Complete | [phase6-completion-summary.md](./phase6-completion-summary.md) |

### 🚀 Quick Start

```bash
# View implementation plan
cat .kennis/krayin-implementation-plan.md

# View architecture
cat .kennis/krayin-architecture.md

# Development guide
cat .kennis/krayin-development-guide.md
```

---

## 📚 General Resources

### CRM Integration Overview

**Overview Document**: [crm-integration-implementation-plan.md](./crm-integration-implementation-plan.md)

This document provides a comprehensive overview of all CRM integrations, including:
- Architecture patterns
- Integration strategies
- Common components
- Best practices

---

## 🔧 Development Conventions

### File Naming
- `*-plan.md` - Implementation or fix plans
- `*-status*.md` - Status reports and analyses
- `*-action-plan.md` - Quick reference with next steps
- `*-guide.md` - Setup, developer, or user guides
- `*-summary.md` - Phase or completion summaries

### Status Indicators
- ✅ Working / Completed
- ⚠️ Warning / Non-critical issue
- ❌ Error / Requires action
- 🔇 Disabled / Not in use
- 📋 Planned / TODO
- ⏭️ Queued / Next

### Priority Levels
- **Critical**: Immediate action required
- **High**: Action needed within 1 week
- **Medium**: Action needed within 1 month
- **Low**: Optional improvement

---

## 📖 Contributing

When adding new documentation:
1. Use descriptive filenames
2. Include date in filename if time-sensitive
3. Update this README index
4. Use consistent markdown formatting
5. Add status indicators (✅ ⚠️ ❌)

---

**Version**: 2.0
**Created**: 2025-01-05
**Updated**: 2025-11-06
**Status**: Active Development
