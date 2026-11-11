# frozen_string_literal: true

require 'legion/extensions/identity/helpers/oauth'
require 'legion/extensions/identity/helpers/browser'
require 'legion/extensions/identity/helpers/callback_server'
require 'legion/extensions/identity/helpers/pkce'
require 'securerandom'
require 'legion/logging'

module Legion
  module Extensions
    module Identity
      module Runners
        module Oauth
          extend self
          extend Legion::Extensions::Identity::Helpers::Oauth
          extend Legion::Extensions::Identity::Helpers::Browser
          extend Legion::Extensions::Identity::Helpers::Pkce

          DEVICE_CODE_GRANT = 'urn:ietf:params:oauth:grant-type:device_code'

          def browser_login(authorization_endpoint:, token_endpoint:, client_id:, scope:, callback_port: 0, callback_timeout: 120, **)
            unless callback_timeout.is_a?(Numeric) && callback_timeout.real? && callback_timeout.finite? && callback_timeout.positive?
              raise ArgumentError, 'callback_timeout must be positive and finite'
            end

            return { error: 'browser_unavailable', description: 'Interactive browser login requires a graphical session' } unless browser_gui_available?

            begin
              pkce = pkce_generate
              state = SecureRandom.hex(32)
              server = Legion::Extensions::Identity::Helpers::CallbackServer.new(port: callback_port)
              redirect_uri = server.redirect_uri
              url = oauth_authorize_url(authorization_endpoint: authorization_endpoint, client_id: client_id,
                                        redirect_uri: redirect_uri, scope: scope, state: state,
                                        code_challenge: pkce[:code_challenge], code_challenge_method: pkce[:code_challenge_method])
              if browser_open(url: url)
                callback = server.wait_for_callback(state: state, timeout: callback_timeout)
                if callback[:error]
                  callback
                else
                  exchange_code(token_endpoint: token_endpoint, client_id: client_id, code: callback[:code],
                                redirect_uri: redirect_uri, code_verifier: pkce[:code_verifier], scope: scope)
                end
              else
                { error: 'browser_launch_failed', description: 'Unable to launch the browser' }
              end
            rescue StandardError => e
              oauth_runner_error(operation: 'identity.oauth.browser_login', exception: e)
            ensure
              server&.shutdown
            end
          end

          def request_device_code(device_authorization_endpoint:, client_id:, scope:, **)
            result = oauth_post(endpoint: device_authorization_endpoint,
                                form:     { client_id: client_id, scope: scope })
            oauth_runner_result(result: result, required_key: :device_code)
          rescue StandardError => e
            oauth_runner_error(operation: 'identity.oauth.request_device_code', exception: e)
          end

          def exchange_code(token_endpoint:, client_id:, code:, redirect_uri:, code_verifier:, scope: nil, **)
            form = {
              grant_type: 'authorization_code', client_id: client_id, code: code,
              redirect_uri: redirect_uri, code_verifier: code_verifier
            }
            form[:scope] = scope unless scope.nil?
            result = oauth_post(endpoint: token_endpoint, form: form)
            oauth_runner_result(result: result, required_key: :access_token)
          rescue StandardError => e
            oauth_runner_error(operation: 'identity.oauth.exchange_code', exception: e)
          end

          def refresh_token(token_endpoint:, client_id:, refresh_token:, scope: nil, **)
            form = { grant_type: 'refresh_token', client_id: client_id, refresh_token: refresh_token }
            form[:scope] = scope unless scope.nil?
            result = oauth_post(endpoint: token_endpoint, form: form)
            oauth_runner_result(result: result, required_key: :access_token)
          rescue StandardError => e
            oauth_runner_error(operation: 'identity.oauth.refresh_token', exception: e)
          end

          def poll_device_code(token_endpoint:, client_id:, device_code:, interval: 5, timeout: 300, **)
            raise ArgumentError, 'interval must be positive' unless interval.positive?
            raise ArgumentError, 'timeout must not be negative' if timeout.negative?

            deadline = oauth_monotonic_now + timeout
            current_interval = interval
            outcome = { error: 'timeout', description: "Device code flow timed out after #{timeout}s" }
            begin
              while (remaining = deadline - oauth_monotonic_now).positive?
                result = oauth_post(endpoint:        token_endpoint,
                                    form:            { grant_type: DEVICE_CODE_GRANT, client_id: client_id, device_code: device_code },
                                    open_timeout:    [remaining, 5].min,
                                    request_timeout: [remaining, 15].min)
                if result[:error] == 'slow_down'
                  current_interval += 5
                elsif result[:error] != 'authorization_pending'
                  outcome = oauth_runner_result(result: result, required_key: :access_token)
                  break
                end
                sleep_for = [current_interval, deadline - oauth_monotonic_now].min
                break if sleep_for <= 0

                sleep(sleep_for)
              end

              outcome
            rescue StandardError => e
              oauth_runner_error(operation: 'identity.oauth.poll_device_code', exception: e)
            end
          end

          private

          def oauth_runner_result(result:, required_key:)
            return { error: result[:error].to_s, description: (result[:error_description] || result[:description]).to_s } if result[:error]
            unless result[required_key].is_a?(String) && !result[required_key].empty?
              return { error: 'invalid_response', description: "OAuth response did not include #{required_key}" }
            end

            { result: result }
          end

          def oauth_runner_error(operation:, exception:)
            sanitized = StandardError.new("OAuth runner failed (#{exception.class})")
            sanitized.set_backtrace(exception.backtrace)
            handle_exception(sanitized, level: :error, operation: operation)
            { error: 'request_failed', description: exception.message }
          end

          def oauth_monotonic_now
            ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          end
        end
      end
    end
  end
end
