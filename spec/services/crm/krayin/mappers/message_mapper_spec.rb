# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Krayin::Mappers::MessageMapper do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'John Doe', email: 'john@example.com') }
  let(:user) { create(:user, account: account, name: 'Agent Smith') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }
  let(:person_id) { 123 }
  let(:settings) { {} }

  describe '.map_to_activity' do
    context 'with outgoing message' do
      let(:message) { create(:message, conversation: conversation, account: account, message_type: 'outgoing', sender: user, content: 'Test message') }

      it 'returns activity data with type email' do
        result = described_class.map_to_activity(message, person_id, settings)

        expect(result[:type]).to eq('email')
        expect(result[:person_id]).to eq(123)
        expect(result[:is_done]).to be true
      end

      it 'includes agent name in title' do
        result = described_class.map_to_activity(message, person_id, settings)

        expect(result[:title]).to include('Agent Smith')
        expect(result[:title]).to include("Conversation ##{conversation.display_id}")
      end
    end

    context 'with incoming message' do
      let(:message) { create(:message, conversation: conversation, account: account, message_type: 'incoming', sender: contact, content: 'Help request') }

      it 'returns activity data with type note' do
        result = described_class.map_to_activity(message, person_id, settings)

        expect(result[:type]).to eq('note')
      end

      it 'includes contact name in title' do
        result = described_class.map_to_activity(message, person_id, settings)

        expect(result[:title]).to include('John Doe')
      end
    end

    context 'with activity message' do
      let(:message) { create(:message, conversation: conversation, account: account, message_type: 'activity', content: 'Status changed') }

      it 'defaults to note type' do
        result = described_class.map_to_activity(message, person_id, settings)

        expect(result[:type]).to eq('note')
      end
    end
  end

  describe 'comment content' do
    let(:message) { create(:message, conversation: conversation, account: account, message_type: 'incoming', sender: contact, content: 'Test content') }

    it 'includes message details section' do
      result = described_class.map_to_activity(message, person_id, settings)

      expect(result[:comment]).to include('Message Details')
      expect(result[:comment]).to include('From: john@example.com')
      expect(result[:comment]).to include('Type: Incoming')
      expect(result[:comment]).to include('Timestamp:')
    end

    it 'includes message content' do
      result = described_class.map_to_activity(message, person_id, settings)

      expect(result[:comment]).to include('Message Content')
      expect(result[:comment]).to include('Test content')
    end

    it 'includes conversation context' do
      result = described_class.map_to_activity(message, person_id, settings)

      expect(result[:comment]).to include('Conversation Context')
      expect(result[:comment]).to include("Conversation ID: #{conversation.display_id}")
      expect(result[:comment]).to include('Status: Open')
      expect(result[:comment]).to include("Inbox: #{inbox.name}")
    end

    it 'includes brand name as source' do
      allow(GlobalConfig).to receive(:get).with('BRAND_NAME').and_return({ 'BRAND_NAME' => 'TestBrand' })

      result = described_class.map_to_activity(message, person_id, settings)

      expect(result[:comment]).to include('Source: TestBrand')
    end

    it 'strips HTML from content' do
      message.content = '<p>Hello <strong>world</strong></p>'

      result = described_class.map_to_activity(message, person_id, settings)

      expect(result[:comment]).to include('Hello world')
      expect(result[:comment]).not_to include('<p>')
      expect(result[:comment]).not_to include('<strong>')
    end

    it 'shows "[No content]" when content is blank' do
      message.content = nil

      result = described_class.map_to_activity(message, person_id, settings)

      expect(result[:comment]).to include('[No content]')
    end
  end

  describe 'attachments' do
    let(:message) { create(:message, conversation: conversation, account: account, sender: contact) }

    before do
      # Mock attachment
      attachment = instance_double('Attachment',
                                   file_type: 'image',
                                   file: double(filename: 'test.png'),
                                   file_size: 1024 * 500) # 500 KB
      allow(message).to receive(:attachments).and_return([attachment])
    end

    it 'includes attachments section' do
      result = described_class.map_to_activity(message, person_id, settings)

      expect(result[:comment]).to include('Attachments')
      expect(result[:comment]).to include('image: test.png')
      expect(result[:comment]).to include('KB')
    end
  end

  describe 'instance methods' do
    let(:mapper) { described_class.new(create(:message, conversation: conversation, account: account, sender: contact)) }

    describe '#sender_info' do
      it 'returns email for contact with email' do
        message = create(:message, conversation: conversation, account: account, sender: contact)
        mapper = described_class.new(message)

        expect(mapper.send(:sender_info)).to eq('john@example.com')
      end

      it 'returns phone for contact without email' do
        contact.email = nil
        contact.phone_number = '+1234567890'
        message = create(:message, conversation: conversation, account: account, sender: contact)
        mapper = described_class.new(message)

        expect(mapper.send(:sender_info)).to eq('+1234567890')
      end

      it 'returns name with (Agent) for user' do
        message = create(:message, conversation: conversation, account: account, sender: user)
        mapper = described_class.new(message)

        expect(mapper.send(:sender_info)).to eq('Agent Smith (Agent)')
      end

      it 'returns "System" when no sender' do
        message = create(:message, conversation: conversation, account: account, sender: nil)
        mapper = described_class.new(message)

        expect(mapper.send(:sender_info)).to eq('System')
      end
    end

    describe '#format_file_size' do
      it 'formats bytes' do
        expect(mapper.send(:format_file_size, 500)).to eq('500.00 B')
      end

      it 'formats kilobytes' do
        expect(mapper.send(:format_file_size, 1024 * 5)).to eq('5.00 KB')
      end

      it 'formats megabytes' do
        expect(mapper.send(:format_file_size, 1024 * 1024 * 2)).to eq('2.00 MB')
      end

      it 'formats gigabytes' do
        expect(mapper.send(:format_file_size, 1024 * 1024 * 1024 * 3)).to eq('3.00 GB')
      end

      it 'returns "0 B" for nil' do
        expect(mapper.send(:format_file_size, nil)).to eq('0 B')
      end

      it 'returns "0 B" for zero' do
        expect(mapper.send(:format_file_size, 0)).to eq('0 B')
      end
    end

    describe '#format_message_content' do
      it 'returns plain text from HTML' do
        message = create(:message, conversation: conversation, account: account, sender: contact,
                                   content: '<div><p>Hello</p><p>World</p></div>')
        mapper = described_class.new(message)

        content = mapper.send(:format_message_content)

        expect(content).to include('Hello')
        expect(content).to include('World')
        expect(content).not_to include('<div>')
      end

      it 'returns "[No content]" for blank content' do
        message = create(:message, conversation: conversation, account: account, sender: contact, content: nil)
        mapper = described_class.new(message)

        expect(mapper.send(:format_message_content)).to eq('[No content]')
      end
    end

    describe '#brand_name' do
      it 'returns configured brand name' do
        allow(GlobalConfig).to receive(:get).with('BRAND_NAME').and_return({ 'BRAND_NAME' => 'MyBrand' })

        expect(mapper.send(:brand_name)).to eq('MyBrand')
      end

      it 'returns Chatwoot as default' do
        allow(GlobalConfig).to receive(:get).with('BRAND_NAME').and_return({})

        expect(mapper.send(:brand_name)).to eq('Chatwoot')
      end
    end
  end
end
