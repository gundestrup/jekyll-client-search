# frozen_string_literal: true

require_relative "lib/jekyll/client_search/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll-client-search"
  spec.version = Jekyll::ClientSearch::VERSION
  spec.authors = ["Svend Gundestrup"]
  spec.email = ["svend@gundestrup.dk"]
  spec.summary = "Build client-side search indexes for Jekyll sites"
  # NOTE: rubygems.org renders the description through RDoc::Markup only
  # when it starts with an == heading at column 0 — keep the heredoc
  # content flush-left or the page renders as one plain <p>.
  spec.description = <<~DESC
    == Client-side search indexes for Jekyll

    Generates a configurable JSON search index and ships pluggable browser
    runtime adapters for client-side JavaScript search engines.

    * Collections, frontmatter fields and output path configurable
    * Client-side runtime stays framework-agnostic
  DESC
  spec.homepage = "https://github.com/gundestrup/jekyll-client-search"
  spec.license = "AGPL-3.0-or-later"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/gundestrup/jekyll-client-search/tree/main",
    "changelog_uri" => "https://github.com/gundestrup/jekyll-client-search/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/gundestrup/jekyll-client-search/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 3.3.0"
  spec.files = Dir["lib/**/*", "assets/**/*", "README.md", "LICENSE", "CHANGELOG.md",
                   "docs/assets/icon.svg", "docs/assets/icon-256.png", "NOTICE", "README.developer.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 4.0", "< 5.0"
end
