require 'rails_helper'

RSpec.describe Crm::Krayin::Api::OrganizationClient do
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

  describe '#search_organization' do
    let(:org_name) { 'Acme Corp' }

    it 'raises ArgumentError when name is missing' do
      expect { client.search_organization(nil) }
        .to raise_error(ArgumentError, 'Organization name is required')
    end

    it 'searches organization and returns data' do
      stub_request(:get, "#{api_url}/contacts/organizations")
        .with(query: { name: org_name }, headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, name: org_name }] }.to_json
        )

      response = client.search_organization(org_name)
      expect(response).to be_an(Array)
      expect(response.first['name']).to eq(org_name)
    end
  end

  describe '#create_organization' do
    let(:org_data) do
      {
        name: 'Acme Corp',
        address: {
          address: '123 Main St',
          city: 'New York',
          state: 'NY',
          postcode: '10001',
          country: 'US'
        }
      }
    end

    it 'raises ArgumentError when organization data is missing' do
      expect { client.create_organization(nil) }
        .to raise_error(ArgumentError, 'Organization data is required')
    end

    it 'creates organization and returns organization ID' do
      stub_request(:post, "#{api_url}/contacts/organizations")
        .with(body: org_data.to_json, headers: headers)
        .to_return(
          status: 201,
          body: { data: { id: 789 } }.to_json
        )

      id = client.create_organization(org_data)
      expect(id).to eq(789)
    end
  end

  describe '#update_organization' do
    let(:org_id) { 789 }
    let(:org_data) { { name: 'Acme Corporation' } }

    it 'raises ArgumentError when organization ID is missing' do
      expect { client.update_organization(org_data, nil) }
        .to raise_error(ArgumentError, 'Organization ID is required')
    end

    it 'raises ArgumentError when organization data is missing' do
      expect { client.update_organization(nil, org_id) }
        .to raise_error(ArgumentError, 'Organization data is required')
    end

    it 'updates organization and returns organization data' do
      stub_request(:put, "#{api_url}/contacts/organizations/#{org_id}")
        .with(body: org_data.to_json, headers: headers)
        .to_return(
          status: 200,
          body: { data: { id: org_id, name: 'Acme Corporation' } }.to_json
        )

      response = client.update_organization(org_data, org_id)
      expect(response['name']).to eq('Acme Corporation')
    end
  end

  describe '#get_organization' do
    let(:org_id) { 789 }

    it 'raises ArgumentError when organization ID is missing' do
      expect { client.get_organization(nil) }
        .to raise_error(ArgumentError, 'Organization ID is required')
    end

    it 'returns organization data' do
      stub_request(:get, "#{api_url}/contacts/organizations/#{org_id}")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: { id: org_id, name: 'Acme Corp' } }.to_json
        )

      response = client.get_organization(org_id)
      expect(response['id']).to eq(org_id)
      expect(response['name']).to eq('Acme Corp')
    end

    it 'raises ApiError when organization not found' do
      stub_request(:get, "#{api_url}/contacts/organizations/#{org_id}")
        .with(headers: headers)
        .to_return(status: 404, body: 'Not Found')

      expect { client.get_organization(org_id) }
        .to raise_error(Crm::Krayin::Api::BaseClient::ApiError, 'Resource not found')
    end
  end
end
