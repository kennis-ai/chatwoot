# StackLab License Stub Implementation

## Overview

This document explains the StackLab license stub implementation that allows Kanban functionality to work without requiring a valid StackLab PRO license.

## Problem Statement

The Kanban integration extracted from `stacklabdigital/kanban:v2.8.7` includes mandatory license validation:

1. **License Check in Controller** (`app/controllers/api/v1/accounts/kanban_items_controller.rb:3`):
   ```ruby
   before_action :check_stacklab_license, except: [:debug]
   ```

2. **License Validation Method**:
   ```ruby
   def check_stacklab_license
     if ChatwootApp.stacklab.token_valid?
       unless ChatwootApp.stacklab?
         render json: { error: 'Plano StackLab insuficiente' }, status: :forbidden
         return
       end
     else
       render json: { error: 'Token StackLab não encontrado' }, status: :not_found
     end
   end
   ```

3. **Impact**: ALL Kanban API endpoints (except debug) are blocked without:
   - Valid `STACKLAB_TOKEN` environment variable
   - PRO plan license from StackLab
   - Network access to `https://pulse.stacklab.digital/api/cw/licenses/verify`

## Solution: License Stub

**File**: `config/initializers/stacklab_stub.rb`

### What It Does

The stub provides a complete implementation of the StackLab licensing API that:

1. **Returns success for all license checks**
2. **Enables all features** (kanban_pro, stacklab_modules, cloud_configs)
3. **Reports PRO plan status**
4. **Works completely offline**
5. **Requires no environment variables**

### How It Works

#### 1. Stub Module Structure

```ruby
module Stacklab
  module LicensingService
    def self.get_license_info(force_refresh: false)
      {
        token_provided: true,
        plan: 'pro',
        features: {
          kanban_pro: true,
          stacklab_modules: true,
          cloud_configs: true
        },
        message: 'Stubbed StackLab license - all features enabled'
      }
    end

    def self.feature_enabled?(feature_key)
      true
    end

    def self.token_valid?
      true
    end

    def self.pro_plan?
      true
    end
    # ... other methods
  end
end
```

#### 2. ChatwootApp Integration

```ruby
module ChatwootApp
  class StacklabLicenseAccessor
    def kanban_pro_active?
      true
    end

    def feature_enabled?(feature_key)
      true
    end

    def plan
      'pro'
    end

    def token_valid?
      true
    end
    # ... other methods
  end

  def self.stacklab
    @stacklab_accessor ||= StacklabLicenseAccessor.new(true)
  end

  def self.stacklab?
    true
  end
end
```

### Loading Strategy

The stub uses `Rails.application.config.after_initialize` to:

1. **Check if real service exists**: Only stubs if `::Stacklab::LicensingService` is not defined
2. **Create stub module**: Provides compatible API
3. **Override ChatwootApp methods**: Ensures correct return values
4. **Log initialization**: Shows stub is active in Rails logs

### Compatibility

The stub is **fully compatible** with the license check code in:
- `app/controllers/api/v1/accounts/kanban_items_controller.rb`
- `app/controllers/api/v1/accounts/kanban_configs_controller.rb`
- Any other code calling `ChatwootApp.stacklab` methods

## Testing the Stub

### 1. Start Rails Console

```bash
bundle exec rails console
```

### 2. Test License Methods

```ruby
# Check if stub is loaded
ChatwootApp.stacklab?
# => true

# Check plan
ChatwootApp.stacklab.plan
# => "pro"

# Check features
ChatwootApp.stacklab.feature_enabled?(:kanban_pro)
# => true

ChatwootApp.stacklab.all_features
# => { kanban_pro: true, stacklab_modules: true, cloud_configs: true }

# Check token validity
ChatwootApp.stacklab.token_valid?
# => true
```

### 3. Test API Endpoint

```bash
# Start Rails server
bundle exec rails server

# Test Kanban items endpoint (should work without license)
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/v1/accounts/1/kanban_items

# Should return 200 OK (or appropriate response based on data)
# NOT 403 Forbidden or 404 Not Found
```

## Logs

When the stub is active, you'll see these log messages at startup:

```
[StackLab Stub] StackLab licensing service not found. Using stub implementation.
[StackLab Stub] Initialization complete. All Kanban features enabled without license validation.
[StackLab Stub] To use real StackLab licensing, delete config/initializers/stacklab_stub.rb and configure STACKLAB_TOKEN
```

## Advantages

### ✅ Pros

1. **No External Dependencies**: Works completely offline
2. **No License Costs**: No need to purchase StackLab license
3. **Full Functionality**: All Kanban features enabled
4. **Simple Implementation**: Single initializer file
5. **Easy to Disable**: Just delete the file to use real licensing
6. **No Code Changes**: No modifications to Kanban controller code
7. **Maintainable**: Clear separation of stub from application code

### ⚠️ Considerations

1. **No License Validation**: Anyone with access can use Kanban features
2. **No Feature Toggling**: All features always enabled (no per-account control)
3. **No Usage Tracking**: No metrics sent to StackLab
4. **Updates**: May need updates if Kanban code changes license API

## Alternatives Considered

### Alternative 1: Comment Out License Check

**Not chosen because**:
- Modifies application code
- Harder to maintain across updates
- Less clean separation

```ruby
# In app/controllers/api/v1/accounts/kanban_items_controller.rb
# before_action :check_stacklab_license, except: [:debug]  # COMMENTED OUT
```

### Alternative 2: Environment Variable Override

**Not chosen because**:
- Still requires code changes
- Less flexible
- Harder to understand

```ruby
def check_stacklab_license
  return if ENV['SKIP_STACKLAB_CHECK'] == 'true'  # ADDED LINE
  # ... rest of method
end
```

### Alternative 3: Use Real StackLab License

**Not chosen because**:
- Requires purchasing license
- External dependency
- Network connectivity required
- Ongoing costs

## Migration Path

### From Stub to Real License

If you later decide to use official StackLab licensing:

1. **Remove stub**:
   ```bash
   rm config/initializers/stacklab_stub.rb
   ```

2. **Extract real licensing files** from Docker image:
   ```bash
   docker run --rm stacklabdigital/kanban:v2.8.7 tar -czf - \
     stacklab/licensing_service.rb \
     stacklab/service-account-kanban-firebase.json | tar -xzf -
   ```

3. **Update lib/chatwoot_app.rb** with StackLab integration code

4. **Set environment variables**:
   ```bash
   STACKLAB_TOKEN=your_token_here
   STACKLAB_API_VERIFY_URL=https://pulse.stacklab.digital/api/cw/licenses/verify
   ```

5. **Restart application**

### From Real License to Stub

If you have real licensing and want to switch to stub:

1. **Create stub file**: `config/initializers/stacklab_stub.rb` (as documented)
2. **Remove** (or backup) `stacklab/` directory
3. **Remove** environment variables
4. **Restart application**

## Security Considerations

### Access Control

The stub **bypasses license checks** but does NOT bypass:
- User authentication (still required)
- Account-based authorization (Kanban items are account-scoped)
- Policy-based permissions (KanbanItemPolicy still enforced)

### Production Use

For production deployments:

1. **Consider access control**: Who should have Kanban access?
2. **Monitor usage**: Add custom analytics if needed
3. **Document decision**: Why stub was chosen over real license
4. **Review regularly**: Ensure stub still meets requirements

## Troubleshooting

### Stub Not Working (Still Getting License Errors)

**Check 1**: Verify stub file exists
```bash
ls -la config/initializers/stacklab_stub.rb
```

**Check 2**: Verify Rails loaded the stub
```bash
bundle exec rails console
> Rails.logger.grep "StackLab Stub"
```

**Check 3**: Check for real licensing service
```bash
bundle exec rails console
> defined?(::Stacklab::LicensingService)
# Should be nil or show stub version
```

**Check 4**: Restart Rails completely
```bash
# Kill all Rails processes
pkill -f rails
# Start fresh
bundle exec rails server
```

### Real Licensing Service Taking Precedence

If the real `stacklab/licensing_service.rb` exists, it will be loaded before the stub and take precedence.

**Solution**: Remove real licensing files
```bash
rm -rf stacklab/
rm -f lib/chatwoot_app.rb  # If it includes StackLab code
```

## Documentation References

- Main Integration Guide: `.kennis/kanban-integration.md`
- Extraction Summary: `.kennis/kanban-extraction-summary.md`
- Stub Implementation: `config/initializers/stacklab_stub.rb`

## Version History

- **v1.0.0** (2025-11-07) - Initial stub implementation for Kanban integration

## Support

For issues with the stub implementation:
1. Check this documentation
2. Review stub code in `config/initializers/stacklab_stub.rb`
3. Check Rails logs for initialization messages
4. Test in Rails console as documented above
