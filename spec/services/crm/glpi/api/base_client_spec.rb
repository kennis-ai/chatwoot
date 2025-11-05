# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Api::BaseClient do
  let(:api_url) { 'https://glpi.example.com/apirest.php' }
  let(:app_token) { SecureRandom.hex }
  let(:user_token) { SecureRandom.hex }
  let(:session_token) { SecureRandom.hex }
  let(:client) { described_class.new(api_url: api_url, app_token: app_token, user_token: user_token) }

  describe '#initialize' do
    it 'creates a client with valid credentials' do
      expect(client.api_url).to eq(api_url)
      expect(client.app_token).to eq(app_token)
      expect(client.user_token).to eq(user_token)
      expect(client.session_token).to be_nil
    end
  end

  describe '#with_session' do
    let(:init_url) { URI.join(api_url, '/initSession').to_s }
    let(:kill_url) { URI.join(api_url, '/killSession').to_s }

    context 'when session initialization succeeds' do
      before do
        stub_request(:get, init_url)
          .with(
            headers: {
              'Content-Type' => 'application/json',
              'App-Token' => app_token,
              'Authorization' => "user_token #{user_token}"
            }
          )
          .to_return(
            status: 200,
            body: { session_token: session_token }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_request(:get, kill_url)
          .with(
            headers: {
              'Content-Type' => 'application/json',
              'App-Token' => app_token,
              'Session-Token' => session_token
            }
          )
          .to_return(status: 200, body: '{}')
      end

      it 'initializes session and yields block' do
        result = client.with_session do
          'test result'
        end

        expect(result).to eq('test result')
      end

      it 'sets session token during block execution' do
        client.with_session do
          expect(client.session_token).to eq(session_token)
        end
      end

      it 'clears session token after block completes' do
        client.with_session { 'test' }
        expect(client.session_token).to be_nil
      end

      it 'kills session even when block raises error' do
        expect do
          client.with_session do
            raise StandardError, 'test error'
          end
        end.to raise_error(StandardError, 'test error')

        expect(client.session_token).to be_nil
      end
    end

    context 'when session initialization fails' do
      before do
        stub_request(:get, init_url)
          .to_return(
            status: 401,
            body: ['ERROR_WRONG_APP_TOKEN_PARAMETER', 401].to_json
          )
      end

      it 'raises ApiError with authentication failure' do
        expect do
          client.with_session { 'test' }
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError) do |error|
          expect(error.code).to eq(401)
          expect(error.message).to include('authentication failed')
        end
      end

      it 'does not set session token' do
        expect do
          client.with_session { 'test' }
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError)

        expect(client.session_token).to be_nil
      end
    end

    context 'when kill session fails' do
      before do
        stub_request(:get, init_url)
          .to_return(
            status: 200,
            body: { session_token: session_token }.to_json
          )

        stub_request(:get, kill_url)
          .to_return(status: 500, body: 'Server Error')
      end

      it 'logs warning but does not raise error' do
        expect(Rails.logger).to receive(:warn).with(/Failed to kill GLPI session/)

        client.with_session { 'test' }
      end

      it 'clears session token anyway' do
        allow(Rails.logger).to receive(:warn)
        client.with_session { 'test' }
        expect(client.session_token).to be_nil
      end
    end
  end

  describe '#get' do
    let(:endpoint) { '/User/123' }
    let(:full_url) { URI.join(api_url, endpoint).to_s }
    let(:init_url) { URI.join(api_url, '/initSession').to_s }
    let(:kill_url) { URI.join(api_url, '/killSession').to_s }

    before do
      stub_request(:get, init_url)
        .to_return(
          status: 200,
          body: { session_token: session_token }.to_json
        )

      stub_request(:get, kill_url)
        .to_return(status: 200, body: '{}')
    end

    context 'when request is successful' do
      before do
        stub_request(:get, full_url)
          .with(
            headers: {
              'Content-Type' => 'application/json',
              'App-Token' => app_token,
              'Session-Token' => session_token
            }
          )
          .to_return(
            status: 200,
            body: { id: 123, name: 'test_user' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response data' do
        result = client.with_session do
          client.get(endpoint)
        end

        expect(result).to include('id' => 123, 'name' => 'test_user')
      end
    end

    context 'when request fails with 404' do
      before do
        stub_request(:get, full_url)
          .to_return(
            status: 404,
            body: ['ERROR_ITEM_NOT_FOUND', 404].to_json
          )
      end

      it 'raises ApiError with not found message' do
        expect do
          client.with_session do
            client.get(endpoint)
          end
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError) do |error|
          expect(error.code).to eq(404)
          expect(error.message).to include('not found')
        end
      end
    end

    context 'when request fails with 422' do
      before do
        stub_request(:get, full_url)
          .to_return(
            status: 422,
            body: ['ERROR_GLPI_PARTIAL_ADD', 422].to_json
          )
      end

      it 'raises ApiError with validation error' do
        expect do
          client.with_session do
            client.get(endpoint)
          end
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError) do |error|
          expect(error.code).to eq(422)
          expect(error.message).to include('validation error')
        end
      end
    end

    context 'when request fails with 500' do
      before do
        stub_request(:get, full_url)
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'raises ApiError with server error' do
        expect do
          client.with_session do
            client.get(endpoint)
          end
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError) do |error|
          expect(error.code).to eq(500)
          expect(error.message).to include('server error')
        end
      end
    end
  end

  describe '#post' do
    let(:endpoint) { '/User' }
    let(:body) { { name: 'test_user', firstname: 'Test' } }
    let(:full_url) { URI.join(api_url, endpoint).to_s }
    let(:init_url) { URI.join(api_url, '/initSession').to_s }
    let(:kill_url) { URI.join(api_url, '/killSession').to_s }

    before do
      stub_request(:get, init_url)
        .to_return(
          status: 200,
          body: { session_token: session_token }.to_json
        )

      stub_request(:get, kill_url)
        .to_return(status: 200, body: '{}')
    end

    context 'when request is successful' do
      before do
        stub_request(:post, full_url)
          .with(
            body: body.to_json,
            headers: {
              'Content-Type' => 'application/json',
              'App-Token' => app_token,
              'Session-Token' => session_token
            }
          )
          .to_return(
            status: 201,
            body: { id: 456, message: 'Item successfully added' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response data' do
        result = client.with_session do
          client.post(endpoint, body)
        end

        expect(result).to include('id' => 456, 'message' => 'Item successfully added')
      end
    end

    context 'when response cannot be parsed' do
      before do
        stub_request(:post, full_url)
          .to_return(
            status: 200,
            body: 'Invalid JSON',
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises ApiError for invalid JSON' do
        expect do
          client.with_session do
            client.post(endpoint, body)
          end
        end.to raise_error(Crm::Glpi::Api::BaseClient::ApiError) do |error|
          expect(error.message).to include('Failed to parse')
        end
      end
    end
  end

  describe '#put' do
    let(:endpoint) { '/User/123' }
    let(:body) { { phone: '+1234567890' } }
    let(:full_url) { URI.join(api_url, endpoint).to_s }
    let(:init_url) { URI.join(api_url, '/initSession').to_s }
    let(:kill_url) { URI.join(api_url, '/killSession').to_s }

    before do
      stub_request(:get, init_url)
        .to_return(
          status: 200,
          body: { session_token: session_token }.to_json
        )

      stub_request(:get, kill_url)
        .to_return(status: 200, body: '{}')
    end

    context 'when request is successful' do
      before do
        stub_request(:put, full_url)
          .with(
            body: body.to_json,
            headers: {
              'Content-Type' => 'application/json',
              'App-Token' => app_token,
              'Session-Token' => session_token
            }
          )
          .to_return(
            status: 200,
            body: { 123 => true, message: 'Item successfully updated' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response data' do
        result = client.with_session do
          client.put(endpoint, body)
        end

        expect(result).to include('message' => 'Item successfully updated')
      end
    end
  end
end
