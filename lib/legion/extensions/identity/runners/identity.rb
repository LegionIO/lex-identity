# frozen_string_literal: true

module Legion
  module Extensions
    module Identity
      module Runners
        module Identity
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)

          def observe_behavior(dimension:, value:, **)
            fingerprint = identity_fingerprint
            fingerprint.observe(dimension, value)

            Legion::Logging.debug "[identity] observe: dim=#{dimension} val=#{value.round(2)} " \
                                  "obs=#{fingerprint.observation_count} maturity=#{fingerprint.maturity}"
            {
              dimension:         dimension,
              recorded:          true,
              observation_count: fingerprint.observation_count,
              maturity:          fingerprint.maturity
            }
          end

          def observe_all(observations:, **)
            fingerprint = identity_fingerprint
            fingerprint.observe_all(observations)

            Legion::Logging.debug "[identity] observe_all: dims=#{observations.keys.join(',')} " \
                                  "obs=#{fingerprint.observation_count} maturity=#{fingerprint.maturity}"
            {
              dimensions_observed: observations.keys,
              observation_count:   fingerprint.observation_count,
              maturity:            fingerprint.maturity
            }
          end

          def check_entropy(observations: {}, **)
            fingerprint = identity_fingerprint
            entropy = fingerprint.current_entropy(observations)
            classification = Helpers::Dimensions.classify_entropy(entropy)
            trend = fingerprint.entropy_trend

            result = {
              entropy:        entropy,
              classification: classification,
              trend:          trend,
              in_range:       Helpers::Dimensions::OPTIMAL_ENTROPY_RANGE.cover?(entropy)
            }

            case classification
            when :high_entropy
              result[:warning] = :possible_impersonation_or_drift
              result[:action] = :enter_caution_mode
              Legion::Logging.warn "[identity] high entropy detected: #{entropy.round(3)} trend=#{trend} - possible impersonation"
            when :low_entropy
              result[:warning] = :possible_automation
              result[:action] = :trigger_verification
              Legion::Logging.warn "[identity] low entropy detected: #{entropy.round(3)} trend=#{trend} - possible automation"
            else
              Legion::Logging.debug "[identity] entropy check: #{entropy.round(3)} classification=#{classification} trend=#{trend}"
            end

            result
          end

          def identity_status(**)
            fingerprint = identity_fingerprint
            Legion::Logging.debug "[identity] status: maturity=#{fingerprint.maturity} observations=#{fingerprint.observation_count}"
            fingerprint.to_h
          end

          def identity_maturity(**)
            { maturity: identity_fingerprint.maturity }
          end

          private

          def identity_fingerprint
            @identity_fingerprint ||= Helpers::Fingerprint.new
          end
        end
      end
    end
  end
end
