require 'rails_helper'

RSpec.describe Crm::Krayin::Api::PersonClient do
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

  describe '#search_person' do
    let(:path) { 'contacts/persons' }
    let(:email) { 'test@example.com' }
    let(:full_url) { "#{api_url}/#{path}" }

    context 'when email and phone are both missing' do
      it 'raises ArgumentError' do
        expect { client.search_person }
          .to raise_error(ArgumentError, 'Email or phone required')
      end
    end

    context 'when searching by email' do
      let(:person_data) do
        {
          'data' => [{
            'id' => 1,
            'name' => 'John Doe',
            'emails' => [{ 'value' => email, 'label' => 'work' }]
          }]
        }
      end

      before do
        stub_request(:get, full_url)
          .with(query: { email: email }, headers: headers)
          .to_return(
            status: 200,
            body: person_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns person data array' do
        response = client.search_person(email: email)
        expect(response).to be_an(Array)
        expect(response.first['name']).to eq('John Doe')
      end
    end

    context 'when searching by phone' do
      let(:phone) { '+1234567890' }
      let(:person_data) do
        {
          'data' => [{
            'id' => 1,
            'name' => 'Jane Doe',
            'contact_numbers' => [{ 'value' => phone, 'label' => 'work' }]
          }]
        }
      end

      before do
        stub_request(:get, full_url)
          .with(query: { phone: phone }, headers: headers)
          .to_return(
            status: 200,
            body: person_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns person data array' do
        response = client.search_person(phone: phone)
        expect(response).to be_an(Array)
        expect(response.first['name']).to eq('Jane Doe')
      end
    end

    context 'when no persons are found' do
      before do
        stub_request(:get, full_url)
          .with(query: { email: email }, headers: headers)
          .to_return(
            status: 200,
            body: { data: [] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns empty array' do
        response = client.search_person(email: email)
        expect(response).to eq([])
      end
    end
  end

  describe '#create_person' do
    let(:path) { 'contacts/persons' }
    let(:full_url) { "#{api_url}/#{path}" }
    let(:person_data) do
      {
        name: 'John Doe',
        emails: [{ value: 'john@example.com', label: 'work' }],
        contact_numbers: [{ value: '+1234567890', label: 'work' }]
      }
    end

    context 'when person data is missing' do
      it 'raises ArgumentError' do
        expect { client.create_person(nil) }
          .to raise_error(ArgumentError, 'Person data is required')
      end
    end

    context 'when person is successfully created' do
      let(:person_id) { 123 }

      before do
        stub_request(:post, full_url)
          .with(
            body: person_data.to_json,
            headers: headers
          )
          .to_return(
            status: 201,
            body: { data: { id: person_id, name: 'John Doe' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns person ID' do
        id = client.create_person(person_data)
        expect(id).to eq(person_id)
      end
    end

    context 'when creation fails with validation error' do
      before do
        stub_request(:post, full_url)
          .with(
            body: person_data.to_json,
            headers: headers
          )
          .to_return(
            status: 422,
            body: { message: 'Validation failed', errors: { emails: ['is required'] } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises ApiError' do
        expect { client.create_person(person_data) }
          .to raise_error(Crm::Krayin::Api::BaseClient::ApiError)
      end
    end
  end

  describe '#update_person' do
    let(:person_id) { 123 }
    let(:path) { "contacts/persons/#{person_id}" }
    let(:full_url) { "#{api_url}/#{path}" }
    let(:person_data) { { name: 'Jane Doe' } }

    context 'when person ID is missing' do
      it 'raises ArgumentError' do
        expect { client.update_person(person_data, nil) }
          .to raise_error(ArgumentError, 'Person ID is required')
      end
    end

    context 'when person data is missing' do
      it 'raises ArgumentError' do
        expect { client.update_person(nil, person_id) }
          .to raise_error(ArgumentError, 'Person data is required')
      end
    end

    context 'when person is successfully updated' do
      before do
        stub_request(:put, full_url)
          .with(
            body: person_data.to_json,
            headers: headers
          )
          .to_return(
            status: 200,
            body: { data: { id: person_id, name: 'Jane Doe' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns updated person data' do
        response = client.update_person(person_data, person_id)
        expect(response['id']).to eq(person_id)
        expect(response['name']).to eq('Jane Doe')
      end
    end
  end

  describe '#get_person' do
    let(:person_id) { 123 }
    let(:path) { "contacts/persons/#{person_id}" }
    let(:full_url) { "#{api_url}/#{path}" }

    context 'when person ID is missing' do
      it 'raises ArgumentError' do
        expect { client.get_person(nil) }
          .to raise_error(ArgumentError, 'Person ID is required')
      end
    end

    context 'when person is found' do
      let(:person_data) do
        {
          'data' => {
            'id' => person_id,
            'name' => 'John Doe',
            'emails' => [{ 'value' => 'john@example.com', 'label' => 'work' }]
          }
        }
      end

      before do
        stub_request(:get, full_url)
          .with(headers: headers)
          .to_return(
            status: 200,
            body: person_data.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns person data' do
        response = client.get_person(person_id)
        expect(response['id']).to eq(person_id)
        expect(response['name']).to eq('John Doe')
      end
    end

    context 'when person is not found' do
      before do
        stub_request(:get, full_url)
          .with(headers: headers)
          .to_return(status: 404, body: 'Not Found')
      end

      it 'raises ApiError' do
        expect { client.get_person(person_id) }
          .to raise_error(Crm::Krayin::Api::BaseClient::ApiError, 'Resource not found')
      end
    end
  end
end
