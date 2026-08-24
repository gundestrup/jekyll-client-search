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
    expect(settings.engine).to eq("minisearch")
    expect(settings.runtime_assets).to eq(["assets/client-search-base.js", "assets/adapters/minisearch.js"])
    expect(settings.output).to eq("search-index.json")
    expect(settings.collections).to eq(["posts"])
    expect(settings).not_to be_include_pages
    expect(settings).to be_copy_runtime
  end

  it "accepts and normalizes site configuration overrides" do
    settings = configuration(
      "engine" => "elasticlunr",
      "output" => "/custom/../custom/index.json",
      "collections" => ["posts", "categories", "posts", nil],
      "include_pages" => true,
      "copy_runtime" => false
    )

    expect(settings.engine).to eq("elasticlunr")
    expect(settings.runtime_assets).to eq(["assets/client-search-base.js", "assets/adapters/elasticlunr.js"])
    expect(settings.output).to eq("custom/index.json")
    expect(settings.collections).to eq(%w[posts categories])
    expect(settings).to be_include_pages
    expect(settings).not_to be_copy_runtime
  end

  it "rejects an unknown engine" do
    expect { configuration("engine" => "pagefind") }
      .to raise_error(Jekyll::Errors::FatalException, /engine must be one of/)
    expect { configuration("engine" => "algolia") }
      .to raise_error(Jekyll::Errors::FatalException, /engine must be one of/)
  end

  it "accepts the semantic engine" do
    settings = configuration("engine" => "semantic")
    expect(settings.engine).to eq("semantic")
    expect(settings.runtime_assets).to eq(["assets/client-search-base.js", "assets/adapters/semantic.js"])
  end

  it "has embedding disabled by default" do
    settings = configuration
    expect(settings).not_to be_embedding_enabled
    expect(settings.embedding_model).to eq("embeddinggemma:300m")
    expect(settings.embedding_base_url).to eq("http://localhost:11434")
  end

  it "accepts embedding configuration overrides" do
    settings = configuration(
      "embedding" => {
        "enabled" => true,
        "model" => "bge-m3",
        "base_url" => "http://gpu-box:11434"
      }
    )
    expect(settings).to be_embedding_enabled
    expect(settings.embedding_model).to eq("bge-m3")
    expect(settings.embedding_base_url).to eq("http://gpu-box:11434")
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
