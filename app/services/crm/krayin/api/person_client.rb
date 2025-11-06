class Crm::Krayin::Api::PersonClient < Crm::Krayin::Api::BaseClient
  def search_person(email: nil, phone: nil)
    raise ArgumentError, 'Email or phone required' if email.blank? && phone.blank?

    params = {}
    params[:email] = email if email.present?
    params[:phone] = phone if phone.present?

    persons = get('contacts/persons', params)
    persons.is_a?(Array) ? persons : persons['data']
  end

  def create_person(person_data)
    raise ArgumentError, 'Person data is required' if person_data.blank?

    response = post('contacts/persons', person_data)
    response['data']['id'] || response['id']
  end

  def update_person(person_data, person_id)
    raise ArgumentError, 'Person ID is required' if person_id.blank?
    raise ArgumentError, 'Person data is required' if person_data.blank?

    response = put("contacts/persons/#{person_id}", person_data)
    response['data'] || response
  end

  def get_person(person_id)
    raise ArgumentError, 'Person ID is required' if person_id.blank?

    response = get("contacts/persons/#{person_id}")
    response['data'] || response
  end
end
