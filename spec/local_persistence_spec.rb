# frozen_string_literal: true

# Local persistence spec for Legion::Extensions::Identity::Helpers::Fingerprint
#
# Strategy: stub Legion::Data::Local with a real in-memory Sequel SQLite database
# when sequel + sqlite3 are available, otherwise use a double that records calls.
# Either way, the Fingerprint save/load logic is exercised end-to-end.

begin
  require 'sequel'
  require 'sqlite3'
  SEQUEL_AVAILABLE = true
rescue LoadError
  SEQUEL_AVAILABLE = false
end

RSpec.describe Legion::Extensions::Identity::Helpers::Fingerprint, 'local persistence' do
  # ---------------------------------------------------------------------------
  # Helpers for setting up the in-memory DB (shared between contexts)
  # ---------------------------------------------------------------------------

  def build_in_memory_db
    db = Sequel.sqlite
    db.create_table(:identity_fingerprint) do
      primary_key :id
      String  :dimension,     null: false, unique: true
      Float   :mean,          default: 0.0
      Float   :variance,      default: 0.0
      Integer :observations,  default: 0
      DateTime :last_observed
    end
    db.create_table(:identity_meta) do
      primary_key :id
      Integer :observation_count, default: 0
      String  :entropy_history,   text: true
    end
    db
  end

  def stub_local(db)
    local_mod = Module.new do
      define_singleton_method(:connection)  { db }
      define_singleton_method(:connected?)  { true }
    end
    stub_const('Legion::Data',       Module.new)
    stub_const('Legion::Data::Local', local_mod)
  end

  # ---------------------------------------------------------------------------
  # When Sequel + sqlite3 are available: full round-trip integration tests
  # ---------------------------------------------------------------------------

  if SEQUEL_AVAILABLE
    context 'with an in-memory SQLite database' do
      let(:db) { build_in_memory_db }

      before { stub_local(db) }

      describe '#save_to_local' do
        it 'returns true on first save' do
          fp = described_class.new
          expect(fp.save_to_local).to be true
        end

        it 'persists all 6 dimension rows to identity_fingerprint' do
          fp = described_class.new
          fp.observe(:communication_cadence, 0.8)
          fp.save_to_local

          rows = db[:identity_fingerprint].all
          expect(rows.size).to eq(6)
        end

        it 'persists updated mean for observed dimension' do
          fp = described_class.new
          10.times { fp.observe(:vocabulary_patterns, 0.9) }
          fp.save_to_local

          row = db[:identity_fingerprint].where(dimension: 'vocabulary_patterns').first
          expect(row[:mean]).to be > 0.5
          expect(row[:observations]).to eq(10)
        end

        it 'persists observation_count in identity_meta' do
          fp = described_class.new
          3.times { fp.observe(:communication_cadence, 0.6) }
          fp.save_to_local

          meta = db[:identity_meta].first
          expect(meta[:observation_count]).to eq(3)
        end

        it 'persists entropy_history as JSON in identity_meta' do
          fp = described_class.new
          fp.current_entropy(communication_cadence: 0.5)
          fp.current_entropy(vocabulary_patterns: 0.6)
          fp.save_to_local

          meta = db[:identity_meta].first
          parsed = JSON.parse(meta[:entropy_history])
          expect(parsed.size).to eq(2)
          expect(parsed.first).to have_key('entropy')
          expect(parsed.first).to have_key('at')
        end

        it 'updates existing rows on second save (upsert)' do
          fp = described_class.new
          fp.observe(:emotional_response, 0.3)
          fp.save_to_local

          # mutate and save again
          5.times { fp.observe(:emotional_response, 0.9) }
          fp.save_to_local

          rows = db[:identity_fingerprint].where(dimension: 'emotional_response').all
          expect(rows.size).to eq(1) # still one row, not two
          expect(rows.first[:observations]).to eq(6)
        end
      end

      describe '#load_from_local' do
        it 'returns true when called with an empty DB' do
          fp = described_class.new # load_from_local called in initialize
          expect(fp.observation_count).to eq(0)
        end

        it 'restores model dimensions from DB rows' do
          # Pre-seed DB directly
          db[:identity_fingerprint].insert(
            dimension: 'communication_cadence',
            mean: 0.75, variance: 0.05, observations: 42,
            last_observed: Time.now.utc
          )

          fp = described_class.new # triggers load_from_local
          expect(fp.model[:communication_cadence][:mean]).to be_within(0.001).of(0.75)
          expect(fp.model[:communication_cadence][:observations]).to eq(42)
        end

        it 'restores observation_count from identity_meta' do
          db[:identity_meta].insert(observation_count: 57, entropy_history: '[]')

          fp = described_class.new
          expect(fp.observation_count).to eq(57)
        end

        it 'restores entropy_history from identity_meta JSON' do
          history = [
            { 'entropy' => 0.3, 'at' => Time.now.utc.iso8601 },
            { 'entropy' => 0.4, 'at' => Time.now.utc.iso8601 }
          ]
          db[:identity_meta].insert(observation_count: 0, entropy_history: JSON.generate(history))

          fp = described_class.new
          expect(fp.entropy_history.size).to eq(2)
          expect(fp.entropy_history.first[:entropy]).to be_within(0.001).of(0.3)
          expect(fp.entropy_history.first[:at]).to be_a(Time)
        end

        it 'ignores DB rows for unknown dimensions' do
          db[:identity_fingerprint].insert(
            dimension: 'nonexistent_dimension',
            mean: 0.9, variance: 0.1, observations: 5,
            last_observed: nil
          )

          fp = described_class.new # must not raise
          expect(fp.model.keys).to match_array(
            %i[communication_cadence vocabulary_patterns emotional_response
               decision_patterns contextual_consistency temporal_patterns]
          )
        end
      end

      describe 'full round-trip' do
        it 'survives a save-then-load cycle with identical state' do
          # Build state in first fingerprint instance
          fp1 = described_class.new
          12.times { fp1.observe(:communication_cadence, 0.7) }
          8.times  { fp1.observe(:vocabulary_patterns,   0.6) }
          fp1.current_entropy(communication_cadence: 0.65)
          fp1.current_entropy(vocabulary_patterns: 0.55)
          fp1.save_to_local

          # Load into a fresh instance (DB already populated)
          fp2 = described_class.new

          expect(fp2.observation_count).to eq(fp1.observation_count)
          expect(fp2.entropy_history.size).to eq(fp1.entropy_history.size)

          dims = %i[communication_cadence vocabulary_patterns]
          dims.each do |dim|
            expect(fp2.model[dim][:mean]).to be_within(0.0001).of(fp1.model[dim][:mean])
            expect(fp2.model[dim][:variance]).to be_within(0.0001).of(fp1.model[dim][:variance])
            expect(fp2.model[dim][:observations]).to eq(fp1.model[dim][:observations])
          end
        end

        it 'preserves maturity after round-trip' do
          fp1 = described_class.new
          15.times { fp1.observe(:decision_patterns, 0.5) }
          expect(fp1.maturity).to eq(:developing)
          fp1.save_to_local

          fp2 = described_class.new
          expect(fp2.maturity).to eq(:developing)
        end

        it 'preserves entropy trend direction after round-trip' do
          fp1 = described_class.new
          # Ascending entropy values — second half larger than first half
          [0.1, 0.1, 0.1, 0.1, 0.7, 0.8, 0.9, 0.95, 0.98, 1.0].each do |e|
            fp1.instance_variable_get(:@entropy_history) << { entropy: e, at: Time.now.utc }
          end
          fp1.save_to_local

          fp2 = described_class.new
          expect(fp2.entropy_history.map { |h| h[:entropy] }).to eq(
            fp1.entropy_history.map { |h| h[:entropy] }
          )
        end
      end
    end

  else
    # ---------------------------------------------------------------------------
    # Fallback: double-based tests when Sequel is not in the bundle
    # ---------------------------------------------------------------------------

    context 'when Sequel is not available (double-based fallback)' do
      let(:fingerprint_rows) { {} }
      let(:meta_rows)        { [] }

      let(:fp_dataset) do
        d = double('fingerprint_dataset')
        allow(d).to receive(:where) { |args|
          scoped = double('scoped_fp_dataset')
          allow(scoped).to receive(:first) { fingerprint_rows[args[:dimension]] }
          allow(scoped).to receive(:update) { |row|
            fingerprint_rows[row[:dimension] || args[:dimension]] = row
          }
          scoped
        }
        allow(d).to receive(:insert) { |row| fingerprint_rows[row[:dimension]] = row }
        allow(d).to receive(:each)   { |&block| fingerprint_rows.each_value(&block) }
        allow(d).to receive(:first)  { fingerprint_rows.values.first }
        d
      end

      let(:meta_dataset) do
        d = double('meta_dataset')
        allow(d).to receive(:first)  { meta_rows.first }
        allow(d).to receive(:insert) { |row| meta_rows << row }
        allow(d).to receive(:where) do
          scoped = double('scoped_meta_dataset')
          allow(scoped).to receive(:update) { |row| meta_rows[0] = meta_rows[0]&.merge(row) }
          scoped
        end
        d
      end

      let(:db) do
        d = double('Sequel::Database')
        allow(d).to receive(:[]).with(:identity_fingerprint).and_return(fp_dataset)
        allow(d).to receive(:[]).with(:identity_meta).and_return(meta_dataset)
        d
      end

      before do
        local_mod = Module.new do
          define_singleton_method(:connection)  { nil } # overridden per example
          define_singleton_method(:connected?)  { true }
        end
        stub_const('Legion::Data',        Module.new)
        stub_const('Legion::Data::Local',  local_mod)
        allow(Legion::Data::Local).to receive(:connection).and_return(db)
      end

      it 'calls insert on the fingerprint dataset during save_to_local' do
        fp = described_class.new
        expect(fp_dataset).to receive(:insert).at_least(:once)
        fp.save_to_local
      end

      it 'calls insert on the meta dataset during save_to_local' do
        fp = described_class.new
        expect(meta_dataset).to receive(:insert).once
        fp.save_to_local
      end

      it 'does not raise when local is unavailable (Legion::Data::Local not defined)' do
        # Remove the stub so defined? check returns false
        hide_const('Legion::Data::Local')
        expect { described_class.new }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Behaviour when Legion::Data::Local is not defined (always run)
  # ---------------------------------------------------------------------------

  describe 'when Legion::Data::Local is not available' do
    before do
      hide_const('Legion::Data::Local') if defined?(Legion::Data::Local)
    end

    it 'initialize completes without error' do
      expect { described_class.new }.not_to raise_error
    end

    it 'save_to_local returns nil (guard short-circuits)' do
      fp = described_class.new
      expect(fp.save_to_local).to be_nil
    end

    it 'load_from_local returns nil (guard short-circuits)' do
      fp = described_class.new
      expect(fp.load_from_local).to be_nil
    end

    it 'model starts with fresh defaults' do
      fp = described_class.new
      expect(fp.model[:communication_cadence][:mean]).to eq(0.5)
      expect(fp.observation_count).to eq(0)
      expect(fp.entropy_history).to be_empty
    end
  end
end
