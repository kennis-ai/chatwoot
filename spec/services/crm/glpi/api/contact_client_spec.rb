# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Api::ContactClient do
  let(:api_url) { 'https://glpi.example.com/apirest.php' }
  let(:app_token) { SecureRandom.hex }
  let(:user_token) { SecureRandom.hex }
  let(:session_token) { SecureRandom.hex }
  let(:client) { described_class.new(api_url: api_url, app_token: app_token, user_token: user_token) }

  before do
    stub_request(:get, URI.join(api_url, '/initSession').to_s)
      .to_return(status: 200, body: { session_token: session_token }.to_json)
    stub_request(:get, URI.join(api_url, '/killSession').to_s)
      .to_return(status: 200, body: '{}')
  end

  describe '#search_contact' do
    let(:email) { 'john.doe@example.com' }

    it 'searches contacts by email' do
      stub_request(:get, URI.join(api_url, '/search/Contact').to_s)
        .to_return(status: 200, body: { 'data' => [{ '2' => 123 }], 'count' => 1 }.to_json)

      result = client.search_contact(email: email)
      expect(result['count']).to eq(1)
    end
  end

  describe '#get_contact' do
    it 'retrieves contact by ID' do
      stub_request(:get, URI.join(api_url, '/Contact/123').to_s)
        .to_return(status: 200, body: { 'id' => 123, 'name' => 'John Doe' }.to_json)

      result = client.get_contact(123)
      expect(result['id']).to eq(123)
    end
  end

  describe '#create_contact' do
    let(:contact_data) { { name: 'John Doe', email: 'john@example.com' } }

    it 'creates a new contact' do
      stub_request(:post, URI.join(api_url, '/Contact').to_s)
        .to_return(status: 201, body: { id: 456 }.to_json)

      result = client.create_contact(contact_data)
      expect(result['id']).to eq(456)
    end
  end

  describe '#update_contact' do
    it 'updates an existing contact' do
      stub_request(:put, URI.join(api_url, '/Contact/123').to_s)
        .to_return(status: 200, body: { message: 'Item successfully updated' }.to_json)

      result = client.update_contact(123, { phone: '+1234567890' })
      expect(result['message']).to eq('Item successfully updated')
    end
  end
end
