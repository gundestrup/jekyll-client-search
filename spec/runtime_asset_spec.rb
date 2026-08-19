# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MiniSearch browser runtime" do
  subject(:runtime) do
    File.read(File.expand_path("../assets/client-search.js", __dir__))
  end

  it "uses DOM APIs instead of injecting result HTML" do
    expect(runtime).to include("document.createElement")
    expect(runtime).to include("textContent")
    expect(runtime).not_to include("innerHTML")
  end

  it "supports configurable selectors and validates the search index shape" do
    expect(runtime).to include("window.clientSearchConfig")
    expect(runtime).to include("Search index must be an array")
  end

  it "restricts result links to same-origin HTTP URLs" do
    expect(runtime).to include("url.origin === window.location.origin")
    expect(runtime).to include('["http:", "https:"]')
  end

  it "uses MiniSearch as the search engine" do
    expect(runtime).to include("window.MiniSearch")
    expect(runtime).to include("new window.MiniSearch")
  end

  it "applies AND-first search with fuzzy OR fallback" do
    expect(runtime).to include('combineWith: "AND"')
    expect(runtime).to include('combineWith: "OR"')
    expect(runtime).to include("fuzzy: 0.2")
  end
end
