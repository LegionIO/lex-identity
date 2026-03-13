# frozen_string_literal: true

require_relative 'lib/legion/extensions/identity/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-identity'
  spec.version       = Legion::Extensions::Identity::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']

  spec.summary       = 'LEX Identity'
  spec.description   = 'Human partner identity modeling and behavioral entropy for brain-modeled agentic AI'
  spec.homepage      = 'https://github.com/LegionIO/lex-identity'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/LegionIO/lex-identity'
  spec.metadata['documentation_uri'] = 'https://github.com/LegionIO/lex-identity'
  spec.metadata['changelog_uri'] = 'https://github.com/LegionIO/lex-identity'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/LegionIO/lex-identity/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir.glob('{lib,spec}/**/*') + %w[lex-identity.gemspec Gemfile]
  end
  spec.require_paths = ['lib']
end
