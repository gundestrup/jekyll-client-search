# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::OllamaEmbeddingAdapter do
  let(:adapter) { described_class.new(model: "embeddinggemma:300m", base_url: "http://localhost:11434") }

  it "is constructed with a model and base URL" do
    expect(adapter.model).to eq("embeddinggemma:300m")
    expect(adapter.base_url).to eq("http://localhost:11434")
  end

  it "uses the default base URL when none is provided" do
    adapter = described_class.new(model: "test-model")
    expect(adapter.model).to eq("test-model")
    expect(adapter.base_url).to eq("http://localhost:11434")
  end

  it "raises a clear error when ollama-ruby is not installed" do
    adapter = described_class.new(model: "test", base_url: "http://localhost:1")
    allow(adapter).to receive(:client).and_raise(LoadError, "cannot load such file -- ollama")

    expect { adapter.embed("test text") }
      .to raise_error(Jekyll::Errors::FatalException, /ollama-ruby/)
  end

  it "returns nil and logs a warning when the server is unreachable" do
    adapter = described_class.new(model: "test", base_url: "http://localhost:1")
    allow(adapter).to receive(:client).and_raise(Errno::ECONNREFUSED, "Connection refused")
    allow(Jekyll.logger).to receive(:warn)

    result = adapter.embed("test text")

    expect(result).to be_nil
    expect(Jekyll.logger).to have_received(:warn).with("ClientSearch:", anything)
  end
end
