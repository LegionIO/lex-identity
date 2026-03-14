# frozen_string_literal: true

require 'bundler/setup'

# Stub framework classes not available outside the full Legion runtime
module Legion
  module Logging
    def self.debug(_msg); end

    def self.info(_msg); end

    def self.warn(_msg); end

    def self.error(_msg); end
  end

  module Extensions
    module Actors
      class Every; end # rubocop:disable Lint/EmptyClass
    end
  end
end

# Prevent re-require of actor base when identity.rb loads orphan_check
$LOADED_FEATURES << 'legion/extensions/actors/every'

require 'legion/extensions/identity'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
