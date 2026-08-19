# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::Configuration do
  def configuration(value = nil)
    site = instance_double(Jekyll::Site, config: value.nil? ? {} : { "client_search" => value })
    described_class.new(site)
  end

  it "uses safe defaults" do
    settings = configuration

    expect(settings).to be_enabled
    expect(settings.output).to eq("search-index.json")
    expect(settings.collections).to eq(["posts"])
    expect(settings).not_to be_include_pages
    expect(settings).to be_copy_runtime
  end

  it "accepts and normalizes site configuration overrides" do
    settings = configuration(
      "output" => "/custom/../custom/index.json",
      "collections" => ["posts", "categories", "posts", nil],
      "include_pages" => true,
      "copy_runtime" => false
    )

    expect(settings.output).to eq("custom/index.json")
    expect(settings.collections).to eq(["posts", "categories"])
    expect(settings).to be_include_pages
    expect(settings).not_to be_copy_runtime
  end

  it "can be disabled with false" do
    expect(configuration(false)).not_to be_enabled
  end

  it "rejects non-mapping configuration" do
    expect { configuration("invalid") }
      .to raise_error(Jekyll::Errors::FatalException, /must be a mapping/)
  end

  it "rejects output paths outside the destination" do
    expect { configuration("output" => "../search.json").output }
      .to raise_error(Jekyll::Errors::FatalException, /relative file path/)
  end

  it "rejects an empty output path" do
    expect { configuration("output" => "").output }
      .to raise_error(Jekyll::Errors::FatalException, /relative file path/)
  end
end
