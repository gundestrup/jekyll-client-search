# frozen_string_literal: true

require_relative "lib/jekyll/elasticlunr_search/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll-elasticlunr-search"
  spec.version = Jekyll::ElasticlunrSearch::VERSION
  spec.authors = ["Svend Gundestrup"]
  spec.email = ["svend@gundestrup.dk"]
  spec.summary = "Build Elasticlunr search indexes for Jekyll sites"
  spec.description = "A Jekyll plugin that generates configurable JSON search indexes for Elasticlunr."
  spec.homepage = "https://github.com/gundestrup/jekyll-elasticlunr-search"
  spec.license = "MIT"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/gundestrup/jekyll-elasticlunr-search/tree/main",
    "changelog_uri" => "https://github.com/gundestrup/jekyll-elasticlunr-search/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/gundestrup/jekyll-elasticlunr-search/issues"
  }

  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["lib/**/*", "assets/**/*", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 4.0", "< 5.0"
end
