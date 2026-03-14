# frozen_string_literal: true

require 'legion/extensions/actors/every'

module Legion
  module Extensions
    module Identity
      module Actor
        # Periodic orphan detection: scans active workers for disabled Entra apps
        # or inactive owners. Runs every 4 hours by default.
        # Requires legion-data for worker records.
        class OrphanCheck < Legion::Extensions::Actors::Every
          ORPHAN_CHECK_INTERVAL = 14_400 # 4 hours in seconds

          def runner_class
            Legion::Extensions::Identity::Runners::Entra
          end

          def runner_function
            'check_orphans'
          end

          def time
            ORPHAN_CHECK_INTERVAL
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
