# frozen_string_literal: true

require "spec_helper"
require "open3"

# These tests verify structural and security properties of the JS runtime
# files that can be checked without a browser. The actual runtime behavior
# (search, ranking, DOM rendering, URL safety) is tested in the JS test
# suite (test/runtime.test.js, test/meta.test.js).
RSpec.describe "ClientSearch browser runtime assets", :unit do
  def asset_path(relative)
    File.expand_path("../#{relative}", __dir__)
  end

  def read_asset(relative)
    File.read(asset_path(relative))
  end

  describe "JavaScript syntax validation" do
    js_files = %w[
      assets/client-search-base.js
      assets/client-search-dropdown.js
      assets/client-search-related.js
      assets/adapters/minisearch.js
      assets/adapters/elasticlunr.js
      assets/adapters/semantic.js
      assets/query-embedders/transformers.js
      assets/query-embedders/transformers-worker.js
      assets/query-embedders/ollama-api.js
    ]
    js_files.each do |rel|
      it "#{rel} has no syntax errors (node --check)" do
        _stdout, status = Open3.capture2("node", "--check", asset_path(rel))
        expect(status.success?).to be(true), "#{rel} has syntax errors"
      end
    end
  end

  describe "base runtime" do
    subject(:runtime) { read_asset("assets/client-search-base.js") }

    it "exposes the ClientSearch global with the adapter interface" do
      expect(runtime).to include("window.ClientSearch")
      expect(runtime).to include("adapter.available")
      expect(runtime).to include("adapter.buildIndex")
      expect(runtime).to include("adapter.search")
    end

    it "does not use innerHTML for result rendering (XSS prevention)" do
      expect(runtime).not_to include("innerHTML")
      expect(runtime).to include("document.createElement")
      expect(runtime).to include("textContent")
    end

    it "validates result URLs are same-origin HTTP" do
      expect(runtime).to include("url.origin === window.location.origin")
      expect(runtime).to match(/http:|https:/)
    end

    it "implements the two-stage AND-then-OR search strategy" do
      expect(runtime).to include('combineWith: "AND"')
      expect(runtime).to include('combineWith: "OR"')
      expect(runtime).to include("fuzzy: false")
      expect(runtime).to include("fuzzy: true")
    end
  end

  describe "dropdown runtime" do
    subject(:runtime) { read_asset("assets/client-search-dropdown.js") }

    it "exposes the dropdown initializer" do
      expect(runtime).to include("initAll")
      expect(runtime).to include("data-client-search-dropdown")
    end

    it "does not use innerHTML for result rendering (XSS prevention)" do
      expect(runtime).not_to include("innerHTML")
      expect(runtime).to include("document.createElement")
      expect(runtime).to include("textContent")
    end

    it "supports keyboard navigation" do
      expect(runtime).to include("ArrowDown")
      expect(runtime).to include("ArrowUp")
      expect(runtime).to include("Escape")
      expect(runtime).to include("Enter")
    end
  end

  describe "related runtime" do
    subject(:runtime) { read_asset("assets/client-search-related.js") }

    it "exposes the related renderer" do
      expect(runtime).to include("ClientSearchRelated")
    end

    it "does not use innerHTML for result rendering (XSS prevention)" do
      expect(runtime).not_to include("innerHTML")
      expect(runtime).to include("document.createElement")
      expect(runtime).to include("textContent")
    end
  end

  describe "minisearch adapter" do
    subject(:runtime) { read_asset("assets/adapters/minisearch.js") }

    it "registers as window.ClientSearchAdapters.minisearch" do
      expect(runtime).to include("window.ClientSearchAdapters.minisearch")
    end

    it "returns results in { ref, score } format" do
      expect(runtime).to include("ref:")
      expect(runtime).to include("score:")
    end
  end

  describe "elasticlunr adapter" do
    subject(:runtime) { read_asset("assets/adapters/elasticlunr.js") }

    it "registers as window.ClientSearchAdapters.elasticlunr" do
      expect(runtime).to include("window.ClientSearchAdapters.elasticlunr")
    end
  end

  describe "semantic adapter" do
    subject(:runtime) { read_asset("assets/adapters/semantic.js") }

    it "registers as window.ClientSearchAdapters.semantic" do
      expect(runtime).to include("window.ClientSearchAdapters.semantic")
    end

    it "implements cosine similarity with a similarity threshold" do
      expect(runtime).to include("cosineSimilarity")
      expect(runtime).to include("SIMILARITY_THRESHOLD")
    end
  end
end
