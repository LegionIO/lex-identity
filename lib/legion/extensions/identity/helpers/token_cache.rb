# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Helpers
        module TokenCache
          REFRESH_BUFFER = 300

          @mutex = Mutex.new
          @tokens = {}

          module_function

          def store(worker_id:, token:, expires_in:)
            @mutex.synchronize do
              @tokens[worker_id] = {
                access_token: token,
                expires_at:   Time.now + expires_in,
                acquired_at:  Time.now
              }
            end
          end

          def fetch(worker_id:)
            @mutex.synchronize do
              entry = @tokens[worker_id]
              return nil unless entry
              return nil if Time.now >= entry[:expires_at]

              entry
            end
          end

          def approaching_expiry?(worker_id:, buffer: REFRESH_BUFFER)
            @mutex.synchronize do
              entry = @tokens[worker_id]
              return true unless entry

              (entry[:expires_at] - Time.now) < buffer
            end
          end

          def clear(worker_id:)
            @mutex.synchronize { @tokens.delete(worker_id) }
          end

          def clear_all
            @mutex.synchronize { @tokens.clear }
          end
        end
      end
    end
  end
end
