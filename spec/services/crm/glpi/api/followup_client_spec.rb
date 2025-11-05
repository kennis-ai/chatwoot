# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Api::FollowupClient do
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

  describe '#create_followup' do
    let(:followup_data) do
      {
        itemtype: 'Ticket',
        items_id: 789,
        content: 'Customer provided additional information',
        is_private: 0
      }
    end

    it 'creates a new followup' do
      stub_request(:post, URI.join(api_url, '/ITILFollowup').to_s)
        .with(body: { input: followup_data }.to_json)
        .to_return(status: 201, body: { id: 222 }.to_json)

      result = client.create_followup(followup_data)
      expect(result['id']).to eq(222)
    end
  end

  describe '#update_followup' do
    it 'updates an existing followup' do
      stub_request(:put, URI.join(api_url, '/ITILFollowup/222').to_s)
        .to_return(status: 200, body: { message: 'Item successfully updated' }.to_json)

      result = client.update_followup(222, { content: 'Updated content' })
      expect(result['message']).to eq('Item successfully updated')
    end
  end

  describe '#get_ticket_followups' do
    it 'retrieves all followups for a ticket' do
      followups = [
        { 'id' => 222, 'content' => 'First followup' },
        { 'id' => 223, 'content' => 'Second followup' }
      ]

      stub_request(:get, URI.join(api_url, '/Ticket/789/ITILFollowup').to_s)
        .to_return(status: 200, body: followups.to_json)

      result = client.get_ticket_followups(789)
      expect(result.length).to eq(2)
      expect(result.first['id']).to eq(222)
    end
  end

  describe '#get_followup' do
    it 'retrieves a specific followup by ID' do
      stub_request(:get, URI.join(api_url, '/ITILFollowup/222').to_s)
        .to_return(status: 200, body: { 'id' => 222, 'content' => 'Test followup' }.to_json)

      result = client.get_followup(222)
      expect(result['id']).to eq(222)
    end
  end
end
