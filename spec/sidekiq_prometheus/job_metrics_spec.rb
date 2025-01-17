# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqPrometheus::JobMetrics do
  class FakeWork
    def prometheus_labels
      { foo: 'bar' }
    end
  end

  let(:middleware) { described_class.new }
  let(:registry) { instance_double Prometheus::Client::Registry }
  let(:metric) { double 'Metric', increment: true, observe: true }
  let(:worker) { FakeWork.new }
  let(:queue) { 'bbq' }
  let(:labels) { { class: worker.class.to_s, queue: queue, foo: 'bar' } }

  after do
    SidekiqPrometheus.registry = SidekiqPrometheus.client.registry
  end

  describe '#call' do
    it 'records the expected metrics' do
      SidekiqPrometheus.registry = registry
      allow(registry).to receive(:get).and_return(metric)

      expect { |b| middleware.call(worker, nil, queue, &b) }.to yield_control

      expect(registry).to have_received(:get).with(:sidekiq_job_count)
      expect(registry).to have_received(:get).with(:sidekiq_job_duration)
      expect(registry).to have_received(:get).with(:sidekiq_job_success)
      expect(registry).to have_received(:get).with(:sidekiq_job_allocated_objects)

      expect(metric).to have_received(:increment).twice.with(labels)
      expect(metric).to have_received(:observe).twice.with(labels, kind_of(Numeric))
    end

    it 'returns the result from the yielded block' do
      SidekiqPrometheus.registry = registry
      allow(registry).to receive(:get).and_return(metric)
      expected = 'Zoot Boot'

      result = middleware.call(worker, nil, queue) { expected }

      expect(result).to eq(expected)
    end

    it 'increments the sidekiq_job_failed metric on error and raises' do
      SidekiqPrometheus.registry = registry
      allow(registry).to receive(:get).and_return(metric)

      expect { middleware.call(worker, nil, queue) { raise 'no way!' } }.to raise_error(StandardError)

      expect(registry).to have_received(:get).with(:sidekiq_job_count)
      expect(registry).to have_received(:get).with(:sidekiq_job_failed)
      expect(registry).not_to have_received(:get).with(:sidekiq_job_duration)
      expect(registry).not_to have_received(:get).with(:sidekiq_job_success)

      expect(metric).to have_received(:increment).twice.with(labels)
      expect(metric).not_to have_received(:observe)
    end
  end
end
