# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Api::TicketClient do
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

  describe '#create_ticket' do
    let(:ticket_data) do
      {
        name: 'Conversation #123',
        content: 'Customer inquiry',
        status: 2,
        priority: 3,
        _users_id_requester: 456
      }
    end

    it 'creates a new ticket' do
      stub_request(:post, URI.join(api_url, '/Ticket').to_s)
        .with(body: { input: ticket_data }.to_json)
        .to_return(status: 201, body: { id: 789 }.to_json)

      result = client.create_ticket(ticket_data)
      expect(result['id']).to eq(789)
    end
  end

  describe '#update_ticket' do
    it 'updates ticket status' do
      stub_request(:put, URI.join(api_url, '/Ticket/789').to_s)
        .with(body: { input: { status: 5 } }.to_json)
        .to_return(status: 200, body: { message: 'Item successfully updated' }.to_json)

      result = client.update_ticket(789, { status: 5 })
      expect(result['message']).to eq('Item successfully updated')
    end
  end

  describe '#get_ticket' do
    it 'retrieves ticket by ID' do
      stub_request(:get, URI.join(api_url, '/Ticket/789').to_s)
        .to_return(status: 200, body: { 'id' => 789, 'name' => 'Test Ticket' }.to_json)

      result = client.get_ticket(789)
      expect(result['id']).to eq(789)
    end
  end

  describe '#add_document' do
    let(:document_data) { { name: 'Screenshot', filename: 'screenshot.png' } }

    it 'attaches document to ticket' do
      stub_request(:post, URI.join(api_url, '/Ticket/789/Document_Item').to_s)
        .to_return(status: 201, body: { id: 111 }.to_json)

      result = client.add_document(789, document_data)
      expect(result['id']).to eq(111)
    end
  end
end
