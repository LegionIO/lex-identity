# frozen_string_literal: true

require 'legion/extensions/identity/version'
require 'legion/extensions/identity/helpers/dimensions'
require 'legion/extensions/identity/helpers/fingerprint'
require 'legion/extensions/identity/helpers/vault_secrets'
require 'legion/extensions/identity/runners/identity'
require 'legion/extensions/identity/runners/entra'
require 'legion/extensions/identity/actors/orphan_check'

module Legion
  module Extensions
    module Identity
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core
    end
  end
end

if defined?(Legion::Data::Local)
  Legion::Data::Local.register_migrations(
    name: :identity,
    path: File.join(__dir__, 'identity', 'local_migrations')
  )
end
