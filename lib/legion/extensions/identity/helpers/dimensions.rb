# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Helpers
        module Dimensions
          # The 6 behavioral dimensions that constitute identity
          IDENTITY_DIMENSIONS = %i[
            communication_cadence
            vocabulary_patterns
            emotional_response
            decision_patterns
            contextual_consistency
            temporal_patterns
          ].freeze

          # Entropy thresholds (from tick-loop-spec Phase 4)
          HIGH_ENTROPY_THRESHOLD = 0.70
          LOW_ENTROPY_THRESHOLD  = 0.20
          OPTIMAL_ENTROPY_RANGE  = (0.20..0.70)

          # EMA alpha for dimension updates
          OBSERVATION_ALPHA = 0.1

          module_function

          def new_identity_model
            IDENTITY_DIMENSIONS.to_h do |dim|
              [dim, { mean: 0.5, variance: 0.1, observations: 0, last_observed: nil }]
            end
          end

          def compute_entropy(observations, model)
            return 0.5 if observations.empty?

            divergences = IDENTITY_DIMENSIONS.filter_map do |dim|
              obs = observations[dim]
              next unless obs

              baseline = model[dim]
              next 0.0 unless baseline && baseline[:observations].positive?

              # Weighted divergence from established baseline
              (obs - baseline[:mean]).abs / [baseline[:variance].to_f, 0.1].max
            end

            return 0.5 if divergences.empty?

            raw = divergences.sum / divergences.size
            clamp(raw / 3.0) # normalize: divergence of 3.0 stddevs = entropy 1.0
          end

          def classify_entropy(entropy)
            if entropy > HIGH_ENTROPY_THRESHOLD
              :high_entropy
            elsif entropy < LOW_ENTROPY_THRESHOLD
              :low_entropy
            else
              :normal
            end
          end

          def clamp(value, min = 0.0, max = 1.0)
            [[value, min].max, max].min
          end
        end
      end
    end
  end
end
