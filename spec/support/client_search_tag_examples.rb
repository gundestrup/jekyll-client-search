# frozen_string_literal: true

# Shared contract for the client-search Liquid tags: engine wiring, render
# modes, engine_url/SRI/baseurl handling, and lazy markup validation. Each
# tag spec passes its tag name and tag-specific HTML markers. `render_tag`
# is defined by the including spec file with its hardcoded tag name.
RSpec.shared_examples "a client-search Liquid tag" do |tag_name:, form_marker:, results_marker:, tag_asset:|
  let(:minisearch_config) do
    { "client_search" => { "enabled" => true, "engine" => "minisearch" } }
  end

  let(:elasticlunr_config) do
    { "client_search" => { "enabled" => true, "engine" => "elasticlunr" } }
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

  it "renders with defaults when client_search config is absent" do
    html = render_tag("")
    expect(html).to include(form_marker)
    expect(html).to include("adapters/minisearch.js")
  end

  it "renders only form HTML with no_scripts mode" do
    html = render_tag("no_scripts", minisearch_config)
    expect(html).to include(form_marker)
    expect(html).to include(results_marker)
    expect(html).not_to include("<script")
  end

  it "renders only scripts with scripts_only mode" do
    html = render_tag("scripts_only", minisearch_config)
    expect(html).to include("<script")
    expect(html).not_to include(form_marker)
    expect(html).not_to include(results_marker)
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
    expect(html).to include("src=\"/blog/assets/#{tag_asset}\"")
  end

  it "raises Liquid::SyntaxError on invalid markup" do
    expect { render_tag("bogus") }.to raise_error(Liquid::SyntaxError)
  end

  it "ignores invalid markup inside a {% comment %} block" do
    # {% comment %} still parses nested tags — initialize must not raise.
    template = Liquid::Template.parse("{% comment %}{% #{tag_name} bogus %}{% endcomment %}")
    site = instance_double(Jekyll::Site, config: {})
    expect(template.render!({}, registers: { site: site }).strip).to eq("")
  end

  it "renders nothing when site is nil" do
    template = Liquid::Template.parse("{% #{tag_name} %}")
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
    expect(html).to include(tag_asset)
    expect(html).to include("adapters/semantic.js")
  end
end
