class Crm::Krayin::Api::OrganizationClient < Crm::Krayin::Api::BaseClient
  def search_organization(name)
    raise ArgumentError, 'Organization name is required' if name.blank?

    params = { name: name }
    organizations = get('contacts/organizations', params)
    organizations.is_a?(Array) ? organizations : organizations['data']
  end

  def create_organization(org_data)
    raise ArgumentError, 'Organization data is required' if org_data.blank?

    response = post('contacts/organizations', org_data)
    response['data']['id'] || response['id']
  end

  def update_organization(org_data, org_id)
    raise ArgumentError, 'Organization ID is required' if org_id.blank?
    raise ArgumentError, 'Organization data is required' if org_data.blank?

    response = put("contacts/organizations/#{org_id}", org_data)
    response['data'] || response
  end

  def get_organization(org_id)
    raise ArgumentError, 'Organization ID is required' if org_id.blank?

    response = get("contacts/organizations/#{org_id}")
    response['data'] || response
  end
end
