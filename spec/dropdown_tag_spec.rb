# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::DropdownTag, :unit do
  def render_tag(markup, config = {})
    site = instance_double(Jekyll::Site, config: config)
    template = Liquid::Template.parse("{% search_dropdown #{markup} %}")
    template.render({}, registers: { site: site })
  end

  let(:minisearch_config) do
    { "client_search" => { "enabled" => true, "engine" => "minisearch" } }
  end

  let(:elasticlunr_config) do
    { "client_search" => { "enabled" => true, "engine" => "elasticlunr" } }
  end

  it "renders dropdown HTML + scripts for minisearch with default CDN URL" do
    html = render_tag("", minisearch_config)
    expect(html).to include("data-client-search-dropdown")
    expect(html).to include("cs-dropdown-input")
    expect(html).to include("cs-dropdown-results")
    expect(html).to include('data-max-items="5"')
    expect(html).to include("minisearch@7.2.0/dist/umd/index.min.js")
    expect(html).to include("search-runtime-config.js")
    expect(html).to include("client-search-dropdown.js")
    expect(html).to include("adapters/minisearch.js")
  end

  it "renders with max:10 override" do
    html = render_tag("max:10", minisearch_config)
    expect(html).to include('data-max-items="10"')
  end

  it "renders different CDN URL and adapter for elasticlunr" do
    html = render_tag("", elasticlunr_config)
    expect(html).to include("elasticlunr@0.9.5/elasticlunr.min.js")
    expect(html).to include("adapters/elasticlunr.js")
    expect(html).not_to include("minisearch")
  end

  it "renders nothing when client_search is disabled" do
    html = render_tag("", "client_search" => { "enabled" => false })
    expect(html.strip).to eq("")
  end

  it "renders nothing when dropdown is disabled" do
    config = { "client_search" => { "enabled" => true, "engine" => "minisearch",
                                    "dropdown" => { "enabled" => false } } }
    html = render_tag("", config)
    expect(html.strip).to eq("")
  end

  it "renders with defaults when client_search config is absent" do
    html = render_tag("")
    expect(html).to include("data-client-search-dropdown")
    expect(html).to include("adapters/minisearch.js")
  end

  it "renders only form HTML with no_scripts mode" do
    html = render_tag("no_scripts", minisearch_config)
    expect(html).to include("data-client-search-dropdown")
    expect(html).to include("cs-dropdown-results")
    expect(html).not_to include("<script")
  end

  it "renders only scripts with scripts_only mode" do
    html = render_tag("scripts_only", minisearch_config)
    expect(html).to include("<script")
    expect(html).not_to include("data-client-search-dropdown")
    expect(html).not_to include("cs-dropdown-results")
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
    expect(html).to include('src="/blog/assets/client-search-dropdown.js"')
  end

  it "raises Liquid::SyntaxError on invalid markup" do
    expect { render_tag("bogus") }.to raise_error(Liquid::SyntaxError)
  end

  it "renders nothing when site is nil" do
    template = Liquid::Template.parse("{% search_dropdown %}")
    html = template.render({}, registers: { site: nil })
    expect(html).to eq("")
  end

  it "renders without engine CDN script for semantic engine" do
    config = {
      "client_search" => {
        "enabled" => true,
        "engine" => "semantic",
        "embedding" => { "enabled" => true, "query_embedder" => { "type" => "transformers" } }
      }
    }
    html = render_tag("", config)
    expect(html).not_to include("cdn.jsdelivr.net")
    expect(html).to include("search-runtime-config.js")
    expect(html).to include("client-search-dropdown.js")
    expect(html).to include("adapters/semantic.js")
  end

  it "is registered as a safe Liquid tag" do
    expect(Liquid::Template.tags["search_dropdown"]).to eq(described_class)
  end
end
