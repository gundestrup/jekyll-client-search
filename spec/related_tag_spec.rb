# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::RelatedTag, :unit do
  def render_tag(markup, config = {})
    site = instance_double(Jekyll::Site, config: config)
    template = Liquid::Template.parse("{% related_articles #{markup} %}")
    template.render({}, registers: { site: site })
  end

  it "renders the container, sort control, and scripts when related is enabled" do
    html = render_tag("", "client_search" => { "related" => { "enabled" => true } })
    expect(html).to include('id="related-articles"')
    expect(html).to include('id="related-sort"')
    expect(html).to include("search-runtime-config.js")
    expect(html).to include("client-search-related.js")
    expect(html).to include("<option value=\"relevance\">")
    expect(html).to include("<option value=\"date\">")
  end

  it "renders nothing when related is disabled" do
    html = render_tag("", "client_search" => { "related" => { "enabled" => false } })
    expect(html.strip).to eq("")
  end

  it "renders nothing when related config is absent" do
    html = render_tag("", "client_search" => {})
    expect(html.strip).to eq("")
  end

  it "renders nothing when client_search config is absent" do
    html = render_tag("")
    expect(html.strip).to eq("")
  end

  it "sets data-related-sort when sort:date is given" do
    html = render_tag("sort:date", "client_search" => { "related" => { "enabled" => true } })
    expect(html).to include('data-related-sort="date"')
  end

  it "omits script tags when no_scripts is given" do
    html = render_tag("no_scripts", "client_search" => { "related" => { "enabled" => true } })
    expect(html).not_to include("search-runtime-config.js")
    expect(html).not_to include("client-search-related.js")
    expect(html).to include('id="related-articles"')
  end

  it "combines sort:date and no_scripts" do
    html = render_tag("sort:date no_scripts", "client_search" => { "related" => { "enabled" => true } })
    expect(html).to include('data-related-sort="date"')
    expect(html).not_to include("<script")
  end

  it "prefixes script URLs with baseurl when set" do
    html = render_tag("", "client_search" => { "related" => { "enabled" => true } },
                          "baseurl" => "/blog")
    expect(html).to include('src="/blog/assets/search-runtime-config.js"')
    expect(html).to include('src="/blog/assets/client-search-related.js"')
  end

  it "raises Liquid::SyntaxError on invalid markup" do
    expect { render_tag("bogus:value") }.to raise_error(Liquid::SyntaxError)
  end

  it "is registered as a safe Liquid tag" do
    expect(Liquid::Template.tags["related_articles"]).to eq(described_class)
  end
end
