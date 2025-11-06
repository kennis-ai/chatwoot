# Krayin CRM Custom Attributes Guide

This guide explains how to use custom attributes in Chatwoot contacts to enhance Krayin CRM synchronization.

## Overview

The Krayin integration automatically maps Chatwoot contact data to Krayin entities (Person, Lead, Organization). Custom attributes allow you to extend this mapping with additional business-specific data.

## Supported Custom Attributes

### Contact/Person Attributes

These attributes are synced to the Person entity in Krayin:

| Attribute Key | Type | Description | Krayin Field |
|--------------|------|-------------|--------------|
| `job_title` | string | Contact's job title | `job_title` |
| `company_name` | string | Company name | Used for Organization sync |
| `company` | string | Alternative company name field | Used for Organization sync |
| `organization` | string | Alternative organization field | Used for Organization sync |

### Lead Attributes

These attributes enhance Lead data in Krayin:

| Attribute Key | Type | Description | Krayin Field |
|--------------|------|-------------|--------------|
| `lead_value` | number | Estimated lead value | `lead_value` |

### Organization Attributes

These attributes are synced when `sync_to_organization` is enabled:

| Attribute Key | Type | Description | Krayin Field |
|--------------|------|-------------|--------------|
| `company_name` | string | Organization name (required) | `name` |
| `company_address` | string | Street address | `address` (part of) |
| `company_city` | string | City | `address` (part of) |
| `company_state` | string | State/Province | `address` (part of) |
| `company_country` | string | Country | `address` (part of) |
| `company_zipcode` | string | Postal/ZIP code | `address` (part of) |

## Setting Custom Attributes

### Via Chatwoot UI

1. Go to **Contacts** → Select a contact
2. Click **Edit Contact**
3. Scroll to **Custom Attributes** section
4. Add key-value pairs

### Via API

```ruby
# Ruby example
contact.update(
  additional_attributes: {
    job_title: 'Senior Developer',
    company_name: 'Acme Corp',
    company_city: 'San Francisco',
    company_country: 'USA',
    lead_value: 50000.00
  }
)
```

```http
# HTTP API example
PATCH /api/v1/accounts/{account_id}/contacts/{id}
Content-Type: application/json

{
  "custom_attributes": {
    "job_title": "Senior Developer",
    "company_name": "Acme Corp",
    "company_city": "San Francisco",
    "company_country": "USA",
    "lead_value": 50000.00
  }
}
```

### Via Webhooks

When receiving webhook data, map incoming fields to Chatwoot custom attributes:

```ruby
# Example webhook processor
def process_webhook(data)
  contact.update(
    additional_attributes: {
      job_title: data['job_title'],
      company_name: data['company']['name'],
      lead_value: calculate_lead_value(data)
    }
  )
end
```

## Custom Attribute Mapping Patterns

### Pattern 1: E-commerce Integration

```ruby
# Map e-commerce data to lead value
contact.additional_attributes = {
  lead_value: customer.lifetime_value,
  company_name: customer.company,
  order_count: customer.orders.count,
  avg_order_value: customer.average_order_value
}
```

### Pattern 2: SaaS Integration

```ruby
# Map SaaS subscription data
contact.additional_attributes = {
  lead_value: subscription.annual_value,
  company_name: account.company_name,
  plan_tier: subscription.plan,
  mrr: subscription.monthly_revenue
}
```

### Pattern 3: Form Submissions

```ruby
# Map form data to custom attributes
contact.additional_attributes = {
  company_name: form_data['company'],
  company_city: form_data['city'],
  company_country: form_data['country'],
  lead_value: estimate_value_from_company_size(form_data['employees']),
  job_title: form_data['title']
}
```

## Attribute Validation

### Required Attributes for Organization Sync

For organization sync to work, at least ONE of these must be present:
- `company_name`
- `company`
- `organization`

### Recommended Attributes

For optimal Krayin data quality, include:
- `job_title` - Helps identify decision makers
- `company_name` - Enables organization grouping
- `lead_value` - Enables pipeline value tracking

## Data Flow

### Contact Creation Flow

```
Chatwoot Contact Created
  ↓
Extract custom attributes
  ↓
Map to Person data (job_title)
  ↓
Sync to Krayin Person
  ↓
IF company_name present AND sync_to_organization enabled
  ↓
  Create/Update Organization
  ↓
  Link Person to Organization
  ↓
Map to Lead data (lead_value, custom description)
  ↓
Sync to Krayin Lead
```

### Attribute Update Flow

```
Contact Attributes Updated
  ↓
Trigger contact.updated event
  ↓
Processor checks for changes
  ↓
Update Person in Krayin
  ↓
IF organization changed
  ↓
  Update or re-link Organization
  ↓
Update Lead in Krayin
```

## Advanced Patterns

### Dynamic Lead Value Calculation

```ruby
# In ContactMapper or custom service
def extract_lead_value
  base_value = contact.additional_attributes&.dig('lead_value')
  return base_value.to_f if base_value.present?

  # Calculate from other attributes
  case contact.additional_attributes&.dig('company_size')
  when 'enterprise'
    100000.0
  when 'mid_market'
    50000.0
  when 'smb'
    10000.0
  else
    0.0
  end
end
```

### Conditional Organization Sync

```ruby
# Only sync to organization for B2B contacts
def should_sync_organization?
  return false unless sync_organizations?

  contact_type = contact.additional_attributes&.dig('contact_type')
  contact_type == 'b2b' && mapper.has_organization?
end
```

### Custom Attribute Enrichment

```ruby
# Enrich contact data before sync
def enrich_contact_attributes
  if contact.email.present?
    # Call clearbit or similar service
    enriched_data = EnrichmentService.lookup(contact.email)

    contact.update(
      additional_attributes: contact.additional_attributes.merge({
        company_name: enriched_data['company']['name'],
        company_domain: enriched_data['company']['domain'],
        job_title: enriched_data['title'],
        lead_value: estimate_value(enriched_data)
      })
    )
  end
end
```

## Troubleshooting

### Organization Not Created

**Problem**: Contact has company_name but no organization created in Krayin

**Solutions**:
1. Check `sync_to_organization` is enabled in integration settings
2. Verify company_name is not empty or whitespace
3. Check Krayin logs for organization creation errors
4. Verify API token has permission to create organizations

### Lead Value Not Syncing

**Problem**: lead_value custom attribute not appearing in Krayin

**Solutions**:
1. Ensure `lead_value` is a number, not a string
2. Check if lead_value is 0 (might be filtered by .compact)
3. Verify Lead was updated after setting lead_value

### Job Title Not Showing

**Problem**: job_title not syncing to Krayin Person

**Solutions**:
1. Check attribute key is exactly `job_title` (underscore, not camelCase)
2. Verify Person record was updated in Krayin
3. Check Krayin Person API response includes job_title field

## Best Practices

1. **Use Consistent Keys**: Always use snake_case for attribute keys
2. **Validate Data Types**: Ensure numbers are numbers, not strings
3. **Handle Missing Data**: Don't assume attributes exist; use safe navigation
4. **Document Custom Fields**: Maintain a list of custom attributes your system uses
5. **Test with Sample Data**: Always test new custom attributes with real Krayin instance
6. **Monitor Sync Logs**: Check Rails logs for sync errors and warnings
7. **Version Your Mappings**: Document which attributes map to which Krayin versions

## Example: Complete Contact Setup

```ruby
# Complete example with all supported attributes
contact = Contact.create!(
  account: account,
  name: 'John Doe',
  email: 'john.doe@acme.com',
  phone_number: '+1234567890',
  additional_attributes: {
    # Person attributes
    job_title: 'VP of Engineering',

    # Organization attributes
    company_name: 'Acme Corporation',
    company_address: '123 Main Street',
    company_city: 'San Francisco',
    company_state: 'CA',
    company_country: 'USA',
    company_zipcode: '94105',

    # Lead attributes
    lead_value: 75000.00,

    # Additional tracking (included in description)
    source_campaign: 'Q4-2024-Enterprise',
    referral_partner: 'TechPartner Inc'
  }
)

# This will sync to Krayin as:
# - Person: John Doe (VP of Engineering)
# - Organization: Acme Corporation (with full address)
# - Lead: John Doe ($75,000 value, with description including source & referral)
```

## API Reference

### Chatwoot Contact Custom Attributes API

```ruby
# Get custom attributes
contact.additional_attributes

# Set single attribute
contact.additional_attributes['key'] = 'value'
contact.save

# Merge multiple attributes
contact.update(
  additional_attributes: contact.additional_attributes.merge(new_attrs)
)

# Replace all attributes
contact.update(additional_attributes: new_attrs)
```

### Checking Sync Status

```ruby
# Get external IDs for contact
contact_inbox = contact.contact_inboxes.find_by(inbox: inbox)
source_id = contact_inbox.source_id
# Format: "krayin:person:123|krayin:lead:456|krayin:organization:789"

# Parse IDs
ids = source_id.split('|').map { |s| s.split(':') }.to_h { |a| [a[1], a[2]] }
person_id = ids['person']
lead_id = ids['lead']
organization_id = ids['organization']
```

## Future Enhancements

Planned features for custom attribute support:

- [ ] Custom attribute validation rules
- [ ] Attribute mapping configuration UI
- [ ] Bi-directional sync of custom fields from Krayin
- [ ] Attribute transformation functions
- [ ] Conditional sync rules based on attributes
- [ ] Attribute-based lead scoring
- [ ] Webhook templates for common integrations
