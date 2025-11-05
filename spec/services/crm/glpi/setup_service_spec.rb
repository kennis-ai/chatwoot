# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::SetupService do
  let(:account) { create(:account) }
  let(:hook) do
    create(:integrations_hook,
           app_id: 'glpi',
           account: account,
           settings: settings)
  end

  let(:valid_settings) do
    {
      'api_url' => 'https://glpi.example.com/apirest.php',
      'app_token' => 'test_app_token_123',
      'user_token' => 'test_user_token_456',
      'entity_id' => '0'
    }
  end

  describe '#validate_and_test' do
    context 'with valid settings and successful connection' do
      let(:settings) { valid_settings }

      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .with(headers: {
                  'App-Token' => 'test_app_token_123',
                  'Authorization' => 'user_token test_user_token_456'
                })
          .to_return(status: 200, body: { session_token: 'session_123' }.to_json)

        stub_request(:get, 'https://glpi.example.com/apirest.php/killSession')
          .with(headers: { 'Session-Token' => 'session_123' })
          .to_return(status: 200, body: '{}')
      end

      it 'validates successfully' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be true
        expect(result[:message]).to eq('GLPI connection successful')
      end
    end

    context 'with missing api_url' do
      let(:settings) { valid_settings.except('api_url') }

      it 'returns error for missing api_url' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be false
        expect(result[:error]).to include('Missing required settings: api_url')
      end
    end

    context 'with missing app_token' do
      let(:settings) { valid_settings.except('app_token') }

      it 'returns error for missing app_token' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be false
        expect(result[:error]).to include('Missing required settings: app_token')
      end
    end

    context 'with missing user_token' do
      let(:settings) { valid_settings.except('user_token') }

      it 'returns error for missing user_token' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be false
        expect(result[:error]).to include('Missing required settings: user_token')
      end
    end

    context 'with multiple missing settings' do
      let(:settings) { { 'api_url' => 'https://glpi.example.com/apirest.php' } }

      it 'returns error listing all missing settings' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be false
        expect(result[:error]).to include('app_token')
        expect(result[:error]).to include('user_token')
      end
    end

    context 'with invalid URL format' do
      let(:settings) { valid_settings.merge('api_url' => 'not-a-valid-url') }

      it 'returns error for invalid URL' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid API URL format')
      end
    end

    context 'with connection failure' do
      let(:settings) { valid_settings }

      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_return(status: 401, body: { 0 => 'ERROR_WRONG_APP_TOKEN_PARAMETER' }.to_json)
      end

      it 'returns error for connection failure' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be false
        expect(result[:error]).to include('API connection failed')
      end
    end

    context 'with network error' do
      let(:settings) { valid_settings }

      before do
        stub_request(:get, 'https://glpi.example.com/apirest.php/initSession')
          .to_raise(SocketError.new('Connection refused'))
      end

      it 'returns error for network failure' do
        service = described_class.new(hook)
        result = service.validate_and_test

        expect(result[:success]).to be false
        expect(result[:error]).to include('Connection test failed')
      end
    end
  end
end
