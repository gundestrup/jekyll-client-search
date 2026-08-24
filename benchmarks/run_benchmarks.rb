#!/usr/bin/env ruby
# frozen_string_literal: true

# Performance benchmark script — measures build time, index size, and
# search speed for the jekyll-client-search gem. Results are saved to
# benchmarks/results.json and used to generate README.performance.md.
#
# Usage:
#   bundle exec ruby benchmarks/run_benchmarks.rb
#   OLLAMA_INTEGRATION=1 bundle exec ruby benchmarks/run_benchmarks.rb  # include LLM
#
# The benchmark results JSON has this structure:
#   {
#     "timestamp": "2026-08-22T12:00:00Z",
#     "ruby_version": "3.4.10",
#     "ollama_model": "embeddinggemma:300m",  # or null if not used
#     "metrics": {
#       "build_time_without_llm_ms": 5000,
#       "build_time_with_llm_ms": 180000,     # or null
#       "index_size_without_llm_bytes": 1956488,
#       "index_size_with_llm_bytes": 3000000, # or null
#       "document_count": 80,
#       "embedding_dimensions": 768,           # or null
#       "cache_size_bytes": 2500000,           # or null
#     }
#   }
#
# When run multiple times, results are appended to a history array
# so you can track performance changes over time.

require "json"
require "time"
require "tmpdir"
require "fileutils"
require "benchmark"

BENCHMARKS_DIR = __dir__
RESULTS_PATH = File.join(BENCHMARKS_DIR, "results.json")
FIXTURE_SITE = File.expand_path("spec/fixtures/site", File.join(BENCHMARKS_DIR, ".."))

def load_results
  return { "history" => [] } unless File.exist?(RESULTS_PATH)

  JSON.parse(File.read(RESULTS_PATH))
rescue JSON::ParserError
  { "history" => [] }
end

def build_site(source, dest, embedding_config = nil)
  require "jekyll"
  require "jekyll-client-search"

  client_search = { "engine" => "minisearch" }
  client_search["embedding"] = embedding_config if embedding_config

  config = Jekyll.configuration(
    "source" => source,
    "destination" => dest,
    "client_search" => client_search,
    "quiet" => true
  )
  site = Jekyll::Site.new(config)
  site.process
end

def measure_build_without_llm
  Dir.mktmpdir("bench-no-llm") do |dest|
    time = Benchmark.realtime do
      build_site(FIXTURE_SITE, dest)
    end

    index_path = File.join(dest, "search-index.json")
    index_size = File.size(index_path)
    documents = JSON.parse(File.read(index_path))

    {
      time_ms: (time * 1000).round,
      index_size_bytes: index_size,
      document_count: documents.length
    }
  end
end

def measure_build_with_llm
  model = "embeddinggemma:300m"
  base_url = "http://localhost:11434"

  # Check if Ollama is available
  require "net/http"
  begin
    uri = URI("#{base_url}/api/tags")
    response = Net::HTTP.get_response(uri)
    models = JSON.parse(response.body).fetch("models", []).map { |m| m["name"] }
    return nil unless models.include?(model)
  rescue Errno::ECONNREFUSED, SocketError
    return nil
  end

  cache_file = File.join(FIXTURE_SITE, ".jekyll-client-search-cache.json")
  FileUtils.rm_f(cache_file)

  Dir.mktmpdir("bench-llm") do |dest|
    time = Benchmark.realtime do
      build_site(FIXTURE_SITE, dest, { "enabled" => true, "model" => model, "base_url" => base_url })
    end

    index_path = File.join(dest, "search-index.json")
    index_size = File.size(index_path)
    documents = JSON.parse(File.read(index_path))
    cache_size = File.exist?(cache_file) ? File.size(cache_file) : 0
    embedding_dims = documents.find { |d| d["embedding"] }&.dig("embedding")&.length

    FileUtils.rm_f(cache_file)

    {
      time_ms: (time * 1000).round,
      index_size_bytes: index_size,
      document_count: documents.length,
      embedding_dimensions: embedding_dims,
      cache_size_bytes: cache_size
    }
  end
end

puts "Running benchmarks..."
puts "  Ruby: #{RUBY_VERSION}"

# Measure build without LLM
print "  Building without LLM... "
no_llm = measure_build_without_llm
puts "#{no_llm[:time_ms]}ms, #{no_llm[:index_size_bytes]} bytes"

# Measure build with LLM (if available)
print "  Building with LLM... "
with_llm = measure_build_with_llm
if with_llm
  puts "#{with_llm[:time_ms]}ms, #{with_llm[:index_size_bytes]} bytes"
else
  puts "skipped (Ollama not available)"
end

# Build result entry
entry = {
  "timestamp" => Time.now.utc.iso8601,
  "ruby_version" => RUBY_VERSION,
  "ollama_model" => with_llm ? "embeddinggemma:300m" : nil,
  "metrics" => {
    "build_time_without_llm_ms" => no_llm[:time_ms],
    "build_time_with_llm_ms" => with_llm&.dig(:time_ms),
    "index_size_without_llm_bytes" => no_llm[:index_size_bytes],
    "index_size_with_llm_bytes" => with_llm&.dig(:index_size_bytes),
    "document_count" => no_llm[:document_count],
    "embedding_dimensions" => with_llm&.dig(:embedding_dimensions),
    "cache_size_bytes" => with_llm&.dig(:cache_size_bytes)
  }
}

# Append to history
results = load_results
results["history"] << entry
results["latest"] = entry
FileUtils.mkdir_p(BENCHMARKS_DIR)
File.write(RESULTS_PATH, JSON.pretty_generate(results))

puts "\nResults saved to #{RESULTS_PATH}"
puts "  History entries: #{results['history'].length}"
