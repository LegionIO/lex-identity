# frozen_string_literal: true

require 'legion/extensions/identity/version'
require 'legion/extensions/identity/helpers/dimensions'
require 'legion/extensions/identity/helpers/fingerprint'
require 'legion/extensions/identity/runners/identity'

module Legion
  module Extensions
    module Identity
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core
    end
  end
end
