# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::SearchTag, :unit do
  def render_tag(markup, config = {})
    site = instance_double(Jekyll::Site, config: config)
    template = Liquid::Template.parse("{% search_form #{markup} %}")
    template.render!({}, registers: { site: site })
  end

  let(:minisearch_config) do
    { "client_search" => { "enabled" => true, "engine" => "minisearch" } }
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

  it_behaves_like "a client-search Liquid tag",
                  tag_name: "search_form",
                  form_marker: 'id="search-form"',
                  results_marker: 'id="search-results"',
                  tag_asset: "client-search-base.js"

  it "renders form + scripts for minisearch with default CDN URL" do
    html = render_tag("", minisearch_config)
    expect(html).to include('id="search-form"')
    expect(html).to include('id="search-query"')
    expect(html).to include('id="search-status"')
    expect(html).to include('id="search-results"')
    expect(html).to include("minisearch@7.2.0/dist/umd/index.min.js")
    expect(html).to include("search-runtime-config.js")
    expect(html).to include("client-search-shared.js")
    expect(html).to include("client-search-base.js")
    expect(html).to include("adapters/minisearch.js")
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

  it "renders without query embedder script for none type" do
    config = {
      "client_search" => {
        "enabled" => true,
        "engine" => "semantic",
        "embedding" => { "enabled" => true, "query_embedder" => { "type" => "none" } }
      }
    }
    html = render_tag("", config)
    expect(html).to include("client-search-base.js")
    expect(html).to include("adapters/semantic.js")
    expect(html).not_to include("query-embedders/")
    expect(html).not_to include("search-embedder-config.js")
  end

  it "is registered as a safe Liquid tag" do
    expect(Liquid::Template.tags["search_form"]).to eq(described_class)
  end
end
