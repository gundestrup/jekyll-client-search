# frozen_string_literal: true

require "spec_helper"

RSpec.describe "gem specification" do
  subject(:specification) do
    Gem::Specification.load(File.expand_path("../jekyll-client-search.gemspec", __dir__))
  end

  it "uses the AGPL-3.0-or-later license" do
    expect(specification.license).to eq("AGPL-3.0-or-later")
  end

  it "requires the supported Ruby baseline" do
    expect(specification.required_ruby_version).to be_satisfied_by(Gem::Version.new("3.4.10"))
    expect(specification.required_ruby_version).not_to be_satisfied_by(Gem::Version.new("3.4.9"))
  end

  it "packages the generator, base runtime, adapters, cache, and embedding adapter" do
    expect(specification.files).to include(
      "lib/jekyll/client_search/generator.rb",
      "lib/jekyll/client_search/index_cache.rb",
      "lib/jekyll/client_search/ollama_embedding_adapter.rb",
      "assets/client-search-base.js",
      "assets/adapters/minisearch.js",
      "assets/adapters/elasticlunr.js",
      "assets/adapters/semantic.js",
      "LICENSE"
    )
  end
end
