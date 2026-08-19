# frozen_string_literal: true

require_relative "lib/jekyll/client_search/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll-client-search"
  spec.version = Jekyll::ClientSearch::VERSION
  spec.authors = ["Svend Gundestrup"]
  spec.email = ["svend@gundestrup.dk"]
  spec.summary = "Build client-side search indexes for Jekyll sites"
  spec.description = "A Jekyll plugin that generates a configurable JSON search index and a MiniSearch browser runtime."
  spec.homepage = "https://github.com/gundestrup/jekyll-client-search"
  spec.license = "AGPL-3.0-or-later"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/gundestrup/jekyll-client-search/tree/main",
    "changelog_uri" => "https://github.com/gundestrup/jekyll-client-search/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/gundestrup/jekyll-client-search/issues"
  }

  spec.required_ruby_version = ">= 3.4.10"
  spec.files = Dir["lib/**/*", "assets/**/*", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 4.0", "< 5.0"
end
