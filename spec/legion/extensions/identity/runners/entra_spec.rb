# frozen_string_literal: true

require 'legion/extensions/identity/runners/entra'

# Minimal stubs for Legion::Logging so the runner can call it without the full framework
unless defined?(Legion::Logging)
  module Legion
    module Logging
      module_function

      def debug(*); end
      def info(*);  end
      def warn(*);  end
    end
  end
end

RSpec.describe Legion::Extensions::Identity::Runners::Entra do
  # Thin host class that includes the runner module so we can call runner methods directly
  let(:host_class) do
    Class.new do
      include Legion::Extensions::Identity::Runners::Entra
    end
  end

  let(:client) { host_class.new }

  # A reusable worker record hash returned by the model double
  let(:worker_record) do
    {
      worker_id:       'worker-abc',
      entra_app_id:    'app-id-123',
      entra_object_id: 'obj-id-456',
      owner_msid:      'alice@example.com',
      lifecycle_state: 'active'
    }
  end

  # Helper: build a model double that responds to .first and .where(...).all
  def build_model_double(worker_hash: worker_record, active_all: [])
    worker_double = instance_double('DigitalWorker')
    allow(worker_double).to receive(:to_hash).and_return(worker_hash)
    allow(worker_double).to receive(:update)

    scope_double = double('Scope')
    allow(scope_double).to receive(:all).and_return(active_all)

    model_double = double('DigitalWorker model')
    allow(model_double).to receive(:first).and_return(worker_double)
    allow(model_double).to receive(:where).and_return(scope_double)

    model_double
  end

  # Helper: stub Legion::Data and the DigitalWorker model constant so `defined?` guards pass
  def stub_data_model(model_double)
    stub_const('Legion::Data', Module.new)
    stub_const('Legion::Data::Model', Module.new)
    stub_const('Legion::Data::Model::DigitalWorker', model_double)
  end

  # ---------------------------------------------------------------------------
  # validate_worker_identity
  # ---------------------------------------------------------------------------

  describe '#validate_worker_identity' do
    context 'when the worker exists with an entra_app_id' do
      it 'returns valid: true with identity fields' do
        stub_data_model(build_model_double)

        result = client.validate_worker_identity(worker_id: 'worker-abc')

        expect(result[:valid]).to be true
        expect(result[:worker_id]).to eq('worker-abc')
        expect(result[:entra_app_id]).to eq('app-id-123')
        expect(result[:owner_msid]).to eq('alice@example.com')
        expect(result[:lifecycle]).to eq('active')
        expect(result[:validated_at]).to be_a(Time)
      end

      it 'uses the caller-supplied entra_app_id when provided' do
        stub_data_model(build_model_double)

        result = client.validate_worker_identity(worker_id: 'worker-abc', entra_app_id: 'override-app-id')

        expect(result[:valid]).to be true
        expect(result[:entra_app_id]).to eq('override-app-id')
      end
    end

    context 'when the worker does not exist' do
      it 'returns valid: false with an error message' do
        model_double = double('DigitalWorker model')
        allow(model_double).to receive(:first).and_return(nil)
        stub_data_model(model_double)

        result = client.validate_worker_identity(worker_id: 'no-such-worker')

        expect(result[:valid]).to be false
        expect(result[:error]).to eq('worker not found')
      end
    end

    context 'when Legion::Data is not available' do
      it 'returns valid: false because find_worker returns nil' do
        result = client.validate_worker_identity(worker_id: 'worker-abc')

        expect(result[:valid]).to be false
        expect(result[:error]).to eq('worker not found')
      end
    end

    context 'when the worker record has no entra_app_id' do
      it 'returns valid: false with no entra_app_id error' do
        worker_without_app = worker_record.merge(entra_app_id: nil)
        stub_data_model(build_model_double(worker_hash: worker_without_app))

        result = client.validate_worker_identity(worker_id: 'worker-abc')

        expect(result[:valid]).to be false
        expect(result[:error]).to eq('no entra_app_id')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # sync_owner
  # ---------------------------------------------------------------------------

  describe '#sync_owner' do
    context 'when the worker exists' do
      it 'returns synced: true with current owner info from local record' do
        stub_data_model(build_model_double)

        result = client.sync_owner(worker_id: 'worker-abc')

        expect(result[:synced]).to be true
        expect(result[:worker_id]).to eq('worker-abc')
        expect(result[:owner_msid]).to eq('alice@example.com')
        expect(result[:source]).to eq(:local)
        expect(result[:synced_at]).to be_a(Time)
      end
    end

    context 'when the worker does not exist' do
      it 'returns synced: false with error' do
        model_double = double('DigitalWorker model')
        allow(model_double).to receive(:first).and_return(nil)
        stub_data_model(model_double)

        result = client.sync_owner(worker_id: 'no-such-worker')

        expect(result[:synced]).to be false
        expect(result[:error]).to eq('worker not found')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # transfer_ownership
  # ---------------------------------------------------------------------------

  describe '#transfer_ownership' do
    context 'when the worker exists and the new owner differs' do
      it 'returns transferred: true with full audit fields' do
        model_double = build_model_double
        stub_data_model(model_double)

        result = client.transfer_ownership(
          worker_id:      'worker-abc',
          new_owner_msid: 'bob@example.com',
          transferred_by: 'admin@example.com',
          reason:         'role change'
        )

        expect(result[:transferred]).to be true
        expect(result[:event]).to eq(:ownership_transferred)
        expect(result[:from_owner]).to eq('alice@example.com')
        expect(result[:to_owner]).to eq('bob@example.com')
        expect(result[:transferred_by]).to eq('admin@example.com')
        expect(result[:reason]).to eq('role change')
        expect(result[:at]).to be_a(Time)
      end

      it 'emits a Legion::Events event when Legion::Events is available' do
        model_double = build_model_double
        stub_data_model(model_double)
        events_double = double('Legion::Events')
        stub_const('Legion::Events', events_double)
        expect(events_double).to receive(:emit).with('worker.ownership_transferred', hash_including(event: :ownership_transferred))

        client.transfer_ownership(
          worker_id:      'worker-abc',
          new_owner_msid: 'bob@example.com',
          transferred_by: 'admin@example.com'
        )
      end

      it 'updates the database record when Legion::Data is available' do
        worker_double = instance_double('DigitalWorker')
        allow(worker_double).to receive(:to_hash).and_return(worker_record)
        expect(worker_double).to receive(:update).with(hash_including(owner_msid: 'bob@example.com'))

        model_double = double('DigitalWorker model')
        allow(model_double).to receive(:first).and_return(worker_double)
        stub_data_model(model_double)

        client.transfer_ownership(
          worker_id:      'worker-abc',
          new_owner_msid: 'bob@example.com',
          transferred_by: 'admin@example.com'
        )
      end
    end

    context 'when new_owner_msid is the same as the current owner' do
      it 'returns transferred: false with same owner error' do
        stub_data_model(build_model_double)

        result = client.transfer_ownership(
          worker_id:      'worker-abc',
          new_owner_msid: 'alice@example.com',
          transferred_by: 'admin@example.com'
        )

        expect(result[:transferred]).to be false
        expect(result[:error]).to eq('same owner')
      end
    end

    context 'when the worker does not exist' do
      it 'returns transferred: false with worker not found error' do
        model_double = double('DigitalWorker model')
        allow(model_double).to receive(:first).and_return(nil)
        stub_data_model(model_double)

        result = client.transfer_ownership(
          worker_id:      'no-such-worker',
          new_owner_msid: 'bob@example.com',
          transferred_by: 'admin@example.com'
        )

        expect(result[:transferred]).to be false
        expect(result[:error]).to eq('worker not found')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # check_orphans
  # ---------------------------------------------------------------------------

  describe '#check_orphans' do
    context 'when Legion::Data is not available' do
      it 'returns empty orphans with source: :unavailable' do
        result = client.check_orphans

        expect(result[:orphans]).to eq([])
        expect(result[:checked]).to eq(0)
        expect(result[:source]).to eq(:unavailable)
      end
    end

    context 'when there are no active workers' do
      it 'returns empty orphans list with checked count of 0' do
        stub_data_model(build_model_double(active_all: []))

        result = client.check_orphans

        expect(result[:orphans]).to eq([])
        expect(result[:checked]).to eq(0)
        expect(result[:source]).to eq(:local)
        expect(result[:checked_at]).to be_a(Time)
      end
    end

    context 'when there are active workers' do
      it 'returns the count of workers scanned and an empty orphans list (pending Entra validation)' do
        active_worker = double('DigitalWorker', worker_id: 'worker-abc', owner_msid: 'alice@example.com',
                                                entra_app_id: 'entra-app-abc')
        stub_data_model(build_model_double(active_all: [active_worker]))

        result = client.check_orphans

        expect(result[:checked]).to eq(1)
        expect(result[:orphans]).to eq([])
        expect(result[:source]).to eq(:local)
      end
    end
  end
end
