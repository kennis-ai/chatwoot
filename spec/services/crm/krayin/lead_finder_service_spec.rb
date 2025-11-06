# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Krayin::LeadFinderService do
  let(:api_url) { 'https://crm.example.com/api/admin' }
  let(:api_token) { SecureRandom.hex }
  let(:lead_client) { Crm::Krayin::Api::LeadClient.new(api_url, api_token) }
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact,
           account: account,
           name: 'John Doe',
           email: 'john@example.com',
           phone_number: '+1234567890')
  end
  let(:person_id) { 123 }
  let(:settings) do
    {
      'lead_source_id' => 1,
      'lead_type_id' => 2,
      'lead_pipeline_id' => 3,
      'lead_pipeline_stage_id' => 4
    }
  end

  let(:service) do
    described_class.new(
      lead_client: lead_client,
      contact: contact,
      person_id: person_id,
      settings: settings
    )
  end

  describe '#perform' do
    context 'when lead exists' do
      let(:existing_lead) { { 'id' => 456, 'title' => 'John Doe', 'person_id' => 123 } }

      before do
        allow(lead_client).to receive(:search_lead).with(email: 'john@example.com').and_return([existing_lead])
      end

      it 'returns existing lead' do
        result = service.perform

        expect(result).to eq(existing_lead)
      end

      it 'does not create new lead' do
        expect(lead_client).not_to receive(:create_lead)

        service.perform
      end
    end

    context 'when lead does not exist by email' do
      before do
        allow(lead_client).to receive(:search_lead).with(email: 'john@example.com').and_return([])
        allow(lead_client).to receive(:search_lead).with(phone: '+1234567890').and_return([])
      end

      it 'tries to find by phone' do
        expect(lead_client).to receive(:search_lead).with(phone: '+1234567890')

        allow(lead_client).to receive(:create_lead).and_return(789)
        allow(lead_client).to receive(:get_lead).and_return({ 'id' => 789 })

        service.perform
      end

      it 'creates new lead when not found' do
        expect(lead_client).to receive(:create_lead).and_return(789)
        expect(lead_client).to receive(:get_lead).with(789).and_return({ 'id' => 789, 'title' => 'John Doe' })

        result = service.perform

        expect(result['id']).to eq(789)
      end

      it 'uses ContactMapper for lead data' do
        expected_lead_data = {
          title: 'John Doe',
          person_id: 123,
          lead_value: 0.0,
          lead_source_id: 1,
          lead_type_id: 2,
          lead_pipeline_id: 3,
          lead_pipeline_stage_id: 4
        }

        expect(Crm::Krayin::Mappers::ContactMapper).to receive(:map_to_lead).with(contact, person_id, settings).and_return(expected_lead_data)
        expect(lead_client).to receive(:create_lead).with(expected_lead_data).and_return(999)
        allow(lead_client).to receive(:get_lead).with(999).and_return({ 'id' => 999 })

        service.perform
      end
    end

    context 'when lead found by phone' do
      let(:existing_lead) { { 'id' => 888, 'title' => 'John Doe' } }

      before do
        allow(lead_client).to receive(:search_lead).with(email: 'john@example.com').and_return([])
        allow(lead_client).to receive(:search_lead).with(phone: '+1234567890').and_return([existing_lead])
      end

      it 'returns lead found by phone' do
        result = service.perform

        expect(result).to eq(existing_lead)
      end

      it 'does not create new lead' do
        expect(lead_client).not_to receive(:create_lead)

        service.perform
      end
    end

    context 'when contact has only email' do
      before do
        contact.phone_number = nil
      end

      it 'only searches by email' do
        expect(lead_client).to receive(:search_lead).with(email: 'john@example.com').and_return([])
        expect(lead_client).not_to receive(:search_lead).with(hash_including(:phone))

        allow(lead_client).to receive(:create_lead).and_return(123)
        allow(lead_client).to receive(:get_lead).and_return({ 'id' => 123 })

        service.perform
      end
    end

    context 'when contact has only phone' do
      before do
        contact.email = nil
      end

      it 'only searches by phone' do
        expect(lead_client).to receive(:search_lead).with(phone: '+1234567890').and_return([])

        allow(lead_client).to receive(:create_lead).and_return(123)
        allow(lead_client).to receive(:get_lead).and_return({ 'id' => 123 })

        service.perform
      end
    end

    context 'when search returns multiple leads' do
      let(:leads) do
        [
          { 'id' => 10, 'title' => 'Lead 1' },
          { 'id' => 11, 'title' => 'Lead 2' }
        ]
      end

      before do
        allow(lead_client).to receive(:search_lead).with(email: 'john@example.com').and_return(leads)
      end

      it 'returns first lead' do
        result = service.perform

        expect(result['id']).to eq(10)
      end
    end

    context 'error handling' do
      context 'when search fails' do
        before do
          allow(lead_client).to receive(:search_lead).and_raise(
            Crm::Krayin::Api::BaseClient::ApiError.new('API Error', 500, nil)
          )
        end

        it 'logs error and returns nil' do
          expect(Rails.logger).to receive(:error).with(/Krayin LeadFinderService - Search error/)

          allow(lead_client).to receive(:create_lead).and_return(123)
          allow(lead_client).to receive(:get_lead).and_return({ 'id' => 123 })

          result = service.perform

          expect(result).to be_present
        end
      end

      context 'when create fails' do
        before do
          allow(lead_client).to receive(:search_lead).and_return([])
          allow(lead_client).to receive(:create_lead).and_raise(
            Crm::Krayin::Api::BaseClient::ApiError.new('Create failed', 422, nil)
          )
        end

        it 'logs error and raises exception' do
          expect(Rails.logger).to receive(:error).with(/Krayin LeadFinderService - Create error/)

          expect { service.perform }.to raise_error(Crm::Krayin::Api::BaseClient::ApiError)
        end
      end
    end

    context 'with settings defaults' do
      let(:settings_with_defaults) do
        {
          'default_lead_type_id' => 10,
          'default_pipeline_id' => 20,
          'default_stage_id' => 30
        }
      end

      let(:service) do
        described_class.new(
          lead_client: lead_client,
          contact: contact,
          person_id: person_id,
          settings: settings_with_defaults
        )
      end

      it 'passes settings to ContactMapper' do
        allow(lead_client).to receive(:search_lead).and_return([])

        expect(Crm::Krayin::Mappers::ContactMapper).to receive(:map_to_lead)
          .with(contact, person_id, settings_with_defaults)
          .and_return({ title: 'Test' })

        allow(lead_client).to receive(:create_lead).and_return(123)
        allow(lead_client).to receive(:get_lead).and_return({ 'id' => 123 })

        service.perform
      end
    end
  end
end
