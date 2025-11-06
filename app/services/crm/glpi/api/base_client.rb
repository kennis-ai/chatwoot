# frozen_string_literal: true

module Crm
  module Glpi
    module Api
      # GLPI API client with session management
      #
      # This client handles the GLPI REST API session lifecycle, including
      # initialization, authentication, and cleanup. All API calls should
      # be wrapped in the with_session block to ensure proper session management.
      #
      # @example Basic usage
      #   client = BaseClient.new(
      #     api_url: 'https://glpi.example.com/apirest.php',
      #     app_token: 'your_app_token',
      #     user_token: 'your_user_token'
      #   )
      #
      #   client.with_session do
      #     result = client.get('/User')
      #   end
      class BaseClient
        include HTTParty

        # Custom exception for GLPI API errors
        class ApiError < StandardError
          attr_reader :code, :response

          # @param code [Integer] HTTP status code
          # @param response [HTTParty::Response] The HTTP response object
          def initialize(code, response)
            @code = code
            @response = response
            super("GLPI API Error: #{code} - #{response.body}")
          end
        end

        attr_reader :api_url, :app_token, :user_token, :session_token

        # Initialize a new GLPI API client
        #
        # @param api_url [String] The GLPI API base URL (e.g., https://glpi.example.com/apirest.php)
        # @param app_token [String] The GLPI application token
        # @param user_token [String] The GLPI user token
        def initialize(api_url:, app_token:, user_token:)
          @api_url = api_url
          @app_token = app_token
          @user_token = user_token
          @session_token = nil
        end

        # Execute a block with an active GLPI session
        #
        # This method ensures that:
        # - A session is initialized before the block executes
        # - The session is always cleaned up after the block completes (even on error)
        #
        # @yield Block to execute with an active session
        # @return The result of the block
        # @raise [ApiError] If session initialization fails
        def with_session(&block)
          init_session
          result = yield
          result
        ensure
          kill_session
        end

        # Perform a GET request to the GLPI API
        #
        # @param endpoint [String] The API endpoint path (e.g., '/User', '/Ticket/123')
        # @param query_params [Hash] Query parameters to include in the request
        # @return [Hash, Array] Parsed JSON response
        # @raise [ApiError] If the request fails
        def get(endpoint, query_params = {})
          full_url = URI.join(api_url, endpoint).to_s

          options = {
            query: query_params,
            headers: headers,
            timeout: 30
          }

          response = self.class.get(full_url, options)
          handle_response(response)
        end

        # Perform a POST request to the GLPI API
        #
        # @param endpoint [String] The API endpoint path
        # @param body [Hash] Request body (will be converted to JSON)
        # @return [Hash, Array] Parsed JSON response
        # @raise [ApiError] If the request fails
        def post(endpoint, body = {})
          full_url = URI.join(api_url, endpoint).to_s

          options = {
            headers: headers,
            body: body.to_json,
            timeout: 30
          }

          response = self.class.post(full_url, options)
          handle_response(response)
        end

        # Perform a PUT request to the GLPI API
        #
        # @param endpoint [String] The API endpoint path
        # @param body [Hash] Request body (will be converted to JSON)
        # @return [Hash, Array] Parsed JSON response
        # @raise [ApiError] If the request fails
        def put(endpoint, body = {})
          full_url = URI.join(api_url, endpoint).to_s

          options = {
            headers: headers,
            body: body.to_json,
            timeout: 30
          }

          response = self.class.put(full_url, options)
          handle_response(response)
        end

        private

        # Initialize a GLPI session
        #
        # @raise [ApiError] If session initialization fails
        def init_session
          return if @session_token.present?

          full_url = URI.join(api_url, '/initSession').to_s

          options = {
            headers: {
              'Content-Type' => 'application/json',
              'App-Token' => app_token,
              'Authorization' => "user_token #{user_token}"
            },
            timeout: 30
          }

          response = self.class.get(full_url, options)

          if response.code == 200
            parsed = parse_json(response)
            @session_token = parsed['session_token']
            Rails.logger.info "GLPI session initialized: #{@session_token[0..7]}..." if @session_token
          else
            handle_error_response(response)
          end
        end

        # Terminate the GLPI session
        def kill_session
          return unless @session_token.present?

          full_url = URI.join(api_url, '/killSession').to_s

          options = {
            headers: {
              'Content-Type' => 'application/json',
              'App-Token' => app_token,
              'Session-Token' => @session_token
            },
            timeout: 10
          }

          begin
            self.class.get(full_url, options)
            Rails.logger.info "GLPI session terminated: #{@session_token[0..7]}..."
          rescue StandardError => e
            Rails.logger.warn "Failed to kill GLPI session: #{e.message}"
          ensure
            @session_token = nil
          end
        end

        # Build headers for authenticated API requests
        #
        # @return [Hash] Headers hash with session token and app token
        def headers
          {
            'Content-Type' => 'application/json',
            'App-Token' => app_token,
            'Session-Token' => @session_token
          }.compact
        end

        # Handle the HTTP response and raise errors if necessary
        #
        # @param response [HTTParty::Response] The HTTP response
        # @return [Hash, Array] Parsed response body
        # @raise [ApiError] If the response indicates an error
        def handle_response(response)
          case response.code
          when 200..299
            parse_json(response)
          else
            handle_error_response(response)
          end
        end

        # Handle error responses from GLPI API
        #
        # @param response [HTTParty::Response] The HTTP response
        # @raise [ApiError] Always raises with appropriate message
        def handle_error_response(response)
          error_details = extract_error_details(response)

          case response.code
          when 401
            error_message = "GLPI authentication failed: #{error_details}"
          when 404
            error_message = "GLPI resource not found: #{error_details}"
          when 422
            error_message = "GLPI validation error: #{error_details}"
          when 500..599
            error_message = "GLPI server error: #{error_details}"
          else
            error_message = "GLPI API error (#{response.code}): #{error_details}"
          end

          Rails.logger.error error_message
          raise ApiError.new(response.code, response)
        end

        # Extract error details from response
        #
        # @param response [HTTParty::Response] The HTTP response
        # @return [String] Error message
        def extract_error_details(response)
          if response.body.present?
            begin
              parsed = JSON.parse(response.body)
              # GLPI error format: [message, error_code]
              if parsed.is_a?(Array) && parsed[0].is_a?(String)
                parsed[0]
              elsif parsed.is_a?(Hash)
                parsed['message'] || parsed['error'] || response.body
              else
                response.body
              end
            rescue JSON::ParserError
              response.body
            end
          else
            'No error details provided'
          end
        end

        # Parse JSON response
        #
        # @param response [HTTParty::Response] The HTTP response
        # @return [Hash, Array] Parsed JSON body
        # @raise [ApiError] If JSON parsing fails
        def parse_json(response)
          response.parsed_response
        rescue JSON::ParserError, TypeError => e
          error_message = "Failed to parse GLPI API response: #{e.message}"
          Rails.logger.error error_message
          raise ApiError.new(response.code, response)
        end
      end
    end
  end
end
