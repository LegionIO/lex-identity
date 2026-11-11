# frozen_string_literal: true

require_relative 'lib/legion/extensions/identity/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-identity'
  spec.version       = Legion::Extensions::Identity::VERSION
  spec.authors       = ['LegionIO']

  spec.summary       = 'Shared LegionIO identity extension base'
  spec.description   = 'Base extension gem for shared behavior across LegionIO identity provider extensions.'
  spec.homepage      = 'https://github.com/LegionIO/lex-identity'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata['homepage_uri']         = spec.homepage
  spec.metadata['source_code_uri']      = spec.homepage
  spec.metadata['documentation_uri']    = "#{spec.homepage}/blob/main/README.md"
  spec.metadata['changelog_uri']        = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri']      = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir.glob('{lib,spec/support}/**/*.rb') + %w[lex-identity.gemspec Gemfile LICENSE README.md CHANGELOG.md]
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday',         '~> 2.0'
  spec.add_dependency 'legion-cache',    '>= 1.3.0'
  spec.add_dependency 'legion-json',     '>= 1.2.1'
  spec.add_dependency 'legion-logging',  '>= 1.5.3'
  spec.add_dependency 'legion-settings', '>= 1.3.14'
end
