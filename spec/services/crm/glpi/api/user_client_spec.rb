# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Api::UserClient do
  let(:api_url) { 'https://glpi.example.com/apirest.php' }
  let(:app_token) { SecureRandom.hex }
  let(:user_token) { SecureRandom.hex }
  let(:session_token) { SecureRandom.hex }
  let(:client) { described_class.new(api_url: api_url, app_token: app_token, user_token: user_token) }

  before do
    # Stub session management
    stub_request(:get, URI.join(api_url, '/initSession').to_s)
      .to_return(
        status: 200,
        body: { session_token: session_token }.to_json
      )

    stub_request(:get, URI.join(api_url, '/killSession').to_s)
      .to_return(status: 200, body: '{}')
  end

  describe '#search_user' do
    let(:email) { 'john.doe@example.com' }
    let(:search_url) { URI.join(api_url, '/search/User').to_s }

    context 'when user is found' do
      let(:search_response) do
        {
          'data' => [
            { '2' => 123, '5' => email, '6' => 'John', '7' => 'Doe' }
          ],
          'count' => 1
        }
      end

      before do
        stub_request(:get, search_url)
          .with(
            query: hash_including('criteria'),
            headers: {
              'Session-Token' => session_token,
              'App-Token' => app_token
            }
          )
          .to_return(
            status: 200,
            body: search_response.to_json
          )
      end

      it 'returns search results with user data' do
        result = client.search_user(email: email)
        expect(result['data']).to be_present
        expect(result['data'].first['2']).to eq(123)
        expect(result['count']).to eq(1)
      end
    end

    context 'when user is not found' do
      before do
        stub_request(:get, search_url)
          .to_return(
            status: 200,
            body: { 'data' => [], 'count' => 0 }.to_json
          )
      end

      it 'returns empty results' do
        result = client.search_user(email: email)
        expect(result['data']).to be_empty
        expect(result['count']).to eq(0)
      end
    end
  end

  describe '#get_user' do
    let(:user_id) { 123 }
    let(:user_url) { URI.join(api_url, "/User/#{user_id}").to_s }

    context 'when user exists' do
      let(:user_data) do
        {
          'id' => user_id,
          'name' => 'john.doe',
          'firstname' => 'John',
          'realname' => 'Doe'
        }
      end

      before do
        stub_request(:get, user_url)
          .to_return(
            status: 200,
            body: user_data.to_json
          )
      end

      it 'returns user data' do
        result = client.get_user(user_id)
        expect(result['id']).to eq(user_id)
        expect(result['firstname']).to eq('John')
      end
    end

    context 'when user does not exist' do
      before do
        stub_request(:get, user_url)
          .to_return(
            status: 404,
            body: ['ERROR_ITEM_NOT_FOUND', 404].to_json
          )
      end

      it 'raises ApiError' do
        expect do
          client.get_user(user_id)
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError)
      end
    end
  end

  describe '#create_user' do
    let(:user_url) { URI.join(api_url, '/User').to_s }
    let(:user_data) do
      {
        name: 'john.doe@example.com',
        firstname: 'John',
        realname: 'Doe',
        _useremails: ['john.doe@example.com'],
        entities_id: 0
      }
    end

    context 'when creation succeeds' do
      before do
        stub_request(:post, user_url)
          .with(
            body: { input: user_data }.to_json
          )
          .to_return(
            status: 201,
            body: { id: 456, message: 'Item successfully added' }.to_json
          )
      end

      it 'returns created user ID' do
        result = client.create_user(user_data)
        expect(result['id']).to eq(456)
      end
    end

    context 'when creation fails due to validation error' do
      before do
        stub_request(:post, user_url)
          .to_return(
            status: 422,
            body: ['ERROR_GLPI_ADD', 422].to_json
          )
      end

      it 'raises ApiError' do
        expect do
          client.create_user(user_data)
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError)
      end
    end
  end

  describe '#update_user' do
    let(:user_id) { 123 }
    let(:user_url) { URI.join(api_url, "/User/#{user_id}").to_s }
    let(:update_data) { { phone: '+1234567890' } }

    context 'when update succeeds' do
      before do
        stub_request(:put, user_url)
          .with(
            body: { input: update_data }.to_json
          )
          .to_return(
            status: 200,
            body: { user_id => true, message: 'Item successfully updated' }.to_json
          )
      end

      it 'returns success response' do
        result = client.update_user(user_id, update_data)
        expect(result['message']).to eq('Item successfully updated')
      end
    end

    context 'when user does not exist' do
      before do
        stub_request(:put, user_url)
          .to_return(
            status: 404,
            body: ['ERROR_ITEM_NOT_FOUND', 404].to_json
          )
      end

      it 'raises ApiError' do
        expect do
          client.update_user(user_id, update_data)
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError)
      end
    end
  end
end
