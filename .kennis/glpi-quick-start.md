# GLPI Integration - Quick Start Guide

## Branch Overview

All branches are created and ready for implementation:

1. ✅ `feature/glpi-phase1-api-clients` - API Clients & Session Management
2. ✅ `feature/glpi-phase2-mappers` - Data Mappers
3. ✅ `feature/glpi-phase3-services` - Core Services
4. ✅ `feature/glpi-phase4-integration` - Configuration & Wiring
5. ✅ `feature/glpi-phase5-testing` - Testing & Refinement
6. ✅ `feature/glpi-phase6-documentation` - Documentation

---

## Getting Started

### Phase 1: API Clients (Current Phase)

```bash
# Switch to Phase 1 branch
git checkout feature/glpi-phase1-api-clients

# Ensure clean state
git status

# Start implementation
# See detailed plan in: .kennis/glpi-integration-implementation-plan.md (lines 29-294)
```

**What to implement:**
1. `app/services/crm/glpi/api/base_client.rb` - Session management, HTTP methods
2. `app/services/crm/glpi/api/user_client.rb` - User CRUD operations
3. `app/services/crm/glpi/api/contact_client.rb` - Contact CRUD operations
4. `app/services/crm/glpi/api/ticket_client.rb` - Ticket CRUD operations
5. `app/services/crm/glpi/api/followup_client.rb` - Followup CRUD operations
6. Complete test suite for all clients

**Testing:**
```bash
# Run tests for Phase 1
bundle exec rspec spec/services/crm/glpi/api/

# Check coverage
open coverage/index.html
```

**Commit Convention:**
```bash
git add app/services/crm/glpi/api/base_client.rb
git commit -m "feat(glpi-api): add BaseClient with session management

- Initialize session with app_token and user_token
- Implement with_session wrapper for automatic cleanup
- Add GET/POST/PUT methods with proper headers
- Handle HTTP status codes and GLPI errors
- Add ApiError exception class"

git add spec/services/crm/glpi/api/base_client_spec.rb
git commit -m "test(glpi-api): add comprehensive tests for BaseClient

- Test session initialization success/failure
- Test session cleanup in ensure block
- Test with_session wrapper behavior
- Test error handling for all status codes
- Mock GLPI API with WebMock"
```

**When Phase 1 is complete:**
```bash
# Ensure all tests pass
bundle exec rspec spec/services/crm/glpi/api/
bundle exec rubocop app/services/crm/glpi/api/

# Create PR
gh pr create --base main --head feature/glpi-phase1-api-clients \
  --title "feat(glpi): Phase 1 - API Clients" \
  --body-file .kennis/pr-templates/phase1-template.md
```

---

### Phase 2: Mappers

```bash
# After Phase 1 is merged or for parallel work
git checkout feature/glpi-phase2-mappers
git merge main  # Get latest changes

# Start implementation
# See detailed plan in: .kennis/glpi-integration-implementation-plan.md (lines 296-528)
```

**What to implement:**
1. `app/services/crm/glpi/mappers/contact_mapper.rb`
2. `app/services/crm/glpi/mappers/conversation_mapper.rb`
3. `app/services/crm/glpi/mappers/message_mapper.rb`
4. Complete test suite

---

### Phase 3: Services

```bash
git checkout feature/glpi-phase3-services
git merge main

# See detailed plan in: .kennis/glpi-integration-implementation-plan.md (lines 531-904)
```

**What to implement:**
1. `app/services/crm/glpi/setup_service.rb`
2. `app/services/crm/glpi/user_finder_service.rb`
3. `app/services/crm/glpi/contact_finder_service.rb`
4. `app/services/crm/glpi/processor_service.rb`
5. Complete test suite

---

### Phase 4: Integration

```bash
git checkout feature/glpi-phase4-integration
git merge main

# See detailed plan in: .kennis/glpi-integration-implementation-plan.md (lines 907-1177)
```

**What to implement:**
1. Update `config/integration/apps.yml`
2. Update `config/locales/en.yml`
3. Update `app/models/integrations/hook.rb`
4. Update `app/listeners/hook_listener.rb`
5. Update `app/jobs/hook_job.rb`
6. Update `app/jobs/crm/setup_job.rb`
7. Add `public/integrations/glpi.png`

---

### Phase 5: Testing

```bash
git checkout feature/glpi-phase5-testing
git merge main

# See detailed plan in: .kennis/glpi-integration-implementation-plan.md (lines 1180-1329)
```

**Setup local GLPI for testing:**
```bash
docker run -d --name glpi \
  -p 8080:80 \
  -e GLPI_INSTALL=true \
  diouxx/glpi:latest

# Access: http://localhost:8080
# Credentials: glpi/glpi
```

**Testing checklist:**
- [ ] Unit tests (>90% coverage)
- [ ] Integration tests with local GLPI
- [ ] Performance tests (bulk operations)
- [ ] Edge cases and error handling
- [ ] Concurrent operation tests (mutex locks)

---

### Phase 6: Documentation

```bash
git checkout feature/glpi-phase6-documentation
git merge main

# See detailed plan in: .kennis/glpi-integration-implementation-plan.md (lines 1332-1670)
```

**What to create:**
1. `docs/glpi-integration.md` - User documentation
2. `docs/development/crm-integrations/glpi.md` - Developer docs
3. YARD comments on all public methods
4. README updates if needed

---

## Development Setup

### Prerequisites

```bash
# Install dependencies (if not already done)
bundle install

# Ensure Redis is running (for mutex locks)
redis-cli ping  # Should return PONG

# Run Chatwoot development server
overmind start -f Procfile.dev
```

### Environment Variables

No additional environment variables needed for development. GLPI credentials are stored in the hook settings.

---

## Testing Workflow

### Run Tests for Specific Phase

```bash
# Phase 1 - API Clients
bundle exec rspec spec/services/crm/glpi/api/

# Phase 2 - Mappers
bundle exec rspec spec/services/crm/glpi/mappers/

# Phase 3 - Services
bundle exec rspec spec/services/crm/glpi/*_service_spec.rb

# All GLPI tests
bundle exec rspec spec/services/crm/glpi/
```

### Linting

```bash
# Ruby/Rails
bundle exec rubocop app/services/crm/glpi/
bundle exec rubocop -a  # Auto-fix

# Check specific files
bundle exec rubocop app/services/crm/glpi/api/base_client.rb
```

---

## Common Commands

### Branch Management

```bash
# List all GLPI branches
git branch | grep glpi

# Check current branch
git branch --show-current

# Switch to phase
git checkout feature/glpi-phase{N}-{description}

# Update branch with main
git checkout feature/glpi-phase{N}-{description}
git merge main

# Delete after merge
git branch -d feature/glpi-phase{N}-{description}
```

### Commit & Push

```bash
# Stage changes
git add app/services/crm/glpi/

# Commit with semantic message
git commit -m "feat(glpi-{scope}): {description}"

# Push to remote
git push origin feature/glpi-phase{N}-{description}
```

### Create Pull Request

```bash
# Using GitHub CLI
gh pr create --base main \
  --head feature/glpi-phase{N}-{description} \
  --title "feat(glpi): Phase {N} - {Title}" \
  --body "{Description}"

# Or use GitHub web interface
# https://github.com/chatwoot/chatwoot/compare/main...feature/glpi-phase{N}-{description}
```

---

## Troubleshooting

### Merge Conflicts

```bash
# If you get merge conflicts when updating from main
git checkout feature/glpi-phase{N}-{description}
git merge main

# Resolve conflicts manually, then:
git add .
git commit -m "chore: resolve merge conflicts from main"
```

### Test Failures

```bash
# Run specific test file
bundle exec rspec spec/services/crm/glpi/api/base_client_spec.rb

# Run specific test by line number
bundle exec rspec spec/services/crm/glpi/api/base_client_spec.rb:42

# Debug with pry
# Add `binding.pry` in your code, then run tests
bundle exec rspec spec/services/crm/glpi/api/base_client_spec.rb
```

### RuboCop Issues

```bash
# Auto-fix common issues
bundle exec rubocop -a app/services/crm/glpi/

# Generate TODO list for complex violations
bundle exec rubocop --auto-gen-config app/services/crm/glpi/
```

---

## Resources

- **Implementation Plan**: `.kennis/glpi-integration-implementation-plan.md`
- **Branch Strategy**: `.kennis/glpi-branch-strategy.md`
- **GLPI API Docs**: https://glpi-project.org/documentation/
- **LeadSquared Reference**: `app/services/crm/leadsquared/`
- **Base Processor**: `app/services/crm/base_processor_service.rb`

---

## Next Steps

1. ✅ Branches created
2. ⏭️ **Start Phase 1**: Switch to `feature/glpi-phase1-api-clients`
3. ⏭️ Implement BaseClient with session management
4. ⏭️ Implement resource clients (User, Contact, Ticket, Followup)
5. ⏭️ Write comprehensive tests
6. ⏭️ Create PR for Phase 1

**Current Status**: Ready to begin Phase 1 implementation

---

**Last Updated**: 2025-01-05
**Implementation Plan**: v1.0
