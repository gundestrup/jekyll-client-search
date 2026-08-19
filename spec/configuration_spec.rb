# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ElasticlunrSearch::Configuration do
  it "uses the posts collection and default output" do
    site = instance_double(Jekyll::Site, config: {})
    configuration = described_class.new(site)

    expect(configuration).to be_enabled
    expect(configuration.output).to eq("search-index.json")
    expect(configuration.collections).to eq(["posts"])
    expect(configuration).not_to be_include_pages
  end

  it "accepts site configuration overrides" do
    site = instance_double(
      Jekyll::Site,
      config: {
        "elasticlunr_search" => {
          "output" => "/custom/index.json",
          "collections" => ["posts", "categories"],
          "include_pages" => true
        }
      }
    )
    configuration = described_class.new(site)

    expect(configuration.output).to eq("custom/index.json")
    expect(configuration.collections).to eq(["posts", "categories"])
    expect(configuration).to be_include_pages
  end
end
