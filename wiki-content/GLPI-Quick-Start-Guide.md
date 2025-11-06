# GLPI Quick Start Guide

Get your GLPI integration up and running in 15 minutes.

## 🎯 What You'll Achieve

By the end of this guide:
- ✅ GLPI API enabled and configured
- ✅ API tokens generated
- ✅ Chatwoot connected to GLPI
- ✅ First conversation synced as a ticket

## ⏱️ Estimated Time

- **GLPI Configuration**: 5 minutes
- **Chatwoot Setup**: 5 minutes
- **Testing**: 5 minutes
- **Total**: 15 minutes

---

## Step 1: Configure GLPI (5 minutes)

### 1.1 Enable REST API

1. Log in to GLPI as **administrator**
2. Navigate to **Setup → General**
3. Click the **API** tab
4. Toggle **Enable REST API** to **Yes**
5. Click **Save**

**Verify**:
- Note the API URL shown: `https://your-glpi-domain.com/apirest.php`
- API should show as "Enabled"

### 1.2 Create Application Token

Still in **Setup → General → API**:

1. Scroll to **API clients** section
2. Click **Add API client**
3. Enter a name: `Chatwoot Integration`
4. Click **Add**
5. **COPY THE APP TOKEN** (shows once only!)

📋 **Save this**: `YOUR_APP_TOKEN_HERE`

### 1.3 Create User Token

1. Go to **Administration → Users**
2. Find or create a user for API access (e.g., "API Service")
3. Click on the user
4. Go to **Remote access keys** tab
5. Click **Add**
6. Enter a name: `Chatwoot API Key`
7. Click **Add**
8. **COPY THE USER TOKEN** (shows once only!)

📋 **Save this**: `YOUR_USER_TOKEN_HERE`

### 1.4 Note Entity ID (Optional)

If using multiple entities:

1. Go to **Administration → Entities**
2. Find your target entity
3. Note the entity ID from the URL: `?id=X`

Default entity ID is `0` (Root entity).

---

## Step 2: Configure Chatwoot (5 minutes)

### 2.1 Navigate to Integrations

1. Log in to Chatwoot as **administrator**
2. Go to **Settings** (⚙️ icon in sidebar)
3. Click **Integrations**
4. Find **CRM** section
5. Locate **GLPI** card

### 2.2 Connect GLPI

Click **Connect** on the GLPI card and fill in:

| Field | Value | Example |
|-------|-------|---------|
| **API Base URL** | Your GLPI API endpoint | `https://glpi.company.com/apirest.php` |
| **App Token** | From Step 1.2 | `aBcDeFgHiJkLmNoPqRsTuVwXyZ123456` |
| **User Token** | From Step 1.3 | `1234567890abcdefghijklmnopqrstuv` |

**Optional Fields**:

| Field | Description | Default |
|-------|-------------|---------|
| **Sync Messages** | Sync conversation messages as ticket followups | Disabled |
| **Entity ID** | GLPI entity for tickets | 0 (root) |
| **Category ID** | Default ticket category | None |

### 2.3 Test Connection

1. Click **Test Connection** button
2. Wait for verification
3. Should show: ✅ **Connection successful!**

**If test fails**, check:
- GLPI API is enabled
- App Token and User Token are correct
- GLPI is accessible from Chatwoot server
- No firewall blocking requests

### 2.4 Save Configuration

1. Click **Save** button
2. Integration status should show: **Connected**
3. You should see the GLPI icon with a green checkmark

---

## Step 3: Test the Integration (5 minutes)

### 3.1 Create Test Conversation

1. Go to **Conversations** in Chatwoot
2. Click **+ New Conversation** or use an existing one
3. Ensure the contact has:
   - ✅ Name
   - ✅ Email OR phone number
4. Send a message: "Test GLPI integration"

### 3.2 Verify in GLPI

1. Go to your GLPI instance
2. Navigate to **Assistance → Tickets**
3. Look for a new ticket with:
   - Title: "Test GLPI integration" (or first 50 chars)
   - Description: Full message content
   - Requester: Your contact name

✅ **Success!** If you see the ticket, integration is working.

### 3.3 Test Message Sync (Optional)

**If you enabled message sync**:

1. In Chatwoot, reply to the conversation
2. In GLPI, open the ticket
3. Check the **Followups** tab
4. Your reply should appear as a followup

### 3.4 Test Status Sync

1. In Chatwoot, resolve the conversation
2. In GLPI, refresh the ticket page
3. Ticket status should change to **Solved**

---

## 🎉 You're Done!

Your GLPI integration is now active and will:
- ✅ Sync new contacts to GLPI Users/Contacts
- ✅ Create tickets from conversations automatically
- ✅ Sync messages as followups (if enabled)
- ✅ Update ticket status when conversations resolve

---

## 📋 Quick Reference

### Chatwoot → GLPI Mapping

| Chatwoot | GLPI | Notes |
|----------|------|-------|
| Contact name | User/Contact name | Split into firstname/lastname |
| Contact email | User email | Creates User if email present |
| Contact phone | Contact phone | Creates Contact if no email |
| Conversation | Ticket | Auto-created on conversation start |
| First message | Ticket title + description | Title: first 50 chars |
| Assignee | Ticket assigned user | If agent assigned in Chatwoot |
| Status (resolved) | Ticket status (solved) | Auto-synced |
| Messages | ITILFollowup | Only if sync enabled |

### Configuration Values

```yaml
API Base URL: https://your-glpi-domain.com/apirest.php
App Token: YOUR_APP_TOKEN
User Token: YOUR_USER_TOKEN
Entity ID: 0 (default, or your entity ID)
Sync Messages: false (or true if needed)
```

---

## 🔍 Troubleshooting

### Connection Test Fails

**Error**: "Could not connect to GLPI"

**Solutions**:
1. Verify GLPI API is enabled
2. Check API URL is correct (include `/apirest.php`)
3. Verify tokens are copied correctly
4. Check network connectivity
5. Review GLPI API logs: Setup → General → Logs → API logs

### Tickets Not Creating

**Problem**: Conversations created but no GLPI tickets

**Solutions**:
1. Check Chatwoot logs: `tail -f log/production.log | grep GLPI`
2. Verify integration is enabled (green checkmark)
3. Ensure contact has email OR phone
4. Check entity ID is valid
5. Check category ID is valid (if set)
6. Verify user token has permission to create tickets

### Contact Matching Issues

**Problem**: Duplicate contacts created in GLPI

**Solutions**:
1. Integration matches by email (exact match)
2. If no email, matches by phone (exact match)
3. Ensure contacts have consistent email/phone format
4. Check for spaces or special characters in phone numbers

### Messages Not Syncing

**Problem**: Messages not appearing as followups

**Solutions**:
1. Verify "Sync Messages" is enabled in settings
2. Check ticket ID is stored in conversation attributes
3. Ensure messages have content
4. Check GLPI API logs for errors

---

## 🚀 Next Steps

Now that your integration is working:

1. **Customize Configuration**
   - Set default category for tickets
   - Configure entity IDs for multi-entity setup
   - Enable/disable message sync based on workflow

2. **Train Your Team**
   - Show agents how conversations sync to GLPI
   - Explain the contact matching behavior
   - Document your specific workflow

3. **Monitor Performance**
   - Check Chatwoot logs regularly
   - Review GLPI API logs
   - Monitor ticket creation success rate

4. **Read Full Documentation**
   - [[GLPI Integration]] - Complete feature guide
   - [[GLPI Troubleshooting]] - Common issues
   - [[GLPI Implementation Plan]] - Technical details

---

## 💡 Pro Tips

1. **Test with a dedicated contact** before rolling out to production
2. **Use consistent email formats** for better matching
3. **Enable message sync** only if you need full conversation history in GLPI
4. **Set up entity IDs** if you have multi-tenant GLPI
5. **Monitor the first week** closely to catch any issues early

---

## 📞 Need Help?

- **Documentation**: [[GLPI Integration]]
- **Troubleshooting**: [[GLPI Troubleshooting]]
- **Issues**: [GitHub Issues](https://github.com/kennis-ai/chatwoot/issues)

---

**Version**: 1.0
**Last Updated**: 2025-11-05
**Tested With**: GLPI 10.x, Chatwoot v4.7.0-kennis-ai.1.0.0
