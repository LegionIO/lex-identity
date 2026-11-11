# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'legion/extensions/identity/helpers/callback_server'

RSpec.describe Legion::Extensions::Identity::Helpers::CallbackServer do
  def start_server(timeout: 2, **)
    server = described_class.new(**)
    results = Queue.new
    thread = Thread.new do
      results << server.wait_for_callback(state: 'state-123', timeout: timeout)
    end
    [server, thread, results]
  end

  def callback_port(server)
    URI.parse(server.redirect_uri).port
  end

  def request(port, target, headers: '')
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write("GET #{target} HTTP/1.1\r\nHost: 127.0.0.1\r\n#{headers}\r\n")
    Timeout.timeout(3) { socket.read }
  ensure
    socket&.close
  end

  def finish_server(server, thread)
    server.shutdown
    finished = thread.join(3)
    thread.kill unless finished
    thread.join
    raise 'Callback fixture did not finish' unless finished

    thread.value
  end

  it 'continues after a wrong state and returns the valid callback result' do
    server, thread, results = start_server
    port = callback_port(server)

    wrong_response = request(port, '/callback?code=wrong&state=other')
    valid_response = request(port, '/callback?code=auth-code&state=state-123')

    expect(wrong_response).to include('400 Bad Request')
    expect(valid_response).to include('200 OK', 'Callback received', 'Cache-Control: no-store')
    expect(results.pop(timeout: 3)).to eq(code: 'auth-code')
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'returns a validated provider denial without reflecting details to the browser' do
    server, thread, results = start_server
    port = callback_port(server)

    response = request(port, '/callback?error=access_denied&error_description=Nope%20%3Cscript%3E&state=state-123')

    expect(response).to include('200 OK', 'Callback received', 'Content-Type: text/plain')
    expect(response).not_to include('access_denied', 'Nope', 'script')
    expect(results.pop(timeout: 3)).to eq(error: 'access_denied', description: 'Nope <script>')
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'rejects duplicate state and code parameters and keeps waiting' do
    server, thread, results = start_server
    port = callback_port(server)

    duplicate_state = request(port, '/callback?code=auth-code&state=state-123&state=state-123')
    duplicate_code = request(port, '/callback?code=first&code=second&state=state-123')
    valid_response = request(port, '/callback?code=auth-code&state=state-123')

    expect(duplicate_state).to include('400 Bad Request')
    expect(duplicate_code).to include('400 Bad Request')
    expect(valid_response).to include('200 OK')
    expect(results.pop(timeout: 3)).to eq(code: 'auth-code')
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'rejects both code and error and keeps waiting' do
    server, thread, results = start_server
    port = callback_port(server)

    response = request(port, '/callback?code=auth-code&error=access_denied&state=state-123')
    valid_response = request(port, '/callback?code=auth-code&state=state-123')

    expect(response).to include('400 Bad Request')
    expect(valid_response).to include('200 OK')
    expect(results.pop(timeout: 3)).to eq(code: 'auth-code')
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'keeps waiting after an unrelated path' do
    server, thread, results = start_server
    port = callback_port(server)

    not_found = request(port, '/other?code=auth-code&state=state-123')
    valid_response = request(port, '/callback?code=auth-code&state=state-123')

    expect(not_found).to include('404 Not Found')
    expect(valid_response).to include('200 OK')
    expect(results.pop(timeout: 3)).to eq(code: 'auth-code')
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'times out when a client stalls before completing headers' do
    server, thread, results = start_server(timeout: 0.2)
    port = callback_port(server)
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write("GET /callback?code=auth-code&state=state-123 HTTP/1.1\r\nHost: 127.0.0.1\r\n")

    expect(results.pop(timeout: 3)).to eq(error: 'timeout', description: 'Timed out waiting for OAuth callback')
    socket.close
  ensure
    socket.close unless socket.nil? || socket.closed?
    finish_server(server, thread) if server && thread
  end

  it 'times out without accepting a callback when the deadline is zero' do
    server, thread, results = start_server(timeout: 0)

    expect(results.pop(timeout: 3)).to eq(error: 'timeout', description: 'Timed out waiting for OAuth callback')
    expect(server.redirect_uri).to match(%r{\Ahttp://127\.0\.0\.1:\d+/callback\z})
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'closes the listener after one callback and makes shutdown idempotent' do
    server, thread, results = start_server
    port = callback_port(server)

    request(port, '/callback?code=auth-code&state=state-123')
    expect(results.pop(timeout: 3)).to eq(code: 'auth-code')
    thread.join(2)
    server.shutdown
    server.shutdown
    expect { TCPSocket.open('127.0.0.1', port, &:close) }.to raise_error(Errno::ECONNREFUSED)
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'binds a registered fixed port' do
    probe = TCPServer.new('127.0.0.1', 0)
    port = probe.addr[1]
    probe.close
    server = described_class.new(port: port)

    expect(server.redirect_uri).to eq("http://127.0.0.1:#{port}/callback")
    expect { described_class.new(port: port) }.to raise_error(SystemCallError)
  ensure
    server&.shutdown
  end

  it 'validates timeout and port arguments' do
    expect { described_class.new(port: -1) }.to raise_error(ArgumentError)
    expect { described_class.new(port: 65_536) }.to raise_error(ArgumentError)
    expect { described_class.new(port: '0') }.to raise_error(ArgumentError)

    server = described_class.new
    expect { server.wait_for_callback(state: 'state-123', timeout: -1) }.to raise_error(ArgumentError)
    expect { server.wait_for_callback(state: 'state-123', timeout: Float::INFINITY) }.to raise_error(ArgumentError)
  ensure
    server&.shutdown
  end
  it 'does not let uncorrelated error callbacks cancel a pending login' do
    server, thread, results = start_server
    port = callback_port(server)

    wrong = request(port, '/callback?error=access_denied&state=wrong')
    missing = request(port, '/callback?error=access_denied')
    valid = request(port, '/callback?code=auth-code&state=state-123')

    expect(wrong).to include('400 Bad Request')
    expect(missing).to include('400 Bad Request')
    expect(valid).to include('200 OK')
    expect(results.pop(timeout: 3)).to eq(code: 'auth-code')
  ensure
    finish_server(server, thread) if server && thread
  end

  it 'rejects an oversized header without consuming the next valid callback' do
    server, thread, results = start_server
    port = callback_port(server)
    socket = TCPSocket.new('127.0.0.1', port)
    prefix = "GET /callback?code=ignored&state=state-123 HTTP/1.1\r\nX-Pad: "
    socket.write(prefix.ljust(described_class::HEADER_LIMIT, 'x'))

    response = Timeout.timeout(3) { socket.read }
    socket.close
    valid = request(port, '/callback?code=auth-code&state=state-123')

    expect(response).to include('400 Bad Request')
    expect(valid).to include('200 OK')
    expect(results.pop(timeout: 3)).to eq(code: 'auth-code')
  ensure
    socket&.close unless socket&.closed?
    finish_server(server, thread) if server && thread
  end
end
