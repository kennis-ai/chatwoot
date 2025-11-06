# Krayin CRM Setup Guide

This guide walks you through setting up the Krayin CRM integration with Chatwoot step-by-step.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Prepare Krayin CRM](#step-1-prepare-krayin-crm)
3. [Step 2: Generate API Token](#step-2-generate-api-token)
4. [Step 3: Configure Chatwoot Integration](#step-3-configure-chatwoot-integration)
5. [Step 4: Test the Connection](#step-4-test-the-connection)
6. [Step 5: Configure Sync Options](#step-5-configure-sync-options)
7. [Step 6: Verify Sync](#step-6-verify-sync)
8. [Advanced Configuration](#advanced-configuration)

## Prerequisites

### Required
- Krayin CRM v2.1.5 or higher installed and accessible
- Krayin REST API Package v2.1.1 installed
- Admin access to Krayin instance
- Admin access to Chatwoot instance
- Chatwoot Enterprise or `crm_integration` feature flag enabled

### Recommended
- Test Krayin instance for initial setup
- Test contact in Chatwoot for verification
- Access to server logs for troubleshooting

## Step 1: Prepare Krayin CRM

### 1.1 Verify Krayin Version

1. Log in to your Krayin CRM instance
2. Navigate to **Settings** → **About**
3. Verify version is **2.1.5** or higher

### 1.2 Install REST API Package

If not already installed:

```bash
# Via Composer
cd /path/to/krayin
composer require krayin/rest-api

# Run migrations
php artisan migrate

# Clear cache
php artisan optimize:clear
```

### 1.3 Verify API Endpoint

Test your API endpoint is accessible:

```bash
curl -X GET https://your-krayin-domain.com/api/admin/leads/pipelines \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"
```

Expected response: JSON array of pipelines

## Step 2: Generate API Token

### 2.1 Create API User (Recommended)

1. In Krayin, navigate to **Settings** → **Users** → **Add User**
2. Fill in details:
   - **Name**: "Chatwoot Integration"
   - **Email**: `chatwoot@yourcompany.com`
   - **Password**: (strong password)
   - **Role**: Admin or custom role with these permissions:
     - View/Create/Edit Persons
     - View/Create/Edit Leads
     - View/Create/Edit Organizations
     - View/Create/Edit Activities
3. Click **Save**

### 2.2 Generate Sanctum Token

**Option A: Via Krayin UI (if available)**

1. Navigate to **Settings** → **API Tokens**
2. Click **Generate New Token**
3. Name: "Chatwoot Integration"
4. Scopes: All CRM scopes
5. Click **Create**
6. **Copy the token immediately** (shown only once)

**Option B: Via Tinker (CLI)**

```bash
cd /path/to/krayin
php artisan tinker

# In tinker console:
$user = \Webkul\User\Models\Admin::where('email', 'chatwoot@yourcompany.com')->first();
$token = $user->createToken('Chatwoot Integration')->plainTextToken;
echo $token;
exit;
```

**Store the token securely!** You won't be able to see it again.

### 2.3 Test API Token

```bash
export KRAYIN_TOKEN="your-token-here"
curl -X GET https://your-krayin-domain.com/api/admin/settings/pipelines \
  -H "Authorization: Bearer $KRAYIN_TOKEN" \
  -H "Accept: application/json"
```

Expected: 200 OK with pipeline data

## Step 3: Configure Chatwoot Integration

### 3.1 Access Integration Settings

1. Log in to Chatwoot as an admin
2. Navigate to **Settings** (gear icon)
3. Click **Integrations** in the sidebar
4. Locate **Krayin CRM** in the list

### 3.2 Basic Configuration

1. Click **Configure** on Krayin CRM card
2. Fill in the configuration form:

| Field | Value | Example |
|-------|-------|---------|
| **API URL** | Your Krayin API endpoint | `https://crm.example.com/api/admin` |
| **API Token** | Token from Step 2 | `1|aBcDeFgHiJkLmNoPqRsTuVwXyZ...` |

**Important**:
- API URL must include `/api/admin` path
- Token must start with number and pipe (e.g., `1|...`)
- No trailing slash in URL

3. Click **Connect**

### 3.3 Connection Validation

Chatwoot will:
1. Test API connection
2. Fetch available pipelines
3. Fetch available stages
4. Fetch lead sources
5. Fetch lead types
6. Store default configuration

**Success**: Green checkmark and "Connected successfully" message

**Failure**: See [Troubleshooting](#troubleshooting) section

## Step 4: Test the Connection

### 4.1 Create Test Contact

1. Navigate to **Contacts** in Chatwoot
2. Click **Add Contact**
3. Fill in test data:
   ```
   Name: Test User
   Email: test@example.com
   Phone: +1234567890
   ```
4. Click **Create Contact**

### 4.2 Verify in Krayin

1. Log in to Krayin CRM
2. Navigate to **Contacts** → **Persons**
3. Search for "Test User"
4. Verify Person record exists with:
   - Name: Test User
   - Email: test@example.com
   - Phone: +1234567890

5. Navigate to **Leads**
6. Search for "Test User"
7. Verify Lead record exists linked to the Person

### 4.3 Check External IDs

In Chatwoot database:

```ruby
# Rails console
contact = Contact.find_by(email: 'test@example.com')
contact_inbox = contact.contact_inboxes.first
puts contact_inbox.source_id
# Should output: "krayin:person:123|krayin:lead:456"
```

## Step 5: Configure Sync Options

### 5.1 Basic Sync Options

Navigate back to **Settings** → **Integrations** → **Krayin CRM** → **Configure**

#### Sync Conversations as Activities
- **Enabled**: Creates an Activity in Krayin for each conversation
- **Use Case**: Track all customer interactions
- **Recommended**: Enable for full conversation history

#### Sync Messages as Activities
- **Enabled**: Creates an Activity for each individual message
- **Use Case**: Detailed message-level tracking
- **Recommended**: Enable only if you need granular detail (creates many activities)

#### Sync to Organizations
- **Enabled**: Creates Organization records from company attributes
- **Use Case**: B2B sales tracking company relationships
- **Recommended**: Enable if you use `company_name` custom attributes

### 5.2 Stage Progression (Advanced)

#### Enable Stage Progression
- **Enabled**: Automatically updates lead stages based on conversation lifecycle
- **Use Case**: Automate lead pipeline progression
- **Recommended**: Enable after mapping stages to your pipeline

#### Stage Configuration

Before enabling, map your Krayin pipeline stages:

1. In Krayin, navigate to **Settings** → **Lead Pipelines**
2. Note the Stage IDs for your pipeline:
   ```
   New → Stage ID: 1
   Contacted → Stage ID: 2
   Qualified → Stage ID: 3
   Won → Stage ID: 4
   ```

3. In Chatwoot integration settings:
   - **Stage on Conversation Created**: `2` (Contacted)
   - **Stage on First Response**: `3` (Qualified)
   - **Stage on Conversation Resolved**: `4` (Won)

Leave blank if you don't want that transition.

### 5.3 Save Configuration

Click **Save Settings** to apply changes.

## Step 6: Verify Sync

### 6.1 Test Contact Sync

1. Create a new contact with company data:
   ```
   Name: John Doe
   Email: john@acme.com
   Phone: +1234567890
   Custom Attributes:
     company_name: Acme Corp
     job_title: VP Sales
     lead_value: 50000
   ```

2. Check Krayin:
   - **Persons**: Verify John Doe exists
   - **Organizations**: Verify Acme Corp exists (if sync enabled)
   - **Leads**: Verify lead exists with $50,000 value

### 6.2 Test Conversation Sync

1. In Chatwoot, start a conversation with the test contact
2. Send a message: "Hi, I need help with pricing"
3. Reply as agent: "Happy to help! Let me get you pricing info."
4. Resolve the conversation

5. Check Krayin:
   - Navigate to **Activities**
   - Filter by Person: John Doe
   - Verify activity exists with conversation details
   - If stage progression enabled, check lead stage updated

### 6.3 Monitor Logs

Check Rails logs for sync confirmations:

```bash
tail -f log/production.log | grep "Krayin ProcessorService"
```

Expected output:
```
Krayin ProcessorService - Processing contact 123
Krayin ProcessorService - Contact 123 synced. Person: 456, Lead: 789
Krayin ProcessorService - Processing conversation ABC
Krayin ProcessorService - Created activity 101 for conversation ABC
```

## Advanced Configuration

### Custom Lead Values

Set dynamic lead values based on contact attributes:

```ruby
# In Rails console or custom code
contact.update(
  additional_attributes: {
    lead_value: calculate_value_from_company_size(contact),
    company_name: 'Enterprise Corp',
    company_size: 'enterprise' # Used for calculation
  }
)

def calculate_value_from_company_size(contact)
  case contact.additional_attributes&.dig('company_size')
  when 'enterprise' then 100000.0
  when 'mid_market' then 50000.0
  when 'smb' then 10000.0
  else 0.0
  end
end
```

### Multiple Inboxes

The integration supports multiple inboxes:
- Each inbox can have its own Krayin hook configuration
- Contacts are synced per inbox
- External IDs are inbox-specific

To configure:
1. Go to **Settings** → **Inboxes** → Select Inbox
2. Navigate to **Integrations** tab
3. Configure Krayin for this specific inbox

### Webhook Configuration (Future)

Currently uses Chatwoot events. Future versions may support Krayin webhooks for bi-directional sync.

## Troubleshooting

### Connection Failed

**Error**: "Unable to connect to Krayin API"

**Solutions**:
1. Verify API URL format: `https://domain.com/api/admin` (no trailing slash)
2. Check token is valid: Test with curl
3. Verify Krayin REST API package installed
4. Check firewall/network allows connection
5. Verify SSL certificate is valid

### Unauthorized Error

**Error**: "Unauthorized: Invalid API token"

**Solutions**:
1. Generate new API token
2. Verify token has required permissions
3. Check token hasn't expired
4. Ensure token belongs to admin user

### Person Created But No Lead

**Possible Causes**:
1. Missing required pipeline configuration
2. Invalid stage IDs in configuration
3. API permission issue for leads

**Solutions**:
1. Re-run setup to fetch fresh configuration
2. Verify default_pipeline_id exists in settings
3. Check Krayin user has lead creation permissions

### Organizations Not Created

**Possible Causes**:
1. "Sync to Organizations" not enabled
2. Contact missing `company_name` attribute
3. API permission issue

**Solutions**:
1. Enable "Sync to Organizations" in settings
2. Add company_name to contact attributes
3. Verify API user has organization permissions

### Stage Not Updating

**Possible Causes**:
1. "Enable Stage Progression" not enabled
2. Stage IDs don't match Krayin pipeline
3. Lead not found or permission issue

**Solutions**:
1. Enable stage progression in settings
2. Verify stage IDs in Krayin: `Settings → Pipelines`
3. Check Rails logs for specific error messages

## Performance Tips

### Optimize for Large Contact Bases

1. **Run migration**: Ensure database indexes are created
   ```bash
   rails db:migrate
   ```

2. **Monitor API usage**: Check Krayin API rate limits
3. **Batch operations**: Import existing contacts in small batches
4. **Schedule sync**: Use off-peak hours for bulk operations

### Reduce API Calls

1. Configuration automatically cached (1 hour)
2. Don't reconnect repeatedly
3. Use webhook-based events (automatic)

## Maintenance

### Regular Tasks

**Weekly**:
- Check sync status for any failures
- Review Rails logs for errors
- Verify critical contacts are syncing

**Monthly**:
- Review and cleanup test data
- Update API token if needed
- Check Krayin version for updates

**Quarterly**:
- Audit sync configuration
- Review stage progression rules
- Optimize custom attribute mappings

### Backup Recommendations

1. **Krayin Database**: Regular backups
2. **API Tokens**: Store securely (password manager)
3. **Configuration**: Document custom mappings

## Migration from Other CRMs

If migrating from another CRM integration:

1. **Export Data**: Export contacts from old CRM
2. **Disable Old Integration**: Stop old CRM sync
3. **Import to Krayin**: Use Krayin import tools
4. **Enable Integration**: Configure Chatwoot → Krayin
5. **Verify Mappings**: Check external IDs match
6. **Test Thoroughly**: Verify no duplicate records

## Next Steps

- [Krayin Custom Attributes Guide](./Krayin-Custom-Attributes) - Learn about custom attribute mapping
- [Krayin Troubleshooting](./Krayin-Troubleshooting) - Common issues and solutions
- [Krayin FAQ](./Krayin-FAQ) - Frequently asked questions

## Support Resources

- **Chatwoot Community**: [chatwoot.com/community](https://chatwoot.com/community)
- **Krayin Documentation**: [krayincrm.com/docs](https://krayincrm.com/docs)
- **GitHub Issues**: [github.com/chatwoot/chatwoot](https://github.com/chatwoot/chatwoot)

---

**Need help?** Check the [Troubleshooting Guide](./Krayin-Troubleshooting) or reach out to the community!
