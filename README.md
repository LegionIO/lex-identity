# lex-identity

Human partner identity modeling for brain-modeled agentic AI. Builds a behavioral fingerprint from observed interactions across six dimensions and detects entropy anomalies that may indicate impersonation or automation.

## Overview

`lex-identity` maintains a model of the agent's human partner by observing behavioral patterns over time. As the model matures from repeated observations, it can detect when behavioral patterns diverge significantly from the established baseline — surfacing potential impersonation or automation attacks.

## Identity Dimensions

| Dimension | Captures |
|-----------|---------|
| `communication_cadence` | Timing patterns, response delays |
| `vocabulary_patterns` | Word choice, phrasing style |
| `emotional_response` | Affective tone and patterns |
| `decision_patterns` | How choices are made |
| `contextual_consistency` | Consistency across contexts |
| `temporal_patterns` | Time-of-day and day-of-week rhythms |

## Model Maturity

| Level | Observation Count |
|-------|------------------|
| `:nascent` | < 10 |
| `:developing` | 10–99 |
| `:established` | 100–999 |
| `:mature` | >= 1000 |

## Installation

Add to your Gemfile:

```ruby
gem 'lex-identity'
```

## Usage

### Observing Behavior

```ruby
require 'legion/extensions/identity'

# Observe a single dimension
Legion::Extensions::Identity::Runners::Identity.observe_behavior(
  dimension: :communication_cadence,
  value: 0.7
)
# => { dimension: :communication_cadence, recorded: true,
#      observation_count: 1, maturity: :nascent }

# Observe multiple dimensions at once
Legion::Extensions::Identity::Runners::Identity.observe_all(
  observations: {
    communication_cadence: 0.7,
    vocabulary_patterns:   0.6,
    emotional_response:    0.5
  }
)
```

### Entropy Checking

```ruby
# Check how much the current observation diverges from established baseline
result = Legion::Extensions::Identity::Runners::Identity.check_entropy(
  observations: {
    communication_cadence: 0.95,  # significantly above normal
    vocabulary_patterns:   0.8
  }
)

result[:entropy]        # => 0.0..1.0
result[:classification] # => :normal | :high_entropy | :low_entropy
result[:trend]          # => :stable | :rising | :falling
result[:in_range]       # => true/false (optimal: 0.20..0.70)

# High entropy warning
# result[:warning] => :possible_impersonation_or_drift
# result[:action]  => :enter_caution_mode

# Low entropy warning
# result[:warning] => :possible_automation
# result[:action]  => :trigger_verification
```

### Status

```ruby
Legion::Extensions::Identity::Runners::Identity.identity_status
Legion::Extensions::Identity::Runners::Identity.identity_maturity
```

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT
