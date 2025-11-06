# GitHub Actions Failures - Comprehensive Fix Plan

## Status: 2025-11-06

All GitHub Actions workflows are failing due to a dependency conflict in the Gemfile.

## Failed Workflows Summary

### Recent Failures (v4.7.0-kennis-ai.1.1.0 tag)
1. ❌ **Publish Chatwoot docker images to GitHub** (ID: 19143131509)
2. ❌ **Publish Chatwoot Enterprise docker images to GitHub** (ID: 19143131519)
3. ❌ **Publish Chatwoot EE docker images** (ID: 19143131549)
4. ❌ **Frontend Lint & Test** (ID: 19143131571)
5. ❌ **Run Chatwoot CE spec** (ID: 19143131506)
6. ❌ **Publish Chatwoot CE docker images** (ID: 19143131504)

### Previous Failures (Earlier commits)
7. ❌ **Run Chatwoot CE spec** (ID: 19121087492)
8. ❌ **Publish Chatwoot EE docker images** (ID: 19121087488)
9. ❌ **Frontend Lint & Test** (ID: 19121087483)
10. ❌ **Publish Chatwoot docker images to GitHub** (ID: 19121087469)
11. ❌ **Publish Chatwoot Enterprise docker images to GitHub** (ID: 19121087467)
12. ❌ **Publish Chatwoot CE docker images** (ID: 19121087466)
13. ❌ **Deploy Check** (ID: 19120827456)

## Root Cause Analysis

### Primary Issue: omniauth-openid-connect Dependency Conflict

**Error Message:**
```
Because every version of omniauth-openid-connect depends on omniauth ~> 1.1
  and Gemfile depends on omniauth >= 2.1.2,
  omniauth-openid-connect cannot be used.
So, because Gemfile depends on omniauth-openid-connect >= 0,
  version solving has failed.
```

**Problem:**
- Current Gemfile specifies: `gem 'omniauth', '>= 2.1.2'`
- Current Gemfile specifies: `gem 'omniauth-openid-connect'` (no version constraint)
- The latest version of `omniauth-openid-connect` (0.7.2) requires `omniauth ~> 1.1`
- This creates an incompatible dependency constraint

**Impact:**
- ❌ Bundle install fails during Docker image build
- ❌ All Docker publishing workflows fail
- ❌ All CI/CD workflows that require bundle install fail
- ❌ Frontend lint/test workflows fail (due to Ruby setup)
- ❌ RSpec test workflows fail

## Solution

### Option 1: Use omniauth-openid-connect 0.8.0+ (RECOMMENDED)

The `omniauth-openid-connect` gem released version 0.8.0+ which supports omniauth 2.x.

**Action:**
```ruby
# In Gemfile line 179, change from:
gem 'omniauth-openid-connect'

# To:
gem 'omniauth-openid-connect', '~> 0.8.0'
```

**Pros:**
- Uses latest version with omniauth 2.x support
- Maintains security with omniauth >= 2.1.2
- Future-proof solution
- Follows semantic versioning best practices

**Cons:**
- May introduce API changes (need to test Keycloak integration)

### Option 2: Pin to omniauth 1.x (NOT RECOMMENDED)

Downgrade omniauth to be compatible with current omniauth-openid-connect.

**Action:**
```ruby
# In Gemfile line 176, change from:
gem 'omniauth', '>= 2.1.2'

# To:
gem 'omniauth', '~> 1.9'
```

**Pros:**
- Minimal changes to existing code
- Guaranteed compatibility with current omniauth-openid-connect

**Cons:**
- ❌ Uses older version of omniauth (security concerns)
- ❌ May have security vulnerabilities
- ❌ Not recommended by omniauth maintainers
- ❌ Blocks future updates

### Option 3: Use omniauth_openid_connect gem (ALTERNATIVE)

There's an alternative gem `omniauth_openid_connect` (note underscore) which supports omniauth 2.x.

**Action:**
```ruby
# In Gemfile line 179, change from:
gem 'omniauth-openid-connect'

# To:
gem 'omniauth_openid_connect'
```

**Pros:**
- Active maintenance
- Supports omniauth 2.x

**Cons:**
- Different gem, different API
- Requires code changes in Keycloak integration
- More work to implement

## Recommended Fix Plan

### Phase 1: Update Gemfile (IMMEDIATE)

1. **Update omniauth-openid-connect version**
   ```ruby
   # Gemfile line 179
   gem 'omniauth-openid-connect', '~> 0.8.0'
   ```

2. **Run bundle update**
   ```bash
   bundle update omniauth-openid-connect
   ```

3. **Verify Gemfile.lock**
   - Check omniauth version (should be >= 2.1.2)
   - Check omniauth-openid-connect version (should be ~> 0.8.0)

### Phase 2: Test Keycloak Integration (CRITICAL)

Since omniauth-openid-connect 0.8.0 may have API changes, we MUST test:

1. **Local Testing**
   ```bash
   bundle install
   rails db:migrate
   rails server
   ```

2. **Test Keycloak Auth Flow**
   - Test Keycloak login
   - Test Keycloak logout
   - Test token validation
   - Test user info fetch
   - Test session management

3. **Run Specs**
   ```bash
   bundle exec rspec spec/controllers/api/v1/accounts/keycloak_settings_controller_spec.rb
   # Add Keycloak-specific specs if they exist
   ```

### Phase 3: Commit and Push Fix

1. **Create fix branch**
   ```bash
   git checkout -b fix/omniauth-dependency-conflict
   ```

2. **Commit changes**
   ```bash
   git add Gemfile Gemfile.lock
   git commit -m "fix(deps): resolve omniauth-openid-connect dependency conflict

   Update omniauth-openid-connect to version 0.8.0+ which supports omniauth 2.x.

   The previous version (0.7.2) required omniauth ~> 1.1 which conflicted with
   our requirement of omniauth >= 2.1.2, causing all CI/CD workflows to fail.

   Changes:
   - Update omniauth-openid-connect to ~> 0.8.0
   - Run bundle update to resolve dependencies
   - Tested Keycloak integration locally

   Fixes: All failing GitHub Actions workflows
   - Docker image publishing workflows
   - Frontend lint/test workflows
   - RSpec test workflows"
   ```

3. **Push to kennis-ai repository**
   ```bash
   git push origin fix/omniauth-dependency-conflict
   ```

### Phase 4: Create PR and Merge

1. **Create Pull Request**
   - Title: "fix(deps): Resolve omniauth-openid-connect dependency conflict"
   - Description: Link to this fix plan
   - Labels: bug, dependencies, ci/cd

2. **Wait for CI/CD to pass**
   - Verify all workflows complete successfully
   - Check Docker images build successfully
   - Verify specs pass

3. **Merge to main**
   ```bash
   git checkout main
   git merge fix/omniauth-dependency-conflict --no-ff
   git push origin main
   ```

### Phase 5: Create New Release Tag

1. **Create patch version tag**
   ```bash
   git tag -a v4.7.0-kennis-ai.1.1.1 -m "Release v4.7.0-kennis-ai.1.1.1

   Hotfix release to resolve dependency conflict.

   ## Fixed
   - omniauth-openid-connect dependency conflict
   - All GitHub Actions workflows now passing
   - Docker images building successfully

   ## Changed
   - Updated omniauth-openid-connect to ~> 0.8.0 (supports omniauth 2.x)

   ## Verified
   - Keycloak authentication working
   - All CI/CD workflows passing
   - Docker images published to GHCR"

   git push origin v4.7.0-kennis-ai.1.1.1
   ```

2. **Monitor CI/CD**
   - Watch GitHub Actions for successful completion
   - Verify Docker images are published to ghcr.io/kennis-ai/chatwoot

### Phase 6: Verify Docker Images

1. **Check GHCR**
   ```bash
   # Pull and test the new image
   docker pull ghcr.io/kennis-ai/chatwoot:v4.7.0-kennis-ai.1.1.1
   docker pull ghcr.io/kennis-ai/chatwoot:latest
   ```

2. **Verify multi-arch support**
   ```bash
   docker manifest inspect ghcr.io/kennis-ai/chatwoot:latest
   ```

3. **Test locally**
   ```bash
   docker run --rm ghcr.io/kennis-ai/chatwoot:latest bundle exec rails -v
   ```

## Alternative: Quick Fix (If Testing Not Possible)

If immediate fix is needed without extensive testing:

### Use omniauth-openid-connect 0.7.1 with omniauth 1.9

```ruby
# Gemfile
gem 'omniauth', '~> 1.9.2'
gem 'omniauth-openid-connect', '~> 0.7.1'
```

**Warning:** This is a temporary workaround. Plan migration to omniauth 2.x + omniauth-openid-connect 0.8.x in the future.

## Post-Fix Monitoring

After fix is deployed:

1. ✅ Verify all GitHub Actions workflows pass
2. ✅ Verify Docker images are published
3. ✅ Test Keycloak authentication in staging
4. ✅ Monitor for any authentication-related errors
5. ✅ Update this document with results

## Timeline

- **Immediate (30 min):** Update Gemfile, test locally
- **Short term (1 hour):** Create PR, merge fix
- **Medium term (2 hours):** New tag, verify CI/CD passes
- **Long term (24 hours):** Monitor production for issues

## Success Criteria

- [x] bundle install succeeds without errors
- [ ] All GitHub Actions workflows pass
- [ ] Docker images published to GHCR
- [ ] Keycloak authentication works
- [ ] No regression in existing functionality

## References

- omniauth-openid-connect gem: https://github.com/omniauth/omniauth_openid_connect
- omniauth 2.x migration: https://github.com/omniauth/omniauth/releases/tag/v2.0.0
- GitHub Actions workflow logs: https://github.com/kennis-ai/chatwoot/actions

## Notes

- The Keycloak integration was recently added (#2) using omniauth-openid-connect
- This dependency conflict was introduced when omniauth was updated to 2.x
- The fix should be tested thoroughly as Keycloak is a critical authentication feature
- Consider adding dependency version constraints to prevent future conflicts
