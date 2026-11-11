# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'legion/json'
require_relative 'support/provider_contract'

RSpec.describe 'identity provider contract' do
  describe 'auth providers' do
    let(:identity_provider) do
      Class.new do
        def self.provider_name = :fixture_auth
        def self.provider_type = :auth
        def self.priority = 50
        def self.trust_weight = 20
        def self.trust_level = :verified
        def self.capabilities = %i[authenticate interactive]

        def self.resolve
          { canonical_name: 'example-user', kind: :human, source: :fixture_auth }
        end
      end
    end

    include_examples 'identity provider contract'
  end

  describe 'profile providers' do
    let(:identity_provider) do
      Class.new do
        def self.provider_name = :fixture_profile
        def self.provider_type = :profile
        def self.priority = 3
        def self.trust_weight = 70
        def self.trust_level = :configured
        def self.capabilities = %i[profile groups]

        def self.resolve(canonical_name:)
          { groups: ["group-#{canonical_name}"], profile: { display_name: 'Example User' }, source: :fixture_profile }
        end
      end
    end

    include_examples 'identity provider contract'
  end

  describe 'fallback providers' do
    let(:identity_provider) do
      Class.new do
        def self.provider_name = :fixture_fallback
        def self.provider_type = :fallback
        def self.priority = -5
        def self.trust_weight = 200
        def self.trust_level = :unverified
        def self.capabilities = [:profile]

        def self.resolve
          { canonical_name: 'fallback-user', kind: :human, source: :fixture_fallback }
        end
      end
    end

    include_examples 'identity provider contract'
  end

  it 'rejects a no-keyword resolve_all through the reusable examples' do
    contract = File.expand_path('support/provider_contract.rb', __dir__)
    fixture = <<~RUBY
      require 'rspec/autorun'
      require #{contract.inspect}

      RSpec.describe 'incompatible profile provider' do
        let(:identity_provider) do
          Class.new do
            def self.provider_name = :fixture_profile
            def self.provider_type = :profile
            def self.priority = 0
            def self.trust_weight = 80
            def self.trust_level = :authenticated
            def self.capabilities = [:profile]
            def self.resolve_all = { profile: {} }
          end
        end

        include_examples 'identity provider contract'
      end
    RUBY
    output, errors, status = Open3.capture3(
      Gem.ruby, '-e', fixture, '--', '--options', File::NULL, '--format', 'json'
    )
    result = Legion::JSON.load(output)

    expect(status.exitstatus).to eq(1), errors
    expect(result[:summary][:failure_count]).to eq(1)
    failure = result[:examples].find { |example| example[:status] == 'failed' }
    expect(failure[:description]).to eq('uses the core resolution call contract')
    expect(failure.dig(:exception, :class)).to eq('ArgumentError')
  end
end
