# Krayin CRM Integration - Testing Guide

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Test Setup](#test-setup)
3. [Unit Testing](#unit-testing)
4. [Integration Testing](#integration-testing)
5. [API Client Testing](#api-client-testing)
6. [Mapper Testing](#mapper-testing)
7. [Service Testing](#service-testing)
8. [WebMock Usage](#webmock-usage)
9. [Test Factories](#test-factories)
10. [Coverage Requirements](#coverage-requirements)
11. [Common Testing Patterns](#common-testing-patterns)
12. [Debugging Tests](#debugging-tests)

## Testing Philosophy

### Goals

- **Confidence**: Tests ensure code works as intended
- **Documentation**: Tests serve as usage examples
- **Regression Prevention**: Tests catch breaking changes
- **Fast Feedback**: Tests run quickly in development

### Principles

1. **Test Behavior, Not Implementation**: Focus on what code does, not how
2. **One Assertion Per Test**: Keep tests focused and clear
3. **Arrange-Act-Assert**: Structure tests consistently
4. **DRY But Readable**: Balance repetition vs clarity
5. **Fast Tests**: Mock external dependencies

## Test Setup

### Install Dependencies

```ruby
# Gemfile (test group)
group :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'webmock'
  gem 'simplecov'
  gem 'shoulda-matchers'
end
```

```bash
bundle install
```

### Configure RSpec

```ruby
# spec/rails_helper.rb

require 'webmock/rspec'

RSpec.configure do |config|
  # Factory Bot
  config.include FactoryBot::Syntax::Methods

  # Disable external HTTP requests
  WebMock.disable_net_connect!(allow_localhost: true)

  # Clear cache before each test
  config.before(:each) do
    Rails.cache.clear
  end
end
```

### Configure SimpleCov

```ruby
# spec/spec_helper.rb

require 'simplecov'
SimpleCov.start 'rails' do
  add_filter '/spec/'
  add_filter '/config/'
  add_group 'Krayin Integration', 'app/services/crm/krayin'

  minimum_coverage 90
  minimum_coverage_by_file 80
end
```

## Unit Testing

### Testing a Simple Method

```ruby
# spec/services/crm/krayin/mappers/contact_mapper_spec.rb

RSpec.describe Crm::Krayin::Mappers::ContactMapper do
  let(:contact) do
    build(:contact,
      name: 'John Doe',
      email: 'john@example.com',
      phone_number: '+1234567890'
    )
  end
  let(:mapper) { described_class.new(contact) }

  describe '#map_to_person' do
    it 'maps name correctly' do
      result = mapper.map_to_person
      expect(result[:name]).to eq('John Doe')
    end

    it 'formats emails as array' do
      result = mapper.map_to_person
      expect(result[:emails]).to eq([
        { value: 'john@example.com', label: 'work' }
      ])
    end

    it 'formats phone numbers as array' do
      result = mapper.map_to_person
      expect(result[:contact_numbers]).to eq([
        { value: '+1234567890', label: 'work' }
      ])
    end
  end
end
```

### Testing Edge Cases

```ruby
describe '#map_to_person' do
  context 'when contact has no email' do
    let(:contact) { build(:contact, email: nil, phone_number: '+1234567890') }

    it 'returns nil for emails' do
      result = mapper.map_to_person
      expect(result[:emails]).to be_nil
    end
  end

  context 'when contact has no phone' do
    let(:contact) { build(:contact, email: 'john@example.com', phone_number: nil) }

    it 'returns nil for contact_numbers' do
      result = mapper.map_to_person
      expect(result[:contact_numbers]).to be_nil
    end
  end

  context 'when contact has no email or phone' do
    let(:contact) { build(:contact, email: nil, phone_number: nil) }

    it 'still includes name' do
      result = mapper.map_to_person
      expect(result[:name]).to eq(contact.name)
      expect(result[:emails]).to be_nil
      expect(result[:contact_numbers]).to be_nil
    end
  end
end
```

### Testing Custom Attributes

```ruby
describe '#map_to_person' do
  context 'with job_title attribute' do
    before do
      contact.additional_attributes = { 'job_title' => 'VP Engineering' }
    end

    it 'includes job_title' do
      result = mapper.map_to_person
      expect(result[:job_title]).to eq('VP Engineering')
    end
  end

  context 'without job_title attribute' do
    it 'does not include job_title' do
      result = mapper.map_to_person
      expect(result.key?(:job_title)).to be false
    end
  end
end
```

## Integration Testing

### Full Contact Sync Flow

```ruby
# spec/integration/krayin_contact_sync_spec.rb

RSpec.describe 'Krayin Contact Sync', type: :integration do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:hook) do
    create(:integrations_hook,
      app_id: 'krayin',
      inbox: inbox,
      settings: {
        'api_url' => 'http://krayin.test/api/admin',
        'api_token' => 'test-token',
        'default_pipeline_id' => 1,
        'default_stage_id' => 1
      }
    )
  end

  before do
    account.enable_features(:crm_integration)
    stub_krayin_setup_requests
    stub_krayin_person_requests
    stub_krayin_lead_requests
  end

  describe 'contact creation' do
    it 'creates person and lead in Krayin' do
      contact = create(:contact,
        account: account,
        inbox: inbox,
        name: 'Test User',
        email: 'test@example.com',
        phone_number: '+1234567890'
      )

      # Verify API calls were made
      expect(WebMock).to have_requested(:post, "#{hook.settings['api_url']}/persons")
        .with(body: hash_including(
          name: 'Test User',
          emails: [{ value: 'test@example.com', label: 'work' }]
        ))

      expect(WebMock).to have_requested(:post, "#{hook.settings['api_url']}/leads")
        .with(body: hash_including(
          title: 'Test User',
          person_id: 123
        ))

      # Verify external IDs stored
      contact_inbox = contact.contact_inboxes.find_by(inbox: inbox)
      expect(contact_inbox.source_id).to include('krayin:person:123')
      expect(contact_inbox.source_id).to include('krayin:lead:456')
    end
  end

  describe 'contact update' do
    let(:contact) do
      create(:contact,
        account: account,
        inbox: inbox,
        name: 'Original Name',
        email: 'original@example.com'
      )
    end

    before do
      contact.contact_inboxes.find_by(inbox: inbox).update!(
        source_id: 'krayin:person:123|krayin:lead:456'
      )
    end

    it 'updates existing person and lead' do
      stub_krayin_update_requests

      contact.update!(name: 'Updated Name', email: 'updated@example.com')

      expect(WebMock).to have_requested(:put, "#{hook.settings['api_url']}/persons/123")
        .with(body: hash_including(
          name: 'Updated Name',
          emails: [{ value: 'updated@example.com', label: 'work' }]
        ))

      expect(WebMock).to have_requested(:put, "#{hook.settings['api_url']}/leads/456")
        .with(body: hash_including(
          title: 'Updated Name'
        ))
    end
  end
end
```

### Full Conversation Sync Flow

```ruby
# spec/integration/krayin_conversation_sync_spec.rb

RSpec.describe 'Krayin Conversation Sync', type: :integration do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:hook) do
    create(:integrations_hook,
      app_id: 'krayin',
      inbox: inbox,
      settings: {
        'api_url' => 'http://krayin.test/api/admin',
        'api_token' => 'test-token',
        'sync_conversations' => true
      }
    )
  end
  let(:contact) { create(:contact, account: account, inbox: inbox) }

  before do
    account.enable_features(:crm_integration)
    contact.contact_inboxes.find_by(inbox: inbox).update!(
      source_id: 'krayin:person:123|krayin:lead:456'
    )
    stub_krayin_activity_requests
  end

  it 'creates activity for conversation' do
    conversation = create(:conversation,
      contact: contact,
      inbox: inbox,
      display_id: 789
    )

    expect(WebMock).to have_requested(:post, "#{hook.settings['api_url']}/activities")
      .with(body: hash_including(
        title: 'Conversation #789',
        type: 'note',
        person_id: 123,
        is_done: false
      ))

    contact_inbox = contact.contact_inboxes.find_by(inbox: inbox)
    expect(contact_inbox.source_id).to include('krayin:activity:101')
  end
end
```

## API Client Testing

### Testing Successful Requests

```ruby
# spec/services/crm/krayin/api/person_client_spec.rb

RSpec.describe Crm::Krayin::Api::PersonClient do
  let(:api_url) { 'http://krayin.test/api/admin' }
  let(:api_token) { 'test-token' }
  let(:client) { described_class.new(api_url, api_token) }

  describe '#create_person' do
    let(:person_data) do
      {
        name: 'John Doe',
        emails: [{ value: 'john@example.com', label: 'work' }]
      }
    end

    context 'successful creation' do
      before do
        stub_request(:post, "#{api_url}/persons")
          .with(
            headers: {
              'Authorization' => "Bearer #{api_token}",
              'Content-Type' => 'application/json',
              'Accept' => 'application/json'
            },
            body: person_data.to_json
          )
          .to_return(
            status: 201,
            body: { data: { id: 123, name: 'John Doe' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'sends correct request' do
        result = client.create_person(person_data)
        expect(result['data']['id']).to eq(123)
      end

      it 'returns parsed JSON' do
        result = client.create_person(person_data)
        expect(result).to be_a(Hash)
        expect(result['data']).to be_a(Hash)
      end
    end
  end
end
```

### Testing Error Handling

```ruby
describe '#create_person' do
  context 'with API error' do
    before do
      stub_request(:post, "#{api_url}/persons")
        .to_return(status: 500, body: 'Internal Server Error')
    end

    it 'raises ApiError' do
      expect {
        client.create_person(person_data)
      }.to raise_error(Crm::Krayin::Api::BaseClient::ApiError, /500/)
    end
  end

  context 'with authentication error' do
    before do
      stub_request(:post, "#{api_url}/persons")
        .to_return(
          status: 401,
          body: { message: 'Unauthorized' }.to_json
        )
    end

    it 'raises ApiError with authentication message' do
      expect {
        client.create_person(person_data)
      }.to raise_error(
        Crm::Krayin::Api::BaseClient::ApiError,
        /Unauthorized/
      )
    end
  end

  context 'with validation error' do
    before do
      stub_request(:post, "#{api_url}/persons")
        .to_return(
          status: 422,
          body: {
            message: 'Validation failed',
            errors: { email: ['Email is required'] }
          }.to_json
        )
    end

    it 'raises ApiError with validation details' do
      expect {
        client.create_person(person_data)
      }.to raise_error(
        Crm::Krayin::Api::BaseClient::ApiError,
        /Validation failed.*email/
      )
    end
  end
end
```

### Testing Retry Logic

```ruby
describe '#create_person with retry' do
  context 'when rate limited' do
    before do
      @attempt = 0
      stub_request(:post, "#{api_url}/persons")
        .to_return do
          @attempt += 1
          if @attempt == 1
            { status: 429, headers: { 'Retry-After' => '2' } }
          else
            { status: 201, body: { data: { id: 123 } }.to_json }
          end
        end
    end

    it 'retries and succeeds' do
      result = client.create_person(person_data)
      expect(result['data']['id']).to eq(123)
      expect(@attempt).to eq(2)
    end
  end

  context 'when temporary server error' do
    before do
      @attempt = 0
      stub_request(:post, "#{api_url}/persons")
        .to_return do
          @attempt += 1
          if @attempt < 3
            { status: 503 }
          else
            { status: 201, body: { data: { id: 123 } }.to_json }
          end
        end
    end

    it 'retries up to 3 times' do
      result = client.create_person(person_data)
      expect(result['data']['id']).to eq(123)
      expect(@attempt).to eq(3)
    end
  end

  context 'when max retries exceeded' do
    before do
      stub_request(:post, "#{api_url}/persons")
        .to_return(status: 503)
    end

    it 'raises error after max retries' do
      expect {
        client.create_person(person_data)
      }.to raise_error(Crm::Krayin::Api::BaseClient::ApiError)
    end
  end
end
```

## Mapper Testing

### Testing Basic Mapping

```ruby
# spec/services/crm/krayin/mappers/contact_mapper_spec.rb

RSpec.describe Crm::Krayin::Mappers::ContactMapper do
  let(:contact) { build(:contact) }
  let(:mapper) { described_class.new(contact) }

  describe '#map_to_person' do
    subject { mapper.map_to_person }

    it 'returns a hash' do
      expect(subject).to be_a(Hash)
    end

    it 'includes required fields' do
      expect(subject).to include(:name)
    end

    it 'excludes nil values' do
      expect(subject.values).not_to include(nil)
    end
  end
end
```

### Testing Data Transformation

```ruby
describe '#format_emails' do
  context 'with valid email' do
    let(:contact) { build(:contact, email: 'test@example.com') }

    it 'formats as Krayin expects' do
      result = mapper.send(:format_emails)
      expect(result).to eq([
        { value: 'test@example.com', label: 'work' }
      ])
    end
  end

  context 'with nil email' do
    let(:contact) { build(:contact, email: nil) }

    it 'returns nil' do
      result = mapper.send(:format_emails)
      expect(result).to be_nil
    end
  end

  context 'with blank email' do
    let(:contact) { build(:contact, email: '') }

    it 'returns nil' do
      result = mapper.send(:format_emails)
      expect(result).to be_nil
    end
  end
end

describe '#format_phones' do
  context 'with E.164 format' do
    let(:contact) { build(:contact, phone_number: '+1234567890') }

    it 'formats as Krayin expects' do
      result = mapper.send(:format_phones)
      expect(result).to eq([
        { value: '+1234567890', label: 'work' }
      ])
    end
  end

  context 'with invalid format' do
    let(:contact) { build(:contact, phone_number: 'invalid') }

    it 'still includes the number' do
      result = mapper.send(:format_phones)
      expect(result).to eq([
        { value: 'invalid', label: 'work' }
      ])
    end
  end
end
```

### Testing Lead Mapping with Settings

```ruby
describe '#map_to_lead' do
  let(:person_id) { 123 }
  let(:settings) do
    {
      'default_pipeline_id' => 1,
      'default_stage_id' => 2,
      'default_source_id' => 3,
      'default_type_id' => 4
    }
  end

  subject { mapper.map_to_lead(person_id, settings) }

  it 'includes person_id' do
    expect(subject[:person_id]).to eq(123)
  end

  it 'includes title from contact name' do
    expect(subject[:title]).to eq(contact.name)
  end

  it 'includes pipeline configuration' do
    expect(subject[:lead_pipeline_id]).to eq(1)
    expect(subject[:lead_pipeline_stage_id]).to eq(2)
    expect(subject[:lead_source_id]).to eq(3)
    expect(subject[:lead_type_id]).to eq(4)
  end

  context 'with lead_value attribute' do
    before do
      contact.additional_attributes = { 'lead_value' => 50000 }
    end

    it 'includes lead_value' do
      expect(subject[:lead_value]).to eq(50000.0)
    end
  end

  context 'without lead_value attribute' do
    it 'defaults to 0' do
      expect(subject[:lead_value]).to eq(0.0)
    end
  end
end
```

## Service Testing

### Testing ProcessorService

```ruby
# spec/services/crm/krayin/processor_service_spec.rb

RSpec.describe Crm::Krayin::ProcessorService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:hook) do
    create(:integrations_hook,
      app_id: 'krayin',
      inbox: inbox,
      settings: settings
    )
  end
  let(:settings) do
    {
      'api_url' => 'http://krayin.test/api/admin',
      'api_token' => 'test-token',
      'default_pipeline_id' => 1,
      'default_stage_id' => 1
    }
  end
  let(:contact) { create(:contact, account: account, inbox: inbox) }

  before do
    account.enable_features(:crm_integration)
    stub_krayin_requests
  end

  describe '#perform' do
    context 'with contact.created event' do
      let(:processor) do
        described_class.new(
          inbox: inbox,
          event_name: 'contact.created',
          event_data: { contact: contact }
        )
      end

      it 'processes contact' do
        expect(processor).to receive(:process_contact)
        processor.perform
      end

      it 'creates person and lead' do
        processor.perform

        expect(WebMock).to have_requested(:post, "#{settings['api_url']}/persons")
        expect(WebMock).to have_requested(:post, "#{settings['api_url']}/leads")
      end

      it 'stores external IDs' do
        processor.perform

        contact_inbox = contact.contact_inboxes.find_by(inbox: inbox)
        expect(contact_inbox.source_id).to be_present
        expect(contact_inbox.source_id).to include('krayin:person:')
      end
    end

    context 'with unknown event' do
      let(:processor) do
        described_class.new(
          inbox: inbox,
          event_name: 'unknown.event',
          event_data: {}
        )
      end

      it 'logs and ignores' do
        expect(Rails.logger).to receive(:info).with(/Ignoring event/)
        processor.perform
      end
    end
  end

  describe 'error handling' do
    context 'when API request fails' do
      before do
        stub_request(:post, "#{settings['api_url']}/persons")
          .to_return(status: 500)
      end

      let(:processor) do
        described_class.new(
          inbox: inbox,
          event_name: 'contact.created',
          event_data: { contact: contact }
        )
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with(/Failed to process/)
        expect { processor.perform }.to raise_error(Crm::Krayin::Api::BaseClient::ApiError)
      end
    end
  end
end
```

### Testing Finder Services

```ruby
# spec/services/crm/krayin/person_finder_service_spec.rb

RSpec.describe Crm::Krayin::PersonFinderService do
  let(:api_url) { 'http://krayin.test/api/admin' }
  let(:api_token) { 'test-token' }
  let(:finder) { described_class.new(api_url, api_token) }

  describe '#find_by_email' do
    context 'when person exists' do
      before do
        stub_request(:get, "#{api_url}/persons")
          .with(query: { email: 'john@example.com' })
          .to_return(
            status: 200,
            body: {
              data: [{ id: 123, name: 'John Doe' }]
            }.to_json
          )
      end

      it 'returns person data' do
        result = finder.find_by_email('john@example.com')
        expect(result['id']).to eq(123)
      end
    end

    context 'when person does not exist' do
      before do
        stub_request(:get, "#{api_url}/persons")
          .with(query: { email: 'notfound@example.com' })
          .to_return(
            status: 200,
            body: { data: [] }.to_json
          )
      end

      it 'returns nil' do
        result = finder.find_by_email('notfound@example.com')
        expect(result).to be_nil
      end
    end

    context 'when API returns error' do
      before do
        stub_request(:get, "#{api_url}/persons")
          .to_return(status: 500)
      end

      it 'raises ApiError' do
        expect {
          finder.find_by_email('error@example.com')
        }.to raise_error(Crm::Krayin::Api::BaseClient::ApiError)
      end
    end
  end
end
```

## WebMock Usage

### Basic Stubbing

```ruby
# Stub GET request
stub_request(:get, "http://api.example.com/users")
  .to_return(status: 200, body: '{"users":[]}')

# Stub POST request with body
stub_request(:post, "http://api.example.com/users")
  .with(body: { name: 'John' }.to_json)
  .to_return(status: 201, body: '{"id":1}')

# Stub with headers
stub_request(:get, "http://api.example.com/users")
  .with(headers: { 'Authorization' => 'Bearer token' })
  .to_return(status: 200, body: '{"users":[]}')

# Stub with query parameters
stub_request(:get, "http://api.example.com/users")
  .with(query: { page: 1, per_page: 10 })
  .to_return(status: 200, body: '{"users":[]}')
```

### Advanced Stubbing

```ruby
# Stub with dynamic responses
stub_request(:get, "http://api.example.com/users")
  .to_return do |request|
    { body: "Request was: #{request.uri}" }
  end

# Stub with sequence of responses
stub_request(:get, "http://api.example.com/users")
  .to_return(
    { status: 429 },
    { status: 429 },
    { status: 200, body: '{"users":[]}' }
  )

# Stub with block
stub_request(:post, "http://api.example.com/users")
  .to_return do |request|
    body = JSON.parse(request.body)
    status = body['name'].present? ? 201 : 422
    { status: status, body: { id: 1, name: body['name'] }.to_json }
  end
```

### Verification

```ruby
# Verify request was made
expect(WebMock).to have_requested(:post, "http://api.example.com/users")

# Verify request with specific body
expect(WebMock).to have_requested(:post, "http://api.example.com/users")
  .with(body: hash_including(name: 'John'))

# Verify request count
expect(WebMock).to have_requested(:get, "http://api.example.com/users").twice

# Verify request was not made
expect(WebMock).not_to have_requested(:delete, "http://api.example.com/users/1")
```

### Helpers

```ruby
# spec/support/krayin_stubs.rb

module KrayinStubs
  def stub_krayin_requests
    stub_krayin_person_requests
    stub_krayin_lead_requests
    stub_krayin_activity_requests
  end

  def stub_krayin_person_requests
    stub_request(:post, %r{/persons$})
      .to_return(
        status: 201,
        body: { data: { id: 123 } }.to_json
      )

    stub_request(:put, %r{/persons/\d+$})
      .to_return(
        status: 200,
        body: { data: { id: 123 } }.to_json
      )

    stub_request(:get, %r{/persons})
      .to_return(
        status: 200,
        body: { data: [] }.to_json
      )
  end

  def stub_krayin_lead_requests
    stub_request(:post, %r{/leads$})
      .to_return(
        status: 201,
        body: { data: { id: 456 } }.to_json
      )

    stub_request(:put, %r{/leads/\d+$})
      .to_return(
        status: 200,
        body: { data: { id: 456 } }.to_json
      )
  end

  def stub_krayin_activity_requests
    stub_request(:post, %r{/activities$})
      .to_return(
        status: 201,
        body: { data: { id: 101 } }.to_json
      )
  end

  def stub_krayin_setup_requests
    stub_request(:get, %r{/settings/pipelines})
      .to_return(
        status: 200,
        body: { data: [{ id: 1, name: 'Sales' }] }.to_json
      )

    stub_request(:get, %r{/settings/sources})
      .to_return(
        status: 200,
        body: { data: [{ id: 1, name: 'Website' }] }.to_json
      )

    stub_request(:get, %r{/settings/types})
      .to_return(
        status: 200,
        body: { data: [{ id: 1, name: 'New Business' }] }.to_json
      )
  end
end

RSpec.configure do |config|
  config.include KrayinStubs
end
```

## Test Factories

### Contact Factory

```ruby
# spec/factories/contacts.rb

FactoryBot.define do
  factory :contact do
    account
    inbox
    name { Faker::Name.name }
    email { Faker::Internet.email }
    phone_number { Faker::PhoneNumber.cell_phone_in_e164 }
    additional_attributes { {} }

    trait :with_company do
      additional_attributes do
        {
          'company_name' => Faker::Company.name,
          'job_title' => Faker::Job.title,
          'lead_value' => Faker::Number.decimal(l_digits: 5, r_digits: 2)
        }
      end
    end

    trait :with_krayin_ids do
      after(:create) do |contact|
        contact.contact_inboxes.first.update!(
          source_id: 'krayin:person:123|krayin:lead:456'
        )
      end
    end
  end
end
```

### Hook Factory

```ruby
# spec/factories/integrations_hooks.rb

FactoryBot.define do
  factory :integrations_hook, class: 'Integrations::Hook' do
    account
    inbox
    app_id { 'krayin' }
    status { 'enabled' }
    settings do
      {
        'api_url' => 'http://krayin.test/api/admin',
        'api_token' => 'test-token',
        'default_pipeline_id' => 1,
        'default_stage_id' => 1,
        'default_source_id' => 1,
        'default_type_id' => 1
      }
    end

    trait :with_sync_options do
      settings do
        {
          'api_url' => 'http://krayin.test/api/admin',
          'api_token' => 'test-token',
          'sync_conversations' => true,
          'sync_messages' => true,
          'sync_to_organization' => true
        }
      end
    end

    trait :with_stage_progression do
      settings do
        {
          'api_url' => 'http://krayin.test/api/admin',
          'api_token' => 'test-token',
          'stage_progression_enabled' => true,
          'stage_on_conversation_created' => 2,
          'stage_on_first_response' => 3,
          'stage_on_conversation_resolved' => 4
        }
      end
    end
  end
end
```

### Conversation Factory

```ruby
# spec/factories/conversations.rb

FactoryBot.define do
  factory :conversation do
    account
    inbox
    contact
    display_id { Faker::Number.unique.number(digits: 6) }
    status { 'open' }

    trait :resolved do
      status { 'resolved' }
    end

    trait :with_messages do
      after(:create) do |conversation|
        create(:message, :incoming, conversation: conversation)
        create(:message, :outgoing, conversation: conversation)
      end
    end
  end
end
```

## Coverage Requirements

### Target Metrics

- **Overall Coverage**: 90%+
- **Per-File Coverage**: 80%+
- **Critical Paths**: 100% (API clients, processors)

### Running Coverage

```bash
# Run with coverage
COVERAGE=true bundle exec rspec spec/services/crm/krayin/

# View HTML report
open coverage/index.html

# View summary
cat coverage/.last_run.json | jq .result
```

### Coverage for Critical Files

```ruby
# spec/services/crm/krayin/processor_service_spec.rb
# Should cover:
# - All event types
# - Success paths
# - Error paths
# - Edge cases (missing data, API errors)
# - External ID management
# - Stage progression logic

# Target: 100% coverage
```

## Common Testing Patterns

### Testing Conditional Logic

```ruby
describe 'conditional sync' do
  context 'when sync_conversations enabled' do
    before { hook.settings['sync_conversations'] = true }

    it 'creates activity' do
      processor.perform
      expect(WebMock).to have_requested(:post, /activities/)
    end
  end

  context 'when sync_conversations disabled' do
    before { hook.settings['sync_conversations'] = false }

    it 'skips activity creation' do
      processor.perform
      expect(WebMock).not_to have_requested(:post, /activities/)
    end
  end
end
```

### Testing Mutex Locks

```ruby
describe 'race condition prevention' do
  let(:redis) { Redis.new }

  before do
    allow(Redis::Alfred).to receive(:new).and_return(redis)
  end

  it 'acquires lock before processing' do
    expect(redis).to receive(:lock).with(/krayin:process:contact/, any_args)
    processor.perform
  end

  it 'releases lock after processing' do
    processor.perform
    lock_key = "mutex:krayin:process:contact:#{contact.id}"
    expect(redis.get(lock_key)).to be_nil
  end
end
```

### Testing Cache

```ruby
describe 'configuration caching' do
  it 'caches configuration' do
    service.fetch_default_configuration

    expect(Rails.cache.exist?(/krayin:setup/)).to be true
  end

  it 'uses cached value on second call' do
    service.fetch_default_configuration

    expect(WebMock).to have_requested(:get, /pipelines/).once

    service.fetch_default_configuration
    expect(WebMock).to have_requested(:get, /pipelines/).once
  end

  it 'expires after 1 hour' do
    Timecop.freeze do
      service.fetch_default_configuration

      Timecop.travel(61.minutes) do
        service.fetch_default_configuration
        expect(WebMock).to have_requested(:get, /pipelines/).twice
      end
    end
  end
end
```

## Debugging Tests

### Print Debug Info

```ruby
it 'creates person' do
  result = client.create_person(person_data)
  puts "Result: #{result.inspect}"  # Debug output
  expect(result['data']['id']).to eq(123)
end
```

### Use Pry

```ruby
it 'creates person' do
  require 'pry'
  binding.pry  # Pauses execution here
  result = client.create_person(person_data)
  expect(result['data']['id']).to eq(123)
end
```

### Focus Specific Test

```ruby
# Run only this test
fit 'creates person' do
  # ...
end

# Run only this describe block
fdescribe '#create_person' do
  # ...
end
```

### View WebMock Requests

```ruby
before do
  WebMock.after_request do |request_signature, response|
    puts "\n=== REQUEST ==="
    puts request_signature
    puts "\n=== RESPONSE ==="
    puts response.body
  end
end
```

### Test Isolation Issues

```ruby
# Clear state between tests
before(:each) do
  Rails.cache.clear
  Redis.new.flushdb
end

# Or use database_cleaner
config.before(:suite) do
  DatabaseCleaner.strategy = :transaction
  DatabaseCleaner.clean_with(:truncation)
end
```

## Running Tests

### Run All Tests

```bash
bundle exec rspec spec/services/crm/krayin/
```

### Run Specific File

```bash
bundle exec rspec spec/services/crm/krayin/processor_service_spec.rb
```

### Run Specific Test

```bash
bundle exec rspec spec/services/crm/krayin/processor_service_spec.rb:45
```

### Run with Options

```bash
# Verbose output
bundle exec rspec spec/services/crm/krayin/ --format documentation

# Fast fail (stop on first failure)
bundle exec rspec spec/services/crm/krayin/ --fail-fast

# Run only failed tests
bundle exec rspec --only-failures

# Run tests in random order
bundle exec rspec spec/services/crm/krayin/ --order random
```

## Continuous Integration

### GitHub Actions Example

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:6
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v2

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true

      - name: Run tests
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
          REDIS_URL: redis://localhost:6379
        run: |
          bundle exec rails db:create db:migrate
          COVERAGE=true bundle exec rspec spec/services/crm/krayin/

      - name: Upload coverage
        uses: actions/upload-artifact@v2
        with:
          name: coverage
          path: coverage/
```

## Resources

- [RSpec Documentation](https://rspec.info/)
- [Factory Bot Documentation](https://github.com/thoughtbot/factory_bot)
- [WebMock Documentation](https://github.com/bblimke/webmock)
- [SimpleCov Documentation](https://github.com/simplecov-ruby/simplecov)
- [Faker Documentation](https://github.com/faker-ruby/faker)

---

**Happy Testing!** ✅
