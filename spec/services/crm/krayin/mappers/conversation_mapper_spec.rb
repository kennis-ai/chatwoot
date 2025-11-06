# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Krayin::Mappers::ConversationMapper do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:user) { create(:user, account: account) }
  let(:conversation) do
    create(:conversation,
           account: account,
           inbox: inbox,
           contact: contact,
           assignee: user,
           status: 'open',
           priority: 1)
  end
  let(:person_id) { 123 }
  let(:settings) { {} }

  before do
    # Create some messages for the conversation
    create(:message, conversation: conversation, account: account, content: 'First message', sender: contact, created_at: 1.hour.ago)
    create(:message, conversation: conversation, account: account, content: 'Second message', sender: user, created_at: 30.minutes.ago)
  end

  describe '.map_to_activity' do
    it 'returns activity data with type note' do
      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:type]).to eq('note')
      expect(result[:person_id]).to eq(123)
    end

    it 'sets title with conversation display_id' do
      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:title]).to eq("Conversation ##{conversation.display_id}")
    end

    it 'includes conversation details in comment' do
      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include("ID: #{conversation.display_id}")
      expect(result[:comment]).to include('Status: Open')
      expect(result[:comment]).to include("Inbox: #{inbox.name}")
      expect(result[:comment]).to include("Assignee: #{user.name}")
    end

    it 'shows Unassigned when no assignee' do
      conversation.assignee = nil

      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include('Assignee: Unassigned')
    end

    it 'includes priority in comment' do
      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include('Priority: 1')
    end

    it 'includes labels when present' do
      label = create(:label, account: account, title: 'urgent')
      conversation.labels << label

      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include('Labels: urgent')
    end

    it 'includes custom attributes when present' do
      conversation.custom_attributes = { 'priority_level' => 'high', 'source' => 'web' }
      conversation.save!

      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include('Custom Attributes')
      expect(result[:comment]).to include('Priority level')
      expect(result[:comment]).to include('high')
    end

    it 'includes conversation URL' do
      ENV['FRONTEND_URL'] = 'https://app.example.com'

      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include('View Conversation')
      expect(result[:comment]).to include("https://app.example.com/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
    end

    it 'includes recent messages summary' do
      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include('Recent Messages')
      expect(result[:comment]).to include('First message')
      expect(result[:comment]).to include('Second message')
      expect(result[:comment]).to include(contact.name)
      expect(result[:comment]).to include(user.name)
    end

    it 'includes brand name as source' do
      allow(GlobalConfig).to receive(:get).with('BRAND_NAME').and_return({ 'BRAND_NAME' => 'TestBrand' })

      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:comment]).to include('Source: TestBrand')
    end

    it 'sets is_done to true when conversation is resolved' do
      conversation.status = 'resolved'

      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:is_done]).to be true
    end

    it 'sets is_done to false when conversation is not resolved' do
      conversation.status = 'open'

      result = described_class.map_to_activity(conversation, person_id, settings)

      expect(result[:is_done]).to be false
    end
  end

  describe 'instance methods' do
    let(:mapper) { described_class.new(conversation) }

    describe '#message_summary' do
      it 'returns message list with timestamps' do
        summary = mapper.send(:message_summary)

        expect(summary).to include('First message')
        expect(summary).to include('Second message')
        expect(summary).to include(contact.name)
        expect(summary).to include(user.name)
      end

      it 'limits to 5 messages' do
        6.times { |i| create(:message, conversation: conversation, account: account, content: "Message #{i}", sender: contact) }

        summary = mapper.send(:message_summary)

        # Should only include 5 most recent messages
        lines = summary.split("\n")
        expect(lines.length).to eq(5)
      end

      it 'returns "No messages yet" when no messages' do
        conversation.messages.destroy_all

        summary = mapper.send(:message_summary)

        expect(summary).to eq('No messages yet')
      end

      it 'truncates long messages' do
        long_content = 'a' * 200
        create(:message, conversation: conversation, account: account, content: long_content, sender: contact)

        summary = mapper.send(:message_summary)

        expect(summary).to include('...')
      end

      it 'strips HTML from message content' do
        html_content = '<p>Hello <strong>world</strong></p>'
        create(:message, conversation: conversation, account: account, content: html_content, sender: contact)

        summary = mapper.send(:message_summary)

        expect(summary).to include('Hello world')
        expect(summary).not_to include('<p>')
        expect(summary).not_to include('<strong>')
      end
    end

    describe '#conversation_url' do
      it 'generates correct URL' do
        ENV['FRONTEND_URL'] = 'https://test.com'

        url = mapper.send(:conversation_url)

        expect(url).to eq("https://test.com/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
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
