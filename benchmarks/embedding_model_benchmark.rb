#!/usr/bin/env ruby
# frozen_string_literal: true

# Embedding model speed benchmark for a real Jekyll site.
#
# Measures Ollama embedding latency per document for each configured model,
# using the same document text the build-time generator embeds
# (document_prefix + title + excerpt + content). Results are printed as a
# table and appended to benchmarks/embedding-model-results.json.
#
# Only site.read is used — the site's plugins and theme are not required —
# so this runs from the gem's own bundle against any site source:
#
#   bundle exec ruby benchmarks/embedding_model_benchmark.rb ../gundestrup.dk
#
# Optional environment:
#   EMBEDDING_MODELS="embeddinggemma:300m,qwen3-embedding:4b" (default: all three)
#   BENCH_LIMIT=25          limit the number of documents
#   OLLAMA_BASE_URL=...     default http://localhost:11434

require "benchmark"
require "json"
require "net/http"
require "time"
require "uri"
require "jekyll"
require "jekyll-client-search"

SITE_DIR = File.expand_path(ARGV[0] || ENV["SITE_DIR"] || Dir.pwd)
RESULTS_PATH = File.join(__dir__, "embedding-model-results.json")
BASE_URL = ENV["OLLAMA_BASE_URL"] || "http://localhost:11434"
MODELS = (ENV["EMBEDDING_MODELS"] || "embeddinggemma:300m,qwen3-embedding:4b,qwen3-embedding:8b")
         .split(",").map(&:strip)
LIMIT = ENV["BENCH_LIMIT"]&.to_i
# Mirror EmbeddingConfiguration#configured_prefix: a model without a known
# entry falls back to an empty document prefix.
PREFIXES = Jekyll::ClientSearch::EmbeddingConfiguration::PREFIXES

def available_models(base_url)
  # Acceptable risk: base_url defaults to http://localhost:11434 (local Ollama).
  uri = URI("#{base_url}/api/tags") # nosemgrep: problem-based-packs.insecure-transport.ruby-stdlib.net-http-request.net-http-request
  JSON.parse(Net::HTTP.get_response(uri).body).fetch("models", []).flat_map do |m|
    name = m["name"].to_s
    [name, name.sub(/:latest\z/, "")]
  end.uniq
rescue Errno::ECONNREFUSED, SocketError
  nil
end

def load_documents(site_dir)
  config = Jekyll.configuration("source" => site_dir,
                                "destination" => File.join(site_dir, "_site"),
                                "quiet" => true)
  # The site's theme gem and plugin gems are not needed to read posts, and
  # they may not be installed in this bundle.
  config["theme"] = nil
  config["plugins"] = []
  site = Jekyll::Site.new(config)

  # Stub Liquid tags the site's plugins would provide — excerpt rendering
  # parses post content and fails on unknown tags.
  %w[imgflow search_form search_dropdown related_articles].each do |tag_name|
    next if Liquid::Template.tags[tag_name]

    Liquid::Template.register_tag(tag_name, Class.new(Liquid::Tag))
  end

  site.read

  labels = config.dig("client_search", "collections") || ["posts"]
  builder = Jekyll::ClientSearch::DocumentBuilder.new
  labels.flat_map do |label|
    collection = label == "posts" ? site.posts : site.collections[label]
    next [] unless collection

    collection.docs.filter_map { |doc| builder.from_document(doc, source: label) }
  end
end

def percentile(sorted, fraction)
  return nil if sorted.empty?

  sorted[((sorted.length - 1) * fraction).ceil]
end

def benchmark_model(model, documents)
  adapter = Jekyll::ClientSearch::OllamaEmbeddingAdapter.new(model: model, base_url: BASE_URL)
  prefix = PREFIXES.fetch(model.split(":").first, {}).fetch("document", "")
  times = []
  failures = 0
  dimensions = nil

  documents.each do |document|
    text = "#{prefix}#{[document["title"], document["excerpt"], document["content"]].compact.join(" ")}"
    elapsed = Benchmark.realtime do
      embedding = adapter.embed(text)
      dimensions ||= embedding&.length
      failures += 1 if embedding.nil?
    end
    times << (elapsed * 1000).round(1)
  end

  sorted = times.sort
  {
    "documents" => times.length,
    "dimensions" => dimensions,
    "failures" => failures,
    "total_ms" => times.sum.round,
    "first_call_ms" => times.first,
    "mean_ms" => (times.sum / times.length).round(1),
    "median_ms" => percentile(sorted, 0.5),
    "p95_ms" => percentile(sorted, 0.95),
    "min_ms" => sorted.first,
    "max_ms" => sorted.last
  }
end

if __FILE__ == $PROGRAM_NAME
  installed = available_models(BASE_URL)
  abort "Ollama is not reachable at #{BASE_URL}" unless installed

  puts "Reading site from #{SITE_DIR}..."
  documents = load_documents(SITE_DIR)
  documents = documents.first(LIMIT) if LIMIT
  puts "Embedding #{documents.length} documents per model"

  results = {}
  MODELS.each do |model|
    unless installed.include?(model)
      puts "  #{model}: skipped (not pulled)"
      next
    end

    print "  #{model}: "
    results[model] = benchmark_model(model, documents)
    stats = results[model]
    puts "#{stats["total_ms"]}ms total, mean #{stats["mean_ms"]}ms, " \
         "median #{stats["median_ms"]}ms, p95 #{stats["p95_ms"]}ms, " \
         "dims #{stats["dimensions"]}, failures #{stats["failures"]}"
  end

  entry = {
    "timestamp" => Time.now.utc.iso8601,
    "site" => SITE_DIR,
    "base_url" => BASE_URL,
    "results" => results
  }
  history = File.exist?(RESULTS_PATH) ? JSON.parse(File.read(RESULTS_PATH)) : { "history" => [] }
  history["history"] << entry
  history["latest"] = entry
  File.write(RESULTS_PATH, JSON.pretty_generate(history))
  puts "Results appended to #{RESULTS_PATH}"
end
