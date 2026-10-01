# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::DropdownTag, :unit do
  def render_tag(markup, config = {})
    site = instance_double(Jekyll::Site, config: config)
    template = Liquid::Template.parse("{% search_dropdown #{markup} %}")
    template.render!({}, registers: { site: site })
  end

  let(:minisearch_config) do
    { "client_search" => { "enabled" => true, "engine" => "minisearch" } }
  end

  it_behaves_like "a client-search Liquid tag",
                  tag_name: "search_dropdown",
                  form_marker: "data-client-search-dropdown",
                  results_marker: "cs-dropdown-results",
                  tag_asset: "client-search-dropdown.js"

  it "renders dropdown HTML + scripts for minisearch with default CDN URL" do
    html = render_tag("", minisearch_config)
    expect(html).to include("data-client-search-dropdown")
    expect(html).to include("cs-dropdown-input")
    expect(html).to include("cs-dropdown-results")
    expect(html).to include('data-max-items="5"')
    expect(html).to include("minisearch@7.2.0/dist/umd/index.min.js")
    expect(html).to include("search-runtime-config.js")
    expect(html).to include("client-search-shared.js")
    expect(html).to include("client-search-dropdown.js")
    expect(html).to include("adapters/minisearch.js")
  end

  it "renders with max:10 override" do
    html = render_tag("max:10", minisearch_config)
    expect(html).to include('data-max-items="10"')
  end

  it "renders nothing when dropdown is disabled" do
    config = { "client_search" => { "enabled" => true, "engine" => "minisearch",
                                    "dropdown" => { "enabled" => false } } }
    html = render_tag("", config)
    expect(html.strip).to eq("")
  end

  it "is registered as a safe Liquid tag" do
    expect(Liquid::Template.tags["search_dropdown"]).to eq(described_class)
  end
end
