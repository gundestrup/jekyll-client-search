# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "net/http"
require "uri"
require_relative "support/mock_embedding_adapter"

# LLM injection test — verifies that the baseline JSON (without embeddings)
# can be enriched with LLM embeddings and produce a valid semantic search
# index.
#
# The baseline JSON (spec/fixtures/baseline/search-index-baseline.json) is a
# committed fixture containing the 80-post index WITHOUT embeddings. This
# test:
#
#   1. Loads the baseline JSON
#   2. Verifies it has no embeddings (clean baseline)
#   3. Verifies all required fields are present
#   4. Simulates LLM injection: adds embedding vectors to each document
#   5. Verifies the enriched index is valid for semantic search
#   6. Verifies that the enriched index matches the structure the generator
#      would produce with embeddings enabled
#
# When OLLAMA_INTEGRATION=1 is set, the test additionally:
#   7. Builds the real index with Ollama embeddings
#   8. Compares the real enriched index structure against the injected one
#   9. Verifies the real embeddings are valid 768-dim float vectors

BASELINE_PATH = File.expand_path("fixtures/baseline/search-index-baseline.json", __dir__).freeze
SEMANTIC_GOLD_PATH = File.expand_path("fixtures/baseline/semantic-embeddings.json", __dir__).freeze

RSpec.describe "LLM injection into baseline JSON", :system do
  let(:baseline_documents) { JSON.parse(File.read(BASELINE_PATH)) }
  let(:semantic_gold) { JSON.parse(File.read(SEMANTIC_GOLD_PATH)) }
  let(:mock_embedding) { Array.new(768) { |i| (i * 0.001).to_f } }

  it "has a committed baseline JSON without embeddings" do
    expect(File.exist?(BASELINE_PATH)).to be(true)
    docs = baseline_documents
    expect(docs.length).to eq(80), "baseline should have 80 documents"
    expect(docs.select { |d| d["embedding"] }).to be_empty,
                                                  "baseline should NOT have embeddings — it's the clean reference"
  end

  it "baseline documents have all required search fields" do
    required_fields = %w[id title url excerpt content categories tags]
    baseline_documents.each do |doc|
      required_fields.each do |field|
        expect(doc).to have_key(field),
                       "document #{doc['id']} missing required field '#{field}'"
      end
    end
  end

  it "has a committed semantic gold fixture for every baseline document" do
    expect(File.exist?(SEMANTIC_GOLD_PATH)).to be(true)
    expect(semantic_gold["model"]).to eq("embeddinggemma:300m")
    expect(semantic_gold["document_prefix"]).to eq("title: none | text: ")
    expect(semantic_gold["query_prefix"]).to eq("task: search result | query: ")
    expect(semantic_gold["schema"]).to eq(2)
    expect(semantic_gold.fetch("document_embeddings").keys.sort)
      .to eq(baseline_documents.map { |entry| entry.fetch("id") }.sort)
    expect(semantic_gold.fetch("document_embeddings").values).to all(
      satisfy { |embedding| embedding.length == 768 && embedding.all?(Float) }
    )
    expect(semantic_gold.fetch("query_embeddings")).not_to be_empty
  end

  it "can inject embeddings into the baseline JSON producing a valid semantic index" do
    docs = baseline_documents.map do |doc|
      doc.merge("embedding" => mock_embedding)
    end

    # Every document should now have an embedding
    expect(docs.select { |d| d["embedding"] }.length).to eq(80)

    # The embedding should be a valid float vector
    docs.each do |doc|
      expect(doc["embedding"].length).to eq(768)
      expect(doc["embedding"]).to all(be_a(Float))
    end

    # The enriched index should be serializable
    json = JSON.generate(docs)
    expect(JSON.parse(json).length).to eq(80)

    # The enriched index should still have all original fields
    enriched = JSON.parse(json)
    required_fields = %w[id title url excerpt content categories tags embedding]
    enriched.each do |doc|
      required_fields.each do |field|
        expect(doc).to have_key(field)
      end
    end
  end

  it "injected index structure matches generator output structure" do
    # Build a real index with mock embeddings
    Dir.mktmpdir("injection-test") do |source|
      # Create a minimal site
      FileUtils.mkdir_p(File.join(source, "_posts"))
      File.write(File.join(source, "_posts", "2026-01-01-test.md"), <<~MD)
        ---
        title: "Test Post"
        ---
        Content about testing.
      MD

      config_data = {
        "plugins" => ["jekyll-client-search"],
        "client_search" => {
          "engine" => "semantic",
          "embedding" => {
            "enabled" => true,
            "model" => "test",
            "base_url" => "http://localhost:1",
            "query_embedder" => { "type" => "none" }
          }
        }
      }
      require "yaml"
      File.write(File.join(source, "_config.yml"), YAML.dump(config_data))

      mock = MockEmbeddingAdapter.new
      allow(Jekyll::ClientSearch::Generator).to receive(:new).and_wrap_original do |method, *args|
        instance = method.call(*args)
        allow(instance).to receive(:build_embedding_adapter).and_return(mock)
        instance
      end

      dest = Dir.mktmpdir("injection-dest")
      begin
        jekyll_config = Jekyll.configuration(
          "source" => source, "destination" => dest, "quiet" => true
        )
        Jekyll::Site.new(jekyll_config).process

        generated = JSON.parse(File.read(File.join(dest, "search-index.json")))
        injected = baseline_documents.first.merge("embedding" => mock_embedding)

        # The generator output should have the same field structure as
        # our injected document
        generated_fields = generated.first.keys.sort
        injected_fields = injected.keys.sort

        expect(generated_fields).to include("embedding"),
                                    "generator output should have embedding field when LLM enabled"
        expect(injected_fields).to include("embedding"),
                                   "injected document should have embedding field"

        # Both should have the same base fields
        base_fields = %w[id title url excerpt content categories tags]
        base_fields.each do |field|
          expect(generated.first).to have_key(field)
          expect(injected).to have_key(field)
        end
      ensure
        FileUtils.rm_rf(dest)
      end
    end
  end

  # When Ollama is available, verify real embeddings match the injection pattern
  context "with real Ollama embeddings", :ollama_integration do
    before(:all) do
      skip "Set OLLAMA_INTEGRATION=1 to run Ollama integration tests" unless ENV["OLLAMA_INTEGRATION"]

      fixture_site = File.expand_path("fixtures/site", __dir__)
      arxiv_present = Dir.glob(File.join(fixture_site, "_posts", "*-arxiv-*.md")).any?
      skip "arXiv fixture posts not found — run download_arxiv.rb (see README.developer.md)" unless arxiv_present

      uri = URI("http://localhost:11434/api/tags")
      response = Net::HTTP.get_response(uri)
      models = JSON.parse(response.body).fetch("models", []).map { |m| m["name"] }
      skip "Model embeddinggemma:300m not installed" unless models.include?("embeddinggemma:300m")
    rescue Errno::ECONNREFUSED, SocketError
      skip "Ollama server not reachable"
    end

    it "real enriched index has same structure as injected baseline" do
      fixture_site = File.expand_path("fixtures/site", __dir__)
      cache_file = File.join(fixture_site, ".jekyll-client-search-cache.json")

      Dir.mktmpdir("ollama-injection") do |dest|
        config = Jekyll.configuration(
          "source" => fixture_site, "destination" => dest,
          "client_search" => {
            "engine" => "semantic",
            "embedding" => { "enabled" => true, "model" => "embeddinggemma:300m",
                             "base_url" => "http://localhost:11434" }
          },
          "quiet" => true
        )
        Jekyll::Site.new(config).process

        real_docs = JSON.parse(File.read(File.join(dest, "search-index.json")))
        baseline_docs = baseline_documents

        # Same number of documents
        expect(real_docs.length).to eq(baseline_docs.length)

        # Same IDs (same articles indexed)
        real_ids = real_docs.map { |d| d["id"] }.sort
        baseline_ids = baseline_docs.map { |d| d["id"] }.sort
        expect(real_ids).to eq(baseline_ids)

        # Real docs have embeddings, baseline doesn't
        expect(real_docs.select { |d| d["embedding"] }.length).to eq(80)
        expect(baseline_docs.select { |d| d["embedding"] }).to be_empty

        # Real embeddings are valid 768-dim float vectors
        real_docs.each do |doc|
          expect(doc["embedding"].length).to eq(768)
          expect(doc["embedding"]).to all(be_a(Float))
        end

        # Same base fields in both
        base_fields = %w[id title url excerpt content categories tags]
        base_fields.each do |field|
          expect(real_docs.first).to have_key(field)
          expect(baseline_docs.first).to have_key(field)
        end

        FileUtils.rm_f(cache_file)
      end
    end
  end
end
