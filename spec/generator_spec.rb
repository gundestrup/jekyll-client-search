# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::Generator, :unit do
  # The baseline post used by most examples: one searchable post tagged and
  # categorised like a real article.
  def default_post_files
    post_files(
      filename: "2026-01-01-example.md",
      title: "Example article",
      frontmatter: { "categories" => ["family"], "tags" => ["example"] },
      content: "Searchable content appears here."
    )
  end

  # Routes every generator instance's embedding adapter to the given stub so
  # examples never reach a real Ollama server. The generator runs inside
  # `jekyll_build`'s site.process, so the stub must be installed beforehand.
  # Returns a probe whose `instance` is the generator Jekyll created.
  def stub_embedding_adapter(adapter)
    probe = Struct.new(:instance).new
    allow(Jekyll::ClientSearch::Generator).to receive(:new).and_wrap_original do |method, *args|
      probe.instance = method.call(*args)
      allow(probe.instance).to receive(:build_embedding_adapter).and_return(adapter)
      probe.instance
    end
    probe
  end

  it "generates a JSON index and registers the packaged runtime asset" do
    jekyll_build(files: default_post_files) do |site, _output_files|
      expect(generated_documents(site)).to include(
        hash_including(
          "title" => "Example article",
          "content" => include("Searchable content appears here."),
          "categories" => ["family"],
          "tags" => ["example"],
          "source" => "posts"
        )
      )
      expect(runtime_asset_paths(site))
        .to contain_exactly("assets/client-search-shared.js",
                            "assets/client-search-base.js", "assets/adapters/minisearch.js",
                            "assets/client-search-dropdown.js")
    end
  end

  it "indexes configured custom collections without duplicates" do
    files = default_post_files.merge(
      "_docs" => { "guide.md" => post_source({ "title" => "Guide" }, "Guide") }
    )

    jekyll_build(
      config: {
        "collections" => { "docs" => { "output" => false } },
        "client_search" => { "collections" => %w[posts docs posts] }
      },
      files: files
    ) do |site, _output_files|
      expect(generated_documents(site).map { |document| document["title"] })
        .to contain_exactly("Example article", "Guide")
    end
  end

  it "includes titled pages when configured" do
    files = { "about.md" => post_source({ "title" => "About" }, "About this site") }

    jekyll_build(config: { "client_search" => { "include_pages" => true } }, files: files) do |site, _output_files|
      expect(generated_documents(site)).to include(
        hash_including("title" => "About", "content" => "About this site", "source" => "pages")
      )
    end
  end

  it "forwards configured passthrough fields from document front matter" do
    files = post_files(
      filename: "2026-01-01-report.md",
      title: "Report",
      frontmatter: { "file_type" => "pdf", "icon_url" => "/icons/pdf.svg", "icon_set" => "color" },
      content: "Content here."
    )

    jekyll_build(
      config: { "client_search" => { "passthrough_fields" => %w[file_type icon_url icon_set] } },
      files: files
    ) do |site, _output_files|
      expect(generated_documents(site).first).to include(
        "source" => "posts",
        "file_type" => "pdf",
        "icon_url" => "/icons/pdf.svg",
        "icon_set" => "color"
      )
    end
  end

  it "renames passthrough fields when hash entries are used" do
    files = post_files(
      filename: "2026-01-01-report.md",
      title: "Report",
      frontmatter: { "file_type" => "pdf", "icon_url" => "/icons/pdf.svg" },
      content: "Content here."
    )

    jekyll_build(
      config: {
        "client_search" => {
          "passthrough_fields" => [{ "file_type" => "doctype" }, { "icon_url" => "thumbnail" }]
        }
      },
      files: files
    ) do |site, _output_files|
      doc = generated_documents(site).first
      expect(doc).to include("doctype" => "pdf", "thumbnail" => "/icons/pdf.svg")
      expect(doc).not_to have_key("file_type")
      expect(doc).not_to have_key("icon_url")
    end
  end

  it "includes iconField in runtime config when icon_field is configured and passthrough includes it" do
    jekyll_build(
      config: {
        "client_search" => {
          "passthrough_fields" => %w[icon_url],
          "icon_field" => "icon_url"
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      config_page = site.pages.find { |p| p.url == "/assets/search-runtime-config.js" }
      expect(config_page).not_to be_nil
      expect(config_page.content).to include('"iconField":"icon_url"')
    end
  end

  it "omits iconField from runtime config when icon_field is not in passthrough_fields" do
    jekyll_build(
      config: {
        "client_search" => {
          "passthrough_fields" => %w[file_type],
          "icon_field" => "icon_url"
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      config_page = site.pages.find { |p| p.url == "/assets/search-runtime-config.js" }
      expect(config_page.content).not_to include("iconField")
    end
  end

  it "does not include dropdown config when dropdown is disabled" do
    jekyll_build(
      config: { "client_search" => { "enabled" => true, "dropdown" => { "enabled" => false } } },
      files: default_post_files
    ) do |site, _output_files|
      config_page = site.pages.find { |p| p.url == "/assets/search-runtime-config.js" }
      expect(config_page).not_to be_nil
      expect(config_page.content).not_to include('"dropdown"')
    end
  end

  it "generates a separate relation JSON page from shared metadata" do
    files = post_files(
      { filename: "2026-01-01-one.md", title: "One",
        frontmatter: { "categories" => ["family"], "tags" => ["example"] },
        content: "Searchable content appears here." },
      { filename: "2026-01-02-two.md", title: "Two",
        frontmatter: { "categories" => ["family"], "tags" => ["example"] },
        content: "Related content." }
    )

    jekyll_build(
      config: { "client_search" => { "related" => { "enabled" => true } } },
      files: files
    ) do |site, _output_files|
      relation_page = site.pages.find { |page| page.url == "/search-relations.json" }
      expect(relation_page).not_to be_nil
      relations = JSON.parse(relation_page.content).fetch("relations")
      one_id = generated_documents(site).find { |document| document["title"] == "One" }.fetch("id")
      expect(relations.fetch(one_id).map { |relation| relation["title"] }).to eq(["Two"])
      expect(relations.fetch(one_id).first["reasons"]).to include("shared-category: family", "shared-tag: example")
      expect(runtime_asset_paths(site)).to include("assets/client-search-related.js")
    end
  end

  it "embeds documents with separate models for the semantic index and related analysis" do
    probe = stub_embedding_adapter(double(embed: [1.0, 0.0]))

    jekyll_build(
      config: {
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "model" => "embeddinggemma-2:570m" },
          "semantic" => { "index_model" => "embeddinggemma:300m" },
          "related" => { "enabled" => true, "index_model" => "embeddinggemma-2:570m" }
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      expect(probe.instance).to have_received(:build_embedding_adapter)
        .with(anything, model: "embeddinggemma:300m")
      expect(probe.instance).to have_received(:build_embedding_adapter)
        .with(anything, model: "embeddinggemma-2:570m")
      documents = generated_documents(site)
      expect(documents.first["embedding"]).to eq([1.0, 0.0])
      expect(documents.first).not_to have_key("related_embedding")
      expect(site.pages.map(&:url)).to include("/search-relations.json")
    end
  end

  it "reuses the index embedding for related analysis when the models match" do
    probe = stub_embedding_adapter(double(embed: [1.0, 0.0]))

    jekyll_build(
      config: {
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "model" => "embeddinggemma-2:570m" },
          "related" => { "enabled" => true }
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      expect(probe.instance).to have_received(:build_embedding_adapter).once
      documents = generated_documents(site)
      expect(documents.first["embedding"]).to eq([1.0, 0.0])
      expect(site.pages.map(&:url)).to include("/search-relations.json")
    end
  end

  it "removes temporary embeddings from a lexical index after related analysis" do
    stub_embedding_adapter(double(embed: [1.0, 0.0]))

    jekyll_build(
      config: {
        "client_search" => {
          "engine" => "minisearch",
          "embedding" => { "enabled" => true, "model" => "test-model" },
          "related" => { "enabled" => true, "minimum_similarity" => -1 }
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      documents = generated_documents(site)
      expect(documents.first).not_to have_key("embedding")
      expect(site.pages.map(&:url)).to include("/search-relations.json")
    end
  end

  it "generates runtime configuration with the index URL and live-search settings" do
    jekyll_build(
      config: {
        "baseurl" => "/blog",
        "client_search" => {
          "output" => "indexes/search.json",
          "live_search" => { "enabled" => true, "debounce_ms" => 200 }
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      page = site.pages.find { |candidate| candidate.url == "/assets/search-runtime-config.js" }
      expect(page).not_to be_nil
      expect(page.content).to include('"indexUrl":"/blog/indexes/search.json"')
      expect(page.content).to include('"enabled":true')
      expect(page.content).to include('"debounceMs":200')
    end
  end

  it "supports a nested output path and disabling the runtime asset" do
    jekyll_build(
      config: {
        "client_search" => {
          "output" => "indexes/search.json",
          "copy_runtime" => false
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      expect(site.pages.map(&:url)).to include("/indexes/search.json")
      expect(site.pages.map(&:url)).not_to include("/assets/search-runtime-config.js")
      expect(runtime_asset_paths(site)).not_to include("assets/client-search-base.js")
      expect(runtime_asset_paths(site)).not_to include("assets/adapters/minisearch.js")
    end
  end

  it "copies the base and adapter runtimes for the configured JS engine" do
    jekyll_build(
      config: { "client_search" => { "engine" => "elasticlunr" } },
      files: default_post_files
    ) do |site, _output_files|
      expect(site.pages.map(&:url)).to include("/search-index.json")
      expect(runtime_asset_paths(site))
        .to contain_exactly("assets/client-search-shared.js",
                            "assets/client-search-base.js", "assets/adapters/elasticlunr.js",
                            "assets/client-search-dropdown.js")
    end
  end

  it "copies the base and minisearch adapter runtimes by default" do
    jekyll_build(files: default_post_files) do |site, _output_files|
      expect(runtime_asset_paths(site))
        .to contain_exactly("assets/client-search-shared.js",
                            "assets/client-search-base.js", "assets/adapters/minisearch.js",
                            "assets/client-search-dropdown.js")
    end
  end

  it "does nothing when disabled" do
    jekyll_build(config: { "client_search" => false }, files: default_post_files) do |site, _output_files|
      expect(site.pages.map(&:url)).not_to include("/search-index.json", "/assets/search-runtime-config.js")
      expect(runtime_asset_paths(site)).to be_empty
    end
  end

  it "skips a configured collection label that does not exist on the site" do
    jekyll_build(
      config: { "client_search" => { "collections" => %w[posts nonexistent] } },
      files: default_post_files
    ) do |site, _output_files|
      expect(generated_documents(site).map { |doc| doc["title"] }).to contain_exactly("Example article")
    end
  end

  it "does not duplicate runtime assets when generate is called twice" do
    jekyll_build(files: default_post_files) do |site, _output_files|
      initial_count = site.static_files.size

      described_class.new.generate(site)

      expect(site.static_files.size).to eq(initial_count),
                                        "second generate call should not add duplicate runtime assets"
    end
  end

  it "generates an embedder config JS file when embeddings are enabled" do
    stub_embedding_adapter(double(embed: [0.1]))

    jekyll_build(
      config: {
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "model" => "embeddinggemma:300m" }
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      config_page = site.pages.find { |p| p.url == "/assets/search-embedder-config.js" }
      expect(config_page).not_to be_nil
      expect(config_page.content).to include("ClientSearchEmbedderConfig")
      expect(config_page.content).to include("onnx-community/embeddinggemma-300m-ONNX")
      expect(config_page.content).to include("embeddinggemma:300m")
    end
  end

  it "copies the query embedder script for semantic engine with embeddings" do
    stub_embedding_adapter(double(embed: [0.1]))

    jekyll_build(
      config: {
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "model" => "embeddinggemma:300m" }
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      expect(runtime_asset_paths(site)).to include(
        "assets/query-embedders/transformers.js",
        "assets/query-embedders/transformers-worker.js"
      )
    end
  end

  it "does not generate embedder config when query_embedder type is none" do
    stub_embedding_adapter(double(embed: [0.1]))

    jekyll_build(
      config: {
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "query_embedder" => { "type" => "none" } }
        }
      },
      files: default_post_files
    ) do |site, _output_files|
      config_page = site.pages.find { |p| p.url == "/assets/search-embedder-config.js" }
      expect(config_page).to be_nil
    end
  end
end
