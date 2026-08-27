# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Jekyll::ClientSearch::Generator, :unit do
  def build_site(source, config = {})
    jekyll_config = Jekyll.configuration(
      { "source" => source, "destination" => File.join(source, "_site"), "quiet" => true }.merge(config)
    )
    site = Jekyll::Site.new(jekyll_config)
    site.read
    site
  end

  def write_post(source, name: "example", title: "Example article")
    FileUtils.mkdir_p(File.join(source, "_posts"))
    File.write(
      File.join(source, "_posts", "2026-01-01-#{name}.md"),
      <<~MARKDOWN
        ---
        title: #{title}
        categories:
          - family
        tags:
          - example
        ---
        Searchable content appears here.
      MARKDOWN
    )
  end

  def generated_documents(site, output = "/search-index.json")
    page = site.pages.find { |candidate| candidate.url == output }
    JSON.parse(page.content)
  end

  it "generates a JSON index and registers the packaged runtime asset" do
    Dir.mktmpdir("client-search-site") do |source|
      write_post(source)
      site = build_site(source)

      described_class.new.generate(site)

      expect(generated_documents(site)).to include(
        hash_including(
          "title" => "Example article",
          "content" => include("Searchable content appears here."),
          "categories" => ["family"],
          "tags" => ["example"],
          "source" => "posts"
        )
      )
      runtime_files = site.static_files.select do |file|
        file.relative_path.to_s.delete_prefix("/").start_with?("assets/")
      end
      expect(runtime_files.map { |file| file.relative_path.to_s.delete_prefix("/") })
        .to contain_exactly("assets/client-search-base.js", "assets/adapters/minisearch.js")
    end
  end

  it "indexes configured custom collections without duplicates" do
    Dir.mktmpdir("client-search-collections") do |source|
      write_post(source, name: "post", title: "Post")
      FileUtils.mkdir_p(File.join(source, "_docs"))
      File.write(File.join(source, "_docs", "guide.md"), "---\ntitle: Guide\n---\nGuide")
      site = build_site(
        source,
        "collections" => { "docs" => { "output" => false } },
        "client_search" => { "collections" => %w[posts docs posts] }
      )

      described_class.new.generate(site)

      expect(generated_documents(site).map { |document| document["title"] })
        .to contain_exactly("Post", "Guide")
    end
  end

  it "includes titled pages when configured" do
    Dir.mktmpdir("client-search-pages") do |source|
      File.write(File.join(source, "about.md"), "---\ntitle: About\n---\nAbout this site")
      site = build_site(source, "client_search" => { "include_pages" => true })

      described_class.new.generate(site)

      expect(generated_documents(site)).to include(
        hash_including("title" => "About", "content" => "About this site", "source" => "pages")
      )
    end
  end

  it "forwards configured passthrough fields from document front matter" do
    Dir.mktmpdir("client-search-passthrough") do |source|
      FileUtils.mkdir_p(File.join(source, "_posts"))
      File.write(File.join(source, "_posts", "2026-01-01-report.md"), <<~MARKDOWN)
        ---
        title: Report
        file_type: pdf
        icon_url: "/icons/pdf.svg"
        icon_set: color
        ---
        Content here.
      MARKDOWN
      site = build_site(source, "client_search" => {
                          "passthrough_fields" => %w[file_type icon_url icon_set]
                        })

      described_class.new.generate(site)

      expect(generated_documents(site).first).to include(
        "source" => "posts",
        "file_type" => "pdf",
        "icon_url" => "/icons/pdf.svg",
        "icon_set" => "color"
      )
    end
  end

  it "renames passthrough fields when hash entries are used" do
    Dir.mktmpdir("client-search-rename") do |source|
      FileUtils.mkdir_p(File.join(source, "_posts"))
      File.write(File.join(source, "_posts", "2026-01-01-report.md"), <<~MARKDOWN)
        ---
        title: Report
        file_type: pdf
        icon_url: "/icons/pdf.svg"
        ---
        Content here.
      MARKDOWN
      site = build_site(source, "client_search" => {
                          "passthrough_fields" => [{ "file_type" => "doctype" },
                                                   { "icon_url" => "thumbnail" }]
                        })

      described_class.new.generate(site)

      doc = generated_documents(site).first
      expect(doc).to include("doctype" => "pdf", "thumbnail" => "/icons/pdf.svg")
      expect(doc).not_to have_key("file_type")
      expect(doc).not_to have_key("icon_url")
    end
  end

  it "includes iconField in runtime config when icon_field is configured and passthrough includes it" do
    Dir.mktmpdir("client-search-icon-field") do |source|
      write_post(source)
      site = build_site(source, "client_search" => {
                          "passthrough_fields" => %w[icon_url],
                          "icon_field" => "icon_url"
                        })

      described_class.new.generate(site)

      config_page = site.pages.find { |p| p.url == "/assets/search-runtime-config.js" }
      expect(config_page).not_to be_nil
      expect(config_page.content).to include('"iconField":"icon_url"')
    end
  end

  it "omits iconField from runtime config when icon_field is not in passthrough_fields" do
    Dir.mktmpdir("client-search-no-icon") do |source|
      write_post(source)
      site = build_site(source, "client_search" => {
                          "passthrough_fields" => %w[file_type],
                          "icon_field" => "icon_url"
                        })

      described_class.new.generate(site)

      config_page = site.pages.find { |p| p.url == "/assets/search-runtime-config.js" }
      expect(config_page.content).not_to include("iconField")
    end
  end

  it "generates a separate relation JSON page from shared metadata" do
    Dir.mktmpdir("client-search-related") do |source|
      write_post(source, name: "one", title: "One")
      FileUtils.mkdir_p(File.join(source, "_posts"))
      File.write(File.join(source, "_posts", "2026-01-02-two.md"), <<~MARKDOWN)
        ---
        title: Two
        categories:
          - family
        tags:
          - example
        ---
        Related content.
      MARKDOWN
      site = build_site(source, "client_search" => { "related" => { "enabled" => true } })

      described_class.new.generate(site)

      relation_page = site.pages.find { |page| page.url == "/search-relations.json" }
      expect(relation_page).not_to be_nil
      relations = JSON.parse(relation_page.content).fetch("relations")
      one_id = generated_documents(site).find { |document| document["title"] == "One" }.fetch("id")
      expect(relations.fetch(one_id).map { |relation| relation["title"] }).to eq(["Two"])
      expect(relations.fetch(one_id).first["reasons"]).to include("shared-category: family", "shared-tag: example")
      expect(site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") })
        .to include("assets/client-search-related.js")
    end
  end

  it "removes temporary embeddings from a lexical index after related analysis" do
    Dir.mktmpdir("client-search-related-embeddings") do |source|
      write_post(source)
      site = build_site(
        source,
        "client_search" => {
          "engine" => "minisearch",
          "embedding" => { "enabled" => true, "model" => "test-model" },
          "related" => { "enabled" => true, "minimum_similarity" => -1 }
        }
      )
      generator = described_class.new
      allow(generator).to receive(:build_embedding_adapter).and_return(double(embed: [1.0, 0.0]))

      generator.generate(site)

      documents = generated_documents(site)
      expect(documents.first).not_to have_key("embedding")
      expect(site.pages.map(&:url)).to include("/search-relations.json")
    end
  end

  it "generates runtime configuration with the index URL and live-search settings" do
    Dir.mktmpdir("client-search-runtime-config") do |source|
      write_post(source)
      site = build_site(
        source,
        "baseurl" => "/blog",
        "client_search" => {
          "output" => "indexes/search.json",
          "live_search" => { "enabled" => true, "debounce_ms" => 200 }
        }
      )

      described_class.new.generate(site)

      page = site.pages.find { |candidate| candidate.url == "/assets/search-runtime-config.js" }
      expect(page).not_to be_nil
      expect(page.content).to include('"indexUrl":"/blog/indexes/search.json"')
      expect(page.content).to include('"enabled":true')
      expect(page.content).to include('"debounceMs":200')
    end
  end

  it "supports a nested output path and disabling the runtime asset" do
    Dir.mktmpdir("client-search-output") do |source|
      write_post(source)
      site = build_site(
        source,
        "client_search" => {
          "output" => "indexes/search.json",
          "copy_runtime" => false
        }
      )

      described_class.new.generate(site)

      expect(site.pages.map(&:url)).to include("/indexes/search.json")
      expect(site.pages.map(&:url)).not_to include("/assets/search-runtime-config.js")
      paths = site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") }
      expect(paths).not_to include("assets/client-search-base.js")
      expect(paths).not_to include("assets/adapters/minisearch.js")
    end
  end

  it "copies the base and adapter runtimes for the configured JS engine" do
    Dir.mktmpdir("client-search-elasticlunr") do |source|
      write_post(source)
      site = build_site(source, "client_search" => { "engine" => "elasticlunr" })

      described_class.new.generate(site)

      expect(site.pages.map(&:url)).to include("/search-index.json")
      expect(site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") })
        .to contain_exactly("assets/client-search-base.js", "assets/adapters/elasticlunr.js")
    end
  end

  it "copies the base and minisearch adapter runtimes by default" do
    Dir.mktmpdir("client-search-minisearch") do |source|
      write_post(source)
      site = build_site(source)

      described_class.new.generate(site)

      expect(site.static_files.map { |file| file.relative_path.to_s.delete_prefix("/") })
        .to contain_exactly("assets/client-search-base.js", "assets/adapters/minisearch.js")
    end
  end

  it "does nothing when disabled" do
    Dir.mktmpdir("client-search-disabled") do |source|
      write_post(source)
      site = build_site(source, "client_search" => false)

      expect { described_class.new.generate(site) }
        .not_to(change { [site.pages.size, site.static_files.size] })
    end
  end

  it "skips a configured collection label that does not exist on the site" do
    Dir.mktmpdir("client-search-missing-collection") do |source|
      write_post(source)
      site = build_site(
        source,
        "client_search" => { "collections" => %w[posts nonexistent] }
      )

      described_class.new.generate(site)

      titles = generated_documents(site).map { |doc| doc["title"] }
      expect(titles).to contain_exactly("Example article")
    end
  end

  it "does not duplicate runtime assets when generate is called twice" do
    Dir.mktmpdir("client-search-duplicate-assets") do |source|
      write_post(source)
      site = build_site(source)

      generator = described_class.new
      generator.generate(site)
      initial_count = site.static_files.size

      generator.generate(site)

      expect(site.static_files.size).to eq(initial_count),
                                        "second generate call should not add duplicate runtime assets"
    end
  end

  it "generates an embedder config JS file when embeddings are enabled" do
    Dir.mktmpdir("client-search-embedder-config") do |source|
      write_post(source)
      site = build_site(
        source,
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "model" => "embeddinggemma:300m" }
        }
      )

      generator = described_class.new
      allow(generator).to receive(:build_embedding_adapter).and_return(double(embed: [0.1]))
      generator.generate(site)

      config_page = site.pages.find { |p| p.url == "/assets/search-embedder-config.js" }
      expect(config_page).not_to be_nil
      expect(config_page.content).to include("ClientSearchEmbedderConfig")
      expect(config_page.content).to include("onnx-community/embeddinggemma-300m-ONNX")
      expect(config_page.content).to include("embeddinggemma:300m")
    end
  end

  it "copies the query embedder script for semantic engine with embeddings" do
    Dir.mktmpdir("client-search-embedder-asset") do |source|
      write_post(source)
      site = build_site(
        source,
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true }
        }
      )

      generator = described_class.new
      allow(generator).to receive(:build_embedding_adapter).and_return(double(embed: [0.1]))
      generator.generate(site)

      paths = site.static_files.map { |f| f.relative_path.to_s.delete_prefix("/") }
      expect(paths).to include(
        "assets/query-embedders/transformers.js",
        "assets/query-embedders/transformers-worker.js"
      )
    end
  end

  it "does not generate embedder config when query_embedder type is none" do
    Dir.mktmpdir("client-search-embedder-none") do |source|
      write_post(source)
      site = build_site(
        source,
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "query_embedder" => { "type" => "none" } }
        }
      )

      generator = described_class.new
      allow(generator).to receive(:build_embedding_adapter).and_return(double(embed: [0.1]))
      generator.generate(site)

      config_page = site.pages.find { |p| p.url == "/assets/search-embedder-config.js" }
      expect(config_page).to be_nil
    end
  end
end
