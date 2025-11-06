class Crm::Krayin::Api::BaseClient
  include HTTParty

  class ApiError < StandardError
    attr_reader :code, :response

    def initialize(message = nil, code = nil, response = nil)
      @code = code
      @response = response
      super(message)
    end
  end

  def initialize(api_url, api_token)
    @api_url = api_url.chomp('/')
    @api_token = api_token
    self.class.base_uri @api_url
  end

  def get(path, params = {})
    response = self.class.get(
      "/#{path}",
      query: params,
      headers: headers
    )
    handle_response(response)
  end

  def post(path, body = {}, params = {})
    response = self.class.post(
      "/#{path}",
      query: params,
      body: body.to_json,
      headers: headers
    )
    handle_response(response)
  end

  def put(path, body = {}, params = {})
    response = self.class.put(
      "/#{path}",
      query: params,
      body: body.to_json,
      headers: headers
    )
    handle_response(response)
  end

  def delete(path, params = {})
    response = self.class.delete(
      "/#{path}",
      query: params,
      headers: headers
    )
    handle_response(response)
  end

  private

  def headers
    {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'Authorization' => "Bearer #{@api_token}"
    }
  end

  def handle_response(response)
    case response.code
    when 200..299
      response.parsed_response
    when 401
      raise ApiError.new('Unauthorized: Invalid API token', response.code, response)
    when 404
      raise ApiError.new('Resource not found', response.code, response)
    when 422
      errors = extract_validation_errors(response)
      raise ApiError.new("Validation failed: #{errors}", response.code, response)
    else
      error_message = "Krayin API error: #{response.code} - #{response.body}"
      Rails.logger.error error_message
      raise ApiError.new(error_message, response.code, response)
    end
  end

  def extract_validation_errors(response)
    body = response.parsed_response
    return body['message'] if body['message']
    return body['errors'].to_s if body['errors']

    response.body
  end
end
