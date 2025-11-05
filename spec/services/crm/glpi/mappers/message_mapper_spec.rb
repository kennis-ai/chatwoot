# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Mappers::MessageMapper do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'John Doe') }
  let(:user) { create(:user, account: account, name: 'Agent Smith') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:ticket_id) { 789 }
  let(:settings) { {} }

  describe '.map_to_followup' do
    context 'with public message from contact' do
      let(:message) do
        create(:message,
               conversation: conversation,
               account: account,
               inbox: inbox,
               content: 'I have a question about billing',
               message_type: :incoming,
               private: false,
               sender: contact)
      end

      it 'maps all fields correctly' do
        result = described_class.map_to_followup(message, ticket_id, settings)

        expect(result[:itemtype]).to eq('Ticket')
        expect(result[:items_id]).to eq(ticket_id)
        expect(result[:content]).to include('John Doe')
        expect(result[:content]).to include('I have a question about billing')
        expect(result[:is_private]).to eq(0)
        expect(result[:date]).to eq(message.created_at.iso8601)
        expect(result[:users_id]).to eq(0)
      end
    end

    context 'with private message' do
      let(:message) do
        create(:message,
               conversation: conversation,
               account: account,
               inbox: inbox,
               content: 'Internal note: customer is VIP',
               message_type: :outgoing,
               private: true,
               sender: user)
      end

      it 'marks followup as private' do
        result = described_class.map_to_followup(message, ticket_id, settings)

        expect(result[:is_private]).to eq(1)
        expect(result[:content]).to include('Agent Smith')
        expect(result[:content]).to include('Internal note')
      end
    end

    context 'with custom user_id setting' do
      let(:settings) { { 'default_user_id' => 42 } }
      let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, sender: contact) }

      it 'uses custom user_id' do
        result = described_class.map_to_followup(message, ticket_id, settings)

        expect(result[:users_id]).to eq(42)
      end
    end

    context 'with message containing attachments' do
      let(:message) do
        create(:message,
               conversation: conversation,
               account: account,
               inbox: inbox,
               content: 'Please see the screenshot',
               sender: contact)
      end

      before do
        allow(message).to receive(:attachments).and_return([
                                                              double(file_url: 'https://example.com/file1.png'),
                                                              double(file_url: 'https://example.com/file2.pdf')
                                                            ])
      end

      it 'includes attachment URLs in content' do
        result = described_class.map_to_followup(message, ticket_id, settings)

        expect(result[:content]).to include('Attachments:')
        expect(result[:content]).to include('- https://example.com/file1.png')
        expect(result[:content]).to include('- https://example.com/file2.pdf')
      end
    end

    context 'with message without sender' do
      let(:message) do
        create(:message,
               conversation: conversation,
               account: account,
               inbox: inbox,
               content: 'System message',
               message_type: :activity,
               sender: nil)
      end

      it 'uses Unknown as sender' do
        result = described_class.map_to_followup(message, ticket_id, settings)

        expect(result[:content]).to include('Unknown:')
        expect(result[:content]).to include('System message')
      end
    end
  end

  describe '.format_message_content' do
    let(:message) do
      create(:message,
             conversation: conversation,
             account: account,
             inbox: inbox,
             content: 'Test message content',
             sender: contact,
             created_at: Time.zone.parse('2025-01-05 14:30:00'))
    end

    context 'without attachments' do
      before do
        allow(message).to receive(:attachments).and_return([])
      end

      it 'formats content with timestamp and sender' do
        result = described_class.format_message_content(message)

        expect(result).to eq("[2025-01-05 14:30:00] John Doe:\nTest message content")
      end
    end

    context 'with attachments' do
      before do
        allow(message).to receive(:attachments).and_return([
                                                              double(file_url: 'https://example.com/file.png')
                                                            ])
      end

      it 'includes attachment list' do
        result = described_class.format_message_content(message)

        expect(result).to include('Test message content')
        expect(result).to include("\n\nAttachments:\n- https://example.com/file.png")
      end
    end

    context 'with multiple attachments' do
      before do
        allow(message).to receive(:attachments).and_return([
                                                              double(file_url: 'https://example.com/file1.png'),
                                                              double(file_url: 'https://example.com/file2.pdf'),
                                                              double(file_url: 'https://example.com/file3.docx')
                                                            ])
      end

      it 'lists all attachments' do
        result = described_class.format_message_content(message)

        expect(result).to include('- https://example.com/file1.png')
        expect(result).to include('- https://example.com/file2.pdf')
        expect(result).to include('- https://example.com/file3.docx')
      end
    end

    context 'with nil sender' do
      let(:message) do
        create(:message,
               conversation: conversation,
               account: account,
               inbox: inbox,
               content: 'No sender',
               sender: nil)
      end

      before do
        allow(message).to receive(:attachments).and_return([])
      end

      it 'uses Unknown as sender name' do
        result = described_class.format_message_content(message)

        expect(result).to include('Unknown:')
      end
    end
  end
end
