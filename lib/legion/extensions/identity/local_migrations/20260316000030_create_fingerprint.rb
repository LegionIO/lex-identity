# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:identity_fingerprint) do
      primary_key :id
      String :dimension, null: false, unique: true
      Float :mean, default: 0.0
      Float :variance, default: 0.0
      Integer :observations, default: 0
      DateTime :last_observed
    end

    create_table(:identity_meta) do
      primary_key :id
      Integer :observation_count, default: 0
      String :entropy_history, text: true
    end
  end
end
