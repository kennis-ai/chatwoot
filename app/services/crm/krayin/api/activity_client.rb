class Crm::Krayin::Api::ActivityClient < Crm::Krayin::Api::BaseClient
  def search_activity(params = {})
    activities = get('activities', params)
    activities.is_a?(Array) ? activities : activities['data']
  end

  def create_activity(activity_data)
    raise ArgumentError, 'Activity data is required' if activity_data.blank?

    response = post('activities', activity_data)
    response['data']['id'] || response['id']
  end

  def update_activity(activity_data, activity_id)
    raise ArgumentError, 'Activity ID is required' if activity_id.blank?
    raise ArgumentError, 'Activity data is required' if activity_data.blank?

    response = put("activities/#{activity_id}", activity_data)
    response['data'] || response
  end

  def get_activity(activity_id)
    raise ArgumentError, 'Activity ID is required' if activity_id.blank?

    response = get("activities/#{activity_id}")
    response['data'] || response
  end
end
