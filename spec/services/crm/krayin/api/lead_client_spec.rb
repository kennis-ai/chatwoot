require 'rails_helper'

RSpec.describe Crm::Krayin::Api::LeadClient do
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

  describe '#search_lead' do
    let(:email) { 'test@example.com' }

    it 'raises ArgumentError when email and phone are missing' do
      expect { client.search_lead }
        .to raise_error(ArgumentError, 'Email or phone required')
    end

    it 'searches by email and returns lead data' do
      stub_request(:get, "#{api_url}/leads")
        .with(query: { email: email }, headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, title: 'Test Lead' }] }.to_json
        )

      response = client.search_lead(email: email)
      expect(response).to be_an(Array)
      expect(response.first['title']).to eq('Test Lead')
    end
  end

  describe '#create_lead' do
    let(:lead_data) do
      {
        title: 'New Lead',
        lead_value: 1000.0,
        person_id: 1,
        lead_source_id: 1,
        lead_type_id: 1,
        lead_pipeline_id: 1,
        lead_pipeline_stage_id: 1
      }
    end

    it 'raises ArgumentError when lead data is missing' do
      expect { client.create_lead(nil) }
        .to raise_error(ArgumentError, 'Lead data is required')
    end

    it 'creates lead and returns lead ID' do
      stub_request(:post, "#{api_url}/leads")
        .with(body: lead_data.to_json, headers: headers)
        .to_return(
          status: 201,
          body: { data: { id: 123 } }.to_json
        )

      id = client.create_lead(lead_data)
      expect(id).to eq(123)
    end
  end

  describe '#update_lead' do
    let(:lead_id) { 123 }
    let(:lead_data) { { title: 'Updated Lead' } }

    it 'raises ArgumentError when lead ID is missing' do
      expect { client.update_lead(lead_data, nil) }
        .to raise_error(ArgumentError, 'Lead ID is required')
    end

    it 'updates lead and returns lead data' do
      stub_request(:put, "#{api_url}/leads/#{lead_id}")
        .with(body: lead_data.to_json, headers: headers)
        .to_return(
          status: 200,
          body: { data: { id: lead_id, title: 'Updated Lead' } }.to_json
        )

      response = client.update_lead(lead_data, lead_id)
      expect(response['title']).to eq('Updated Lead')
    end
  end

  describe '#get_lead' do
    let(:lead_id) { 123 }

    it 'raises ArgumentError when lead ID is missing' do
      expect { client.get_lead(nil) }
        .to raise_error(ArgumentError, 'Lead ID is required')
    end

    it 'returns lead data' do
      stub_request(:get, "#{api_url}/leads/#{lead_id}")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: { id: lead_id, title: 'Test Lead' } }.to_json
        )

      response = client.get_lead(lead_id)
      expect(response['id']).to eq(lead_id)
    end
  end

  describe '#get_pipelines' do
    it 'returns pipelines data' do
      stub_request(:get, "#{api_url}/pipelines")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, name: 'Sales Pipeline' }] }.to_json
        )

      response = client.get_pipelines
      expect(response).to be_an(Array)
      expect(response.first['name']).to eq('Sales Pipeline')
    end
  end

  describe '#get_stages' do
    it 'returns all stages when pipeline_id is not provided' do
      stub_request(:get, "#{api_url}/stages")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, name: 'New' }] }.to_json
        )

      response = client.get_stages
      expect(response).to be_an(Array)
    end

    it 'returns pipeline-specific stages when pipeline_id is provided' do
      pipeline_id = 1
      stub_request(:get, "#{api_url}/pipelines/#{pipeline_id}/stages")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, name: 'New', pipeline_id: pipeline_id }] }.to_json
        )

      response = client.get_stages(pipeline_id)
      expect(response).to be_an(Array)
    end
  end

  describe '#get_sources' do
    it 'returns lead sources' do
      stub_request(:get, "#{api_url}/sources")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, name: 'Website' }] }.to_json
        )

      response = client.get_sources
      expect(response).to be_an(Array)
    end
  end

  describe '#get_types' do
    it 'returns lead types' do
      stub_request(:get, "#{api_url}/types")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, name: 'New Business' }] }.to_json
        )

      response = client.get_types
      expect(response).to be_an(Array)
    end
  end
end
