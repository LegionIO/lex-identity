# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Helpers
        module GraphClient
          GRAPH_BASE = 'https://graph.microsoft.com/v1.0'

          module_function

          def connection(token:, base: GRAPH_BASE)
            require 'faraday'
            Faraday.new(url: base) do |conn|
              conn.request :json
              conn.response :json, content_type: /\bjson$/
              conn.headers['Authorization'] = "Bearer #{token}"
              conn.headers['Content-Type'] = 'application/json'
            end
          end
        end
      end
    end
  end
end
