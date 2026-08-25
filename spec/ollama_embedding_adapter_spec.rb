# frozen_string_literal: true

require "spec_helper"
require "ollama"

RSpec.describe Jekyll::ClientSearch::OllamaEmbeddingAdapter, :unit do
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

  it "passes configured timeouts to the Ollama client" do
    adapter = described_class.new(
      model: "test-model", base_url: "http://ollama", connect_timeout: 2, read_timeout: 30
    )
    client_class = class_double(Ollama::Client).as_stubbed_const
    allow(client_class).to receive(:new).and_return(instance_double(Ollama::Client))

    adapter.send(:client)

    expect(client_class).to have_received(:new).with(
      base_url: "http://ollama", connect_timeout: 2, read_timeout: 30
    )
  end

  it "rejects an empty or invalid embedding response" do
    response = Ollama::Response.new("embeddings" => [[]])
    client = instance_double(Ollama::Client, embed: response)
    allow(adapter).to receive(:client).and_return(client)
    allow(Jekyll.logger).to receive(:warn)

    expect(adapter.embed("test text")).to be_nil
    expect(Jekyll.logger).to have_received(:warn).with("ClientSearch:", /empty or invalid/)
  end

  it "returns nil when the response has no embeddings field" do
    response = Ollama::Response.new("embeddings" => nil)
    client = instance_double(Ollama::Client, embed: response)
    allow(adapter).to receive(:client).and_return(client)
    allow(Jekyll.logger).to receive(:warn)

    expect(adapter.embed("test text")).to be_nil
    expect(Jekyll.logger).to have_received(:warn).with("ClientSearch:", /empty or invalid/)
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
