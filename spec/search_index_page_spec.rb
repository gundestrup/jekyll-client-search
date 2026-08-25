# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Jekyll::ClientSearch::SearchIndexPage, :unit do
  it "creates valid JSON without a layout or sitemap entry" do
    Dir.mktmpdir("client-search-page") do |source|
      site = Jekyll::Site.new(
        Jekyll.configuration(
          "source" => source,
          "destination" => File.join(source, "_site"),
          "quiet" => true
        )
      )
      documents = [{ "id" => "/æ/", "title" => "Æble" }]

      page = described_class.new(site, "indexes/search.json", documents)

      expect(page.url).to eq("/indexes/search.json")
      expect(page.data).to include("layout" => nil, "sitemap" => false)
      expect(JSON.parse(page.content)).to eq(documents)
    end
  end
end
