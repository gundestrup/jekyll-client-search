# frozen_string_literal: true

require "spec_helper"

RSpec.describe "gem specification", :unit do
  subject(:specification) do
    Gem::Specification.load(File.expand_path("../jekyll-client-search.gemspec", __dir__))
  end

  it "uses the AGPL-3.0-or-later license" do
    expect(specification.license).to eq("AGPL-3.0-or-later")
  end

  it "requires the supported Ruby baseline" do
    expect(specification.required_ruby_version).to be_satisfied_by(Gem::Version.new("3.2.0"))
    expect(specification.required_ruby_version).not_to be_satisfied_by(Gem::Version.new("3.1.9"))
  end

  it "packages the generator, base runtime, adapters, cache, and embedding adapter" do
    expect(specification.files).to include(
      "lib/jekyll/client_search/generator.rb",
      "lib/jekyll/client_search/index_cache.rb",
      "lib/jekyll/client_search/ollama_embedding_adapter.rb",
      "lib/jekyll/client_search/embedder_config_page.rb",
      "lib/jekyll/client_search/runtime_config_page.rb",
      "lib/jekyll/client_search/live_search_configuration.rb",
      "lib/jekyll/client_search/related_configuration.rb",
      "lib/jekyll/client_search/related_analyzer.rb",
      "lib/jekyll/client_search/related_page.rb",
      "lib/jekyll/client_search/query_embedder_configuration.rb",
      "assets/client-search-base.js",
      "assets/adapters/minisearch.js",
      "assets/adapters/elasticlunr.js",
      "assets/adapters/semantic.js",
      "LICENSE"
    )
  end

  it "packages the project icon" do
    expect(specification.files).to include("docs/assets/icon.svg", "docs/assets/icon-256.png")
  end

  it "packages the query embedder scripts" do
    expect(specification.files).to include(
      "assets/query-embedders/transformers.js",
      "assets/query-embedders/transformers-worker.js",
      "assets/query-embedders/ollama-api.js",
      "assets/client-search-related.js"
    )
  end

  it "does not package test fixtures or benchmark data" do
    expect(specification.files).not_to include(
      "spec/fixtures/baseline/search-index-baseline.json",
      "spec/fixtures/baseline/semantic-embeddings.json",
      "benchmarks/results.json"
    )
  end
end
