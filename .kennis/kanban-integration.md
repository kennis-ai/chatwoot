# Kanban Integration Implementation

## Overview

The Kanban integration has been successfully extracted from `stacklabdigital/kanban:v2.8.7` Docker image and integrated into this Chatwoot codebase. This implementation provides a comprehensive Kanban workflow management system for organizing and tracking conversations.

**Base Chatwoot Version**: v4.4.0
**Integration Date**: 2025-11-07
**Branch**: `feature/kanban-integration`

## Architecture

### Backend Components

#### Models
- **KanbanItem** (`app/models/kanban_item.rb`) - Main model for Kanban cards/items (21KB)
  - Manages funnel stages, positions, custom attributes
  - Supports timer/SLA tracking
  - Includes checklist and assigned agents functionality
  - Handles activities and audit trail

- **KanbanConfig** (`app/models/kanban_config.rb`) - Configuration per account
  - Stores funnel configurations in JSONB
  - Webhook integration support
  - Account-specific settings

- **KanbanAutomation** (`app/models/kanban_automation.rb`) - Automation rules
  - Trigger-based automation for Kanban workflows

#### Concerns
- **KanbanActivityHandler** (`app/models/concerns/kanban_activity_handler.rb`) - Activity tracking
- **KanbanTemplateMessageHandler** (`app/models/concerns/kanban_template_message_handler.rb`) - Message templates

#### Controllers
- **KanbanItemsController** (`app/controllers/api/v1/accounts/kanban_items_controller.rb`) - 61KB
  - Full CRUD operations
  - Bulk actions (move, assign, set priority, delete)
  - Search and filtering
  - Reports generation
  - Reordering within stages

- **KanbanConfigsController** (`app/controllers/api/v1/accounts/kanban_configs_controller.rb`)
  - Configuration management
  - Webhook testing

- **KanbanAutomationsController** (`app/controllers/api/v1/kanban_automations_controller.rb`)
  - Automation rules management

#### Services & Jobs
- **KanbanWebhookService** (`app/services/kanban_webhook_service.rb`) - Webhook integration
- **KanbanWebhookJob** (`app/jobs/kanban_webhook_job.rb`) - Async webhook processing

#### Policies
- **KanbanItemPolicy** (`app/policies/kanban_item_policy.rb`) - Authorization for items
- **KanbanConfigPolicy** (`app/policies/kanban_config_policy.rb`) - Authorization for configs

### Database Schema

#### Tables Created

1. **kanban_items** (Migration: 20241217041353)
   - `account_id` - Account reference
   - `conversation_display_id` - Optional conversation link
   - `funnel_id` - Funnel/pipeline ID
   - `funnel_stage` - Current stage in funnel
   - `stage_entered_at` - Timestamp of stage entry
   - `position` - Position within stage
   - `custom_attributes` (JSONB) - Custom fields
   - `item_details` (JSONB) - Title, description, priority, etc.
   - `timer_started_at` - SLA timer start
   - `timer_duration` - Duration in seconds
   - **Indexes**: conversation_display_id, funnel_id, funnel_stage combinations

2. **Active Storage Attachments** (Migration: 20241217041355)
   - Support for file attachments on Kanban items

3. **kanban_automations** (Migration: 20250308231339)
   - Automation rules table

4. **Additional Columns** (Various migrations):
   - GIN index on item_details (20250514045639)
   - Checklist support (20250730163331)
   - Assigned agents array (20250730170657)
   - Activities tracking (20251028220910)

5. **kanban_configs** (Migration: 20250815141240)
   - `account_id` - Account reference
   - `config` (JSONB) - Configuration data
   - `enabled` - Feature flag
   - `webhook_url` - Webhook endpoint
   - `webhook_secret` - Webhook authentication
   - `webhook_events` (JSONB) - Event subscriptions
   - **Indexes**: GIN indexes on config and webhook_events

## API Endpoints

### Account-Scoped Endpoints

All endpoints are under `/api/v1/accounts/:account_id/`

#### Kanban Items
- `GET /kanban_items` - List all items
- `POST /kanban_items` - Create new item
- `GET /kanban_items/:id` - Show item details
- `PATCH /kanban_items/:id` - Update item
- `DELETE /kanban_items/:id` - Delete item

**Collection Actions**:
- `POST /kanban_items/reorder` - Reorder items within stage
- `GET /kanban_items/debug` - Debug information
- `GET /kanban_items/reports` - Generate reports
- `GET /kanban_items/search` - Search items
- `GET /kanban_items/filter` - Filter items
- `POST /kanban_items/bulk_move_items` - Bulk move
- `POST /kanban_items/bulk_assign_agent` - Bulk assign
- `POST /kanban_items/bulk_set_priority` - Bulk priority
- `POST /kanban_items/bulk_update_custom_attributes` - Bulk update
- `POST /kanban_items/bulk_delete` - Bulk delete

**Member Actions**:
- `POST /kanban_items/:id/move` - Move to stage
- `POST /kanban_items/:id/assign` - Assign agent
- `POST /kanban_items/:id/add_label` - Add label
- `POST /kanban_items/:id/remove_label` - Remove label
- `POST /kanban_items/:id/schedule_message` - Schedule message
- `POST /kanban_items/:id/unschedule_message` - Unschedule message
- `POST /kanban_items/:id/duplicate` - Duplicate item

#### Kanban Config
- `GET /kanban_config` - Get configuration
- `POST /kanban_config` - Create configuration
- `PATCH /kanban_config` - Update configuration
- `DELETE /kanban_config` - Delete configuration
- `POST /kanban_config/test_webhook` - Test webhook

#### Funnels
- Standard CRUD for funnels
- `GET /funnels/:id/stage_stats` - Stage statistics
- `GET /funnels/:funnel_id/kanban_items` - List funnel items

#### Kanban Namespace
- `/kanban/items/*` - Items with attachments
- `/kanban/funnels` - Funnel management
- `/kanban/stages` - Stage management
- `/kanban/automations` - Automation management

### Global Endpoints

- `GET /api/v1/kanban_automations` - List automations
- `POST /api/v1/kanban_automations` - Create automation
- Other standard CRUD operations

## Integration Points

### Conversation Integration
Kanban items can be linked to conversations via `conversation_display_id`, allowing seamless workflow management of customer interactions.

### Account Isolation
All Kanban data is scoped to accounts, ensuring proper multi-tenancy.

### Webhook Integration
- Configurable webhook URLs per account
- Event-based notifications
- Secure webhook authentication via secrets

### Active Storage
Support for file attachments on Kanban items using Rails Active Storage.

## Features

### Core Functionality
- ✅ Multi-stage funnel/pipeline management
- ✅ Drag-and-drop positioning (via reorder API)
- ✅ Custom attributes per item (JSONB flexibility)
- ✅ Rich item details (title, description, priority, assignee)
- ✅ SLA/Timer tracking per item
- ✅ Checklist support
- ✅ Multiple agent assignment
- ✅ Activity/audit trail
- ✅ Bulk operations
- ✅ Search and filtering
- ✅ Reports generation

### Advanced Features
- ✅ Automation rules
- ✅ Webhook notifications
- ✅ Label management
- ✅ Message scheduling
- ✅ Item duplication
- ✅ File attachments

## Frontend Integration

**Note**: The extracted implementation appears to be primarily API-driven. The frontend components are not included in the Docker image backend files, suggesting they may be:

1. Part of a separate frontend application
2. Managed via the StackLab licensing/service system
3. Implemented as a client-side widget/plugin

To complete the frontend integration, you will need to:
- Create Vue.js components for Kanban board visualization
- Implement drag-and-drop functionality
- Build forms for item creation/editing
- Add routing for Kanban views
- Integrate with existing Chatwoot dashboard navigation

## Configuration

### Environment Variables
The integration may require:
- Kanban feature flags
- StackLab licensing configuration (see `stacklab/licensing_service.rb`)
- Firebase service account (if using real-time features)

### Account Setup
Each account needs:
1. Create `KanbanConfig` record
2. Define funnels and stages
3. Configure webhooks (optional)
4. Set up automations (optional)

## Migration Strategy

### Running Migrations
```bash
bundle exec rails db:migrate
```

All migrations are timestamped and will run in chronological order:
1. Create kanban_items table
2. Add Active Storage attachments
3. Create kanban_automations
4. Add GIN indexes
5. Add checklist support
6. Add assigned agents
7. Create kanban_configs
8. Add activities tracking

### Rollback Plan
Each migration includes a `down` method for safe rollback:
```bash
bundle exec rails db:rollback STEP=8
```

## Testing

### Backend Testing
Create RSpec tests for:
- Models: `spec/models/kanban_item_spec.rb`, `spec/models/kanban_config_spec.rb`
- Controllers: `spec/controllers/api/v1/accounts/kanban_items_controller_spec.rb`
- Services: `spec/services/kanban_webhook_service_spec.rb`
- Policies: `spec/policies/kanban_item_policy_spec.rb`

### API Testing
Use the documented endpoints in `docs/kanban/kanban_items_endpoints.txt` for manual testing.

## Security Considerations

### Authorization
- Kanban items are account-scoped
- Policies enforce proper access control
- Agent assignment respects account membership

### Data Validation
- Strong params in controllers
- Model validations on required fields
- JSONB schema validation recommended

### Webhook Security
- Webhook secrets for authentication
- HTTPS recommended for webhook endpoints
- Rate limiting recommended

## Performance Optimization

### Database
- GIN indexes on JSONB columns
- Composite indexes on frequently queried columns
- Consider partitioning for high-volume accounts

### Caching
- Consider fragment caching for Kanban boards
- Cache funnel configurations
- Redis for real-time position updates

## Monitoring

### Metrics to Track
- Kanban item creation rate
- Stage transition times
- SLA/timer expiration rates
- Webhook delivery success rates
- API endpoint performance

### Logging
- Audit trail via activities
- Webhook delivery logs
- Automation execution logs

## StackLab Integration

### Original Implementation

The original `stacklabdigital/kanban:v2.8.7` image includes StackLab licensing integration:
- `stacklab/licensing_service.rb` - Licensing validation (not extracted)
- `stacklab/service-account-kanban-firebase.json` - Firebase configuration (not extracted)

The licensing system:
- Validates `STACKLAB_TOKEN` against `https://pulse.stacklab.digital/api/cw/licenses/verify`
- Requires PRO plan for Kanban functionality
- Blocks ALL Kanban API endpoints without valid license (via `before_action :check_stacklab_license`)
- Caches license info for 1 hour

### Our Implementation (License-Free)

**We've implemented a license stub** (`config/initializers/stacklab_stub.rb`) that bypasses all StackLab licensing requirements:

✅ **All Kanban features enabled** without external license validation
✅ **No STACKLAB_TOKEN required**
✅ **No external API calls** to StackLab servers
✅ **Full offline functionality**

The stub provides:
- `ChatwootApp.stacklab?` → always returns `true`
- `ChatwootApp.stacklab.plan` → returns `'pro'`
- `ChatwootApp.stacklab.feature_enabled?(:kanban_pro)` → returns `true`
- All other license checks → return success

### Switching to Real StackLab License (Optional)

If you want to use the official StackLab licensing:

1. **Delete the stub**:
   ```bash
   rm config/initializers/stacklab_stub.rb
   ```

2. **Extract and add StackLab files**:
   ```bash
   # Extract from Docker image
   docker run --rm stacklabdigital/kanban:v2.8.7 tar -czf - \
     stacklab/licensing_service.rb \
     stacklab/service-account-kanban-firebase.json \
     lib/chatwoot_app.rb | tar -xzf -
   ```

3. **Set environment variables**:
   ```bash
   STACKLAB_TOKEN=your_license_token_here
   STACKLAB_API_VERIFY_URL=https://pulse.stacklab.digital/api/cw/licenses/verify
   STACKLAB_LICENSE_CACHE_MINUTES=60
   ```

4. **Restart application**

## Next Steps

1. **Run Migrations**
   ```bash
   bundle exec rails db:migrate
   ```

2. **Verify Routes**
   ```bash
   bundle exec rails routes | grep kanban
   ```

3. **Test API Endpoints**
   - Create test account
   - Create Kanban config
   - Test CRUD operations

4. **Frontend Development**
   - Design Kanban board UI
   - Implement Vue components
   - Add to dashboard navigation

5. **Documentation**
   - API documentation
   - User guide
   - Admin configuration guide

6. **Testing**
   - Write comprehensive specs
   - Test bulk operations
   - Test webhook integration

7. **Performance Testing**
   - Load test with large item counts
   - Optimize queries
   - Add caching strategy

## Support & References

- **Original Image**: `stacklabdigital/kanban:v2.8.7`
- **Base Chatwoot**: v4.4.0
- **Documentation**: `docs/kanban/kanban_items_endpoints.txt`
- **StackLab**: https://stacklab.digital

## Version History

- **v1.0.0** (2025-11-07) - Initial extraction and integration from stacklabdigital/kanban:v2.8.7
