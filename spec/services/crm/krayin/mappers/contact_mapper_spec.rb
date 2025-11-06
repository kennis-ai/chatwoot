# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Krayin::Mappers::ContactMapper do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact,
           account: account,
           name: 'John Doe',
           email: 'john@example.com',
           phone_number: '+1234567890',
           additional_attributes: {
             'job_title' => 'Software Engineer',
             'company' => 'Acme Corp',
             'lead_value' => '5000.0',
             'custom_field' => 'custom_value'
           })
  end

  describe '.map_to_person' do
    it 'returns person data with emails array' do
      result = described_class.map_to_person(contact)

      expect(result[:name]).to eq('John Doe')
      expect(result[:emails]).to be_an(Array)
      expect(result[:emails].first[:value]).to eq('john@example.com')
      expect(result[:emails].first[:label]).to eq('work')
    end

    it 'returns person data with contact_numbers array' do
      result = described_class.map_to_person(contact)

      expect(result[:contact_numbers]).to be_an(Array)
      expect(result[:contact_numbers].first[:value]).to eq('+1234567890')
      expect(result[:contact_numbers].first[:label]).to eq('work')
    end

    it 'includes job_title from additional_attributes' do
      result = described_class.map_to_person(contact)

      expect(result[:job_title]).to eq('Software Engineer')
    end

    it 'returns empty arrays when email and phone are blank' do
      contact.email = nil
      contact.phone_number = nil

      result = described_class.map_to_person(contact)

      expect(result[:emails]).to eq([])
      expect(result[:contact_numbers]).to eq([])
    end

    it 'compacts nil values' do
      contact.additional_attributes = {}

      result = described_class.map_to_person(contact)

      expect(result).not_to have_key(:job_title)
    end

    it 'formats phone number to E.164' do
      contact.phone_number = '(123) 456-7890'

      result = described_class.map_to_person(contact)

      expect(result[:contact_numbers].first[:value]).to match(/^\+/)
    end

    it 'keeps original phone if parsing fails' do
      contact.phone_number = 'invalid-phone'

      result = described_class.map_to_person(contact)

      expect(result[:contact_numbers].first[:value]).to eq('invalid-phone')
    end
  end

  describe '.map_to_lead' do
    let(:person_id) { 123 }
    let(:settings) do
      {
        'lead_source_id' => 1,
        'lead_type_id' => 2,
        'lead_pipeline_id' => 3,
        'lead_pipeline_stage_id' => 4
      }
    end

    it 'returns lead data with required fields' do
      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result[:title]).to eq('John Doe')
      expect(result[:person_id]).to eq(123)
      expect(result[:lead_source_id]).to eq(1)
      expect(result[:lead_type_id]).to eq(2)
      expect(result[:lead_pipeline_id]).to eq(3)
      expect(result[:lead_pipeline_stage_id]).to eq(4)
    end

    it 'uses contact ID as title fallback when name is blank' do
      contact.name = nil

      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result[:title]).to eq("Contact #{contact.id}")
    end

    it 'extracts lead_value from additional_attributes' do
      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result[:lead_value]).to eq(5000.0)
    end

    it 'uses default lead_value when not present' do
      contact.additional_attributes = {}

      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result[:lead_value]).to eq(0.0)
    end

    it 'uses default IDs from settings when specific IDs not present' do
      settings_with_defaults = {
        'default_lead_type_id' => 10,
        'default_pipeline_id' => 20,
        'default_stage_id' => 30
      }

      result = described_class.map_to_lead(contact, person_id, settings_with_defaults)

      expect(result[:lead_type_id]).to eq(10)
      expect(result[:lead_pipeline_id]).to eq(20)
      expect(result[:lead_pipeline_stage_id]).to eq(30)
    end

    it 'builds description with contact details' do
      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result[:description]).to include('Email: john@example.com')
      expect(result[:description]).to include('Phone: +1234567890')
      expect(result[:description]).to include('Company: Acme Corp')
    end

    it 'includes brand name in description' do
      allow(GlobalConfig).to receive(:get).with('BRAND_NAME').and_return({ 'BRAND_NAME' => 'TestBrand' })

      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result[:description]).to include('Source: TestBrand')
    end

    it 'includes custom attributes in description' do
      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result[:description]).to include('custom_field')
    end

    it 'compacts nil values' do
      settings = {}

      result = described_class.map_to_lead(contact, person_id, settings)

      expect(result).not_to have_key(:lead_source_id)
      expect(result).not_to have_key(:lead_type_id)
    end
  end

  describe 'instance methods' do
    let(:mapper) { described_class.new(contact) }

    describe '#format_phone_number' do
      it 'returns original if blank' do
        expect(mapper.send(:format_phone_number, nil)).to be_nil
      end

      it 'formats valid phone to E.164' do
        result = mapper.send(:format_phone_number, '+1 (234) 567-8900')
        expect(result).to match(/^\+1/)
      end

      it 'returns original if invalid' do
        result = mapper.send(:format_phone_number, 'not-a-phone')
        expect(result).to eq('not-a-phone')
      end
    end

    describe '#brand_name' do
      it 'returns configured brand name' do
        allow(GlobalConfig).to receive(:get).with('BRAND_NAME').and_return({ 'BRAND_NAME' => 'MyBrand' })

        expect(mapper.send(:brand_name)).to eq('MyBrand')
      end

      it 'returns Chatwoot as default' do
        allow(GlobalConfig).to receive(:get).with('BRAND_NAME').and_return({})

        expect(mapper.send(:brand_name)).to eq('Chatwoot')
      end
    end
  end
end
