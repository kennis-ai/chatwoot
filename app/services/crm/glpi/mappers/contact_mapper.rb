# frozen_string_literal: true

module Crm
  module Glpi
    module Mappers
      # Maps Chatwoot Contact to GLPI User or Contact format
      #
      # This mapper transforms Chatwoot contact data into the format expected
      # by the GLPI API. It can map to either GLPI Users (with login access)
      # or GLPI Contacts (external contacts without login).
      #
      # @example Map to GLPI User
      #   contact = Contact.find(123)
      #   user_data = ContactMapper.map_to_user(contact, entity_id: 0)
      #   # => {
      #   #   name: 'john.doe@example.com',
      #   #   firstname: 'John',
      #   #   realname: 'Doe',
      #   #   phone: '+1 234 567 8900',
      #   #   mobile: '+1 234 567 8900',
      #   #   _useremails: ['john.doe@example.com'],
      #   #   entities_id: 0
      #   # }
      #
      # @example Map to GLPI Contact
      #   contact_data = ContactMapper.map_to_contact(contact, entity_id: 0)
      class ContactMapper
        class << self
          # Map Chatwoot Contact to GLPI User format
          #
          # GLPI Users are internal users or external users with login access.
          # The 'name' field is the login name (usually email or phone).
          #
          # @param contact [Contact] The Chatwoot contact
          # @param entity_id [Integer] The GLPI entity ID to assign
          # @return [Hash] GLPI User attributes
          #
          # @example
          #   user_data = ContactMapper.map_to_user(contact, entity_id: 0)
          def map_to_user(contact, entity_id)
            first_name, last_name = split_name(contact.name)

            {
              name: contact.email || contact.phone_number,
              firstname: first_name,
              realname: last_name,
              phone: format_phone_number(contact.phone_number),
              mobile: format_phone_number(contact.phone_number),
              _useremails: [contact.email].compact,
              entities_id: entity_id
            }.compact
          end

          # Map Chatwoot Contact to GLPI Contact format
          #
          # GLPI Contacts are external contacts (customers, suppliers) without login access.
          # The 'name' field is the full name.
          #
          # @param contact [Contact] The Chatwoot contact
          # @param entity_id [Integer] The GLPI entity ID to assign
          # @return [Hash] GLPI Contact attributes
          #
          # @example
          #   contact_data = ContactMapper.map_to_contact(contact, entity_id: 0)
          def map_to_contact(contact, entity_id)
            first_name, last_name = split_name(contact.name)

            {
              name: contact.name,
              firstname: first_name,
              email: contact.email,
              phone: format_phone_number(contact.phone_number),
              entities_id: entity_id
            }.compact
          end

          # Split a full name into first and last name
          #
          # Splits on the first space character. If no space is found,
          # the entire name is used as the first name.
          #
          # @param full_name [String] The full name to split
          # @return [Array<String, String>] [first_name, last_name]
          #
          # @example
          #   ContactMapper.split_name('John Doe')
          #   # => ['John', 'Doe']
          #
          # @example Single name
          #   ContactMapper.split_name('Madonna')
          #   # => ['Madonna', nil]
          #
          # @example Multiple spaces
          #   ContactMapper.split_name('Mary Jane Watson')
          #   # => ['Mary', 'Jane Watson']
          def split_name(full_name)
            return [nil, nil] if full_name.blank?

            parts = full_name.split(' ', 2)
            [parts[0], parts[1]]
          end

          # Format phone number to international format
          #
          # Uses the TelephoneNumber gem to parse and format phone numbers
          # in international format (+XX XXXXXXXXX). If parsing fails,
          # returns the original phone number unchanged.
          #
          # @param phone_number [String] The phone number to format
          # @return [String, nil] Formatted phone number or nil if blank
          #
          # @example Valid phone number
          #   ContactMapper.format_phone_number('+12345678900')
          #   # => '+1 234 567 8900'
          #
          # @example Invalid phone number
          #   ContactMapper.format_phone_number('invalid')
          #   # => 'invalid'
          #
          # @example Nil or blank
          #   ContactMapper.format_phone_number(nil)
          #   # => nil
          def format_phone_number(phone_number)
            return nil if phone_number.blank?

            parsed = TelephoneNumber.parse(phone_number)
            parsed.international_string
          rescue TelephoneNumber::InvalidNumberError
            phone_number
          end
        end
      end
    end
  end
end
