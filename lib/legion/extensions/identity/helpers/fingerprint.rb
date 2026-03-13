# frozen_string_literal: true

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

            diff = second_half.sum / second_half.size - first_half.sum / first_half.size
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
              model:             @model,
              observation_count: @observation_count,
              maturity:          maturity,
              entropy_history_size: @entropy_history.size
            }
          end
        end
      end
    end
  end
end
