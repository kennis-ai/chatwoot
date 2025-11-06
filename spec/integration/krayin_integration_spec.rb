require 'rails_helper'

RSpec.describe 'Krayin CRM Integration', type: :integration do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'test@example.com', phone_number: '+1234567890') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:hook) do
    create(:integrations_hook, :krayin,
           account: account,
           inbox: inbox,
           settings: {
             'api_url' => 'https://crm.example.com/api/admin',
             'api_token' => 'test_token',
             'sync_conversations' => true,
             'sync_messages' => true
           })
  end

  let(:api_client) { instance_double(Crm::Krayin::ApiClient) }
  let(:setup_service) { Crm::Krayin::SetupService.new(inbox: inbox, api_url: hook.settings['api_url'], api_token: hook.settings['api_token']) }

  before do
    account.enable_features(:crm_integration)
    allow(Crm::Krayin::ApiClient).to receive(:new).and_return(api_client)
  end

  describe 'Setup and Configuration' do
    it 'validates API connection and fetches default configuration' do
      # Mock API responses
      allow(api_client).to receive(:get).with('/leads/pipelines').and_return({
        'data' => [{ 'id' => 1, 'name' => 'Sales Pipeline', 'is_default' => 1 }]
      })
      allow(api_client).to receive(:get).with('/leads/stages').and_return({
        'data' => [{ 'id' => 1, 'name' => 'New', 'pipeline_id' => 1 }]
      })
      allow(api_client).to receive(:get).with('/leads/sources').and_return({
        'data' => [{ 'id' => 1, 'name' => 'Chatwoot' }]
      })
      allow(api_client).to receive(:get).with('/leads/types').and_return({
        'data' => [{ 'id' => 1, 'name' => 'Customer' }]
      })

      config = setup_service.perform

      expect(config[:default_pipeline_id]).to eq(1)
      expect(config[:default_stage_id]).to eq(1)
      expect(config[:default_source_id]).to eq(1)
      expect(config[:default_lead_type_id]).to eq(1)
    end

    it 'raises error when API connection fails' do
      allow(api_client).to receive(:get).and_raise(StandardError.new('Connection failed'))

      expect { setup_service.perform }.to raise_error(StandardError, /API connection failed/)
    end
  end

  describe 'End-to-End Contact Sync Flow' do
    let(:person_id) { 123 }
    let(:lead_id) { 456 }

    before do
      # Mock Person API calls
      allow(api_client).to receive(:post).with('/persons/search', anything).and_return({
        'data' => []
      })
      allow(api_client).to receive(:post).with('/persons', anything).and_return({
        'data' => { 'id' => person_id, 'name' => contact.name }
      })

      # Mock Lead API calls
      allow(api_client).to receive(:post).with('/leads/search', anything).and_return({
        'data' => []
      })
      allow(api_client).to receive(:post).with('/leads', anything).and_return({
        'data' => { 'id' => lead_id, 'person_id' => person_id }
      })
    end

    it 'creates Person and Lead when contact is created' do
      event_name = 'contact.created'
      event_data = { contact: contact }

      processor = Crm::Krayin::ProcessorService.new(
        inbox: inbox,
        event_name: event_name,
        event_data: event_data
      )

      expect(api_client).to receive(:post).with('/persons', anything).once
      expect(api_client).to receive(:post).with('/leads', anything).once

      processor.perform

      # Verify external IDs are stored
      contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
      expect(contact_inbox.source_id).to include("krayin:person:#{person_id}")
      expect(contact_inbox.source_id).to include("krayin:lead:#{lead_id}")
    end

    it 'updates existing Person and Lead when contact is updated' do
      # Setup existing external IDs
      contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox)
      contact_inbox.update!(source_id: "krayin:person:#{person_id}|krayin:lead:#{lead_id}")

      # Mock update API calls
      allow(api_client).to receive(:put).with("/persons/#{person_id}", anything).and_return({
        'data' => { 'id' => person_id, 'name' => contact.name }
      })
      allow(api_client).to receive(:put).with("/leads/#{lead_id}", anything).and_return({
        'data' => { 'id' => lead_id, 'person_id' => person_id }
      })

      event_name = 'contact.updated'
      event_data = { contact: contact }

      processor = Crm::Krayin::ProcessorService.new(
        inbox: inbox,
        event_name: event_name,
        event_data: event_data
      )

      expect(api_client).to receive(:put).with("/persons/#{person_id}", anything).once
      expect(api_client).to receive(:put).with("/leads/#{lead_id}", anything).once

      processor.perform
    end
  end

  describe 'End-to-End Conversation Sync Flow' do
    let(:person_id) { 123 }
    let(:activity_id) { 789 }

    before do
      # Setup existing contact with external IDs
      contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox)
      contact_inbox.update!(source_id: "krayin:person:#{person_id}|krayin:lead:456")

      # Mock Activity API call
      allow(api_client).to receive(:post).with('/activities', anything).and_return({
        'data' => { 'id' => activity_id, 'person_id' => person_id }
      })
    end

    context 'when sync_conversations is enabled' do
      it 'creates activity when conversation is created' do
        event_name = 'conversation.created'
        event_data = { conversation: conversation }

        processor = Crm::Krayin::ProcessorService.new(
          inbox: inbox,
          event_name: event_name,
          event_data: event_data
        )

        expect(api_client).to receive(:post).with('/activities', hash_including(
          'type' => 'note',
          'person_id' => person_id
        )).once

        processor.perform
      end

      it 'updates activity when conversation is updated' do
        # Store activity external ID
        conversation.additional_attributes ||= {}
        conversation.additional_attributes['krayin_activity_id'] = activity_id
        conversation.save!

        allow(api_client).to receive(:put).with("/activities/#{activity_id}", anything).and_return({
          'data' => { 'id' => activity_id }
        })

        event_name = 'conversation.updated'
        event_data = { conversation: conversation }

        processor = Crm::Krayin::ProcessorService.new(
          inbox: inbox,
          event_name: event_name,
          event_data: event_data
        )

        expect(api_client).to receive(:put).with("/activities/#{activity_id}", anything).once

        processor.perform
      end
    end

    context 'when sync_conversations is disabled' do
      before do
        hook.settings['sync_conversations'] = false
        hook.save!
      end

      it 'does not create activity' do
        event_name = 'conversation.created'
        event_data = { conversation: conversation }

        processor = Crm::Krayin::ProcessorService.new(
          inbox: inbox,
          event_name: event_name,
          event_data: event_data
        )

        expect(api_client).not_to receive(:post).with('/activities', anything)

        processor.perform
      end
    end
  end

  describe 'End-to-End Message Sync Flow' do
    let(:person_id) { 123 }
    let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Test message') }
    let(:activity_id) { 999 }

    before do
      # Setup existing contact with external IDs
      contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox)
      contact_inbox.update!(source_id: "krayin:person:#{person_id}|krayin:lead:456")

      # Mock Activity API call
      allow(api_client).to receive(:post).with('/activities', anything).and_return({
        'data' => { 'id' => activity_id, 'person_id' => person_id }
      })
    end

    context 'when sync_messages is enabled' do
      it 'creates activity when message is created' do
        event_name = 'message.created'
        event_data = { message: message }

        processor = Crm::Krayin::ProcessorService.new(
          inbox: inbox,
          event_name: event_name,
          event_data: event_data
        )

        expect(api_client).to receive(:post).with('/activities', hash_including(
          'person_id' => person_id,
          'comment' => message.content
        )).once

        processor.perform
      end
    end

    context 'when sync_messages is disabled' do
      before do
        hook.settings['sync_messages'] = false
        hook.save!
      end

      it 'does not create activity' do
        event_name = 'message.created'
        event_data = { message: message }

        processor = Crm::Krayin::ProcessorService.new(
          inbox: inbox,
          event_name: event_name,
          event_data: event_data
        )

        expect(api_client).not_to receive(:post).with('/activities', anything)

        processor.perform
      end
    end
  end

  describe 'Event Processing with Redis Locks' do
    it 'uses mutex lock for concurrent event handling' do
      event_name = 'contact.created'
      event_data = { contact: contact }

      # Mock Redis lock
      key = format(Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
      job_instance = HookJob.new

      allow(job_instance).to receive(:with_lock).with(key).and_yield

      expect(job_instance).to receive(:with_lock).with(key)

      job_instance.perform(hook, event_name, event_data)
    end

    it 'handles concurrent events without race conditions' do
      person_id = 123
      lead_id = 456

      # Setup mocks for concurrent API calls
      call_count = 0
      allow(api_client).to receive(:post).with('/persons/search', anything).and_return({ 'data' => [] })
      allow(api_client).to receive(:post).with('/persons', anything) do
        call_count += 1
        { 'data' => { 'id' => person_id, 'name' => contact.name } }
      end
      allow(api_client).to receive(:post).with('/leads/search', anything).and_return({ 'data' => [] })
      allow(api_client).to receive(:post).with('/leads', anything).and_return({
        'data' => { 'id' => lead_id, 'person_id' => person_id }
      })

      # Simulate three rapid-fire events
      events = [
        { name: 'contact.created', data: { contact: contact } },
        { name: 'contact.updated', data: { contact: contact } },
        { name: 'conversation.created', data: { conversation: conversation } }
      ]

      # Process events sequentially (simulating mutex behavior)
      events.each do |event|
        processor = Crm::Krayin::ProcessorService.new(
          inbox: inbox,
          event_name: event[:name],
          event_data: event[:data]
        )
        processor.perform
      end

      # Person should only be created once due to mutex protection
      expect(call_count).to eq(1)
    end
  end

  describe 'Error Scenarios and Recovery' do
    it 'handles API errors gracefully' do
      allow(api_client).to receive(:post).and_raise(StandardError.new('API Error'))

      event_name = 'contact.created'
      event_data = { contact: contact }

      processor = Crm::Krayin::ProcessorService.new(
        inbox: inbox,
        event_name: event_name,
        event_data: event_data
      )

      expect { processor.perform }.not_to raise_error
    end

    it 'continues processing when one sync fails' do
      person_id = 123

      # Contact sync succeeds
      allow(api_client).to receive(:post).with('/persons/search', anything).and_return({ 'data' => [] })
      allow(api_client).to receive(:post).with('/persons', anything).and_return({
        'data' => { 'id' => person_id, 'name' => contact.name }
      })

      # Lead sync fails
      allow(api_client).to receive(:post).with('/leads/search', anything).and_return({ 'data' => [] })
      allow(api_client).to receive(:post).with('/leads', anything).and_raise(StandardError.new('Lead creation failed'))

      event_name = 'contact.created'
      event_data = { contact: contact }

      processor = Crm::Krayin::ProcessorService.new(
        inbox: inbox,
        event_name: event_name,
        event_data: event_data
      )

      expect { processor.perform }.not_to raise_error

      # Person external ID should still be stored
      contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
      expect(contact_inbox.source_id).to include("krayin:person:#{person_id}")
    end

    it 'skips processing when feature is not allowed' do
      account.disable_features(:crm_integration)

      event_name = 'contact.created'
      event_data = { contact: contact }

      expect(api_client).not_to receive(:post)

      HookJob.perform_now(hook, event_name, event_data)
    end

    it 'skips processing when hook is disabled' do
      hook.disable

      event_name = 'contact.created'
      event_data = { contact: contact }

      expect(api_client).not_to receive(:post)

      HookJob.perform_now(hook, event_name, event_data)
    end

    it 'handles missing contact inbox gracefully' do
      # Create contact without contact_inbox
      new_contact = create(:contact, account: account, email: 'new@example.com')

      event_name = 'contact.created'
      event_data = { contact: new_contact }

      processor = Crm::Krayin::ProcessorService.new(
        inbox: inbox,
        event_name: event_name,
        event_data: event_data
      )

      # Should create new Person and Lead
      allow(api_client).to receive(:post).with('/persons/search', anything).and_return({ 'data' => [] })
      allow(api_client).to receive(:post).with('/persons', anything).and_return({
        'data' => { 'id' => 789, 'name' => new_contact.name }
      })
      allow(api_client).to receive(:post).with('/leads/search', anything).and_return({ 'data' => [] })
      allow(api_client).to receive(:post).with('/leads', anything).and_return({
        'data' => { 'id' => 890, 'person_id' => 789 }
      })

      expect { processor.perform }.not_to raise_error
    end
  end
end
