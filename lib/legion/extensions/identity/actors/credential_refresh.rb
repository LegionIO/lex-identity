# frozen_string_literal: true

require 'legion/extensions/actors/every'

module Legion
  module Extensions
    module Identity
      module Actor
        class CredentialRefresh < Legion::Extensions::Actors::Every
          CREDENTIAL_REFRESH_INTERVAL = 21_600 # 6 hours

          def runner_class
            Legion::Extensions::Identity::Runners::Entra
          end

          def runner_function
            'credential_refresh_cycle'
          end

          def time
            CREDENTIAL_REFRESH_INTERVAL
          end

          def enabled?
            defined?(Legion::Data) && Legion::Settings[:data][:connected] != false
          rescue StandardError
            false
          end

          def use_runner?
            false
          end

          def check_subtask?
            false
          end

          def generate_task?
            false
          end
        end
      end
    end
  end
end
