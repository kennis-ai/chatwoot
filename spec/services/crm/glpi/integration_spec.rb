# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GLPI Integration End-to-End', type: :integration do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
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
      'default_user_id' => '2'
    }
  end

  before do
    # Stub session management
    stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
      .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

    stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
      .to_return(status: 200, body: '{}')
  end

  describe 'Full Contact to Ticket Flow' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'John Doe',
             email: 'john@example.com',
             phone_number: '+12345678900')
    end

    context 'when creating a new conversation with messages' do
      it 'syncs contact, creates ticket, and adds followups' do
        # Step 1: Search for user (not found)
        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
          .to_return(status: 200, body: { data: [] }.to_json)

        # Step 2: Create user
        stub_request(:post, 'https://glpi.example.com/apirest.php/User')
          .to_return(status: 201, body: { id: 123, message: 'User created' }.to_json)

        # Step 3: Create ticket
        stub_request(:post, 'https://glpi.example.com/apirest.php/Ticket')
          .to_return(status: 201, body: { id: 456, message: 'Ticket created' }.to_json)

        # Step 4: Create followups
        stub_request(:post, 'https://glpi.example.com/apirest.php/Ticket/456/ITILFollowup')
          .to_return(status: 201, body: { id: 789, message: 'Followup created' }.to_json)

        # Step 5: Update ticket
        stub_request(:put, 'https://glpi.example.com/apirest.php/Ticket/456')
          .to_return(status: 200, body: [{ 456 => true, message: 'Ticket updated' }].to_json)

        # Create conversation
        conversation = create(:conversation,
                              account: account,
                              inbox: inbox,
                              contact: contact,
                              status: :open,
                              priority: :high)

        # Add first message
        first_message = create(:message,
                               conversation: conversation,
                               account: account,
                               inbox: inbox,
                               content: 'I need help with my account',
                               sender: contact)

        # Process contact.created event
        processor = Crm::Glpi::ProcessorService.new(hook)
        contact_result = processor.process_event('contact.created', contact)

        expect(contact_result[:success]).to be true

        # Verify contact has external ID
        contact.reload
        expect(contact.additional_attributes.dig('external', 'glpi_user_id')).to eq(123)

        # Process conversation.created event
        conversation_result = processor.process_event('conversation.created', conversation)

        expect(conversation_result[:success]).to be true

        # Verify conversation has ticket ID
        conversation.reload
        expect(conversation.additional_attributes.dig('glpi', 'ticket_id')).to eq(456)

        # Add second message
        second_message = create(:message,
                                conversation: conversation,
                                account: account,
                                inbox: inbox,
                                content: 'Can someone help me?',
                                sender: contact)

        # Process conversation.updated event
        update_result = processor.process_event('conversation.updated', conversation)

        expect(update_result[:success]).to be true

        # Verify last synced message ID updated
        conversation.reload
        expect(conversation.additional_attributes.dig('glpi', 'last_synced_message_id')).to eq(second_message.id)
      end
    end
  end

  describe 'Contact Sync Type Switch' do
    context 'when sync_type is contact' do
      let(:settings) do
        {
          'api_url' => 'https://glpi.example.com/apirest.php',
          'app_token' => 'test_app_token',
          'user_token' => 'test_user_token',
          'entity_id' => '0',
          'sync_type' => 'contact'
        }
      end

      let(:contact) do
        create(:contact,
               account: account,
               name: 'Jane Smith',
               email: 'jane@example.com')
      end

      it 'creates GLPI Contact instead of User' do
        # Search for contact (not found)
        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/Contact})
          .to_return(status: 200, body: { data: [] }.to_json)

        # Create contact
        stub_request(:post, 'https://glpi.example.com/apirest.php/Contact')
          .to_return(status: 201, body: { id: 789, message: 'Contact created' }.to_json)

        processor = Crm::Glpi::ProcessorService.new(hook)
        result = processor.process_event('contact.created', contact)

        expect(result[:success]).to be true

        contact.reload
        expect(contact.additional_attributes.dig('external', 'glpi_contact_id')).to eq(789)
        expect(contact.additional_attributes.dig('external', 'glpi_user_id')).to be_nil
      end
    end
  end

  describe 'Error Handling' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'Bob Wilson',
             email: 'bob@example.com')
    end

    context 'when API returns error' do
      it 'handles error gracefully and returns failure' do
        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
          .to_return(status: 500, body: { 0 => 'ERROR_INTERNAL' }.to_json)

        processor = Crm::Glpi::ProcessorService.new(hook)
        result = processor.process_event('contact.created', contact)

        expect(result[:success]).to be true # ProcessorService handles errors internally
        contact.reload
        expect(contact.additional_attributes.dig('external', 'glpi_user_id')).to be_nil
      end
    end

    context 'when contact is not identifiable' do
      let(:contact) do
        create(:contact,
               account: account,
               name: nil,
               email: nil,
               phone_number: nil)
      end

      it 'skips processing' do
        processor = Crm::Glpi::ProcessorService.new(hook)
        result = processor.process_event('contact.created', contact)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Contact not identifiable')
      end
    end
  end

  describe 'Update Existing Records' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'Alice Cooper',
             email: 'alice@example.com')
    end

    context 'when contact already has GLPI user_id' do
      before do
        contact.additional_attributes = {
          'external' => { 'glpi_user_id' => 999 }
        }
        contact.save!
      end

      it 'updates existing user instead of creating new one' do
        stub_request(:put, 'https://glpi.example.com/apirest.php/User/999')
          .to_return(status: 200, body: [{ 999 => true, message: 'User updated' }].to_json)

        processor = Crm::Glpi::ProcessorService.new(hook)
        result = processor.process_event('contact.updated', contact)

        expect(result[:success]).to be true

        # Verify update was called, not create
        expect(WebMock).to have_requested(:put, 'https://glpi.example.com/apirest.php/User/999')
        expect(WebMock).not_to have_requested(:post, 'https://glpi.example.com/apirest.php/User')
      end
    end
  end

  describe 'Message Attachment Handling' do
    let(:contact) { create(:contact, account: account, email: 'test@example.com') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    before do
      # Setup existing user and ticket
      contact.additional_attributes = {
        'external' => { 'glpi_user_id' => 111 }
      }
      contact.save!

      conversation.additional_attributes = {
        'glpi' => { 'ticket_id' => 222 }
      }
      conversation.save!

      stub_request(:put, 'https://glpi.example.com/apirest.php/Ticket/222')
        .to_return(status: 200, body: [{ 222 => true }].to_json)

      stub_request(:post, 'https://glpi.example.com/apirest.php/Ticket/222/ITILFollowup')
        .to_return(status: 201, body: { id: 333 }.to_json)
    end

    it 'includes attachment URLs in followup content' do
      message = create(:message,
                       conversation: conversation,
                       account: account,
                       inbox: inbox,
                       content: 'Please see the screenshot',
                       sender: contact)

      # Mock attachments
      allow(message).to receive(:attachments).and_return([
                                                            double(file_url: 'https://example.com/file1.png'),
                                                            double(file_url: 'https://example.com/file2.pdf')
                                                          ])

      processor = Crm::Glpi::ProcessorService.new(hook)
      result = processor.process_event('conversation.updated', conversation)

      expect(result[:success]).to be true

      # Verify followup was created with attachment URLs
      expect(WebMock).to have_requested(:post, 'https://glpi.example.com/apirest.php/Ticket/222/ITILFollowup')
        .with { |req|
          body = JSON.parse(req.body)
          body['input']['content'].include?('https://example.com/file1.png') &&
            body['input']['content'].include?('https://example.com/file2.pdf')
        }
    end
  end
end
