#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates the committed baseline search-index JSON from the fixture site.
# Requires both Wikipedia and arXiv fixture posts to be present.
# Run `ruby spec/fixtures/download_arxiv.rb` first if arXiv posts are missing.
# See README.developer.md for the full fixture setup process.

require "json"
require "tmpdir"
require "jekyll"
require "jekyll-client-search"

fixture_root = __dir__
source_path = File.join(fixture_root, "site")
output_path = File.join(fixture_root, "baseline", "search-index-baseline.json")

arxiv_count = Dir.glob(File.join(source_path, "_posts", "*-arxiv-*.md")).length
wiki_count = Dir.glob(File.join(source_path, "_posts", "*-wikipedia-*.md")).length
abort "Expected 40 Wikipedia posts, found #{wiki_count} — run download_wikipedia.rb" unless wiki_count == 40
abort "Expected 40 arXiv posts, found #{arxiv_count} — run download_arxiv.rb first (see README.developer.md)" unless arxiv_count == 40

Dir.mktmpdir("client-search-baseline") do |destination|
  config = Jekyll.configuration(
    "source" => source_path,
    "destination" => destination,
    "client_search" => {
      "engine" => "minisearch",
      "embedding" => { "enabled" => false }
    },
    "quiet" => true
  )
  Jekyll::Site.new(config).process
  documents = JSON.parse(File.read(File.join(destination, "search-index.json")))
  abort "Expected 80 baseline documents, got #{documents.length}" unless documents.length == 80

  File.write(output_path, JSON.pretty_generate(documents))
  puts "Wrote #{output_path} (#{File.size(output_path)} bytes)"
end
