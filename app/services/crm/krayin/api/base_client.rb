class Crm::Krayin::Api::BaseClient
  include HTTParty

  class ApiError < StandardError
    attr_reader :code, :response, :status_code

    def initialize(message = nil, code = nil, response = nil)
      @code = code
      @status_code = code
      @response = response
      super(message)
    end

    def retriable?
      # Retry on rate limits and temporary server errors
      [429, 502, 503, 504].include?(status_code)
    end

    def rate_limited?
      status_code == 429
    end
  end

  MAX_RETRIES = 3
  INITIAL_BACKOFF = 1 # seconds

  def initialize(api_url, api_token)
    @api_url = api_url.chomp('/')
    @api_token = api_token
    self.class.base_uri @api_url
  end

  def get(path, params = {})
    request_with_retry(:get, path, nil, params)
  end

  def post(path, body = {}, params = {})
    request_with_retry(:post, path, body, params)
  end

  def put(path, body = {}, params = {})
    request_with_retry(:put, path, body, params)
  end

  def delete(path, params = {})
    request_with_retry(:delete, path, nil, params)
  end

  private

  def request_with_retry(method, path, body = nil, params = {}, attempt = 1)
    response = execute_request(method, path, body, params)
    handle_response(response)
  rescue ApiError => e
    if e.retriable? && attempt < MAX_RETRIES
      wait_time = calculate_backoff(attempt, e.rate_limited?)
      log_retry(method, path, attempt, wait_time, e)
      sleep(wait_time)
      request_with_retry(method, path, body, params, attempt + 1)
    else
      log_error(method, path, e)
      raise
    end
  rescue StandardError => e
    log_error(method, path, e)
    raise ApiError.new("Request failed: #{e.message}", nil, nil)
  end

  def execute_request(method, path, body, params)
    case method
    when :get
      self.class.get("/#{path}", query: params, headers: headers)
    when :post
      self.class.post("/#{path}", query: params, body: body.to_json, headers: headers)
    when :put
      self.class.put("/#{path}", query: params, body: body.to_json, headers: headers)
    when :delete
      self.class.delete("/#{path}", query: params, headers: headers)
    else
      raise ArgumentError, "Unsupported HTTP method: #{method}"
    end
  end

  def calculate_backoff(attempt, rate_limited)
    if rate_limited
      # For rate limits, use longer backoff
      INITIAL_BACKOFF * (3**attempt)
    else
      # For other retriable errors, use exponential backoff
      INITIAL_BACKOFF * (2**attempt)
    end
  end

  def log_retry(method, path, attempt, wait_time, error)
    Rails.logger.warn(
      "Krayin API #{method.upcase} /#{path} failed (attempt #{attempt}/#{MAX_RETRIES}): " \
      "#{error.message}. Retrying in #{wait_time}s..."
    )
  end

  def log_error(method, path, error)
    Rails.logger.error(
      "Krayin API #{method.upcase} /#{path} error: #{error.class} - #{error.message}"
    )
  end

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
      raise ApiError.new(
        'Unauthorized: Invalid API token. Please check your API credentials.',
        response.code,
        response
      )
    when 403
      raise ApiError.new(
        'Forbidden: API token does not have required permissions.',
        response.code,
        response
      )
    when 404
      raise ApiError.new(
        'Resource not found. The requested endpoint or resource does not exist.',
        response.code,
        response
      )
    when 422
      errors = extract_validation_errors(response)
      raise ApiError.new(
        "Validation failed: #{errors}",
        response.code,
        response
      )
    when 429
      retry_after = response.headers['Retry-After'] || 60
      raise ApiError.new(
        "Rate limit exceeded. Retry after #{retry_after} seconds.",
        response.code,
        response
      )
    when 500
      raise ApiError.new(
        'Internal server error. The Krayin server encountered an error.',
        response.code,
        response
      )
    when 502, 503, 504
      raise ApiError.new(
        "Service temporarily unavailable (#{response.code}). Please try again later.",
        response.code,
        response
      )
    else
      error_message = extract_error_message(response)
      raise ApiError.new(
        "Krayin API error (#{response.code}): #{error_message}",
        response.code,
        response
      )
    end
  end

  def extract_validation_errors(response)
    body = response.parsed_response
    return body['message'] if body['message']
    return body['errors'].to_s if body['errors']

    response.body
  end

  def extract_error_message(response)
    body = response.parsed_response rescue nil
    return body['message'] if body&.dig('message')
    return body['error'] if body&.dig('error')

    response.body&.truncate(200) || 'Unknown error'
  end
end
