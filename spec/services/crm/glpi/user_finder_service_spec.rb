# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::UserFinderService do
  let(:account) { create(:account) }
  let(:entity_id) { 0 }
  let(:user_client) do
    Crm::Glpi::Api::UserClient.new(
      api_url: 'https://glpi.example.com/apirest.php',
      app_token: 'test_app_token',
      user_token: 'test_user_token'
    )
  end
  let(:service) { described_class.new(user_client, entity_id) }

  describe '#find_or_create' do
    let(:contact) do
      create(:contact,
             account: account,
             name: 'John Doe',
             email: 'john@example.com',
             phone_number: '+12345678900')
    end

    context 'when contact has stored user_id' do
      before do
        contact.additional_attributes = {
          'external' => { 'glpi_user_id' => 123 }
        }
        contact.save!
      end

      it 'returns stored user_id without API call' do
        result = service.find_or_create(contact)
        expect(result).to eq(123)
      end
    end

    context 'when user exists by email' do
      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
          .with(query: hash_including('criteria' => anything))
          .to_return(status: 200, body: { data: [{ id: 456 }] }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'finds and returns existing user_id' do
        result = service.find_or_create(contact)
        expect(result).to eq(456)
      end
    end

    context 'when user does not exist' do
      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        # Search returns empty
        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
          .to_return(status: 200, body: { data: [] }.to_json)

        # Create user
        stub_request(:post, 'https://glpi.example.com/apirest.php/User')
          .to_return(status: 201, body: { id: 789, message: 'User created' }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'creates new user and returns user_id' do
        result = service.find_or_create(contact)
        expect(result).to eq(789)
      end
    end

    context 'when contact has no email' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Jane Smith',
               email: nil,
               phone_number: '+12345678900')
      end

      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:post, 'https://glpi.example.com/apirest.php/User')
          .to_return(status: 201, body: { id: 999, message: 'User created' }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .to_return(status: 200, body: '{}')
      end

      it 'creates user with phone as name' do
        result = service.find_or_create(contact)
        expect(result).to eq(999)
      end
    end

    context 'when API returns error' do
      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
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

        stub_request(:get, %r{https://glpi.example.com/apirest.php/search/User})
          .to_return(status: 200, body: { data: [] }.to_json)

        stub_request(:post, 'https://glpi.example.com/apirest.php/User')
          .to_return(status: 201, body: { message: 'User created' }.to_json)

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
