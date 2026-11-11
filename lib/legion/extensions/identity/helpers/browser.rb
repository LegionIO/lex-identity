# frozen_string_literal: true

require 'rbconfig'
require 'legion/logging/helper'

module Legion
  module Extensions
    module Identity
      module Helpers
        module Browser
          include Legion::Logging::Helper

          def browser_gui_available?(**)
            return true if /darwin|mswin|mingw/.match?(browser_host_os)

            !ENV['DISPLAY'].nil? || !ENV['WAYLAND_DISPLAY'].nil?
          end

          def browser_open(url:, **)
            command = case browser_host_os
                      when /darwin/ then 'open'
                      when /linux/ then 'xdg-open'
                      when /mswin|mingw/ then 'start'
                      end
            unless command
              log.warn('No browser command is available for this operating system')
              return false
            end

            opened = system(command, url) == true
            log.warn('Browser launch failed') unless opened
            opened
          end

          private

          def browser_host_os
            RbConfig::CONFIG['host_os']
          end
        end
      end
    end
  end
end
