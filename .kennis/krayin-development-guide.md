# Krayin CRM Integration - Development Guide

## Table of Contents

1. [Development Environment Setup](#development-environment-setup)
2. [Project Structure](#project-structure)
3. [Running the Integration Locally](#running-the-integration-locally)
4. [Debugging](#debugging)
5. [Adding New Features](#adding-new-features)
6. [API Client Development](#api-client-development)
7. [Mapper Development](#mapper-development)
8. [Testing Your Changes](#testing-your-changes)
9. [Code Style Guidelines](#code-style-guidelines)
10. [Common Development Tasks](#common-development-tasks)

## Development Environment Setup

### Prerequisites

```bash
# Ruby 3.2+
ruby -v

# Rails 7.0+
rails -v

# PostgreSQL
psql --version

# Redis
redis-cli --version

# Bundler
gem install bundler
```

### Local Setup

```bash
# Clone repository
git clone https://github.com/chatwoot/chatwoot.git
cd chatwoot

# Install dependencies
bundle install
yarn install

# Setup database
rails db:create db:migrate

# Setup Redis (required for mutex and caching)
redis-server

# Start Sidekiq (required for background jobs)
bundle exec sidekiq -C config/sidekiq.yml

# Start Rails server
rails server
```

### Enable Krayin Integration

```ruby
# Rails console
rails console

# Enable feature flag
account = Account.first
account.enable_features(:crm_integration)
account.save!

# Verify
account.feature_enabled?(:crm_integration)
# => true
```

### Configure Test Krayin Instance

For development, set up a local Krayin instance:

```bash
# Clone Krayin
git clone https://github.com/krayin/laravel-crm.git krayin
cd krayin

# Install dependencies
composer install
cp .env.example .env
php artisan key:generate

# Setup database
php artisan migrate
php artisan db:seed

# Install REST API package
composer require krayin/rest-api
php artisan migrate
php artisan optimize:clear

# Start server
php artisan serve
# Krayin available at: http://localhost:8000
```

### Generate API Token

```bash
php artisan tinker

# In Tinker console
$user = \Webkul\User\Models\Admin::first();
$token = $user->createToken('Development')->plainTextToken;
echo $token;
```

## Project Structure

```
app/services/crm/krayin/
├── api/
│   ├── base_client.rb          # HTTP client with retry logic
│   ├── person_client.rb        # Person API operations
│   ├── lead_client.rb          # Lead API operations
│   ├── organization_client.rb  # Organization API operations
│   └── activity_client.rb      # Activity API operations
├── mappers/
│   ├── contact_mapper.rb       # Contact → Person/Lead mapping
│   ├── conversation_mapper.rb  # Conversation → Activity mapping
│   └── message_mapper.rb       # Message → Activity mapping
├── processor_service.rb        # Main orchestrator
├── setup_service.rb            # Configuration fetch & cache
├── person_finder_service.rb    # Person lookup by email
└── lead_finder_service.rb      # Lead lookup by person

spec/services/crm/krayin/
├── api/
│   ├── base_client_spec.rb
│   ├── person_client_spec.rb
│   ├── lead_client_spec.rb
│   ├── organization_client_spec.rb
│   └── activity_client_spec.rb
├── mappers/
│   ├── contact_mapper_spec.rb
│   ├── conversation_mapper_spec.rb
│   └── message_mapper_spec.rb
├── processor_service_spec.rb
├── setup_service_spec.rb
├── person_finder_service_spec.rb
└── lead_finder_service_spec.rb

config/integration/
└── apps.yml                     # Integration configuration

db/migrate/
└── *_optimize_krayin_lookups.rb # Performance indexes
```

## Running the Integration Locally

### 1. Configure Integration via UI

```
1. Login to Chatwoot: http://localhost:3000
2. Navigate to Settings → Integrations
3. Find "Krayin CRM"
4. Click "Configure"
5. Enter:
   - API URL: http://localhost:8000/api/admin
   - API Token: [token from setup]
6. Click "Connect"
```

### 2. Verify Connection

Check Rails logs:

```bash
tail -f log/development.log | grep Krayin
```

Expected output:
```
Krayin SetupService - Fetching configuration from http://localhost:8000/api/admin
Krayin SetupService - Successfully fetched configuration
```

### 3. Test Contact Sync

```ruby
# Rails console
contact = Contact.create!(
  account: Account.first,
  name: 'Test Developer',
  email: 'dev@test.com',
  phone_number: '+1234567890',
  inbox: Inbox.first
)

# Check logs for sync
# Check Krayin for Person/Lead creation
```

### 4. Monitor Background Jobs

```bash
# Watch Sidekiq
bundle exec sidekiq -C config/sidekiq.yml -v

# Or use Sidekiq Web UI
# Visit: http://localhost:3000/sidekiq
```

## Debugging

### Enable Debug Logging

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.log_level = :debug
end
```

### Debug Specific Service

```ruby
# Add to service
Rails.logger.debug "[Krayin] Processing contact: #{contact.inspect}"
Rails.logger.debug "[Krayin] API Response: #{response.body}"
```

### Debug API Calls

```ruby
# In API client
def log_request(method, url, body)
  Rails.logger.debug "[Krayin API] #{method.upcase} #{url}"
  Rails.logger.debug "[Krayin API] Body: #{body.to_json}" if body
end

def log_response(response)
  Rails.logger.debug "[Krayin API] Status: #{response.code}"
  Rails.logger.debug "[Krayin API] Body: #{response.body}"
end
```

### Use Rails Console

```ruby
rails console

# Test processor directly
processor = Crm::Krayin::ProcessorService.new(
  inbox: Inbox.first,
  event_name: 'contact.created',
  event_data: { contact: Contact.first }
)
processor.perform

# Test mapper
mapper = Crm::Krayin::Mappers::ContactMapper.new(Contact.first)
mapper.map_to_person
# => { name: "...", emails: [...], ... }

# Test API client
client = Crm::Krayin::Api::PersonClient.new(
  'http://localhost:8000/api/admin',
  'your-token'
)
client.find_person_by_email('test@example.com')
```

### Debug with Pry

```ruby
# Add to Gemfile
gem 'pry-rails'
gem 'pry-byebug'

# In code
require 'pry'
binding.pry  # Execution stops here
```

### Check Redis Mutex

```bash
redis-cli

# Check for locks
KEYS "mutex:krayin:*"

# View lock details
GET "mutex:krayin:process:contact:123"

# Clear stuck lock (if needed)
DEL "mutex:krayin:process:contact:123"
```

### Inspect WebMock Stubs (Tests)

```ruby
# In test
WebMock.after_request do |request_signature, response|
  puts "Request: #{request_signature}"
  puts "Response: #{response.body}"
end
```

## Adding New Features

### Example: Add Custom Field Mapping

**1. Update Mapper**

```ruby
# app/services/crm/krayin/mappers/contact_mapper.rb

def map_to_person
  {
    name: contact.name,
    emails: format_emails,
    contact_numbers: format_phones,
    job_title: extract_attribute('job_title'),
    # Add new field
    department: extract_attribute('department')
  }.compact
end
```

**2. Update Tests**

```ruby
# spec/services/crm/krayin/mappers/contact_mapper_spec.rb

it 'maps department from additional attributes' do
  contact.additional_attributes = { 'department' => 'Engineering' }
  person_data = mapper.map_to_person

  expect(person_data[:department]).to eq('Engineering')
end
```

**3. Update Documentation**

```markdown
# In Wiki: Krayin-Custom-Attributes.md

| Chatwoot Attribute | Krayin Field | Type | Example |
|--------------------|--------------|------|---------|
| department | department | String | Engineering |
```

### Example: Add New API Client Method

**1. Add Method to Client**

```ruby
# app/services/crm/krayin/api/person_client.rb

def search_persons(query)
  params = { search: query }
  request_with_retry(:get, '/persons', nil, params)
end
```

**2. Add Tests**

```ruby
# spec/services/crm/krayin/api/person_client_spec.rb

describe '#search_persons' do
  it 'searches persons by query' do
    stub_request(:get, "#{api_url}/persons")
      .with(query: { search: 'John' })
      .to_return(
        status: 200,
        body: { data: [{ id: 1, name: 'John Doe' }] }.to_json
      )

    result = client.search_persons('John')
    expect(result['data']).to be_an(Array)
    expect(result['data'].first['name']).to eq('John Doe')
  end
end
```

**3. Use in Service**

```ruby
# app/services/crm/krayin/processor_service.rb

def find_or_create_person
  # Try exact email match first
  person = person_finder.find_by_email(contact.email)
  return person if person

  # Try fuzzy search by name
  person_client = Crm::Krayin::Api::PersonClient.new(api_url, api_token)
  results = person_client.search_persons(contact.name)

  # Use first result or create new
  results['data'].first || create_person
end
```

## API Client Development

### Creating a New Client

```ruby
# app/services/crm/krayin/api/custom_client.rb

module Crm
  module Krayin
    module Api
      class CustomClient < BaseClient
        # GET /custom-endpoint
        def get_custom_data(params = {})
          request_with_retry(:get, '/custom-endpoint', nil, params)
        end

        # POST /custom-endpoint
        def create_custom_data(data)
          request_with_retry(:post, '/custom-endpoint', data)
        end

        # PUT /custom-endpoint/:id
        def update_custom_data(data, id)
          request_with_retry(:put, "/custom-endpoint/#{id}", data)
        end

        # DELETE /custom-endpoint/:id
        def delete_custom_data(id)
          request_with_retry(:delete, "/custom-endpoint/#{id}")
        end
      end
    end
  end
end
```

### Best Practices

1. **Always extend BaseClient** - Inherit retry logic and error handling
2. **Use request_with_retry** - Don't call HTTP methods directly
3. **Log important operations** - Add debug logging for troubleshooting
4. **Handle nil responses** - API might return nil for 404s
5. **Document parameters** - Add comments for complex parameters
6. **Test all methods** - Include success and error cases

### Error Handling

```ruby
def create_entity(data)
  request_with_retry(:post, '/entities', data)
rescue Crm::Krayin::Api::BaseClient::ApiError => e
  Rails.logger.error "Failed to create entity: #{e.message}"
  # Re-raise for processor to handle
  raise
end
```

## Mapper Development

### Creating a New Mapper

```ruby
# app/services/crm/krayin/mappers/custom_mapper.rb

module Crm
  module Krayin
    module Mappers
      class CustomMapper
        attr_reader :source_object

        def initialize(source_object)
          @source_object = source_object
        end

        def map_to_krayin
          {
            field1: extract_field1,
            field2: extract_field2,
            # Nested data
            nested: {
              sub_field: extract_nested
            }
          }.compact  # Remove nil values
        end

        private

        def extract_field1
          source_object.attribute1 || default_value
        end

        def extract_field2
          # Transform data
          source_object.attribute2&.upcase
        end

        def extract_nested
          source_object.additional_attributes&.dig('custom_field')
        end

        def default_value
          'Default'
        end
      end
    end
  end
end
```

### Mapper Best Practices

1. **Use compact** - Remove nil values before sending to API
2. **Provide defaults** - Use `||` for required fields
3. **Safe navigation** - Use `&.` for optional attributes
4. **Extract methods** - Keep map methods clean with private helpers
5. **Type coercion** - Convert types as needed (String, Integer, Boolean)
6. **Format consistency** - E.164 for phones, standard email format

### Testing Mappers

```ruby
# spec/services/crm/krayin/mappers/custom_mapper_spec.rb

RSpec.describe Crm::Krayin::Mappers::CustomMapper do
  let(:source_object) do
    double(
      attribute1: 'Value 1',
      attribute2: 'value 2',
      additional_attributes: { 'custom_field' => 'Custom' }
    )
  end
  let(:mapper) { described_class.new(source_object) }

  describe '#map_to_krayin' do
    it 'maps all fields correctly' do
      result = mapper.map_to_krayin

      expect(result[:field1]).to eq('Value 1')
      expect(result[:field2]).to eq('VALUE 2')
      expect(result[:nested][:sub_field]).to eq('Custom')
    end

    it 'uses default for missing field1' do
      allow(source_object).to receive(:attribute1).and_return(nil)
      result = mapper.map_to_krayin

      expect(result[:field1]).to eq('Default')
    end

    it 'removes nil values' do
      allow(source_object).to receive(:additional_attributes).and_return(nil)
      result = mapper.map_to_krayin

      expect(result.key?(:nested)).to be false
    end
  end
end
```

## Testing Your Changes

### Run All Krayin Tests

```bash
# All Krayin specs
bundle exec rspec spec/services/crm/krayin/

# Specific file
bundle exec rspec spec/services/crm/krayin/processor_service_spec.rb

# Specific test
bundle exec rspec spec/services/crm/krayin/processor_service_spec.rb:45
```

### Test with Coverage

```bash
# Install SimpleCov
# Gemfile
gem 'simplecov', require: false

# spec/spec_helper.rb
require 'simplecov'
SimpleCov.start 'rails'

# Run tests with coverage
COVERAGE=true bundle exec rspec spec/services/crm/krayin/

# View coverage report
open coverage/index.html
```

### Integration Testing

```ruby
# spec/integration/krayin_integration_spec.rb

RSpec.describe 'Krayin Integration', type: :integration do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:hook) { create(:integrations_hook, :krayin, inbox: inbox) }

  before do
    account.enable_features(:crm_integration)
    stub_krayin_api_requests
  end

  it 'syncs contact to Krayin' do
    contact = create(:contact, account: account, inbox: inbox)

    expect(WebMock).to have_requested(:post, /persons/)
    expect(WebMock).to have_requested(:post, /leads/)

    contact_inbox = contact.contact_inboxes.first
    expect(contact_inbox.source_id).to include('krayin:person:')
    expect(contact_inbox.source_id).to include('krayin:lead:')
  end

  it 'syncs conversation to Krayin' do
    contact = create(:contact, account: account, inbox: inbox)
    conversation = create(:conversation, contact: contact, inbox: inbox)

    expect(WebMock).to have_requested(:post, /activities/)

    contact_inbox = contact.contact_inboxes.first
    expect(contact_inbox.source_id).to include('krayin:activity:')
  end
end
```

## Code Style Guidelines

### Ruby Style

Follow Chatwoot's RuboCop configuration:

```bash
# Check style
bundle exec rubocop app/services/crm/krayin/

# Auto-fix
bundle exec rubocop -a app/services/crm/krayin/
```

### Key Guidelines

1. **Line Length**: Max 150 characters
2. **Module Nesting**: Use compact style
   ```ruby
   # Good
   module Crm::Krayin::Api
     class PersonClient < BaseClient
   ```

3. **Method Length**: Keep methods under 25 lines
4. **Class Length**: Keep classes under 200 lines
5. **Comments**: Document public methods with RDoc
   ```ruby
   # Creates or updates a person in Krayin
   #
   # @param data [Hash] Person data to sync
   # @return [Hash] Created/updated person
   # @raise [ApiError] If API request fails
   def sync_person(data)
   ```

6. **Error Messages**: Be specific and actionable
   ```ruby
   raise ApiError, "Invalid email format: #{email}. Expected format: user@domain.com"
   ```

## Common Development Tasks

### Add New Event Handler

```ruby
# app/services/crm/krayin/processor_service.rb

def perform
  case @event_name
  when 'contact.created', 'contact.updated'
    process_contact
  when 'conversation.created', 'conversation.updated'
    process_conversation
  when 'message.created'
    process_message
  when 'custom.event'  # Add new event
    process_custom_event
  else
    Rails.logger.info "Krayin ProcessorService - Ignoring event: #{@event_name}"
  end
end

private

def process_custom_event
  # Implementation
  Rails.logger.info "Processing custom event: #{@event_data.inspect}"
end
```

### Add Configuration Option

**1. Update apps.yml**

```yaml
# config/integration/apps.yml
krayin:
  settings_json_schema:
    properties:
      'new_option': { 'type': 'boolean' }

  settings_form_schema:
    - {
        'label': 'Enable New Feature',
        'type': 'checkbox',
        'name': 'new_option',
        'help': 'Description of what this does',
      }
```

**2. Use in Service**

```ruby
def new_feature_enabled?
  @hook.settings['new_option'] == true
end

def process_with_new_feature
  return unless new_feature_enabled?

  # Implementation
end
```

### Add Database Migration

```bash
rails generate migration AddKrayinFieldToContacts krayin_field:string

# Edit migration
class AddKrayinFieldToContacts < ActiveRecord::Migration[7.0]
  def change
    add_column :contacts, :krayin_field, :string
    add_index :contacts, :krayin_field
  end
end

# Run migration
rails db:migrate
```

### Update External ID Format

```ruby
# app/services/crm/krayin/processor_service.rb

def update_external_ids(contact_inbox, person_id, lead_id, org_id = nil, activity_id = nil)
  ids = []
  ids << "krayin:person:#{person_id}" if person_id
  ids << "krayin:lead:#{lead_id}" if lead_id
  ids << "krayin:organization:#{org_id}" if org_id
  ids << "krayin:activity:#{activity_id}" if activity_id

  contact_inbox.update!(source_id: ids.join('|'))
end

def extract_id(source_id, type)
  return nil unless source_id

  match = source_id.match(/krayin:#{type}:(\d+)/)
  match ? match[1].to_i : nil
end
```

### Clear Cache

```ruby
# Rails console

# Clear all Krayin caches
Rails.cache.delete_matched("krayin:*")

# Clear specific setup cache
cache_key = "krayin:setup:#{Digest::MD5.hexdigest(api_url)}"
Rails.cache.delete(cache_key)
```

## Troubleshooting Development Issues

### Hook Not Firing

```ruby
# Check hook status
hook = Integrations::Hook.find_by(app_id: 'krayin', inbox: inbox)
hook.status  # Should be 'enabled'

# Re-enable if disabled
hook.update!(status: 'enabled')
```

### Background Job Not Processing

```bash
# Check Sidekiq is running
ps aux | grep sidekiq

# Check queue
redis-cli LLEN queue:medium

# Process job manually
job_class = HookJob
job_args = [hook.id, 'contact.created', { contact: contact }]
job_class.perform_now(*job_args)
```

### API Connection Issues

```bash
# Test connection
curl -X GET http://localhost:8000/api/admin/leads/pipelines \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"

# Check Krayin logs
tail -f krayin/storage/logs/laravel.log

# Verify REST API package
cd krayin
composer show krayin/rest-api
```

### Database Issues

```sql
-- Check external IDs
SELECT * FROM contact_inboxes WHERE source_id LIKE 'krayin:%';

-- Check hooks
SELECT * FROM integrations_hooks WHERE app_id = 'krayin';

-- Find orphaned records
SELECT c.* FROM contacts c
LEFT JOIN contact_inboxes ci ON c.id = ci.contact_id
WHERE ci.source_id IS NULL OR ci.source_id NOT LIKE 'krayin:%';
```

## Resources

- [Krayin API Documentation](https://docs.krayincrm.com/1.x/api/)
- [HTTParty Documentation](https://github.com/jnunemaker/httparty)
- [RSpec Best Practices](https://rspec.info/documentation/)
- [WebMock Usage](https://github.com/bblimke/webmock)
- [Sidekiq Documentation](https://github.com/mperham/sidekiq/wiki)

## Getting Help

- **Code Review**: Submit PR with detailed description
- **Debugging**: Use Rails console and debug logs
- **Testing**: Run full test suite before submitting
- **Questions**: Ask in Chatwoot developer community

---

**Happy Coding!** 🚀
