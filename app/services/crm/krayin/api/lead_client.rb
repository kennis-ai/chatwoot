class Crm::Krayin::Api::LeadClient < Crm::Krayin::Api::BaseClient
  def search_lead(email: nil, phone: nil)
    raise ArgumentError, 'Email or phone required' if email.blank? && phone.blank?

    params = {}
    params[:email] = email if email.present?
    params[:phone] = phone if phone.present?

    leads = get('leads', params)
    leads.is_a?(Array) ? leads : leads['data']
  end

  def create_lead(lead_data)
    raise ArgumentError, 'Lead data is required' if lead_data.blank?

    response = post('leads', lead_data)
    response['data']['id'] || response['id']
  end

  def update_lead(lead_data, lead_id)
    raise ArgumentError, 'Lead ID is required' if lead_id.blank?
    raise ArgumentError, 'Lead data is required' if lead_data.blank?

    response = put("leads/#{lead_id}", lead_data)
    response['data'] || response
  end

  def get_lead(lead_id)
    raise ArgumentError, 'Lead ID is required' if lead_id.blank?

    response = get("leads/#{lead_id}")
    response['data'] || response
  end

  def get_pipelines
    response = get('pipelines')
    response['data'] || response
  end

  def get_stages(pipeline_id = nil)
    path = pipeline_id ? "pipelines/#{pipeline_id}/stages" : 'stages'
    response = get(path)
    response['data'] || response
  end

  def get_sources
    response = get('sources')
    response['data'] || response
  end

  def get_types
    response = get('types')
    response['data'] || response
  end
end
