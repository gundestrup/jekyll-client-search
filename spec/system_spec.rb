# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

# Fixture site path shared with the JS system tests.
# The fixture site contains 80 real-world posts:
#   - 40 Wikipedia articles (CC BY-SA 3.0) on arctic, climbing, photography,
#     food, and technology topics
#   - 40 arXiv papers (arXiv license) on information retrieval, NLP,
#     computer vision, recommendation systems, and knowledge graphs
FIXTURE_SITE = File.expand_path("fixtures/site", __dir__).freeze
EXPECTED_POST_COUNT = 80

RSpec.describe "ClientSearch system build", :system do
  # Build the fixture site once for each JS engine and verify the generated
  # JSON index contains the expected documents. The JS system tests
  # (test/system.test.js) then load this JSON in jsdom to verify search
  # behaviour uniformly across engines.
  %w[minisearch elasticlunr].each do |engine|
    context "with engine: #{engine}" do
      it "generates a JSON index with all #{EXPECTED_POST_COUNT} fixture posts and copies runtime assets" do
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

          # Verify Wikipedia articles are present with source attribution
          glacier = documents.find { |doc| doc["title"] == "Glacier" }
          expect(glacier).not_to be_nil
          expect(glacier["content"]).to include("ice")

          # Verify arXiv papers are present (categorized by their CS subfield)
          arxiv_categories = %w[information-retrieval natural-language-processing
                                computer-vision recommendation-systems knowledge-graphs]
          arxiv_docs = documents.select { |doc| arxiv_categories.include?(doc["categories"].first) }
          expect(arxiv_docs.length).to eq(40)

          # Verify all documents have required fields
          documents.each do |doc|
            expect(doc["id"]).not_to be_nil
            expect(doc["title"]).not_to be_nil
            expect(doc["content"]).not_to be_nil
          end

          expect(File.exist?(File.join(dest, "assets", "client-search-base.js"))).to be(true)
          expect(File.exist?(File.join(dest, "assets", "adapters", "#{engine}.js"))).to be(true)
        end
      end
    end
  end
end

# Copy the generated JSON to the fixture _site directory so the JS system
# tests can find it. Runs after the Ruby system specs via RSpec configuration.
RSpec.configure do |config|
  config.after(:suite) do
    next unless File.directory?(FIXTURE_SITE)

    Dir.mktmpdir("client-search-system-js") do |dest|
      jekyll_config = Jekyll.configuration(
        "source" => FIXTURE_SITE,
        "destination" => dest,
        "quiet" => true
      )
      site = Jekyll::Site.new(jekyll_config)
      site.process

      target_dir = File.join(FIXTURE_SITE, "_site")
      FileUtils.rm_rf(target_dir)
      FileUtils.cp_r(dest, target_dir)
    end
  end
end
