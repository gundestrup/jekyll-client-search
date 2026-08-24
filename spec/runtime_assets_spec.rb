# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ClientSearch browser runtime assets" do
  def read_asset(relative)
    File.read(File.expand_path("../#{relative}", __dir__))
  end

  # These tests verify structural properties of the JS runtime files
  # that can be checked without a browser. The actual runtime behavior
  # (search, ranking, DOM rendering, URL safety) is tested in the JS
  # test suite (test/runtime.test.js, test/meta.test.js).

  describe "base runtime" do
    subject(:runtime) { read_asset("assets/client-search-base.js") }

    it "is valid JavaScript with no syntax errors" do
      # Use node --check to verify syntax
      require "open3"
      stdout, status = Open3.capture2("node", "--check", File.expand_path("../assets/client-search-base.js", __dir__))
      expect(status.success?).to be(true), "client-search-base.js has syntax errors: #{stdout}"
    end

    it "exposes the ClientSearch global with the adapter interface" do
      # Verify the file assigns to window.ClientSearch and calls adapter methods
      expect(runtime).to include("window.ClientSearch")
      expect(runtime).to include("adapter.available")
      expect(runtime).to include("adapter.buildIndex")
      expect(runtime).to include("adapter.search")
    end

    it "does not use innerHTML for result rendering" do
      # Security: innerHTML is XSS-prone, the runtime must use DOM APIs
      expect(runtime).not_to include("innerHTML")
      expect(runtime).to include("document.createElement")
      expect(runtime).to include("textContent")
    end

    it "validates result URLs are same-origin HTTP" do
      # Security: result URLs must be validated to prevent javascript: or
      # cross-origin links from being injected into the DOM
      expect(runtime).to include("url.origin === window.location.origin")
      expect(runtime).to match(/http:|https:/)
    end

    it "implements the two-stage AND-then-OR search strategy" do
      # The base runtime owns the strategy: try AND first, fall back to OR
      expect(runtime).to include('combineWith: "AND"')
      expect(runtime).to include('combineWith: "OR"')
      expect(runtime).to include("fuzzy: false")
      expect(runtime).to include("fuzzy: true")
    end
  end

  describe "minisearch adapter" do
    subject(:runtime) { read_asset("assets/adapters/minisearch.js") }

    it "is valid JavaScript with no syntax errors" do
      require "open3"
      _stdout, status = Open3.capture2("node", "--check",
                                       File.expand_path("../assets/adapters/minisearch.js", __dir__))
      expect(status.success?).to be(true), "minisearch.js has syntax errors"
    end

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

    it "is valid JavaScript with no syntax errors" do
      require "open3"
      _stdout, status = Open3.capture2("node", "--check",
                                       File.expand_path("../assets/adapters/elasticlunr.js", __dir__))
      expect(status.success?).to be(true), "elasticlunr.js has syntax errors"
    end

    it "registers as window.ClientSearchAdapters.elasticlunr" do
      expect(runtime).to include("window.ClientSearchAdapters.elasticlunr")
    end

    it "documents that ElasticLunr returns { ref, score } natively" do
      # ElasticLunr returns { ref, score } natively, so the adapter
      # doesn't need to transform results — it passes them through.
      expect(runtime).to include("{ ref, score }")
    end
  end

  describe "semantic adapter" do
    subject(:runtime) { read_asset("assets/adapters/semantic.js") }

    it "is valid JavaScript with no syntax errors" do
      require "open3"
      _stdout, status = Open3.capture2("node", "--check",
                                       File.expand_path("../assets/adapters/semantic.js", __dir__))
      expect(status.success?).to be(true), "semantic.js has syntax errors"
    end

    it "registers as window.ClientSearchAdapters.semantic" do
      expect(runtime).to include("window.ClientSearchAdapters.semantic")
    end

    it "implements cosine similarity with a similarity threshold" do
      expect(runtime).to include("cosineSimilarity")
      expect(runtime).to include("SIMILARITY_THRESHOLD")
    end

    it "filters documents to only those with embeddings" do
      expect(runtime).to include("embedding")
    end
  end
end
