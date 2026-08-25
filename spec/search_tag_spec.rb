# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::SearchTag, :unit do
  def render_tag(markup, config = {})
    site = instance_double(Jekyll::Site, config: config)
    template = Liquid::Template.parse("{% search_form #{markup} %}")
    template.render({}, registers: { site: site })
  end

  let(:minisearch_config) do
    { "client_search" => { "enabled" => true, "engine" => "minisearch" } }
  end

  let(:elasticlunr_config) do
    { "client_search" => { "enabled" => true, "engine" => "elasticlunr" } }
  end

  let(:semantic_config) do
    {
      "client_search" => {
        "enabled" => true,
        "engine" => "semantic",
        "embedding" => { "enabled" => true, "query_embedder" => { "type" => "transformers" } }
      }
    }
  end

  it "renders form + scripts for minisearch with default CDN URL" do
    html = render_tag("", minisearch_config)
    expect(html).to include('id="search-form"')
    expect(html).to include('id="search-query"')
    expect(html).to include('id="search-status"')
    expect(html).to include('id="search-results"')
    expect(html).to include("minisearch@7.2.0/dist/umd/index.min.js")
    expect(html).to include("search-runtime-config.js")
    expect(html).to include("client-search-base.js")
    expect(html).to include("adapters/minisearch.js")
  end

  it "renders different CDN URL and adapter for elasticlunr" do
    html = render_tag("", elasticlunr_config)
    expect(html).to include("elasticlunr@0.9.5/elasticlunr.min.js")
    expect(html).to include("adapters/elasticlunr.js")
    expect(html).not_to include("minisearch")
  end

  it "renders embedder config and query embedder for semantic engine" do
    html = render_tag("", semantic_config)
    expect(html).to include("search-embedder-config.js")
    expect(html).to include("query-embedders/transformers.js")
    expect(html).to include("adapters/semantic.js")
    # Semantic has no external engine library
    expect(html).not_to include("cdn.jsdelivr.net/npm/minisearch")
    expect(html).not_to include("cdn.jsdelivr.net/npm/elasticlunr")
  end

  it "renders nothing when client_search is disabled" do
    html = render_tag("", "client_search" => { "enabled" => false })
    expect(html.strip).to eq("")
  end

  it "renders with defaults when client_search config is absent" do
    html = render_tag("")
    expect(html).to include('id="search-form"')
    expect(html).to include("adapters/minisearch.js")
  end

  it "renders only form HTML with no_scripts mode" do
    html = render_tag("no_scripts", minisearch_config)
    expect(html).to include('id="search-form"')
    expect(html).to include('id="search-results"')
    expect(html).not_to include("<script")
  end

  it "renders only scripts with scripts_only mode" do
    html = render_tag("scripts_only", minisearch_config)
    expect(html).to include("<script")
    expect(html).not_to include('id="search-form"')
    expect(html).not_to include('id="search-results"')
  end

  it "uses engine_url from config when provided" do
    config = {
      "client_search" => {
        "enabled" => true,
        "engine" => "minisearch",
        "engine_url" => "/assets/vendor/minisearch.min.js"
      }
    }
    html = render_tag("", config)
    expect(html).to include('src="/assets/vendor/minisearch.min.js"')
    expect(html).not_to include("cdn.jsdelivr.net")
  end

  it "includes SRI and crossorigin attributes when configured" do
    config = {
      "client_search" => {
        "enabled" => true,
        "engine" => "minisearch",
        "engine_url" => "https://cdn.example.com/minisearch.min.js",
        "engine_sri" => "sha384-abc123",
        "engine_crossorigin" => "anonymous"
      }
    }
    html = render_tag("", config)
    expect(html).to include('integrity="sha384-abc123"')
    expect(html).to include('crossorigin="anonymous"')
  end

  it "prefixes script URLs with baseurl when set" do
    config = {
      "client_search" => { "enabled" => true, "engine" => "minisearch" },
      "baseurl" => "/blog"
    }
    html = render_tag("", config)
    expect(html).to include('src="/blog/assets/search-runtime-config.js"')
    expect(html).to include('src="/blog/assets/client-search-base.js"')
  end

  it "raises Liquid::SyntaxError on invalid markup" do
    expect { render_tag("bogus") }.to raise_error(Liquid::SyntaxError)
  end

  it "is registered as a safe Liquid tag" do
    expect(Liquid::Template.tags["search_form"]).to eq(described_class)
  end
end
