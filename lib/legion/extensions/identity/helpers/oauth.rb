# frozen_string_literal: true

require 'uri'
require 'faraday'
require 'legion/json'
require 'legion/json/helper'
require 'legion/logging'

module Legion
  module Extensions
    module Identity
      module Helpers
        module Oauth
          include Legion::Logging::Helper
          include Legion::JSON::Helper

          def oauth_authorize_url(authorization_endpoint:, client_id:, redirect_uri:, scope:, state:, code_challenge:,
                                  code_challenge_method: 'S256', **)
            uri = URI.parse(authorization_endpoint)
            params = {
              'client_id' => client_id, 'response_type' => 'code', 'redirect_uri' => redirect_uri,
              'scope' => scope, 'state' => state, 'code_challenge' => code_challenge,
              'code_challenge_method' => code_challenge_method
            }
            query = URI.decode_www_form(uri.query.to_s).reject { |key, _value| params.key?(key) }
            uri.query = URI.encode_www_form(query + params.to_a)
            uri.to_s
          end

          def oauth_post(endpoint:, form:, open_timeout: 5, request_timeout: 15, **)
            connection = Faraday.new do |http|
              http.headers['Accept'] = 'application/json'
              http.headers['Content-Type'] = 'application/x-www-form-urlencoded'
              http.options.open_timeout = open_timeout
              http.options.timeout = request_timeout
            end
            response = connection.post(endpoint, URI.encode_www_form(form))
            oauth_parse_response(response: response)
          end

          private

          def oauth_parse_response(response:)
            body = response.body.to_s.empty? ? {} : json_load(response.body)
            return body if body.is_a?(Hash) && body[:error]
            return { error: "http_#{response.status}", error_description: response.reason_phrase.to_s } unless response.success?
            return body if body.is_a?(Hash)

            { error: 'invalid_response', error_description: 'OAuth response must be a JSON object' }
          rescue Legion::JSON::ParseError => e
            sanitized = StandardError.new("OAuth response parsing failed (#{e.class})")
            sanitized.set_backtrace(e.backtrace)
            handle_exception(sanitized, level: :error, operation: 'identity.oauth_parse_response')
            return { error: "http_#{response.status}", error_description: response.reason_phrase.to_s } unless response.success?

            { error: 'invalid_response', error_description: 'OAuth response is not valid JSON' }
          end
        end
      end
    end
  end
end
