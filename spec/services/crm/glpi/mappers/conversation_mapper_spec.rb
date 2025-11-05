# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Mappers::ConversationMapper do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'John Doe') }
  let(:user) { create(:user, account: account, name: 'Agent Smith') }
  let(:requester_id) { 456 }
  let(:entity_id) { 0 }
  let(:settings) { {} }

  describe '.map_to_ticket' do
    context 'with complete conversation data' do
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
               content: 'I need help with my account',
               message_type: :incoming,
               sender: contact)
      end

      it 'maps all fields correctly' do
        result = described_class.map_to_ticket(conversation, requester_id, entity_id, settings)

        expect(result[:name]).to eq("Conversation ##{conversation.display_id}")
        expect(result[:content]).to include('John Doe')
        expect(result[:content]).to include('I need help with my account')
        expect(result[:status]).to eq(2) # Processing
        expect(result[:priority]).to eq(4) # High
        expect(result[:_users_id_requester]).to eq(requester_id)
        expect(result[:entities_id]).to eq(entity_id)
        expect(result[:type]).to eq(1) # Default Incident
      end
    end

    context 'with custom settings' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let(:settings) { { 'ticket_type' => 2, 'category_id' => 10 } }

      it 'uses custom settings' do
        result = described_class.map_to_ticket(conversation, requester_id, entity_id, settings)

        expect(result[:type]).to eq(2) # Request
        expect(result[:itilcategories_id]).to eq(10)
      end
    end

    context 'without first message' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

      it 'generates default content' do
        result = described_class.map_to_ticket(conversation, requester_id, entity_id, settings)

        expect(result[:content]).to eq('New conversation from John Doe')
      end
    end

    context 'with conversation missing contact name' do
      let(:contact) { create(:contact, account: account, name: nil) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

      it 'uses Unknown as fallback' do
        result = described_class.map_to_ticket(conversation, requester_id, entity_id, settings)

        expect(result[:content]).to eq('New conversation from Unknown')
      end
    end
  end

  describe '.map_status' do
    it 'maps open to Processing' do
      expect(described_class.map_status('open')).to eq(2)
    end

    it 'maps pending to Pending' do
      expect(described_class.map_status('pending')).to eq(4)
    end

    it 'maps resolved to Solved' do
      expect(described_class.map_status('resolved')).to eq(5)
    end

    it 'maps snoozed to Processing' do
      expect(described_class.map_status('snoozed')).to eq(2)
    end

    it 'defaults to New for unknown status' do
      expect(described_class.map_status('unknown')).to eq(1)
    end

    it 'defaults to New for nil status' do
      expect(described_class.map_status(nil)).to eq(1)
    end
  end

  describe '.map_priority' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    context 'with low priority' do
      before { conversation.update!(priority: :low) }

      it 'returns GLPI Low priority' do
        expect(described_class.map_priority(conversation)).to eq(2)
      end
    end

    context 'with medium priority' do
      before { conversation.update!(priority: :medium) }

      it 'returns GLPI Medium priority' do
        expect(described_class.map_priority(conversation)).to eq(3)
      end
    end

    context 'with high priority' do
      before { conversation.update!(priority: :high) }

      it 'returns GLPI High priority' do
        expect(described_class.map_priority(conversation)).to eq(4)
      end
    end

    context 'with urgent priority' do
      before { conversation.update!(priority: :urgent) }

      it 'returns GLPI Very High priority' do
        expect(described_class.map_priority(conversation)).to eq(5)
      end
    end

    context 'with nil priority' do
      before { conversation.update!(priority: nil) }

      it 'defaults to Medium priority' do
        expect(described_class.map_priority(conversation)).to eq(3)
      end
    end
  end

  describe 'status constants' do
    it 'has correct status mappings' do
      expect(described_class::CHATWOOT_TO_GLPI_STATUS).to eq({
                                                                'open' => 2,
                                                                'pending' => 4,
                                                                'resolved' => 5,
                                                                'snoozed' => 2
                                                              })
    end
  end

  describe 'priority constants' do
    it 'has correct priority mappings' do
      expect(described_class::CHATWOOT_TO_GLPI_PRIORITY).to eq({
                                                                  'low' => 2,
                                                                  'medium' => 3,
                                                                  'high' => 4,
                                                                  'urgent' => 5
                                                                })
    end
  end
end
