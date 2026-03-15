# frozen_string_literal: true

# Stub the framework actor base class since legionio gem is not available in test
module Legion
  module Extensions
    module Actors
      class Every # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

# Intercept the require in the actor file so it doesn't fail
$LOADED_FEATURES << 'legion/extensions/actors/every'

require 'legion/extensions/identity/actors/orphan_check'

RSpec.describe Legion::Extensions::Identity::Actor::OrphanCheck do
  subject(:actor) { described_class.new }

  describe 'ORPHAN_CHECK_INTERVAL' do
    it 'is 14400 seconds (4 hours)' do
      expect(described_class::ORPHAN_CHECK_INTERVAL).to eq(14_400)
    end
  end

  describe '#runner_class' do
    it 'returns the Entra module' do
      expect(actor.runner_class).to eq(Legion::Extensions::Identity::Runners::Entra)
    end
  end

  describe '#runner_function' do
    it 'returns check_orphans' do
      expect(actor.runner_function).to eq('check_orphans')
    end
  end

  describe '#time' do
    it 'returns 14400 seconds using the constant' do
      expect(actor.time).to eq(Legion::Extensions::Identity::Actor::OrphanCheck::ORPHAN_CHECK_INTERVAL)
    end

    it 'returns 14400' do
      expect(actor.time).to eq(14_400)
    end
  end

  describe '#use_runner?' do
    it 'returns false' do
      expect(actor.use_runner?).to be false
    end
  end

  describe '#check_subtask?' do
    it 'returns false' do
      expect(actor.check_subtask?).to be false
    end
  end

  describe '#generate_task?' do
    it 'returns false' do
      expect(actor.generate_task?).to be false
    end
  end

  describe '#enabled?' do
    context 'when Legion::Data is not defined' do
      it 'returns false' do
        hide_const('Legion::Data') if defined?(Legion::Data)
        expect(actor.enabled?).to be_falsey
      end
    end

    context 'when Legion::Data is defined and data is connected' do
      it 'returns truthy' do
        stub_const('Legion::Data', Module.new)
        stub_const('Legion::Settings', Class.new)
        settings_double = { connected: true }
        allow(Legion::Settings).to receive(:[]).with(:data).and_return(settings_double)
        expect(actor.enabled?).to be_truthy
      end
    end

    context 'when Legion::Data is defined but connected is false' do
      it 'returns false' do
        stub_const('Legion::Data', Module.new)
        stub_const('Legion::Settings', Class.new)
        settings_double = { connected: false }
        allow(Legion::Settings).to receive(:[]).with(:data).and_return(settings_double)
        expect(actor.enabled?).to be false
      end
    end

    context 'when Legion::Settings raises an error' do
      it 'returns false' do
        stub_const('Legion::Data', Module.new)
        stub_const('Legion::Settings', Class.new)
        allow(Legion::Settings).to receive(:[]).with(:data).and_raise(StandardError)
        expect(actor.enabled?).to be false
      end
    end
  end
end
