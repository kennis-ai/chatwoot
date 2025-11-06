# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Krayin::SetupService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:api_url) { 'https://crm.example.com/api/admin' }
  let(:api_token) { SecureRandom.hex }

  let(:service) do
    described_class.new(
      inbox: inbox,
      api_url: api_url,
      api_token: api_token
    )
  end

  let(:pipelines_response) do
    [
      { 'id' => 1, 'name' => 'Sales Pipeline' },
      { 'id' => 2, 'name' => 'Marketing Pipeline' }
    ]
  end

  let(:stages_response) do
    [
      { 'id' => 10, 'name' => 'New', 'pipeline_id' => 1 },
      { 'id' => 11, 'name' => 'Qualified', 'pipeline_id' => 1 }
    ]
  end

  let(:sources_response) do
    [
      { 'id' => 100, 'name' => 'Website' },
      { 'id' => 101, 'name' => 'Referral' }
    ]
  end

  let(:types_response) do
    [
      { 'id' => 200, 'name' => 'New Business' },
      { 'id' => 201, 'name' => 'Existing Business' }
    ]
  end

  before do
    stub_request(:get, "#{api_url}/pipelines")
      .to_return(status: 200, body: { data: pipelines_response }.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, "#{api_url}/pipelines/1/stages")
      .to_return(status: 200, body: { data: stages_response }.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, "#{api_url}/sources")
      .to_return(status: 200, body: { data: sources_response }.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, "#{api_url}/types")
      .to_return(status: 200, body: { data: types_response }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    it 'validates API connection' do
      expect_any_instance_of(Crm::Krayin::Api::LeadClient).to receive(:get_pipelines).and_return(pipelines_response)

      service.perform
    end

    it 'fetches and stores default configuration' do
      config = service.perform

      expect(config['api_url']).to eq(api_url)
      expect(config['api_token']).to eq(api_token)
      expect(config['default_pipeline_id']).to eq(1)
      expect(config['default_pipeline_name']).to eq('Sales Pipeline')
      expect(config['default_stage_id']).to eq(10)
      expect(config['default_stage_name']).to eq('New')
      expect(config['default_source_id']).to eq(100)
      expect(config['default_source_name']).to eq('Website')
      expect(config['default_lead_type_id']).to eq(200)
      expect(config['default_lead_type_name']).to eq('New Business')
    end

    it 'creates hook with configuration' do
      service.perform

      hook = inbox.hooks.find_by(app_id: 'krayin')

      expect(hook).to be_present
      expect(hook.status).to eq('enabled')
      expect(hook.hook_type).to eq('inbox')
      expect(hook.settings['api_url']).to eq(api_url)
      expect(hook.settings['default_pipeline_id']).to eq(1)
    end

    it 'updates existing hook if already present' do
      existing_hook = create(:integrations_hook, inbox: inbox, app_id: 'krayin', settings: { 'old_key' => 'old_value' })

      service.perform

      existing_hook.reload
      expect(existing_hook.settings['api_url']).to eq(api_url)
      expect(existing_hook.settings['default_pipeline_id']).to eq(1)
    end

    it 'prefers Website source over others' do
      sources_with_web = [
        { 'id' => 100, 'name' => 'Direct' },
        { 'id' => 101, 'name' => 'Web Form' },
        { 'id' => 102, 'name' => 'Referral' }
      ]

      stub_request(:get, "#{api_url}/sources")
        .to_return(status: 200, body: { data: sources_with_web }.to_json)

      config = service.perform

      expect(config['default_source_id']).to eq(101)
      expect(config['default_source_name']).to eq('Web Form')
    end

    it 'uses first source if no web-related source found' do
      sources_without_web = [
        { 'id' => 100, 'name' => 'Direct' },
        { 'id' => 101, 'name' => 'Referral' }
      ]

      stub_request(:get, "#{api_url}/sources")
        .to_return(status: 200, body: { data: sources_without_web }.to_json)

      config = service.perform

      expect(config['default_source_id']).to eq(100)
      expect(config['default_source_name']).to eq('Direct')
    end

    context 'when API connection fails' do
      before do
        stub_request(:get, "#{api_url}/pipelines")
          .to_return(status: 401, body: 'Unauthorized')
      end

      it 'raises error' do
        expect { service.perform }.to raise_error(StandardError, /Failed to connect to Krayin API/)
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with(/Krayin SetupService - API connection failed/)

        expect { service.perform }.to raise_error(StandardError)
      end
    end

    context 'when API returns empty pipelines' do
      before do
        stub_request(:get, "#{api_url}/pipelines")
          .to_return(status: 200, body: { data: [] }.to_json)
      end

      it 'raises error' do
        expect { service.perform }.to raise_error(StandardError, 'Unable to connect to Krayin API')
      end
    end

    context 'when fetching configuration fails' do
      before do
        stub_request(:get, "#{api_url}/sources")
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'raises error with message' do
        expect { service.perform }.to raise_error(StandardError, /Failed to fetch Krayin configuration/)
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with(/Krayin SetupService - Failed to fetch configuration/)

        expect { service.perform }.to raise_error(StandardError)
      end
    end

    context 'when storing configuration fails' do
      before do
        allow_any_instance_of(Integrations::Hook).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'raises error' do
        expect { service.perform }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with(/Krayin SetupService - Failed to store configuration/)

        expect { service.perform }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'when stages are not available' do
      before do
        stub_request(:get, "#{api_url}/pipelines/1/stages")
          .to_return(status: 200, body: { data: [] }.to_json)
      end

      it 'stores config without stage IDs' do
        config = service.perform

        expect(config['default_pipeline_id']).to eq(1)
        expect(config).not_to have_key('default_stage_id')
      end
    end

    context 'when sources are not available' do
      before do
        stub_request(:get, "#{api_url}/sources")
          .to_return(status: 200, body: { data: [] }.to_json)
      end

      it 'stores config without source ID' do
        config = service.perform

        expect(config).not_to have_key('default_source_id')
      end
    end

    context 'when types are not available' do
      before do
        stub_request(:get, "#{api_url}/types")
          .to_return(status: 200, body: { data: [] }.to_json)
      end

      it 'stores config without type ID' do
        config = service.perform

        expect(config).not_to have_key('default_lead_type_id')
      end
    end

    it 'logs successful connection' do
      expect(Rails.logger).to receive(:info).with(/Krayin SetupService - Successfully connected to API/)
      expect(Rails.logger).to receive(:info).with(/Krayin SetupService - Configuration saved/)

      service.perform
    end
  end
end
