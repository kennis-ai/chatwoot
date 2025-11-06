# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::ContactFinderService do
  let(:account) { create(:account) }
  let(:entity_id) { 0 }
  let(:contact_client) do
    Crm::Glpi::Api::ContactClient.new(
      api_url: 'https://glpi.example.com/apirest.php',
      app_token: 'test_app_token',
      user_token: 'test_user_token'
    )
  end
  let(:service) { described_class.new(contact_client, entity_id) }

  describe '#find_or_create' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'Alice Cooper',
             email: 'alice@example.com',
             phone_number: '+12345678900')
    end

    context 'when contact has stored contact_id' do
      before do
        contact.additional_attributes = {
          'external' => { 'glpi_contact_id' => 321 }
        }
        contact.save!
      end

      it 'returns stored contact_id without API call' do
        result = service.find_or_create(contact)
        expect(result).to eq(321)
      end
    end

    context 'when contact exists by email' do
      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/Contact})
          .with(query: hash_including('criteria' => anything))
          .to_return(status: 200, body: { data: [{ id: 654 }] }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'finds and returns existing contact_id' do
        result = service.find_or_create(contact)
        expect(result).to eq(654)
      end
    end

    context 'when contact does not exist' do
      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        # Search returns empty
        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/Contact})
          .to_return(status: 200, body: { data: [] }.to_json)

        # Create contact
        stub_request(:post, 'https://glpi.example.com/apirest.php/Contact')
          .to_return(status: 201, body: { id: 987, message: 'Contact created' }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'creates new contact and returns contact_id' do
        result = service.find_or_create(contact)
        expect(result).to eq(987)
      end
    end

    context 'when contact has no email' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Bob Johnson',
               email: nil,
               phone_number: '+12345678900')
      end

      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:post, 'https://glpi.example.com/apirest.php/Contact')
          .to_return(status: 201, body: { id: 111, message: 'Contact created' }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'creates contact with available data' do
        result = service.find_or_create(contact)
        expect(result).to eq(111)
      end
    end

    context 'when API returns error' do
      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/Contact})
          .to_return(status: 500, body: { 0 => 'ERROR_INTERNAL' }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'returns nil on API error' do
        result = service.find_or_create(contact)
        expect(result).to be_nil
      end
    end

    context 'when create returns no ID' do
      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/Contact})
          .to_return(status: 200, body: { data: [] }.to_json)

        stub_request(:post, 'https://glpi.example.com/apirest.php/Contact')
          .to_return(status: 201, body: { message: 'Contact created' }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'returns nil when create fails to return ID' do
        result = service.find_or_create(contact)
        expect(result).to be_nil
      end
    end
  end
end
