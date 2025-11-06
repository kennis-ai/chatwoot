require 'rails_helper'

RSpec.describe Crm::Krayin::Api::BaseClient do
  let(:api_url) { 'https://crm.example.com/api/admin' }
  let(:api_token) { SecureRandom.hex }
  let(:headers) do
    {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'Authorization' => "Bearer #{api_token}"
    }
  end

  let(:client) { described_class.new(api_url, api_token) }

  describe '#initialize' do
    it 'creates a client with valid credentials' do
      expect(client.instance_variable_get(:@api_url)).to eq(api_url)
      expect(client.instance_variable_get(:@api_token)).to eq(api_token)
    end

    it 'strips trailing slash from API URL' do
      client_with_slash = described_class.new('https://crm.example.com/api/admin/', api_token)
      expect(client_with_slash.instance_variable_get(:@api_url)).to eq(api_url)
    end
  end

  describe '#get' do
    let(:path) { 'contacts/persons' }
    let(:params) { { email: 'test@example.com' } }
    let(:full_url) { "#{api_url}/#{path}" }

    context 'when request is successful' do
      before do
        stub_request(:get, full_url)
          .with(
            query: params,
            headers: headers
          )
          .to_return(
            status: 200,
            body: { data: [{ id: 1, name: 'John Doe' }] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response data' do
        response = client.get(path, params)
        expect(response).to include('data')
        expect(response['data']).to be_an(Array)
      end
    end

    context 'when request returns 401 unauthorized' do
      before do
        stub_request(:get, full_url)
          .with(
            query: params,
            headers: headers
          )
          .to_return(status: 401, body: 'Unauthorized')
      end

      it 'raises ApiError with unauthorized message' do
        expect { client.get(path, params) }.to raise_error(
          Crm::Krayin::Api::BaseClient::ApiError,
          'Unauthorized: Invalid API token'
        )
      end
    end

    context 'when request returns 404 not found' do
      before do
        stub_request(:get, full_url)
          .with(
            query: params,
            headers: headers
          )
          .to_return(status: 404, body: 'Not Found')
      end

      it 'raises ApiError with not found message' do
        expect { client.get(path, params) }.to raise_error(
          Crm::Krayin::Api::BaseClient::ApiError,
          'Resource not found'
        )
      end
    end

    context 'when request returns 422 validation error' do
      before do
        stub_request(:get, full_url)
          .with(
            query: params,
            headers: headers
          )
          .to_return(
            status: 422,
            body: { message: 'Validation failed', errors: { email: ['is invalid'] } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises ApiError with validation message' do
        expect { client.get(path, params) }.to raise_error do |error|
          expect(error).to be_a(Crm::Krayin::Api::BaseClient::ApiError)
          expect(error.message).to include('Validation failed')
          expect(error.code).to eq(422)
        end
      end
    end

    context 'when request fails with server error' do
      before do
        stub_request(:get, full_url)
          .with(
            query: params,
            headers: headers
          )
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'raises ApiError with status code' do
        expect { client.get(path, params) }.to raise_error do |error|
          expect(error).to be_a(Crm::Krayin::Api::BaseClient::ApiError)
          expect(error.message).to include('Internal Server Error')
          expect(error.code).to eq(500)
        end
      end
    end
  end

  describe '#post' do
    let(:path) { 'contacts/persons' }
    let(:body) { { name: 'John Doe', emails: [{ value: 'john@example.com', label: 'work' }] } }
    let(:params) { {} }
    let(:full_url) { "#{api_url}/#{path}" }

    context 'when request is successful' do
      before do
        stub_request(:post, full_url)
          .with(
            query: params,
            body: body.to_json,
            headers: headers
          )
          .to_return(
            status: 201,
            body: { data: { id: 1, name: 'John Doe' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response data' do
        response = client.post(path, body, params)
        expect(response).to include('data')
        expect(response['data']['id']).to eq(1)
      end
    end

    context 'when request returns validation error' do
      before do
        stub_request(:post, full_url)
          .with(
            query: params,
            body: body.to_json,
            headers: headers
          )
          .to_return(
            status: 422,
            body: { message: 'Validation failed', errors: { name: ['is required'] } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises ApiError with validation message' do
        expect { client.post(path, body, params) }.to raise_error do |error|
          expect(error).to be_a(Crm::Krayin::Api::BaseClient::ApiError)
          expect(error.message).to include('Validation failed')
        end
      end
    end
  end

  describe '#put' do
    let(:path) { 'contacts/persons/1' }
    let(:body) { { name: 'Jane Doe' } }
    let(:params) { {} }
    let(:full_url) { "#{api_url}/#{path}" }

    context 'when request is successful' do
      before do
        stub_request(:put, full_url)
          .with(
            query: params,
            body: body.to_json,
            headers: headers
          )
          .to_return(
            status: 200,
            body: { data: { id: 1, name: 'Jane Doe' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response data' do
        response = client.put(path, body, params)
        expect(response).to include('data')
        expect(response['data']['name']).to eq('Jane Doe')
      end
    end
  end

  describe '#delete' do
    let(:path) { 'contacts/persons/1' }
    let(:params) { {} }
    let(:full_url) { "#{api_url}/#{path}" }

    context 'when request is successful' do
      before do
        stub_request(:delete, full_url)
          .with(
            query: params,
            headers: headers
          )
          .to_return(
            status: 200,
            body: { message: 'Deleted successfully' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response data' do
        response = client.delete(path, params)
        expect(response).to include('message')
      end
    end
  end
end
