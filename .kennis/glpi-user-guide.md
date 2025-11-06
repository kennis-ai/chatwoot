# GLPI Integration User Guide

## Overview

The GLPI integration for Chatwoot allows you to automatically synchronize contacts and conversations with your GLPI Service Desk instance. This integration enables:

- **Automatic Contact Sync**: Create GLPI Users or Contacts from Chatwoot contacts
- **Ticket Creation**: Automatically create GLPI tickets from conversations
- **Message Synchronization**: Sync conversation messages as GLPI ticket followups
- **Status Tracking**: Keep ticket status in sync with conversation status
- **Attachment Support**: Include attachment URLs in ticket followups

---

## Prerequisites

Before setting up the GLPI integration, ensure you have:

1. **GLPI Instance**: Running GLPI 10.0 or higher with API enabled
2. **API Access**: GLPI API enabled in Setup → General → API
3. **Tokens**: Both Application Token and User Token generated
4. **Permissions**: User account with permissions to create Users/Contacts, Tickets, and Followups
5. **Feature Flag**: The `crm_integration` feature flag enabled for your Chatwoot account

---

## Step 1: Enable GLPI API

### In GLPI Admin Panel

1. Navigate to **Setup → General → API**
2. Enable **REST API**
3. Click **Add** to generate an **Application Token**
4. Copy and save the Application Token securely

### In GLPI User Preferences

1. Navigate to **My Settings → Remote Access Keys**
2. Click **Regenerate** under **API token**
3. Copy and save the User Token securely

---

## Step 2: Enable Feature Flag in Chatwoot

The GLPI integration requires the `crm_integration` feature flag to be enabled.

### Via Rails Console

```ruby
account = Account.find_by(id: YOUR_ACCOUNT_ID)
account.enable_features('crm_integration')
```

### Via Database

```sql
UPDATE accounts
SET selected_feature_flags = selected_feature_flags || '["crm_integration"]'::jsonb
WHERE id = YOUR_ACCOUNT_ID;
```

---

## Step 3: Configure GLPI Integration

1. Log in to your Chatwoot account
2. Navigate to **Settings → Integrations**
3. Find **GLPI** in the integrations list
4. Click **Connect**

### Required Settings

#### API URL
- **Format**: `https://your-glpi-domain.com/apirest.php`
- **Example**: `https://glpi.example.com/apirest.php`
- **Note**: Must include `/apirest.php` at the end

#### App Token
- The Application Token generated in GLPI Setup → General → API
- **Example**: `abcdef123456`
- **Security**: This token is encrypted and stored securely

#### User Token
- The User Token from your GLPI user preferences
- **Example**: `xyz789abc123`
- **Security**: This token is encrypted and stored securely

### Optional Settings

#### Entity ID
- **Default**: `0` (root entity)
- **Description**: The GLPI entity ID where records will be created
- **How to find**: Check entity ID in GLPI URL when viewing an entity

#### Sync Type
- **Options**:
  - **User (Requester)**: Sync contacts as internal GLPI users
  - **Contact (External)**: Sync contacts as external GLPI contacts
- **Default**: User
- **Recommendation**: Use "User" for internal support, "Contact" for external customers

#### Ticket Type
- **Options**:
  - **1**: Incident
  - **2**: Request
- **Default**: 1 (Incident)
- **Description**: The default type for newly created tickets

#### Category ID
- **Optional**: Specify a GLPI ticket category ID
- **Example**: `5`
- **How to find**: Check category ID in GLPI Administration → Dropdowns → Categories
- **Note**: Leave blank if no default category is needed

#### Default User ID
- **Optional**: GLPI user ID for creating followups
- **Default**: `0` (system user)
- **Example**: `2`
- **Note**: Leave blank to use system default

---

## Step 4: Test the Integration

### Test 1: Contact Sync

1. Create a new contact in Chatwoot with:
   - Name: Test User
   - Email: test@example.com
   - Phone: +1234567890

2. Check GLPI to verify:
   - New User/Contact created with matching details
   - Email and phone number populated correctly

3. In Chatwoot, check contact metadata:
   ```
   Contact → Additional Attributes → External
   Should contain: glpi_user_id or glpi_contact_id
   ```

### Test 2: Ticket Creation

1. Create a conversation with the test contact
2. Add a message to the conversation
3. Check GLPI to verify:
   - New Ticket created
   - Requester matches the contact
   - Ticket title matches conversation subject
   - First message appears in ticket description

4. In Chatwoot, check conversation metadata:
   ```
   Conversation → Additional Attributes → GLPI
   Should contain: ticket_id
   ```

### Test 3: Message Sync

1. Add multiple messages to the conversation
2. Update the conversation status
3. Check GLPI ticket to verify:
   - New followups added for each message
   - Followup content matches message content
   - Sender information is correct
   - Timestamps are accurate

4. In Chatwoot, check metadata:
   ```
   Conversation → Additional Attributes → GLPI
   Should contain: last_synced_message_id
   ```

---

## Understanding the Sync Process

### Contact Synchronization

**When**: Triggered on contact creation or update

**Sync Type: User**
- Creates/updates GLPI User
- Stores `glpi_user_id` in contact metadata
- Uses User as ticket requester

**Sync Type: Contact**
- Creates/updates GLPI Contact
- Stores `glpi_contact_id` in contact metadata
- Links Contact to tickets

**What's Synced**:
- Name (split into firstname/realname)
- Email
- Phone number (formatted)

**Identifiable Contact Requirements**:
- Must have at least one of: name, email, or phone number
- Contacts without any identifier will be skipped

### Conversation Synchronization

**When**: Triggered on conversation creation or update

**First Time** (conversation.created):
1. Ensures contact is synced to GLPI
2. Creates GLPI Ticket with:
   - Requester (from contact's GLPI User/Contact ID)
   - Title (from conversation subject or first message)
   - Description (first message content)
   - Status (mapped from conversation status)
   - Priority (mapped from conversation priority)
   - Type (from integration settings)
3. Stores `ticket_id` in conversation metadata

**Subsequent Updates** (conversation.updated):
1. Updates ticket status and priority
2. Syncs new messages as followups:
   - Only syncs messages created after last sync
   - Tracks `last_synced_message_id`
   - Includes attachment URLs
   - Respects private message flag

### Message Synchronization

**What's Included**:
- Message content (plain text)
- Sender information
- Message type (incoming/outgoing)
- Private/public flag
- Attachment URLs (listed at bottom)

**Not Included**:
- Actual attachment files (only URLs provided)
- Message formatting (converted to plain text)
- Internal message metadata

---

## Status and Priority Mapping

### Conversation Status → GLPI Ticket Status

| Chatwoot Status | GLPI Status Code | GLPI Status Name |
|----------------|------------------|------------------|
| Open | 2 | Processing (assigned) |
| Pending | 4 | Pending |
| Resolved | 5 | Solved |
| Snoozed | 4 | Pending |

### Conversation Priority → GLPI Ticket Priority

| Chatwoot Priority | GLPI Priority Code | GLPI Priority Name |
|-------------------|-------------------|-------------------|
| Low | 2 | Low |
| Medium | 3 | Medium |
| High | 4 | High |
| Urgent | 5 | Very High |
| None | 3 | Medium (default) |

---

## Troubleshooting

### Connection Issues

**Problem**: "API connection failed" error

**Solutions**:
1. Verify API URL is correct and includes `/apirest.php`
2. Check that GLPI API is enabled (Setup → General → API)
3. Verify tokens are correct and not expired
4. Test connectivity from Chatwoot server to GLPI:
   ```bash
   curl -X GET 'https://your-glpi.com/apirest.php/initSession' \
     -H 'Content-Type: application/json' \
     -H 'App-Token: YOUR_APP_TOKEN' \
     -H 'Authorization: user_token YOUR_USER_TOKEN'
   ```

### Contact Not Syncing

**Problem**: Contacts created in Chatwoot don't appear in GLPI

**Solutions**:
1. Check that contact has at least one identifier (name, email, or phone)
2. Verify feature flag is enabled: `account.enabled_features.include?('crm_integration')`
3. Check Sidekiq dashboard for failed jobs: `/sidekiq`
4. Review Rails logs for errors: `tail -f log/production.log | grep GLPI`
5. Ensure GLPI user has permission to create Users/Contacts

### Tickets Not Created

**Problem**: Conversations don't create GLPI tickets

**Solutions**:
1. Verify contact was synced first (check for `glpi_user_id` or `glpi_contact_id`)
2. Check conversation has at least one message
3. Verify GLPI user has permission to create Tickets
4. Review ticket type setting (1=Incident, 2=Request)
5. Check entity ID is valid and user has access

### Messages Not Syncing as Followups

**Problem**: New messages don't appear as followups in GLPI

**Solutions**:
1. Verify ticket was created (check for `ticket_id` in conversation metadata)
2. Check that `conversation.updated` event is triggered
3. Ensure GLPI user has permission to create Followups
4. Review `last_synced_message_id` to verify sync progress
5. Check Sidekiq for queued/failed jobs

### Duplicate Records

**Problem**: Multiple GLPI Users/Contacts for same Chatwoot contact

**Solutions**:
1. Verify Redis is running and accessible
2. Check Redis mutex locks are working
3. Review Sidekiq concurrency settings
4. Manually update contact metadata with correct `glpi_user_id`
5. Delete duplicate records in GLPI

### Performance Issues

**Problem**: Slow sync or timeouts

**Solutions**:
1. Check GLPI server performance and load
2. Review network latency between Chatwoot and GLPI
3. Increase timeout settings if needed
4. Monitor Sidekiq queue length
5. Consider rate limiting if syncing many contacts

---

## Best Practices

### Contact Management

1. **Ensure Complete Information**: Add email and phone to contacts before creating conversations
2. **Choose Sync Type Carefully**: Use "User" for internal teams, "Contact" for external customers
3. **Clean Up Test Data**: Remove test contacts/tickets after testing

### Conversation Management

1. **Add Initial Message**: Always add at least one message when creating conversations
2. **Use Clear Subjects**: Conversation subjects become ticket titles
3. **Update Status**: Keep conversation status updated to reflect ticket progress
4. **Set Priority**: Use priority field to indicate urgency

### Message Management

1. **Use Private Messages**: Mark internal notes as private to prevent customer visibility in GLPI
2. **Include Context**: Provide enough context in messages for GLPI users
3. **Attachment URLs**: Remember that only attachment URLs sync, not the files themselves
4. **Plain Text**: Messages are converted to plain text in GLPI

### Monitoring

1. **Check Sidekiq**: Regularly monitor `/sidekiq` for failed jobs
2. **Review Logs**: Watch Rails logs for GLPI-related errors
3. **Verify Metadata**: Spot-check conversation metadata to ensure `ticket_id` is populated
4. **Test Regularly**: Periodically test the integration end-to-end

---

## Security Considerations

### Token Security

- **Never share tokens**: Keep App Token and User Token confidential
- **Rotate regularly**: Regenerate tokens periodically (every 90 days recommended)
- **Limit permissions**: Use a GLPI user with minimal required permissions
- **Monitor access**: Review GLPI API logs for unusual activity

### Data Privacy

- **Customer data**: Be aware that contact information syncs to GLPI
- **Message content**: All messages sync to GLPI, including private ones (marked as private)
- **Attachments**: Only URLs sync, actual files remain in Chatwoot
- **GDPR compliance**: Ensure GLPI instance complies with data protection regulations

### Network Security

- **Use HTTPS**: Always use HTTPS for API URL
- **Firewall rules**: Configure firewall to allow Chatwoot → GLPI API traffic
- **IP whitelisting**: Consider IP whitelisting in GLPI if possible
- **VPN/tunnel**: Use VPN or secure tunnel for on-premise GLPI instances

---

## Disabling or Removing the Integration

### Temporarily Disable

1. Navigate to **Settings → Integrations → GLPI**
2. Click **Edit**
3. Toggle **Status** to **Disabled**
4. Click **Update**

**Effect**: Events will no longer be processed, but configuration is preserved

### Permanently Remove

1. Navigate to **Settings → Integrations → GLPI**
2. Click **Delete**
3. Confirm deletion

**Effect**: Integration is removed, all settings deleted

**Note**: Existing GLPI records (Users, Contacts, Tickets) are NOT deleted

---

## Limitations

### Current Limitations

1. **One-way sync**: Changes in GLPI don't sync back to Chatwoot
2. **No bulk sync**: Historical data must be synced manually
3. **Attachment files**: Only URLs sync, not actual file content
4. **Single entity**: Only one entity ID per integration
5. **No custom fields**: Custom fields not supported yet

### Planned Enhancements

1. **Bidirectional sync**: GLPI → Chatwoot updates
2. **Bulk import**: Historical data synchronization
3. **Custom field mapping**: Map Chatwoot custom attributes to GLPI fields
4. **Multiple entities**: Support for multi-entity configurations
5. **Webhook support**: Real-time GLPI → Chatwoot updates

---

## FAQ

**Q: Can I use multiple GLPI integrations?**
A: No, `allow_multiple_hooks: false` in the configuration. One GLPI integration per account.

**Q: What happens if GLPI is down?**
A: Events are queued in Sidekiq and will retry automatically when GLPI is back online.

**Q: Can I change sync type after setup?**
A: Yes, but existing contacts won't be re-synced. Only new/updated contacts use the new sync type.

**Q: Are GLPI sessions cleaned up?**
A: Yes, sessions are automatically killed after each API operation to prevent session leaks.

**Q: Can I sync to multiple GLPI entities?**
A: Not currently. One integration syncs to one entity ID.

**Q: What about GLPI 9.x?**
A: Only GLPI 10.0+ is officially supported due to API changes.

**Q: Can I customize ticket categories?**
A: Yes, set the category_id in integration settings. It applies to all new tickets.

**Q: What if a contact has no email or phone?**
A: Contacts without any identifier (name, email, phone) are skipped with a "Contact not identifiable" error.

---

## Support and Resources

### Documentation

- **GLPI REST API**: https://github.com/glpi-project/glpi/blob/main/apirest.md
- **Chatwoot Integrations**: https://www.chatwoot.com/docs/product/integrations/
- **Feature Flags**: https://www.chatwoot.com/docs/self-hosted/deployment/feature-flags

### Getting Help

1. **Check logs**: Start with Rails logs and Sidekiq dashboard
2. **Test manually**: Use manual testing steps in this guide
3. **Review configuration**: Verify all settings are correct
4. **Community support**: Ask in Chatwoot community forums
5. **Report bugs**: File issues on GitHub if you find bugs

---

## Version Information

- **Integration Version**: 1.0.0
- **Supported GLPI Versions**: 10.0+
- **Supported Chatwoot Versions**: Latest
- **Last Updated**: 2025-11-05
