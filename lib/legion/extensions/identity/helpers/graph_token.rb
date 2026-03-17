# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Helpers
        module GraphToken
          TOKEN_ENDPOINT = 'https://login.microsoftonline.com/%<tenant_id>s/oauth2/v2.0/token'
          GRAPH_SCOPE = 'https://graph.microsoft.com/.default'

          class GraphTokenError < StandardError; end

          module_function

          def fetch(tenant_id:, client_id:, client_secret:)
            require 'faraday'
            url = format(TOKEN_ENDPOINT, tenant_id: tenant_id)
            conn = Faraday.new(url: url) do |c|
              c.request :url_encoded
              c.response :json, content_type: /\bjson$/
            end
            resp = conn.post('', grant_type: 'client_credentials', client_id: client_id,
                                 client_secret: client_secret, scope: GRAPH_SCOPE)
            raise GraphTokenError, resp.body['error_description'] unless resp.success?

            resp.body['access_token']
          end
        end
      end
    end
  end
end
