# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Krayin::PersonFinderService do
  let(:api_url) { 'https://crm.example.com/api/admin' }
  let(:api_token) { SecureRandom.hex }
  let(:person_client) { Crm::Krayin::Api::PersonClient.new(api_url, api_token) }
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact,
           account: account,
           name: 'John Doe',
           email: 'john@example.com',
           phone_number: '+1234567890')
  end

  let(:service) do
    described_class.new(
      person_client: person_client,
      contact: contact
    )
  end

  describe '#perform' do
    context 'when person exists' do
      let(:existing_person) { { 'id' => 123, 'name' => 'John Doe', 'emails' => [{ 'value' => 'john@example.com' }] } }

      before do
        allow(person_client).to receive(:search_person).with(email: 'john@example.com').and_return([existing_person])
      end

      it 'returns existing person' do
        result = service.perform

        expect(result).to eq(existing_person)
      end

      it 'does not create new person' do
        expect(person_client).not_to receive(:create_person)

        service.perform
      end
    end

    context 'when person does not exist by email' do
      before do
        allow(person_client).to receive(:search_person).with(email: 'john@example.com').and_return([])
        allow(person_client).to receive(:search_person).with(phone: '+1234567890').and_return([])
      end

      it 'tries to find by phone' do
        expect(person_client).to receive(:search_person).with(phone: '+1234567890')

        allow(person_client).to receive(:create_person).and_return(456)
        allow(person_client).to receive(:get_person).and_return({ 'id' => 456 })

        service.perform
      end

      it 'creates new person when not found' do
        expect(person_client).to receive(:create_person).and_return(456)
        expect(person_client).to receive(:get_person).with(456).and_return({ 'id' => 456, 'name' => 'John Doe' })

        result = service.perform

        expect(result['id']).to eq(456)
      end

      it 'uses ContactMapper for person data' do
        expected_person_data = {
          name: 'John Doe',
          emails: [{ value: 'john@example.com', label: 'work' }],
          contact_numbers: [{ value: '+1234567890', label: 'work' }]
        }

        expect(Crm::Krayin::Mappers::ContactMapper).to receive(:map_to_person).with(contact).and_return(expected_person_data)
        expect(person_client).to receive(:create_person).with(expected_person_data).and_return(789)
        allow(person_client).to receive(:get_person).with(789).and_return({ 'id' => 789 })

        service.perform
      end
    end

    context 'when person found by phone' do
      let(:existing_person) { { 'id' => 999, 'name' => 'John Doe' } }

      before do
        allow(person_client).to receive(:search_person).with(email: 'john@example.com').and_return([])
        allow(person_client).to receive(:search_person).with(phone: '+1234567890').and_return([existing_person])
      end

      it 'returns person found by phone' do
        result = service.perform

        expect(result).to eq(existing_person)
      end

      it 'does not create new person' do
        expect(person_client).not_to receive(:create_person)

        service.perform
      end
    end

    context 'when contact has only email' do
      before do
        contact.phone_number = nil
      end

      it 'only searches by email' do
        expect(person_client).to receive(:search_person).with(email: 'john@example.com').and_return([])
        expect(person_client).not_to receive(:search_person).with(hash_including(:phone))

        allow(person_client).to receive(:create_person).and_return(123)
        allow(person_client).to receive(:get_person).and_return({ 'id' => 123 })

        service.perform
      end
    end

    context 'when contact has only phone' do
      before do
        contact.email = nil
      end

      it 'only searches by phone' do
        expect(person_client).to receive(:search_person).with(phone: '+1234567890').and_return([])

        allow(person_client).to receive(:create_person).and_return(123)
        allow(person_client).to receive(:get_person).and_return({ 'id' => 123 })

        service.perform
      end
    end

    context 'when search returns multiple persons' do
      let(:persons) do
        [
          { 'id' => 1, 'name' => 'John Doe' },
          { 'id' => 2, 'name' => 'John Doe Jr.' }
        ]
      end

      before do
        allow(person_client).to receive(:search_person).with(email: 'john@example.com').and_return(persons)
      end

      it 'returns first person' do
        result = service.perform

        expect(result['id']).to eq(1)
      end
    end

    context 'error handling' do
      context 'when search fails' do
        before do
          allow(person_client).to receive(:search_person).and_raise(
            Crm::Krayin::Api::BaseClient::ApiError.new('API Error', 500, nil)
          )
        end

        it 'logs error and returns nil' do
          expect(Rails.logger).to receive(:error).with(/Krayin PersonFinderService - Search error/)

          allow(person_client).to receive(:create_person).and_return(123)
          allow(person_client).to receive(:get_person).and_return({ 'id' => 123 })

          result = service.perform

          expect(result).to be_present
        end
      end

      context 'when create fails' do
        before do
          allow(person_client).to receive(:search_person).and_return([])
          allow(person_client).to receive(:create_person).and_raise(
            Crm::Krayin::Api::BaseClient::ApiError.new('Create failed', 422, nil)
          )
        end

        it 'logs error and raises exception' do
          expect(Rails.logger).to receive(:error).with(/Krayin PersonFinderService - Create error/)

          expect { service.perform }.to raise_error(Crm::Krayin::Api::BaseClient::ApiError)
        end
      end
    end
  end
end
