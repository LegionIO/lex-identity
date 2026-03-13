# lex-identity

**Level 3 Documentation**
- **Parent**: `extensions-agentic/CLAUDE.md`
- **Grandparent**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Human partner identity modeling for the LegionIO cognitive architecture. Builds a behavioral fingerprint across six dimensions via exponential moving average, computes entropy as divergence from the established baseline, and detects anomalies (impersonation, automation).

## Gem Info

- **Gem name**: `lex-identity`
- **Version**: `0.1.0`
- **Module**: `Legion::Extensions::Identity`
- **Ruby**: `>= 3.4`
- **License**: MIT

## File Structure

```
lib/legion/extensions/identity/
  version.rb
  helpers/
    dimensions.rb   # IDENTITY_DIMENSIONS, entropy thresholds, new_identity_model, compute_entropy, classify_entropy
    fingerprint.rb  # Fingerprint class - EMA model, observation tracking, entropy history
  runners/
    identity.rb     # observe_behavior, observe_all, check_entropy, identity_status, identity_maturity
spec/
  legion/extensions/identity/
    helpers/
      dimensions_spec.rb
      fingerprint_spec.rb
    runners/
      identity_spec.rb
    client_spec.rb
```

## Key Constants (Helpers::Dimensions)

```ruby
IDENTITY_DIMENSIONS = %i[
  communication_cadence vocabulary_patterns emotional_response
  decision_patterns contextual_consistency temporal_patterns
]
HIGH_ENTROPY_THRESHOLD = 0.70
LOW_ENTROPY_THRESHOLD  = 0.20
OPTIMAL_ENTROPY_RANGE  = (0.20..0.70)
OBSERVATION_ALPHA      = 0.1   # EMA alpha for dimension updates
```

## Fingerprint Class

`Helpers::Fingerprint` holds:
- `@model` - Hash of dimension => `{ mean: 0.5, variance: 0.1, observations: 0, last_observed: nil }`
- `@observation_count` - total observations across all dimensions
- `@entropy_history` - last 200 entropy readings with timestamps

`observe(dimension, value)` applies EMA update to mean and variance (treating absolute deviation as the variance input). Only recognized dimensions are recorded.

`current_entropy(observations)` calls `Dimensions.compute_entropy` and appends to entropy history.

## Entropy Computation

`Dimensions.compute_entropy(observations, model)`:
1. For each observed dimension, computes weighted divergence: `|obs - mean| / max(variance, 0.1)`
2. Averages divergences
3. Normalizes: raw / 3.0 (3 stddevs = entropy 1.0), clamped to `[0, 1]`
4. Returns 0.5 if no observations or model has no data yet

## Entropy Trend

`Fingerprint#entropy_trend(window: 10)` computes the mean of the first half vs second half of the last N entropy readings:
- Diff > 0.1 -> `:rising`
- Diff < -0.1 -> `:falling`
- else -> `:stable`

## Integration Points

- **lex-tick**: `identity_entropy_check` phase calls `check_entropy` each tick
- **lex-coldstart**: observations during imprint window build the initial baseline
- **lex-privatecore**: high entropy triggers caution mode

## Development Notes

- `OBSERVATION_ALPHA = 0.1` makes the EMA slow to adapt — deliberate, identity should be stable
- Dimensions not in `IDENTITY_DIMENSIONS` are silently ignored in `observe`
- The `observations` parameter to `check_entropy` is the current-tick observation hash, not cumulative; the model is the cumulative baseline
- Maturity levels (`:nascent`, `:developing`, `:established`, `:mature`) are based on total `observation_count`, not per-dimension counts
