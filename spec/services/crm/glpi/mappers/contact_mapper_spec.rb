# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Glpi::Mappers::ContactMapper do
  let(:account) { create(:account) }

  describe '.map_to_user' do
    let(:entity_id) { 0 }

    context 'with complete contact data' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'John Doe',
               email: 'john.doe@example.com',
               phone_number: '+12345678900')
      end

      it 'maps all fields correctly' do
        result = described_class.map_to_user(contact, entity_id)

        expect(result[:name]).to eq('john.doe@example.com')
        expect(result[:firstname]).to eq('John')
        expect(result[:realname]).to eq('Doe')
        expect(result[:phone]).to eq('+1 234 567 8900')
        expect(result[:mobile]).to eq('+1 234 567 8900')
        expect(result[:_useremails]).to eq(['john.doe@example.com'])
        expect(result[:entities_id]).to eq(entity_id)
      end
    end

    context 'with only email (no phone)' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Jane Smith',
               email: 'jane@example.com',
               phone_number: nil)
      end

      it 'maps email as name and excludes phone fields' do
        result = described_class.map_to_user(contact, entity_id)

        expect(result[:name]).to eq('jane@example.com')
        expect(result[:firstname]).to eq('Jane')
        expect(result[:realname]).to eq('Smith')
        expect(result[:phone]).to be_nil
        expect(result[:mobile]).to be_nil
        expect(result[:_useremails]).to eq(['jane@example.com'])
      end
    end

    context 'with only phone (no email)' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Bob Johnson',
               email: nil,
               phone_number: '+12345678900')
      end

      it 'maps phone as name and excludes email fields' do
        result = described_class.map_to_user(contact, entity_id)

        expect(result[:name]).to eq('+12345678900')
        expect(result[:firstname]).to eq('Bob')
        expect(result[:realname]).to eq('Johnson')
        expect(result[:phone]).to eq('+1 234 567 8900')
        expect(result[:_useremails]).to eq([])
      end
    end

    context 'with single name' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Madonna',
               email: 'madonna@example.com')
      end

      it 'uses single name as firstname' do
        result = described_class.map_to_user(contact, entity_id)

        expect(result[:firstname]).to eq('Madonna')
        expect(result[:realname]).to be_nil
      end
    end

    context 'with name containing multiple spaces' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Mary Jane Watson',
               email: 'mary@example.com')
      end

      it 'splits on first space only' do
        result = described_class.map_to_user(contact, entity_id)

        expect(result[:firstname]).to eq('Mary')
        expect(result[:realname]).to eq('Jane Watson')
      end
    end

    context 'with blank name' do
      let(:contact) do
        create(:contact,
               account: account,
               name: '',
               email: 'test@example.com')
      end

      it 'excludes name fields' do
        result = described_class.map_to_user(contact, entity_id)

        expect(result[:firstname]).to be_nil
        expect(result[:realname]).to be_nil
        expect(result[:name]).to eq('test@example.com')
      end
    end
  end

  describe '.map_to_contact' do
    let(:entity_id) { 0 }

    context 'with complete contact data' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Alice Cooper',
               email: 'alice@example.com',
               phone_number: '+12345678900')
      end

      it 'maps all fields correctly' do
        result = described_class.map_to_contact(contact, entity_id)

        expect(result[:name]).to eq('Alice Cooper')
        expect(result[:firstname]).to eq('Alice')
        expect(result[:email]).to eq('alice@example.com')
        expect(result[:phone]).to eq('+1 234 567 8900')
        expect(result[:entities_id]).to eq(entity_id)
      end
    end

    context 'with missing fields' do
      let(:contact) do
        create(:contact,
               account: account,
               name: 'Test User',
               email: nil,
               phone_number: nil)
      end

      it 'excludes nil fields' do
        result = described_class.map_to_contact(contact, entity_id)

        expect(result[:name]).to eq('Test User')
        expect(result[:email]).to be_nil
        expect(result[:phone]).to be_nil
      end
    end
  end

  describe '.split_name' do
    it 'splits normal full name' do
      first, last = described_class.split_name('John Doe')
      expect(first).to eq('John')
      expect(last).to eq('Doe')
    end

    it 'handles single name' do
      first, last = described_class.split_name('Madonna')
      expect(first).to eq('Madonna')
      expect(last).to be_nil
    end

    it 'splits on first space only' do
      first, last = described_class.split_name('John Paul Jones')
      expect(first).to eq('John')
      expect(last).to eq('Paul Jones')
    end

    it 'handles blank string' do
      first, last = described_class.split_name('')
      expect(first).to be_nil
      expect(last).to be_nil
    end

    it 'handles nil' do
      first, last = described_class.split_name(nil)
      expect(first).to be_nil
      expect(last).to be_nil
    end
  end

  describe '.format_phone_number' do
    it 'formats valid US phone number' do
      result = described_class.format_phone_number('+12345678900')
      expect(result).to eq('+1 234 567 8900')
    end

    it 'formats valid international phone number' do
      result = described_class.format_phone_number('+441234567890')
      expect(result).to eq('+44 1234 567890')
    end

    it 'returns original for invalid phone number' do
      result = described_class.format_phone_number('invalid')
      expect(result).to eq('invalid')
    end

    it 'handles blank string' do
      result = described_class.format_phone_number('')
      expect(result).to be_nil
    end

    it 'handles nil' do
      result = described_class.format_phone_number(nil)
      expect(result).to be_nil
    end
  end
end
