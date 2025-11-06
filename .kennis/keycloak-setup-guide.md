# Keycloak OpenID Connect Integration Guide

## Overview

This guide covers the integration of Keycloak as an OpenID Connect (OIDC) identity provider for Chatwoot authentication.

---

## What's Included

### Authentication Method

- **Protocol**: OpenID Connect (OAuth 2.0 + identity layer)
- **Provider**: Keycloak
- **Flow**: Authorization Code Flow
- **Scopes**: openid, profile, email
- **User Identification**: preferred_username (Keycloak default)

### Features

- ✅ Single Sign-On (SSO) with Keycloak
- ✅ Automatic user provisioning
- ✅ Email and profile synchronization
- ✅ Seamless integration with existing Google OAuth and SAML
- ✅ Mobile app support (via deep linking)
- ✅ Configurable via environment variables OR UI (per-account)
- ✅ Multi-tenant support with per-account Keycloak settings
- ✅ Connection testing before saving configuration
- ✅ Encrypted storage of client secrets

---

## Prerequisites

### Keycloak Requirements

1. **Keycloak Instance**: Running Keycloak 18.0+ (or compatible version)
2. **Realm**: A Keycloak realm for Chatwoot users
3. **Admin Access**: Ability to create and configure clients

### Chatwoot Requirements

1. **Ruby Gem**: `omniauth-openid-connect` (added to Gemfile)
2. **Environment Variables**: Keycloak configuration
3. **HTTPS**: Required for production (Keycloak enforces HTTPS)

---

## Step 1: Configure Keycloak

### 1.1 Create a New Client

1. Log in to Keycloak Admin Console
2. Navigate to your realm (or create a new one)
3. Go to **Clients** → **Create Client**

**Client Configuration**:
```
Client Type: OpenID Connect
Client ID: chatwoot
Name: Chatwoot
Description: Chatwoot customer support platform
```

### 1.2 Client Settings

**General Settings**:
- **Client ID**: `chatwoot`
- **Name**: Chatwoot
- **Enabled**: ON

**Access Settings**:
- **Client authentication**: ON (confidential client)
- **Standard flow**: Enabled
- **Direct access grants**: Disabled (optional, based on needs)

**Login Settings**:
- **Root URL**: `https://your-chatwoot-domain.com`
- **Valid redirect URIs**:
  ```
  https://your-chatwoot-domain.com/omniauth/keycloak/callback
  http://localhost:3000/omniauth/keycloak/callback  (for development)
  ```
- **Valid post logout redirect URIs**: `https://your-chatwoot-domain.com/*`
- **Web origins**: `https://your-chatwoot-domain.com`

### 1.3 Get Client Credentials

1. Navigate to **Clients** → **chatwoot** → **Credentials** tab
2. Copy the **Client Secret** (you'll need this for Chatwoot configuration)

### 1.4 Configure Scopes (Optional but Recommended)

Ensure the following scopes are available:
- **openid**: Required for OIDC
- **profile**: User profile information
- **email**: User email address

These are typically available by default.

### 1.5 Configure User Attributes (Optional)

If you want to map additional Keycloak user attributes to Chatwoot:

1. Go to **Clients** → **chatwoot** → **Client scopes**
2. Add mappers for custom attributes as needed

**Example: Map full name**:
- Mapper Type: User Property
- Property: username
- Token Claim Name: preferred_username

---

## Step 2: Configure Chatwoot

### 2.1 Install Dependencies

```bash
# Install the omniauth-openid-connect gem
bundle install
```

### 2.2 Set Environment Variables

Add the following to your `.env` file or environment configuration:

```bash
# Enable Keycloak authentication
KEYCLOAK_ENABLED=true

# Keycloak Issuer URL (realm-specific)
# Format: https://{keycloak-domain}/realms/{realm-name}
KEYCLOAK_ISSUER=https://keycloak.example.com/realms/chatwoot

# Client credentials from Keycloak
KEYCLOAK_CLIENT_ID=chatwoot
KEYCLOAK_CLIENT_SECRET=your-client-secret-here

# Your Chatwoot frontend URL (must match Keycloak redirect URIs)
FRONTEND_URL=https://your-chatwoot-domain.com
```

### 2.3 Restart Chatwoot

```bash
# Development
overmind start -f Procfile.dev

# Production (Docker)
docker-compose restart

# Production (systemd)
sudo systemctl restart chatwoot.target
```

---

## Step 2 (Alternative): UI-Based Configuration

Starting from this update, you can configure Keycloak settings per account via the Chatwoot UI instead of using environment variables. This approach is recommended for multi-tenant installations.

### 2A.1 Access Keycloak Settings

1. Log in to Chatwoot as an **Administrator**
2. Navigate to **Settings** → **Integrations** → **Keycloak** (or similar path)
3. You'll see the Keycloak Settings configuration panel

### 2A.2 Configure Keycloak Settings

Fill in the following fields:

**Required Fields**:
- **Enable Keycloak**: Toggle to enable/disable authentication
- **Issuer URL**: Your Keycloak realm issuer URL
  - Format: `https://keycloak.example.com/realms/your-realm`
- **Client ID**: The client ID from Keycloak (e.g., `chatwoot`)
- **Client Secret**: The client secret from Keycloak credentials tab
- **UID Field**: User identifier field (default: `preferred_username`)
- **Scopes**: Space-separated OIDC scopes (default: `openid profile email`)

**Example Configuration**:
```
Enable Keycloak: ✓ (checked)
Issuer URL: https://keycloak.example.com/realms/chatwoot
Client ID: chatwoot
Client Secret: abc123xyz789...
UID Field: preferred_username
Scopes: openid profile email
```

### 2A.3 Test Connection (Optional)

Before saving, you can test the connection:
1. Click **Test Connection** button
2. The system will verify:
   - Issuer URL is accessible
   - OIDC discovery endpoint responds correctly
   - Configuration is valid
3. If successful, you'll see a success message
4. If failed, check the error message and adjust configuration

### 2A.4 Save Configuration

1. Click **Save** or **Update** to persist settings
2. The OmniAuth middleware will automatically reload with new settings
3. Keycloak login option will appear on the login page

### 2A.5 Retrieve Redirect URI

After saving, the UI will display:
- **Redirect URI**: The callback URL to configure in Keycloak
  - Format: `https://your-chatwoot-domain.com/omniauth/keycloak_{account_id}/callback`
- **Discovery URL**: The OIDC discovery endpoint for verification

Copy the **Redirect URI** and add it to Keycloak's **Valid redirect URIs** list.

### 2A.6 API Endpoints (for programmatic access)

For automation or advanced use cases, you can use the REST API:

```bash
# Get current Keycloak settings
curl -X GET https://chatwoot.example.com/api/v1/accounts/{account_id}/keycloak_settings \
  -H "api_access_token: YOUR_TOKEN"

# Create/Update Keycloak settings
curl -X PUT https://chatwoot.example.com/api/v1/accounts/{account_id}/keycloak_settings \
  -H "api_access_token: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "keycloak_settings": {
      "enabled": true,
      "issuer": "https://keycloak.example.com/realms/chatwoot",
      "client_id": "chatwoot",
      "client_secret": "your-secret",
      "uid_field": "preferred_username",
      "scopes": "openid profile email"
    }
  }'

# Test connection
curl -X POST https://chatwoot.example.com/api/v1/accounts/{account_id}/keycloak_settings/test \
  -H "api_access_token: YOUR_TOKEN"

# Delete Keycloak settings
curl -X DELETE https://chatwoot.example.com/api/v1/accounts/{account_id}/keycloak_settings \
  -H "api_access_token: YOUR_TOKEN"
```

### UI vs Environment Variables

You can use **both** approaches simultaneously:

1. **Global Configuration (Environment Variables)**:
   - Sets a default Keycloak provider for all accounts
   - Useful for single-tenant installations
   - Provider name: `:keycloak`

2. **Per-Account Configuration (UI/Database)**:
   - Each account can have its own Keycloak settings
   - Useful for multi-tenant installations
   - Provider name: `:keycloak_{account_id}`

**Priority**: Both configurations can coexist. Users will see multiple Keycloak login options if both are enabled.

---

## Step 3: Test the Integration

### 3.1 Access Keycloak Login

1. Navigate to Chatwoot login page: `https://your-chatwoot-domain.com/app/login`
2. You should see a "Sign in with Keycloak" button (or similar)
3. Click the Keycloak login option
4. You'll be redirected to Keycloak login page

### 3.2 Login Flow

1. **Keycloak Login**: Enter your Keycloak username/password
2. **Consent (if configured)**: Grant permissions to Chatwoot
3. **Redirect**: You'll be redirected back to Chatwoot
4. **Account Creation**:
   - If user exists: Logged in automatically
   - If new user: Account created and logged in

### 3.3 Verify User Creation

```ruby
# Rails console
User.find_by(email: 'keycloak-user@example.com')
# Should return the user created via Keycloak
```

---

## Environment Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `KEYCLOAK_ENABLED` | Enable/disable Keycloak | `true` |
| `KEYCLOAK_ISSUER` | Keycloak realm issuer URL | `https://keycloak.example.com/realms/chatwoot` |
| `KEYCLOAK_CLIENT_ID` | Keycloak client ID | `chatwoot` |
| `KEYCLOAK_CLIENT_SECRET` | Keycloak client secret | `abc123...` |
| `FRONTEND_URL` | Chatwoot frontend URL | `https://chat.example.com` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KEYCLOAK_SCOPES` | Custom OIDC scopes | `openid profile email` |
| `KEYCLOAK_UID_FIELD` | User ID field | `preferred_username` |

---

## Architecture

### Authentication Flow

```
┌────────────┐                ┌──────────────┐               ┌──────────┐
│            │                │              │               │          │
│   User     │──1. Login─────▶│  Chatwoot    │──2. Redirect─▶│ Keycloak │
│            │                │              │               │          │
└────────────┘                └──────────────┘               └──────────┘
      ▲                              │                             │
      │                              │                             │
      │                              │                             │
      │                              ▼                             │
      │                       ┌──────────────┐                     │
      │                       │              │                     │
      │                       │   OmniAuth   │◀─3. Auth Response──┘
      │                       │   Callback   │
      │                       │              │
      │                       └──────────────┘
      │                              │
      │                              │ 4. Create/Login User
      │                              ▼
      │                       ┌──────────────┐
      │                       │              │
      │                       │  User Model  │
      │                       │              │
      │                       └──────────────┘
      │                              │
      │                              │ 5. Generate SSO Token
      │                              ▼
      └────────────6. Redirect with Token────┘
```

### Component Overview

1. **OmniAuth Middleware**: Handles OIDC protocol
2. **Keycloak Provider**: Configured in `config/initializers/omniauth.rb`
   - Supports both environment variables and database-driven configuration
   - Loads enabled providers dynamically at startup
3. **KeycloakSetting Model**: `app/models/keycloak_setting.rb`
   - Stores per-account Keycloak configuration
   - Encrypts client secrets using Rails 7 encryption
4. **Keycloak Settings Controller**: `app/controllers/api/v1/accounts/keycloak_settings_controller.rb`
   - REST API for CRUD operations
   - Administrator-only access via Pundit policy
5. **Callbacks Controller**: `app/controllers/devise_overrides/omniauth_callbacks_controller.rb`
6. **User Model**: `app/models/user.rb` (includes `:keycloak` provider)

---

## User Provisioning

### New User Flow

When a user logs in via Keycloak for the first time:

1. **User Lookup**: Chatwoot searches for existing user by email
2. **User Creation** (if not found):
   - Email from OIDC token
   - Name from OIDC profile
   - Username from `preferred_username`
   - Auto-confirmed (skips email verification)
3. **SSO Token**: Generated for seamless login
4. **Redirect**: User redirected to Chatwoot dashboard

### Existing User Flow

When an existing user logs in via Keycloak:

1. **User Lookup**: Found by email
2. **Skip Confirmation**: Email automatically confirmed
3. **SSO Token**: Generated for login
4. **Redirect**: User logged in immediately

---

## Keycloak Discovery

The integration uses **OpenID Connect Discovery** to automatically configure:

- Authorization endpoint
- Token endpoint
- UserInfo endpoint
- JWKS URI
- Supported scopes and claims

**Discovery URL**: `{KEYCLOAK_ISSUER}/.well-known/openid-configuration`

**Example**:
```
https://keycloak.example.com/realms/chatwoot/.well-known/openid-configuration
```

---

## Security Considerations

### Token Security

- ✅ **Client Secret**: Stored in environment variables (encrypted)
- ✅ **State Parameter**: CSRF protection via OmniAuth
- ✅ **HTTPS Only**: Required for production
- ✅ **Token Validation**: Automatic via OpenID Connect Discovery

### Session Management

- ✅ **SSO Token**: Generated per login for Chatwoot session
- ✅ **Keycloak Session**: Independent session in Keycloak
- ✅ **Logout**: Requires logout from both Chatwoot and Keycloak

### Best Practices

1. **Use HTTPS**: Always use HTTPS for production
2. **Rotate Secrets**: Periodically rotate client secret
3. **Limit Scopes**: Only request necessary scopes
4. **Monitor Access**: Review Keycloak audit logs
5. **Network Security**: Use firewall rules to restrict access

---

## Customization

### Custom User Attributes

To map custom Keycloak attributes to Chatwoot:

1. **Configure Mapper in Keycloak**:
   - Client → chatwoot → Client Scopes → Add Mapper
   - Map user attributes to token claims

2. **Update Callback Controller** (optional):
   ```ruby
   # app/controllers/devise_overrides/omniauth_callbacks_controller.rb

   def get_resource_from_auth_hash
     # Extract custom attributes from auth hash
     custom_attr = auth_hash.info.custom_field

     # Use custom attributes during user creation
     @resource = User.where(email: auth_hash.info.email).first_or_initialize
     @resource.custom_field = custom_attr if @resource.new_record?
     @resource.save!
   end
   ```

### Custom Scopes

To request additional scopes:

```ruby
# config/initializers/omniauth.rb
provider :openid_connect, {
  name: :keycloak,
  scope: [:openid, :profile, :email, :custom_scope], # Add custom scope
  # ... rest of config
}
```

### Custom UID Field

To use a different field as user identifier:

```ruby
# config/initializers/omniauth.rb
provider :openid_connect, {
  name: :keycloak,
  uid_field: 'sub', # Use 'sub' instead of 'preferred_username'
  # ... rest of config
}
```

---

## Troubleshooting

### Issue 1: Redirect URI Mismatch

**Error**: "Invalid redirect_uri"

**Solution**:
1. Check Keycloak client valid redirect URIs
2. Ensure FRONTEND_URL matches exactly
3. Include `/omniauth/keycloak/callback` path

### Issue 2: Discovery Fails

**Error**: "Could not discover OpenID Connect configuration"

**Solution**:
1. Verify KEYCLOAK_ISSUER is correct
2. Test discovery URL manually:
   ```bash
   curl https://keycloak.example.com/realms/chatwoot/.well-known/openid-configuration
   ```
3. Check network connectivity from Chatwoot to Keycloak

### Issue 3: Invalid Client Credentials

**Error**: "invalid_client"

**Solution**:
1. Verify KEYCLOAK_CLIENT_ID matches Keycloak client ID
2. Verify KEYCLOAK_CLIENT_SECRET is correct
3. Check client authentication is enabled in Keycloak

### Issue 4: User Not Created

**Error**: User logged in but not found in Chatwoot

**Solution**:
1. Check Rails logs for errors
2. Verify email is included in OIDC token
3. Check account signup settings in Chatwoot

### Issue 5: HTTPS Required

**Error**: "Keycloak requires HTTPS"

**Solution**:
1. Use HTTPS in production
2. For development, configure Keycloak to allow HTTP:
   - Realm Settings → Login → Require SSL: None (development only)

---

## Testing

### Manual Testing

1. **Test Discovery**:
   ```bash
   curl https://keycloak.example.com/realms/chatwoot/.well-known/openid-configuration
   ```

2. **Test Login Flow**:
   - Navigate to Chatwoot login
   - Click "Sign in with Keycloak"
   - Complete Keycloak login
   - Verify redirect back to Chatwoot

3. **Verify User Creation**:
   ```ruby
   # Rails console
   User.where(provider: 'keycloak').count
   # Should show users created via Keycloak
   ```

### Automated Testing

```ruby
# spec/features/keycloak_authentication_spec.rb (example)
require 'rails_helper'

RSpec.describe 'Keycloak Authentication', type: :feature do
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:keycloak] = OmniAuth::AuthHash.new({
      provider: 'keycloak',
      uid: 'testuser',
      info: {
        email: 'test@example.com',
        name: 'Test User'
      }
    })
  end

  it 'creates user on first login' do
    visit '/users/auth/keycloak'
    expect(User.find_by(email: 'test@example.com')).to be_present
  end
end
```

---

## Mobile App Integration

### Deep Linking

For mobile apps using Keycloak authentication:

**Callback URL Format**:
```
chatwootapp://auth/keycloak?email={email}&sso_auth_token={token}
```

**Mobile Configuration**:
1. Register deep link scheme in mobile app
2. Handle callback in app
3. Use SSO token for authentication

---

## Multi-Realm Support (Optional)

To support multiple Keycloak realms:

```ruby
# config/initializers/omniauth.rb

# Realm 1
provider :openid_connect, {
  name: :keycloak_realm1,
  issuer: ENV['KEYCLOAK_REALM1_ISSUER'],
  # ... config
}

# Realm 2
provider :openid_connect, {
  name: :keycloak_realm2,
  issuer: ENV['KEYCLOAK_REALM2_ISSUER'],
  # ... config
}
```

---

## Migration from Google OAuth

If migrating from Google OAuth to Keycloak:

1. **Keep both providers active** during migration
2. **User matching**: Match users by email
3. **Communication**: Notify users of new login method
4. **Gradual rollout**: Enable Keycloak for groups progressively
5. **Deprecation**: Remove Google OAuth after full migration

---

## Performance Considerations

### Caching

- OIDC discovery responses are cached by the gem
- JWKS keys are cached and refreshed automatically
- No additional caching configuration needed

### Network

- Keycloak should be on fast network relative to Chatwoot
- Consider using internal network for on-premise deployments
- Monitor network latency between services

---

## Monitoring

### Metrics to Track

1. **Authentication Success Rate**: Login success vs failures
2. **Authentication Latency**: Time from redirect to callback
3. **User Provisioning**: New users created via Keycloak
4. **Errors**: Authentication errors and causes

### Logging

Check Rails logs for Keycloak-related activity:

```bash
# Development
tail -f log/development.log | grep -i keycloak

# Production
tail -f log/production.log | grep -i keycloak
```

---

## FAQ

**Q: Can I use multiple identity providers simultaneously?**
A: Yes! Keycloak, Google OAuth, and SAML can all be active at the same time.

**Q: What happens if Keycloak is down?**
A: Users can still login with email/password or other configured providers (Google, SAML).

**Q: Can I customize the login button text?**
A: Yes, update the frontend i18n files to customize the button label.

**Q: Does this support MFA/2FA?**
A: Yes, if configured in Keycloak. Keycloak handles MFA before redirecting to Chatwoot.

**Q: Can I map user roles from Keycloak?**
A: Not directly in this integration. Role mapping would require custom implementation.

**Q: Is this compatible with Keycloak.X?**
A: Yes, this integration works with both Keycloak and Keycloak.X (Quarkus-based).

**Q: Can I use this with Red Hat SSO?**
A: Yes, Red Hat SSO is based on Keycloak and is fully compatible.

---

## References

- **Keycloak Documentation**: https://www.keycloak.org/documentation
- **OpenID Connect Spec**: https://openid.net/specs/openid-connect-core-1_0.html
- **OmniAuth OpenID Connect**: https://github.com/omniauth/omniauth_openid_connect
- **Chatwoot Documentation**: https://www.chatwoot.com/docs/

---

## Support

For issues or questions:
1. Check this guide and troubleshooting section
2. Review Keycloak and Chatwoot logs
3. Test OIDC discovery endpoint
4. Verify environment variables
5. Contact your team or community support

---

**Version**: 1.0.0
**Last Updated**: 2025-11-05
**Status**: Production Ready
