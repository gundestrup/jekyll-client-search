# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Fixture site path shared with the JS system tests.
# The fixture site contains up to 80 real-world source posts:
#   - 40 Wikipedia articles (CC BY-SA 3.0) on arctic, climbing, photography,
#     food, and technology topics — always committed
#   - 40 unique arXiv papers on information retrieval, NLP, computer vision,
#     recommendation systems, and knowledge graphs — NOT committed due to
#     mixed/restrictive licenses; developers run download_arxiv.rb to fetch
#     them. See README.developer.md.
FIXTURE_SITE = File.expand_path("fixtures/site", __dir__).freeze
BASELINE_INDEX = File.expand_path("fixtures/baseline/search-index-baseline.json", __dir__).freeze
WIKIPEDIA_POST_COUNT = 40
ARXIV_POST_COUNT = 40
FULL_POST_COUNT = WIKIPEDIA_POST_COUNT + ARXIV_POST_COUNT

# Detect whether arXiv fixture posts have been downloaded.
ARXIV_POSTS_PRESENT = Dir.glob(File.join(FIXTURE_SITE, "_posts", "*-arxiv-*.md")).any?
EXPECTED_POST_COUNT = ARXIV_POSTS_PRESENT ? FULL_POST_COUNT : WIKIPEDIA_POST_COUNT

RSpec.describe "ClientSearch system build", :system do
  # Build the fixture site once for each JS engine and verify the generated
  # JSON index contains the expected documents. JS tests use the committed
  # baseline generated from the same fixture content.
  %w[minisearch elasticlunr].each do |engine|
    context "with engine: #{engine}" do
      it "generates a JSON index with #{EXPECTED_POST_COUNT} fixture posts and copies runtime assets" do
        Dir.mktmpdir("client-search-system-#{engine}") do |dest|
          config = Jekyll.configuration(
            "source" => FIXTURE_SITE,
            "destination" => dest,
            "client_search" => { "engine" => engine },
            "quiet" => true
          )
          site = Jekyll::Site.new(config)
          site.process

          index_json = File.join(dest, "search-index.json")
          expect(File.exist?(index_json)).to be(true)

          documents = JSON.parse(File.read(index_json))
          expect(documents.length).to eq(EXPECTED_POST_COUNT)

          # When all 80 posts are present, the generated index must exactly
          # match the committed baseline. With only Wikipedia posts (arXiv
          # not yet downloaded), skip the baseline comparison — the baseline
          # is a gold-standard artifact for the full 80-post fixture set.
          expect(documents).to eq(JSON.parse(File.read(BASELINE_INDEX))) if ARXIV_POSTS_PRESENT

          # Verify Wikipedia articles are present with source attribution
          glacier = documents.find { |doc| doc["title"] == "Glacier" }
          expect(glacier).not_to be_nil
          expect(glacier["content"]).to include("ice")

          # Verify arXiv papers are present when the fixture posts are available
          if ARXIV_POSTS_PRESENT
            arxiv_categories = %w[information-retrieval natural-language-processing
                                  computer-vision recommendation-systems knowledge-graphs]
            arxiv_docs = documents.select { |doc| arxiv_categories.include?(doc["categories"].first) }
            expect(arxiv_docs.length).to eq(ARXIV_POST_COUNT)
            expect(arxiv_docs.map { |doc| doc["title"] }.uniq.length).to eq(ARXIV_POST_COUNT)
          end

          # Verify all documents have required fields
          documents.each do |doc|
            expect(doc["id"]).not_to be_nil
            expect(doc["title"]).not_to be_nil
            expect(doc["content"]).not_to be_nil
          end

          expect(File.exist?(File.join(dest, "assets", "search-runtime-config.js"))).to be(true)
          expect(File.exist?(File.join(dest, "assets", "client-search-base.js"))).to be(true)
          expect(File.exist?(File.join(dest, "assets", "adapters", "#{engine}.js"))).to be(true)
        end
      end
    end
  end

  context "with related articles enabled" do
    it "generates search-relations.json with correct structure" do
      Dir.mktmpdir("client-search-related") do |dest|
        config = Jekyll.configuration(
          "source" => FIXTURE_SITE,
          "destination" => dest,
          "quiet" => true
        )
        site = Jekyll::Site.new(config)
        site.process

        relations_json = File.join(dest, "search-relations.json")
        expect(File.exist?(relations_json)).to be(true)

        data = JSON.parse(File.read(relations_json))
        expect(data["version"]).to eq(1)
        expect(data["minimum_similarity"]).to eq(0.55)
        expect(data["relations"]).to be_a(Hash)
        expect(data["relations"].size).to eq(EXPECTED_POST_COUNT)

        # Each article should have at least one relation (shared tags/categories)
        _sample_url, sample_relations = data["relations"].first
        expect(sample_relations).to be_an(Array)
        expect(sample_relations).not_to be_empty

        first = sample_relations.first
        expect(first).to include("id", "title", "url", "score", "reasons")
        expect(first["score"]).to be_a(Numeric)
        expect(first["reasons"]).to be_an(Array)
        expect(first["reasons"]).not_to be_empty

        # Without embeddings, relations are metadata-only (tags/categories)
        expect(first["reasons"]).to include(match(/shared-(tag|category|domain)/))
        expect(first).not_to have_key("semantic_similarity")
      end
    end

    it "copies client-search-related.js and includes relatedUrl in runtime config" do
      Dir.mktmpdir("client-search-related-assets") do |dest|
        config = Jekyll.configuration(
          "source" => FIXTURE_SITE,
          "destination" => dest,
          "quiet" => true
        )
        site = Jekyll::Site.new(config)
        site.process

        expect(File.exist?(File.join(dest, "assets", "client-search-related.js"))).to be(true)

        config_content = File.read(File.join(dest, "assets", "search-runtime-config.js"))
        expect(config_content).to include("relatedUrl")
        expect(config_content).to include("search-relations.json")
      end
    end

    it "renders the {% related_articles %} Liquid tag in post pages" do
      Dir.mktmpdir("client-search-related-tag") do |dest|
        config = Jekyll.configuration(
          "source" => FIXTURE_SITE,
          "destination" => dest,
          "quiet" => true
        )
        site = Jekyll::Site.new(config)
        site.process

        # Find a built post HTML file
        post_html = Dir.glob(File.join(dest, "**", "*.html")).find do |path|
          File.read(path).include?("related-articles-section")
        end
        expect(post_html).not_to be_nil, "no built post contains related-articles-section"

        content = File.read(post_html)
        expect(content).to include('id="related-articles"')
        expect(content).to include('id="related-sort"')
        expect(content).to include('value="relevance"')
        expect(content).to include('value="date"')
        expect(content).to include("client-search-related.js")
        expect(content).to include("search-runtime-config.js")
      end
    end

    it "renders the demo page with all variant sections" do
      Dir.mktmpdir("client-search-related-demo") do |dest|
        config = Jekyll.configuration(
          "source" => FIXTURE_SITE,
          "destination" => dest,
          "quiet" => true
        )
        site = Jekyll::Site.new(config)
        site.process

        demo_path = File.join(dest, "related-test", "index.html")
        expect(File.exist?(demo_path)).to be(true)

        content = File.read(demo_path)
        # Section 1: default Liquid tag
        expect(content).to include("related-articles-section")
        # Section 2: sort:date variant
        expect(content).to include('data-related-sort="date"')
        # Section 3: custom renderItem
        expect(content).to include("renderItem")
        # Section 4: filter
        expect(content).to include("filter:")
        # Section 5: raw JSON link
        expect(content).to include("search-relations.json")
      end
    end

    it "excludes self from relations and sorts by score descending" do
      Dir.mktmpdir("client-search-related-self") do |dest|
        config = Jekyll.configuration(
          "source" => FIXTURE_SITE,
          "destination" => dest,
          "quiet" => true
        )
        site = Jekyll::Site.new(config)
        site.process

        data = JSON.parse(File.read(File.join(dest, "search-relations.json")))
        data["relations"].each do |url, relations|
          # No article should list itself as a relation
          relation_urls = relations.map { |r| r["url"] }
          expect(relation_urls).not_to include(url),
                                       "#{url} listed itself as a relation"

          # Relations should be sorted by score descending
          scores = relations.map { |r| r["score"] }
          expect(scores).to eq(scores.sort.reverse),
                            "relations for #{url} not sorted by score descending"
        end
      end
    end
  end

  context "with {% search_form %} Liquid tag" do
    it "renders the search form and all scripts for the configured engine" do
      Dir.mktmpdir("client-search-tag") do |dest|
        config = Jekyll.configuration(
          "source" => FIXTURE_SITE,
          "destination" => dest,
          "quiet" => true
        )
        site = Jekyll::Site.new(config)
        site.process

        search_page = File.join(dest, "search-test", "index.html")
        expect(File.exist?(search_page)).to be(true)

        content = File.read(search_page)

        # Form elements
        expect(content).to include('id="search-form"')
        expect(content).to include('id="search-query"')
        expect(content).to include('id="search-status"')
        expect(content).to include('id="search-results"')

        # Scripts in the right order: engine, config, base, adapter
        expect(content).to include("minisearch@7.2.0")
        expect(content).to include("search-runtime-config.js")
        expect(content).to include("client-search-base.js")
        expect(content).to include("adapters/minisearch.js")

        # Verify script order: engine before config before base before adapter
        engine_pos = content.index("minisearch@7.2.0")
        config_pos = content.index("search-runtime-config.js")
        base_pos = content.index("client-search-base.js")
        adapter_pos = content.index("adapters/minisearch.js")
        expect(engine_pos).to be < config_pos
        expect(config_pos).to be < base_pos
        expect(base_pos).to be < adapter_pos
      end
    end

    it "renders different scripts when engine is elasticlunr" do
      Dir.mktmpdir("client-search-elasticlunr-tag") do |dest|
        config = Jekyll.configuration(
          "source" => FIXTURE_SITE,
          "destination" => dest,
          "client_search" => { "engine" => "elasticlunr" },
          "quiet" => true
        )
        site = Jekyll::Site.new(config)
        site.process

        content = File.read(File.join(dest, "search-test", "index.html"))
        expect(content).to include("elasticlunr@0.9.5")
        expect(content).to include("adapters/elasticlunr.js")
        expect(content).not_to include("minisearch")
      end
    end

    it "renders scripts_only without form HTML" do
      Dir.mktmpdir("client-search-scripts-only") do |dest|
        # Create a temp page that uses scripts_only
        page_content = "---\ntitle: Scripts only\npermalink: /scripts-only/\n---\n{% search_form scripts_only %}\n"
        File.write(File.join(FIXTURE_SITE, "scripts-only-test.html"), page_content)

        begin
          config = Jekyll.configuration(
            "source" => FIXTURE_SITE,
            "destination" => dest,
            "quiet" => true
          )
          site = Jekyll::Site.new(config)
          site.process

          content = File.read(File.join(dest, "scripts-only", "index.html"))
          expect(content).to include("<script")
          expect(content).not_to include('id="search-form"')
          expect(content).not_to include('id="search-results"')
        ensure
          File.delete(File.join(FIXTURE_SITE, "scripts-only-test.html"))
        end
      end
    end
  end
end
