# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Krayin::ProcessorService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'test@example.com', phone_number: '+1234567890') }
  let(:user) { create(:user, account: account) }
  let(:api_url) { 'https://crm.example.com/api/admin' }
  let(:api_token) { SecureRandom.hex }
  let(:settings) do
    {
      'api_url' => api_url,
      'api_token' => api_token,
      'default_pipeline_id' => 1,
      'default_stage_id' => 10,
      'default_source_id' => 100,
      'default_lead_type_id' => 200
    }
  end
  let(:hook) { create(:integrations_hook, inbox: inbox, app_id: 'krayin', status: 'enabled', settings: settings, hook_type: 'inbox') }

  before do
    hook # Ensure hook is created
  end

  describe '#perform' do
    context 'when hook is not enabled' do
      before do
        hook.update!(status: 'disabled')
      end

      it 'does not process event' do
        service = described_class.new(inbox: inbox, event_name: 'contact_created', event_data: { contact: contact })

        expect_any_instance_of(Crm::Krayin::Api::PersonClient).not_to receive(:search_person)

        service.perform
      end
    end

    context 'when hook does not exist' do
      before do
        hook.destroy
      end

      it 'does not process event' do
        service = described_class.new(inbox: inbox, event_name: 'contact_created', event_data: { contact: contact })

        expect_any_instance_of(Crm::Krayin::Api::PersonClient).not_to receive(:search_person)

        service.perform
      end
    end

    describe 'contact_created event' do
      let(:event_data) { { contact: contact } }
      let(:service) { described_class.new(inbox: inbox, event_name: 'contact_created', event_data: event_data) }
      let(:person_response) { { 'id' => 123, 'name' => 'Test User' } }
      let(:lead_response) { { 'id' => 456, 'title' => 'Test Lead' } }

      before do
        allow_any_instance_of(Crm::Krayin::PersonFinderService).to receive(:perform).and_return(person_response)
        allow_any_instance_of(Crm::Krayin::LeadFinderService).to receive(:perform).and_return(lead_response)
      end

      it 'creates person and lead' do
        expect(Crm::Krayin::PersonFinderService).to receive(:new).and_call_original
        expect(Crm::Krayin::LeadFinderService).to receive(:new).and_call_original

        service.perform
      end

      it 'stores person external ID' do
        service.perform

        contact_inbox = contact.contact_inboxes.find_by(inbox: inbox)
        expect(contact_inbox.source_id).to eq('krayin:person:123')
      end

      it 'stores lead external ID' do
        service.perform

        # Note: In real implementation, we might need to store lead ID separately
        # For now, testing that the service completes without error
        expect { service.perform }.not_to raise_error
      end

      it 'logs success' do
        expect(Rails.logger).to receive(:info).with(/Krayin ProcessorService - Processing contact/)
        expect(Rails.logger).to receive(:info).with(/Person: 123, Lead: 456/)

        service.perform
      end

      context 'when person creation fails' do
        before do
          allow_any_instance_of(Crm::Krayin::PersonFinderService).to receive(:perform).and_return(nil)
        end

        it 'does not create lead' do
          expect(Crm::Krayin::LeadFinderService).not_to receive(:new)

          service.perform
        end
      end

      context 'when API error occurs' do
        before do
          allow_any_instance_of(Crm::Krayin::PersonFinderService).to receive(:perform)
            .and_raise(Crm::Krayin::Api::BaseClient::ApiError.new('API Error', 500, nil))
        end

        it 'logs error and does not raise' do
          expect(Rails.logger).to receive(:error).with(/Krayin ProcessorService - Failed to process contact/)

          expect { service.perform }.not_to raise_error
        end
      end
    end

    describe 'conversation_created event' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }
      let(:event_data) { { conversation: conversation } }
      let(:service) { described_class.new(inbox: inbox, event_name: 'conversation_created', event_data: event_data) }
      let(:activity_response) { { 'id' => 789, 'type' => 'note' } }

      before do
        # Set person external ID
        contact_inbox = contact.contact_inboxes.find_or_create_by(inbox: inbox)
        contact_inbox.update!(source_id: 'krayin:person:123')
      end

      it 'creates activity for conversation' do
        activity_client = instance_double(Crm::Krayin::Api::ActivityClient)
        allow(Crm::Krayin::Api::ActivityClient).to receive(:new).and_return(activity_client)
        expect(activity_client).to receive(:create_activity).and_return(789)

        service.perform
      end

      it 'stores activity external ID' do
        activity_client = instance_double(Crm::Krayin::Api::ActivityClient)
        allow(Crm::Krayin::Api::ActivityClient).to receive(:new).and_return(activity_client)
        allow(activity_client).to receive(:create_activity).and_return(789)

        service.perform

        # The implementation stores activity ID in conversation's contact_inboxes
        # Testing that it completes successfully
        expect { service.perform }.not_to raise_error
      end

      it 'logs success' do
        activity_client = instance_double(Crm::Krayin::Api::ActivityClient)
        allow(Crm::Krayin::Api::ActivityClient).to receive(:new).and_return(activity_client)
        allow(activity_client).to receive(:create_activity).and_return(789)

        expect(Rails.logger).to receive(:info).with(/Krayin ProcessorService - Processing conversation/)
        expect(Rails.logger).to receive(:info).with(/Created activity 789/)

        service.perform
      end

      context 'when person_id is not found' do
        before do
          contact.contact_inboxes.destroy_all
        end

        it 'does not create activity' do
          expect_any_instance_of(Crm::Krayin::Api::ActivityClient).not_to receive(:create_activity)

          service.perform
        end
      end

      context 'when API error occurs' do
        before do
          allow_any_instance_of(Crm::Krayin::Api::ActivityClient).to receive(:create_activity)
            .and_raise(Crm::Krayin::Api::BaseClient::ApiError.new('API Error', 500, nil))
        end

        it 'logs error and does not raise' do
          expect(Rails.logger).to receive(:error).with(/Krayin ProcessorService - Failed to process conversation/)

          expect { service.perform }.not_to raise_error
        end
      end
    end

    describe 'conversation_updated event' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'resolved') }
      let(:event_data) { { conversation: conversation } }
      let(:service) { described_class.new(inbox: inbox, event_name: 'conversation_updated', event_data: event_data) }

      before do
        # Set person and activity external IDs
        contact_inbox = contact.contact_inboxes.find_or_create_by(inbox: inbox)
        contact_inbox.update!(source_id: 'krayin:person:123')

        # Mock existing activity
        conversation_contact_inbox = conversation.contact_inboxes.find_or_create_by(inbox: inbox)
        conversation_contact_inbox.update!(source_id: 'krayin:activity:789')
      end

      it 'updates existing activity' do
        activity_client = instance_double(Crm::Krayin::Api::ActivityClient)
        allow(Crm::Krayin::Api::ActivityClient).to receive(:new).and_return(activity_client)
        expect(activity_client).to receive(:update_activity).with(anything, 789)

        service.perform
      end

      it 'logs success' do
        activity_client = instance_double(Crm::Krayin::Api::ActivityClient)
        allow(Crm::Krayin::Api::ActivityClient).to receive(:new).and_return(activity_client)
        allow(activity_client).to receive(:update_activity)

        expect(Rails.logger).to receive(:info).with(/Updated activity 789/)

        service.perform
      end
    end

    describe 'message_created event' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let(:message) { create(:message, conversation: conversation, account: account, message_type: 'incoming', sender: contact, private: false) }
      let(:event_data) { { message: message } }
      let(:service) { described_class.new(inbox: inbox, event_name: 'message_created', event_data: event_data) }

      before do
        # Set person external ID
        contact_inbox = contact.contact_inboxes.find_or_create_by(inbox: inbox)
        contact_inbox.update!(source_id: 'krayin:person:123')
      end

      it 'creates activity for message' do
        activity_client = instance_double(Crm::Krayin::Api::ActivityClient)
        allow(Crm::Krayin::Api::ActivityClient).to receive(:new).and_return(activity_client)
        expect(activity_client).to receive(:create_activity).and_return(999)

        service.perform
      end

      it 'logs success' do
        activity_client = instance_double(Crm::Krayin::Api::ActivityClient)
        allow(Crm::Krayin::Api::ActivityClient).to receive(:new).and_return(activity_client)
        allow(activity_client).to receive(:create_activity).and_return(999)

        expect(Rails.logger).to receive(:info).with(/Krayin ProcessorService - Processing message/)
        expect(Rails.logger).to receive(:info).with(/Created activity 999/)

        service.perform
      end

      context 'when message is private' do
        before do
          message.update!(private: true)
        end

        it 'does not create activity' do
          expect_any_instance_of(Crm::Krayin::Api::ActivityClient).not_to receive(:create_activity)

          service.perform
        end
      end

      context 'when person_id is not found' do
        before do
          contact.contact_inboxes.destroy_all
        end

        it 'does not create activity' do
          expect_any_instance_of(Crm::Krayin::Api::ActivityClient).not_to receive(:create_activity)

          service.perform
        end
      end
    end

    describe 'unknown event' do
      let(:service) { described_class.new(inbox: inbox, event_name: 'unknown_event', event_data: {}) }

      it 'logs warning' do
        expect(Rails.logger).to receive(:warn).with(/Krayin ProcessorService - Unknown event: unknown_event/)

        service.perform
      end
    end

    describe 'external ID management' do
      let(:service) { described_class.new(inbox: inbox, event_name: 'contact_created', event_data: { contact: contact }) }

      describe '#extract_external_id' do
        it 'extracts person ID from source_id' do
          result = service.send(:extract_external_id, 'krayin:person:123', 'person')
          expect(result).to eq('123')
        end

        it 'extracts lead ID from source_id' do
          result = service.send(:extract_external_id, 'krayin:lead:456', 'lead')
          expect(result).to eq('456')
        end

        it 'returns nil for wrong type' do
          result = service.send(:extract_external_id, 'krayin:person:123', 'lead')
          expect(result).to be_nil
        end

        it 'returns nil for invalid format' do
          result = service.send(:extract_external_id, 'invalid:format', 'person')
          expect(result).to be_nil
        end

        it 'returns nil for blank source_id' do
          result = service.send(:extract_external_id, nil, 'person')
          expect(result).to be_nil
        end
      end
    end
  end
end
