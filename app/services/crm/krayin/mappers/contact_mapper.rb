class Crm::Krayin::Mappers::ContactMapper
  def self.map_to_person(contact)
    new(contact).map_to_person
  end

  def self.map_to_lead(contact, person_id, settings)
    new(contact).map_to_lead(person_id, settings)
  end

  def initialize(contact)
    @contact = contact
  end

  def map_to_person
    {
      name: contact.name.presence,
      emails: format_emails,
      contact_numbers: format_contact_numbers,
      job_title: contact.additional_attributes&.dig('job_title')
    }.compact
  end

  def map_to_lead(person_id, settings)
    {
      title: contact.name.presence || "Contact #{contact.id}",
      person_id: person_id,
      lead_value: extract_lead_value,
      description: build_description,
      lead_source_id: settings['lead_source_id'],
      lead_type_id: settings['lead_type_id'] || settings['default_lead_type_id'],
      lead_pipeline_id: settings['lead_pipeline_id'] || settings['default_pipeline_id'],
      lead_pipeline_stage_id: settings['lead_pipeline_stage_id'] || settings['default_stage_id']
    }.compact
  end

  private

  attr_reader :contact

  def format_emails
    return [] if contact.email.blank?

    [
      {
        value: contact.email,
        label: 'work'
      }
    ]
  end

  def format_contact_numbers
    return [] if contact.phone_number.blank?

    [
      {
        value: format_phone_number(contact.phone_number),
        label: 'work'
      }
    ]
  end

  def format_phone_number(phone)
    return phone if phone.blank?

    # Try to parse and format phone number, fallback to original if invalid
    parsed = TelephoneNumber.parse(phone)
    return phone unless parsed.valid?

    parsed.e164_number
  rescue StandardError
    phone
  end

  def extract_lead_value
    # Try to extract lead value from custom attributes
    value = contact.additional_attributes&.dig('lead_value')
    return value.to_f if value.present?

    # Default lead value from contact type or fallback
    default_lead_value
  end

  def default_lead_value
    # Could be customized based on contact source or type
    0.0
  end

  def build_description
    parts = []

    parts << "Email: #{contact.email}" if contact.email.present?
    parts << "Phone: #{contact.phone_number}" if contact.phone_number.present?
    parts << "Company: #{contact.additional_attributes['company']}" if contact.additional_attributes&.dig('company').present?
    parts << "Source: #{brand_name}"

    # Add custom attributes if present
    if contact.additional_attributes.present?
      custom_attrs = contact.additional_attributes.except('company', 'job_title', 'lead_value')
      unless custom_attrs.empty?
        parts << "Additional Info: #{custom_attrs.to_json}"
      end
    end

    parts.join("\n")
  end

  def brand_name
    ::GlobalConfig.get('BRAND_NAME')['BRAND_NAME'] || 'Chatwoot'
  end
end
