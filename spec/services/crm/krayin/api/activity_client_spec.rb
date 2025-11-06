require 'rails_helper'

RSpec.describe Crm::Krayin::Api::ActivityClient do
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

  describe '#search_activity' do
    it 'searches activities and returns data' do
      params = { type: 'note' }
      stub_request(:get, "#{api_url}/activities")
        .with(query: params, headers: headers)
        .to_return(
          status: 200,
          body: { data: [{ id: 1, type: 'note', comment: 'Test note' }] }.to_json
        )

      response = client.search_activity(params)
      expect(response).to be_an(Array)
      expect(response.first['type']).to eq('note')
    end

    it 'returns empty array when no activities found' do
      stub_request(:get, "#{api_url}/activities")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: [] }.to_json
        )

      response = client.search_activity
      expect(response).to eq([])
    end
  end

  describe '#create_activity' do
    let(:activity_data) do
      {
        type: 'note',
        comment: 'Test activity'
      }
    end

    it 'raises ArgumentError when activity data is missing' do
      expect { client.create_activity(nil) }
        .to raise_error(ArgumentError, 'Activity data is required')
    end

    it 'creates activity and returns activity ID' do
      stub_request(:post, "#{api_url}/activities")
        .with(body: activity_data.to_json, headers: headers)
        .to_return(
          status: 201,
          body: { data: { id: 456 } }.to_json
        )

      id = client.create_activity(activity_data)
      expect(id).to eq(456)
    end
  end

  describe '#update_activity' do
    let(:activity_id) { 456 }
    let(:activity_data) { { comment: 'Updated comment' } }

    it 'raises ArgumentError when activity ID is missing' do
      expect { client.update_activity(activity_data, nil) }
        .to raise_error(ArgumentError, 'Activity ID is required')
    end

    it 'raises ArgumentError when activity data is missing' do
      expect { client.update_activity(nil, activity_id) }
        .to raise_error(ArgumentError, 'Activity data is required')
    end

    it 'updates activity and returns activity data' do
      stub_request(:put, "#{api_url}/activities/#{activity_id}")
        .with(body: activity_data.to_json, headers: headers)
        .to_return(
          status: 200,
          body: { data: { id: activity_id, comment: 'Updated comment' } }.to_json
        )

      response = client.update_activity(activity_data, activity_id)
      expect(response['comment']).to eq('Updated comment')
    end
  end

  describe '#get_activity' do
    let(:activity_id) { 456 }

    it 'raises ArgumentError when activity ID is missing' do
      expect { client.get_activity(nil) }
        .to raise_error(ArgumentError, 'Activity ID is required')
    end

    it 'returns activity data' do
      stub_request(:get, "#{api_url}/activities/#{activity_id}")
        .with(headers: headers)
        .to_return(
          status: 200,
          body: { data: { id: activity_id, type: 'note' } }.to_json
        )

      response = client.get_activity(activity_id)
      expect(response['id']).to eq(activity_id)
    end

    it 'raises ApiError when activity not found' do
      stub_request(:get, "#{api_url}/activities/#{activity_id}")
        .with(headers: headers)
        .to_return(status: 404, body: 'Not Found')

      expect { client.get_activity(activity_id) }
        .to raise_error(Crm::Krayin::Api::BaseClient::ApiError, 'Resource not found')
    end
  end
end
