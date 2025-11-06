# Keycloak Setup Guide

Complete step-by-step guide to configure Keycloak OpenID Connect authentication for Chatwoot.

## 📋 Overview

This guide walks you through setting up Keycloak as an identity provider for Chatwoot using OpenID Connect (OIDC). Choose between environment variable configuration (simple) or UI configuration (multi-tenant).

**Time Required**: 20-30 minutes

## 🎯 What You'll Need

- **Keycloak Instance**: Keycloak 18.0+ running and accessible
- **Admin Access**: Keycloak administrator credentials
- **Chatwoot Access**: Administrator access to Chatwoot
- **HTTPS**: Required for production (HTTP OK for development/localhost)

---

## Part 1: Configure Keycloak

### Step 1: Create a Realm (Optional)

If you don't have a dedicated realm for Chatwoot:

1. Log in to **Keycloak Admin Console**
2. Click dropdown in top-left (says "master" by default)
3. Click **Create Realm**
4. Enter name: `chatwoot` (or your preference)
5. Click **Create**

**Skip this step** if using an existing realm.

### Step 2: Create OpenID Connect Client

1. In your realm, go to **Clients** (left sidebar)
2. Click **Create client** button

**General Settings** tab:
- **Client type**: `OpenID Connect`
- **Client ID**: `chatwoot`
- Click **Next**

**Capability config** tab:
- **Client authentication**: ON
- **Authorization**: OFF
- **Standard flow**: ON ✓
- **Direct access grants**: OFF
- Click **Next**

**Login settings** tab:
- **Root URL**: `https://your-chatwoot-domain.com`
- **Valid redirect URIs**:
  ```
  https://your-chatwoot-domain.com/omniauth/keycloak/callback
  http://localhost:3000/omniauth/keycloak/callback
  ```
- **Valid post logout redirect URIs**: `https://your-chatwoot-domain.com/*`
- **Web origins**: `https://your-chatwoot-domain.com`
- Click **Save**

📝 **Note**: For UI configuration, you'll add a different redirect URI later (includes account_id).

### Step 3: Get Client Credentials

1. Stay in the **chatwoot** client
2. Click the **Credentials** tab
3. **Copy the Client Secret** - you'll need this soon

📋 **Save these values**:
- Client ID: `chatwoot`
- Client Secret: `abc123...` (the value you just copied)

### Step 4: Get Issuer URL

The issuer URL format is:
```
https://{keycloak-domain}/realms/{realm-name}
```

**Example**:
- Keycloak domain: `keycloak.company.com`
- Realm name: `chatwoot`
- Issuer URL: `https://keycloak.company.com/realms/chatwoot`

📋 **Save your issuer URL**: `___________________________________`

### Step 5: Configure Scopes (Verify)

The default scopes should work, but verify:

1. In your realm, go to **Client scopes** (left sidebar)
2. Verify these scopes exist:
   - `openid` ✓
   - `profile` ✓
   - `email` ✓

These are included by default in most Keycloak installations.

### Step 6: Test OIDC Discovery

Verify your Keycloak OIDC discovery endpoint works:

```bash
curl https://your-keycloak-domain/realms/your-realm/.well-known/openid-configuration
```

You should get a JSON response with configuration details.

**Keycloak configuration complete!** ✅

---

## Part 2: Configure Chatwoot

Choose **one** of these configuration methods:

### Method A: Environment Variables

**Best for**: Single-tenant, simple deployments

#### 1. Set Environment Variables

Add to your `.env` file or environment:

```bash
# Enable Keycloak
KEYCLOAK_ENABLED=true

# Keycloak Configuration
KEYCLOAK_ISSUER=https://keycloak.example.com/realms/chatwoot
KEYCLOAK_CLIENT_ID=chatwoot
KEYCLOAK_CLIENT_SECRET=your-client-secret-from-step-3

# Chatwoot URL
FRONTEND_URL=https://your-chatwoot-domain.com

# Optional: Customize behavior
KEYCLOAK_UID_FIELD=preferred_username
KEYCLOAK_SCOPES=openid profile email
```

**Replace**:
- `keycloak.example.com` → Your Keycloak domain
- `chatwoot` → Your realm name
- `your-client-secret-from-step-3` → The client secret you saved
- `your-chatwoot-domain.com` → Your Chatwoot domain

#### 2. Restart Chatwoot

```bash
# Docker
docker-compose restart

# Development
overmind restart

# Systemd
sudo systemctl restart chatwoot.target
```

#### 3. Verify

1. Go to Chatwoot login page
2. You should see "Sign in with Keycloak" button
3. Click it to test (creates new user on first login)

**Done!** Skip to Part 3: Testing.

---

### Method B: UI Configuration

**Best for**: Multi-tenant, per-account configuration

#### 1. Log in as Administrator

Log in to Chatwoot with an administrator account.

#### 2. Navigate to Keycloak Settings

1. Click **Settings** (⚙️ icon) in left sidebar
2. Go to **Integrations** section
3. Find **Keycloak** integration card
4. Click **Configure** or **Connect**

#### 3. Fill Configuration Form

| Field | Value |
|-------|-------|
| **Enable Keycloak** | ✓ Check the box |
| **Issuer URL** | `https://keycloak.example.com/realms/chatwoot` |
| **Client ID** | `chatwoot` |
| **Client Secret** | [paste from Step 3] |
| **UID Field** | `preferred_username` (default) |
| **Scopes** | `openid profile email` (default) |

**Replace** with your actual values from Part 1.

#### 4. Test Connection

1. Click **Test Connection** button
2. Wait for verification (~5 seconds)
3. Should show: ✅ **Connection successful!**

**If test fails**:
- Check issuer URL format
- Verify client secret is correct
- Ensure Keycloak is accessible from Chatwoot server
- Check firewall/network settings

#### 5. Save Configuration

1. Click **Save** button
2. Configuration is encrypted and stored
3. Integration status shows: **Connected** with green checkmark

#### 6. Get Redirect URI

After saving, the UI displays:

**Redirect URI**: `https://your-chatwoot.com/omniauth/keycloak_{account_id}/callback`

**Example**: `https://chatwoot.company.com/omniauth/keycloak_1/callback`

📋 **Copy this exact URI** - you need it for the next step.

#### 7. Update Keycloak Redirect URI

Go back to Keycloak:

1. Navigate to **Clients** → **chatwoot**
2. Scroll to **Valid redirect URIs**
3. **Add** the redirect URI you just copied
4. Keep the existing URIs (don't remove them)
5. Click **Save**

**You should now have**:
```
https://your-chatwoot-domain.com/omniauth/keycloak/callback
https://your-chatwoot-domain.com/omniauth/keycloak_1/callback
http://localhost:3000/omniauth/keycloak/callback
```

#### 8. Verify

1. Go to Chatwoot login page
2. You should see "Sign in with Keycloak" button
3. No restart needed (changes apply immediately)

**Done!** Continue to Part 3: Testing.

---

## Part 3: Test the Integration

### Test 1: Admin Login

1. **Open incognito/private browser window**
2. Go to Chatwoot login page
3. Click **"Sign in with Keycloak"**
4. Enter Keycloak credentials
5. Should redirect to Chatwoot dashboard

✅ **Success**: You're logged in via Keycloak

### Test 2: New User Creation

1. Create a test user in Keycloak:
   - Go to **Users** → **Add user**
   - Set username, email, first name, last name
   - Go to **Credentials** tab → Set password
   - Disable "Temporary" toggle
   - Save
2. Log out of Chatwoot
3. Click "Sign in with Keycloak"
4. Enter test user credentials
5. Should be redirected and logged in
6. In Chatwoot, go to **Settings** → **Agents**
7. Test user should appear (auto-created)

✅ **Success**: New users auto-provisioned

### Test 3: Profile Sync

1. In Keycloak, edit the test user's name
2. Log out and log back in to Chatwoot
3. User profile should update with new name

✅ **Success**: Profile synchronization working

---

## Part 4: Production Checklist

Before going to production:

### Security

- [ ] Using HTTPS for both Chatwoot and Keycloak
- [ ] Client secrets are secure (not in version control)
- [ ] Redirect URIs are exact (no wildcards in production)
- [ ] Web origins configured correctly
- [ ] Keycloak realm is secured (not using master realm)

### Configuration

- [ ] OIDC discovery endpoint accessible: `{issuer}/.well-known/openid-configuration`
- [ ] All required scopes enabled: openid, profile, email
- [ ] Keycloak users have email addresses
- [ ] Test with multiple users
- [ ] Verified user auto-provisioning works

### Monitoring

- [ ] Check Chatwoot logs for errors: `grep KEYCLOAK log/production.log`
- [ ] Monitor Keycloak admin events
- [ ] Set up alerts for authentication failures

### Documentation

- [ ] Document the configuration for your team
- [ ] Share Keycloak login URL with users
- [ ] Provide support contact for login issues

---

## 🔧 Troubleshooting

### Issue: "Connection failed" during test

**Causes**:
- Issuer URL incorrect or unreachable
- Client secret wrong
- Firewall blocking Chatwoot → Keycloak

**Solutions**:
1. Verify issuer URL format: `https://{domain}/realms/{realm}`
2. Check Keycloak is accessible: `curl {issuer}/.well-known/openid-configuration`
3. Regenerate client secret in Keycloak if unsure
4. Check network/firewall rules

### Issue: "Invalid redirect_uri" error

**Cause**: Redirect URI not registered in Keycloak

**Solution**:
1. Go to Keycloak → Clients → chatwoot
2. Check **Valid redirect URIs** includes your Chatwoot callback URL
3. For env vars: `{FRONTEND_URL}/omniauth/keycloak/callback`
4. For UI config: `{FRONTEND_URL}/omniauth/keycloak_{account_id}/callback`
5. Save Keycloak client

### Issue: Login button not appearing

**Causes**:
- Integration not enabled
- Chatwoot not restarted (env vars)
- Configuration error

**Solutions**:
1. Verify `KEYCLOAK_ENABLED=true` (env vars) or enabled in UI
2. Restart Chatwoot (if using env vars)
3. Check Chatwoot logs for errors
4. Clear browser cache

### Issue: User created but can't access anything

**Cause**: User auto-created but not assigned to account

**Solution**:
1. Go to **Settings** → **Agents**
2. Find the user
3. Ensure they're assigned to at least one inbox
4. Check their role (Agent vs Administrator)

### Issue: "Email not found in token" error

**Cause**: Keycloak user missing email

**Solution**:
1. Go to Keycloak → Users
2. Edit the user
3. Add email address
4. Toggle **Email verified** to ON
5. Save

---

## 📚 Advanced Configuration

### Custom User Attributes

Map additional Keycloak attributes to Chatwoot:

1. Keycloak → Clients → chatwoot → **Client scopes**
2. Select **chatwoot-dedicated** scope
3. Click **Add mapper** → **By configuration**
4. Choose **User Property**
5. Configure mapping:
   - **Name**: Custom mapper name
   - **Property**: Keycloak user property
   - **Token Claim Name**: Claim name in token
6. Save

### Multiple Keycloak Instances

With UI configuration, each Chatwoot account can have its own Keycloak:

1. **Account A** → Keycloak instance 1
2. **Account B** → Keycloak instance 2

Each account independently configures via Settings → Integrations.

### Custom UID Field

Change which field identifies users:

**Environment Variables**:
```bash
KEYCLOAK_UID_FIELD=email
```

**UI Configuration**:
- Set **UID Field** to `email` or other attribute

Common options:
- `preferred_username` (default)
- `email`
- `sub` (Keycloak user ID)

### Custom Scopes

Request additional OIDC scopes:

**Environment Variables**:
```bash
KEYCLOAK_SCOPES=openid profile email groups roles
```

**UI Configuration**:
- Set **Scopes** to `openid profile email groups roles`

---

## 📖 Additional Resources

- [[Keycloak Authentication]] - Full feature documentation
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html)
- [OmniAuth OpenID Connect Gem](https://github.com/omniauth/omniauth_openid_connect)

---

## ✅ Setup Complete!

Your Keycloak integration is now configured. Users can:

- ✅ Log in with Keycloak credentials
- ✅ Auto-provision on first login
- ✅ Sync profile updates from Keycloak
- ✅ Use SSO across your organization

**Next Steps**:
1. Inform users about new login method
2. Test with your team
3. Monitor logs for issues
4. Set up additional realms/accounts as needed

---

**Version**: 1.0
**Last Updated**: 2025-11-05
**Tested With**: Keycloak 18.0+, Chatwoot v4.7.0-kennis-ai.1.0.0
