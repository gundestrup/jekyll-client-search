# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Jekyll::ClientSearch::SearchIndexPage, :unit do
  def build_page(source, output, documents)
    site = Jekyll::Site.new(
      Jekyll.configuration(
        "source" => source,
        "destination" => File.join(source, "_site"),
        "quiet" => true
      )
    )
    described_class.new(site, output, documents)
  end

  it "creates valid JSON without a layout or sitemap entry" do
    Dir.mktmpdir("client-search-page") do |source|
      documents = [{ "id" => "/æ/", "title" => "Æble" }]

      page = build_page(source, "indexes/search.json", documents)

      expect(page.url).to eq("/indexes/search.json")
      expect(page.data).to include("layout" => nil, "sitemap" => false)
      expect(JSON.parse(page.content)).to eq(documents)
    end
  end

  it "resolves the default root-level output path" do
    Dir.mktmpdir("client-search-page") do |source|
      page = build_page(source, "search-index.json", [])

      expect(page.url).to eq("/search-index.json")
    end
  end

  it "serializes an empty document list as an empty JSON array" do
    Dir.mktmpdir("client-search-page") do |source|
      page = build_page(source, "search-index.json", [])

      expect(JSON.parse(page.content)).to eq([])
    end
  end

  it "preserves document order and all fields verbatim" do
    Dir.mktmpdir("client-search-page") do |source|
      documents = [
        { "id" => "/b/", "title" => "Beta", "tags" => %w[x y], "embedding" => [0.1, -0.2] },
        { "id" => "/a/", "title" => "Alpha" }
      ]

      page = build_page(source, "search-index.json", documents)

      expect(JSON.parse(page.content)).to eq(documents)
    end
  end
end
