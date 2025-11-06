# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::ProcessorService do
  let(:account) { create(:account) }
  let(:hook) do
    create(:integrations_hook,
           app_id: 'glpi',
           account: account,
           settings: settings)
  end

  let(:settings) do
    {
      'api_url' => 'https://glpi.example.com/apirest.php',
      'app_token' => 'test_app_token',
      'user_token' => 'test_user_token',
      'entity_id' => '0',
      'sync_type' => 'user',
      'ticket_type' => '1',
      'category_id' => '10',
      'default_user_id' => '2'
    }
  end

  let(:processor) { described_class.new(hook) }

  describe '.crm_name' do
    it 'returns glpi' do
      expect(described_class.crm_name).to eq('glpi')
    end
  end

  describe '#initialize' do
    it 'initializes with hook settings' do
      expect(processor).to be_a(Crm::Glpi::ProcessorService)
    end

    it 'sets up API clients' do
      expect(processor.instance_variable_get(:@user_client)).to be_a(Crm::Glpi::Api::UserClient)
      expect(processor.instance_variable_get(:@contact_client)).to be_a(Crm::Glpi::Api::ContactClient)
      expect(processor.instance_variable_get(:@ticket_client)).to be_a(Crm::Glpi::Api::TicketClient)
      expect(processor.instance_variable_get(:@followup_client)).to be_a(Crm::Glpi::Api::FollowupClient)
    end

    it 'sets up finder services' do
      expect(processor.instance_variable_get(:@user_finder)).to be_a(Crm::Glpi::UserFinderService)
      expect(processor.instance_variable_get(:@contact_finder)).to be_a(Crm::Glpi::ContactFinderService)
    end
  end

  describe '#handle_contact_created' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'John Doe',
             email: 'john@example.com',
             phone_number: '+12345678900')
    end

    before do
      stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
        .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

      stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
        .to_return(status: 200, body: { data: [] }.to_json)

      stub_request(:post, 'https://glpi.example.com/apirest.php/User')
        .to_return(status: 201, body: { id: 123, message: 'User created' }.to_json)

      stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
        .to_return(status: 200, body: '{}')
    end

    it 'creates GLPI user and stores ID' do
      result = processor.handle_contact_created(contact)

      expect(result[:success]).to be true
      contact.reload
      expect(contact.additional_attributes.dig('external', 'glpi_user_id')).to eq(123)
    end

    context 'with sync_type=contact' do
      let(:settings) do
        {
          'api_url' => 'https://glpi.example.com/apirest.php',
          'app_token' => 'test_app_token',
          'user_token' => 'test_user_token',
          'entity_id' => '0',
          'sync_type' => 'contact'
        }
      end

      before do
        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/Contact})
          .to_return(status: 200, body: { data: [] }.to_json)

        stub_request(:post, 'https://glpi.example.com/apirest.php/Contact')
          .to_return(status: 201, body: { id: 456, message: 'Contact created' }.to_json)
      end

      it 'creates GLPI contact instead of user' do
        result = processor.handle_contact_created(contact)

        expect(result[:success]).to be true
        contact.reload
        expect(contact.additional_attributes.dig('external', 'glpi_contact_id')).to eq(456)
      end
    end

    context 'with non-identifiable contact' do
      let(:contact) do
        create(:contact,
               account: account,
               name: nil,
               email: nil,
               phone_number: nil)
      end

      it 'skips non-identifiable contact' do
        result = processor.handle_contact_created(contact)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Contact not identifiable')
      end
    end
  end

  describe '#handle_contact_updated' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'John Doe',
             email: 'john@example.com')
    end

    before do
      contact.additional_attributes = {
        'external' => { 'glpi_user_id' => 123 }
      }
      contact.save!

      stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
        .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

      stub_request(:put, 'https://glpi.example.com/apirest.php/User/123')
        .to_return(status: 200, body: [{ 123 => true, message: 'User updated' }].to_json)

      stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
        .to_return(status: 200, body: '{}')
    end

    it 'updates existing GLPI user' do
      result = processor.handle_contact_updated(contact)

      expect(result[:success]).to be true
    end
  end

  describe '#handle_conversation_created' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) do
      create(:contact,
             account: account,
             name: 'Jane Smith',
             email: 'jane@example.com')
    end
    let(:conversation) do
      create(:conversation,
             account: account,
             inbox: inbox,
             contact: contact,
             status: :open,
             priority: :high)
    end
    let!(:first_message) do
      create(:message,
             conversation: conversation,
             account: account,
             inbox: inbox,
             content: 'I need help',
             sender: contact)
    end

    before do
      stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
        .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

      stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
        .to_return(status: 200, body: { data: [{ id: 789 }] }.to_json)

      stub_request(:post, 'https://glpi.example.com/apirest.php/Ticket')
        .to_return(status: 201, body: { id: 999, message: 'Ticket created' }.to_json)

      stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
        .to_return(status: 200, body: '{}')
    end

    it 'creates GLPI ticket and stores ticket_id' do
      result = processor.handle_conversation_created(conversation)

      expect(result[:success]).to be true
      conversation.reload
      expect(conversation.additional_attributes.dig('glpi', 'ticket_id')).to eq(999)
    end
  end

  describe '#handle_conversation_updated' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) do
      create(:contact,
             account: account,
             name: 'Bob Wilson',
             email: 'bob@example.com')
    end
    let(:conversation) do
      create(:conversation,
             account: account,
             inbox: inbox,
             contact: contact,
             status: :resolved)
    end
    let!(:message) do
      create(:message,
             conversation: conversation,
             account: account,
             inbox: inbox,
             content: 'Follow up message',
             sender: contact)
    end

    before do
      conversation.additional_attributes = {
        'glpi' => { 'ticket_id' => 999 }
      }
      conversation.save!

      stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
        .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

      stub_request(:put, 'https://glpi.example.com/apirest.php/Ticket/999')
        .to_return(status: 200, body: [{ 999 => true, message: 'Ticket updated' }].to_json)

      stub_request(:post, 'https://glpi.example.com/apirest.php/Ticket/999/ITILFollowup')
        .to_return(status: 201, body: { id: 111, message: 'Followup created' }.to_json)

      stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
        .to_return(status: 200, body: '{}')
    end

    it 'updates ticket status and creates followups' do
      result = processor.handle_conversation_updated(conversation)

      expect(result[:success]).to be true
      conversation.reload
      expect(conversation.additional_attributes.dig('glpi', 'last_synced_message_id')).to eq(message.id)
    end
  end

  describe '#process_event' do
    let(:contact) { create(:contact, account: account, email: 'test@example.com') }

    it 'routes contact.created event' do
      expect(processor).to receive(:handle_contact_created).with(contact).and_return({ success: true })
      processor.process_event('contact.created', contact)
    end

    it 'routes contact.updated event' do
      expect(processor).to receive(:handle_contact_updated).with(contact).and_return({ success: true })
      processor.process_event('contact.updated', contact)
    end

    it 'returns error for unsupported event' do
      result = processor.process_event('unsupported.event', contact)
      expect(result[:success]).to be false
      expect(result[:error]).to include('Unsupported event')
    end
  end
end
