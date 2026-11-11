# frozen_string_literal: true

require 'socket'
require 'uri'
require 'legion/logging/helper'

module Legion
  module Extensions
    module Identity
      module Helpers
        class CallbackServer
          include Legion::Logging::Helper

          HEADER_LIMIT = 8192
          CLIENT_TIMEOUT = 2
          RESPONSE_BODY = "Callback received. Return to the application.\n"

          attr_reader :redirect_uri

          def initialize(port: 0, **)
            raise ArgumentError, 'port must be an integer between 0 and 65535' unless port.is_a?(Integer) && (0..65_535).cover?(port)

            @listener = TCPServer.new('127.0.0.1', port)
            @redirect_uri = "http://127.0.0.1:#{@listener.addr[1]}/callback"
          end

          def wait_for_callback(state:, timeout: 120, **)
            raise ArgumentError, 'timeout must be finite and nonnegative' unless timeout.is_a?(Numeric) && timeout.real? && timeout.finite? && timeout >= 0
            raise ArgumentError, 'state must be a nonempty string' unless state.is_a?(String) && !state.empty?
            raise IOError, 'callback server is closed' if @listener.closed?

            deadline = callback_now + timeout
            while callback_wait(io: @listener, deadline: deadline)
              @client = @listener.accept_nonblock(exception: false)
              next if @client == :wait_readable

              result = callback_receive(client: @client, state: state, deadline: [deadline, callback_now + CLIENT_TIMEOUT].min)
              return result if result
            end
            { error: 'timeout', description: 'Timed out waiting for OAuth callback' }
          rescue IOError, SystemCallError => e
            handle_exception(e, level: :warn, operation: 'identity.callback.wait')
            { error: 'callback_failed', description: 'OAuth callback listener failed' }
          ensure
            shutdown
          end

          def shutdown(**)
            callback_close(socket: @client) if @client.is_a?(IO)
            callback_close(socket: @listener)
            nil
          end

          private

          def callback_now
            ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          end

          def callback_wait(io:, deadline:, writable: false)
            remaining = deadline - callback_now
            return false unless remaining.positive?

            readers, writers = writable ? [nil, [io]] : [[io], nil]
            !IO.select(readers, writers, nil, remaining).nil?
          end

          def callback_receive(client:, state:, deadline:)
            header = callback_read_header(client: client, deadline: deadline)
            status, result = header ? callback_parse(header: header, state: state) : [400, nil]
            callback_respond(client: client, status: status, deadline: deadline)
            result
          rescue IOError, SystemCallError => e
            handle_exception(e, level: :warn, operation: 'identity.callback.receive')
            nil
          ensure
            callback_close(socket: client)
          end

          def callback_read_header(client:, deadline:)
            header = +''.b
            while header.bytesize < HEADER_LIMIT && callback_wait(io: client, deadline: deadline)
              chunk = client.read_nonblock(HEADER_LIMIT - header.bytesize, exception: false)
              next if chunk == :wait_readable
              return if chunk.nil?

              header << chunk
              return header if header.include?("\r\n\r\n")
            end
            nil
          end

          def callback_parse(header:, state:)
            return [400, nil] unless header.end_with?("\r\n\r\n")

            request, *headers = header.delete_suffix("\r\n\r\n").split("\r\n")
            match = %r{\AGET (/[^\s]*) HTTP/1\.[01]\z}.match(request.to_s)
            return [400, nil] unless match && callback_headers_valid?(headers: headers)

            target = match[1]
            return [400, nil] if target.start_with?('//') || /[^\x21-\x7e]|%(?![0-9a-fA-F]{2})/.match?(target)

            uri = URI.parse(target)
            return [400, nil] if uri.host || uri.fragment
            return [404, nil] unless uri.path == '/callback'

            callback_result(query: uri.query.to_s, state: state)
          rescue URI::InvalidURIError, ArgumentError => e
            sanitized = ArgumentError.new('Rejected malformed OAuth callback request')
            sanitized.set_backtrace(e.backtrace)
            handle_exception(sanitized, level: :warn, operation: 'identity.callback.parse')
            [400, nil]
          end

          def callback_headers_valid?(headers:)
            headers.all? do |header|
              match = /\A([!#$%&'*+.^_`|~0-9A-Za-z-]+):[\t\x20-\x7e]*\z/.match(header)
              next false unless match

              name = match[1].downcase
              next false if name == 'transfer-encoding'
              next false if name == 'content-length' && header.split(':', 2).last.strip != '0'

              true
            end
          end

          def callback_result(query:, state:)
            pairs = URI.decode_www_form(query, Encoding::UTF_8)
            params = pairs.to_h
            return [400, nil] if pairs.length != params.length || params['state'] != state
            return [400, nil] if params.key?('code') == params.key?('error')

            if params.key?('code')
              return [400, nil] if params['code'].empty? || params.key?('error_description') || params.key?('error_uri')

              [200, { code: params['code'] }]
            else
              return [400, nil] if params['error'].empty?

              [200, { error: params['error'], description: params.fetch('error_description', '') }]
            end
          end

          def callback_respond(client:, status:, deadline:)
            reason = { 200 => 'OK', 400 => 'Bad Request', 404 => 'Not Found' }.fetch(status)
            body = status == 200 ? RESPONSE_BODY : "Callback request not accepted.\n"
            response = "HTTP/1.1 #{status} #{reason}\r\nContent-Type: text/plain; charset=utf-8\r\n" \
                       "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
            offset = 0
            while offset < response.bytesize && callback_wait(io: client, deadline: deadline, writable: true)
              written = client.write_nonblock(response.byteslice(offset..), exception: false)
              next if written == :wait_writable

              offset += written
            end
          rescue IOError, SystemCallError => e
            handle_exception(e, level: :warn, operation: 'identity.callback.respond')
          end

          def callback_close(socket:)
            socket.close unless socket.closed?
          rescue IOError, SystemCallError => e
            handle_exception(e, level: :warn, operation: 'identity.callback.close')
          end
        end
      end
    end
  end
end
