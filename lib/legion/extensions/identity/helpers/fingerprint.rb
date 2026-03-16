# frozen_string_literal: true

require 'json'
require 'time'

module Legion
  module Extensions
    module Identity
      module Helpers
        class Fingerprint
          attr_reader :model, :observation_count, :entropy_history

          def initialize
            @model = Dimensions.new_identity_model
            @observation_count = 0
            @entropy_history = []
            load_from_local
          end

          def observe(dimension, value)
            return unless Dimensions::IDENTITY_DIMENSIONS.include?(dimension)

            dim = @model[dimension]
            dim[:observations] += 1
            @observation_count += 1

            alpha = Dimensions::OBSERVATION_ALPHA
            old_mean = dim[:mean]
            dim[:mean] = (alpha * value) + ((1.0 - alpha) * old_mean)
            deviation = (value - dim[:mean]).abs
            dim[:variance] = (alpha * deviation) + ((1.0 - alpha) * dim[:variance])
            dim[:last_observed] = Time.now.utc
          end

          def observe_all(observations)
            observations.each { |dim, value| observe(dim, value) }
          end

          def current_entropy(observations = {})
            entropy = Dimensions.compute_entropy(observations, @model)
            @entropy_history << { entropy: entropy, at: Time.now.utc }
            @entropy_history.shift while @entropy_history.size > 200
            entropy
          end

          def entropy_trend(window: 10)
            recent = @entropy_history.last(window)
            return :stable if recent.size < 2

            values = recent.map { |e| e[:entropy] }
            first_half = values[0...(values.size / 2)]
            second_half = values[(values.size / 2)..]

            diff = (second_half.sum / second_half.size) - (first_half.sum / first_half.size)
            if diff > 0.1
              :rising
            elsif diff < -0.1
              :falling
            else
              :stable
            end
          end

          def maturity
            if @observation_count < 10
              :nascent
            elsif @observation_count < 100
              :developing
            elsif @observation_count < 1000
              :established
            else
              :mature
            end
          end

          def to_h
            {
              model:                @model,
              observation_count:    @observation_count,
              maturity:             maturity,
              entropy_history_size: @entropy_history.size
            }
          end

          def save_to_local
            return unless local_available?

            db = Legion::Data::Local.connection

            @model.each do |dimension, data|
              existing = db[:identity_fingerprint].where(dimension: dimension.to_s).first
              row = {
                dimension:     dimension.to_s,
                mean:          data[:mean],
                variance:      data[:variance],
                observations:  data[:observations],
                last_observed: data[:last_observed]
              }
              if existing
                db[:identity_fingerprint].where(dimension: dimension.to_s).update(row)
              else
                db[:identity_fingerprint].insert(row)
              end
            end

            history_json = ::JSON.generate(@entropy_history.map { |e| { entropy: e[:entropy], at: e[:at].iso8601 } })
            meta = db[:identity_meta].first
            if meta
              db[:identity_meta].where(id: meta[:id]).update(
                observation_count: @observation_count,
                entropy_history:   history_json
              )
            else
              db[:identity_meta].insert(
                observation_count: @observation_count,
                entropy_history:   history_json
              )
            end

            true
          rescue StandardError => e
            Legion::Logging.warn "lex-identity: save_to_local failed: #{e.message}" if defined?(Legion::Logging)
            false
          end

          def load_from_local
            return unless local_available?

            db = Legion::Data::Local.connection

            db[:identity_fingerprint].each do |row|
              dim = row[:dimension].to_sym
              next unless @model.key?(dim)

              @model[dim][:mean]          = row[:mean].to_f
              @model[dim][:variance]      = row[:variance].to_f
              @model[dim][:observations]  = row[:observations].to_i
              @model[dim][:last_observed] = row[:last_observed]
            end

            meta = db[:identity_meta].first
            if meta
              @observation_count = meta[:observation_count].to_i
              raw = meta[:entropy_history]
              if raw && !raw.empty?
                parsed = ::JSON.parse(raw)
                @entropy_history = parsed.map { |e| { entropy: e['entropy'].to_f, at: Time.parse(e['at']) } }
              end
            end

            true
          rescue StandardError => e
            Legion::Logging.warn "lex-identity: load_from_local failed: #{e.message}" if defined?(Legion::Logging)
            false
          end

          private

          def local_available?
            defined?(Legion::Data::Local) && Legion::Data::Local.connected?
          end
        end
      end
    end
  end
end
