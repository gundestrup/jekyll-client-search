#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates README.performance.md from benchmark results.
#
# The template has a "baseline" section (the first measurement) and a
# "current" section (the latest measurement). This lets you see at a
# glance how performance has changed over time.
#
# Usage:
#   bundle exec ruby benchmarks/generate_perf_readme.rb
#
# Requires benchmarks/results.json (run benchmarks/run_benchmarks.rb first).

require "json"
require "erb"

BENCHMARKS_DIR = __dir__
RESULTS_PATH = File.join(BENCHMARKS_DIR, "results.json")
OUTPUT_PATH = File.join(BENCHMARKS_DIR, "..", "README.performance.md")

def load_results
  return nil unless File.exist?(RESULTS_PATH)

  JSON.parse(File.read(RESULTS_PATH))
end

def format_bytes(bytes)
  return "N/A" unless bytes

  if bytes > 1_000_000
    "#{(bytes / 1_000_000.0).round(2)} MB"
  elsif bytes > 1_000
    "#{(bytes / 1_000.0).round(1)} KB"
  else
    "#{bytes} bytes"
  end
end

def format_ms(ms)
  return "N/A" unless ms

  if ms > 60_000
    "#{(ms / 60_000.0).round(2)} min"
  elsif ms > 1_000
    "#{(ms / 1_000.0).round(2)} s"
  else
    "#{ms} ms"
  end
end

def delta(current, baseline)
  return "" unless current && baseline

  diff = current - baseline
  pct = baseline.positive? ? (diff.to_f / baseline * 100).round(1) : 0
  arrow = if diff.positive?
            "↑"
          else
            diff.negative? ? "↓" : "→"
          end
  "#{arrow} #{pct.abs}% (#{format_bytes(diff) if current.is_a?(Integer)})"
end

def delta_ms(current, baseline)
  return "" unless current && baseline

  diff = current - baseline
  pct = baseline.positive? ? (diff.to_f / baseline * 100).round(1) : 0
  arrow = if diff.positive?
            "↑"
          else
            diff.negative? ? "↓" : "→"
          end
  "#{arrow} #{pct.abs}% (#{format_ms(diff.abs)})"
end

results = load_results
unless results
  puts "No benchmark results found. Run benchmarks/run_benchmarks.rb first."
  exit 1
end

history = results["history"] || []
baseline = history.find { |entry| entry["benchmark_schema"] == 3 } || history.first
latest = results["latest"] || history.last

def history_section(history, baseline)
  history.each_with_index.map do |entry, i|
    title = entry.equal?(baseline) ? "Baseline" : "Run ##{i + 1}"
    <<~SECTION
      ### #{title} — #{entry['timestamp']}

      | Metric | Value |
      | --- | --- |
      | Benchmark schema | #{entry['benchmark_schema'] || 'legacy'} |
      | Ruby | #{entry['ruby_version']} |
      | Ollama model | #{entry['ollama_model'] || 'not used'} |
      | Build time (no LLM) | #{format_ms(entry['metrics']['build_time_without_llm_ms'])} |
      | Cold build time (with LLM) | #{format_ms(entry['metrics']['build_time_with_llm_ms'])} |
      | Warm build time (with LLM) | #{format_ms(entry['metrics']['warm_build_time_with_llm_ms'])} |
      | Incremental build time (with LLM) | #{format_ms(entry['metrics']['incremental_build_time_with_llm_ms'])} |
      | Index size (no LLM) | #{format_bytes(entry['metrics']['index_size_without_llm_bytes'])} |
      | Index size (with LLM) | #{format_bytes(entry['metrics']['index_size_with_llm_bytes'])} |
      | Documents | #{entry['metrics']['document_count']} |
      | Embedding dims | #{entry['metrics']['embedding_dimensions'] || 'N/A'} |
      | Cache size | #{format_bytes(entry['metrics']['cache_size_bytes'])} |
      | MiniSearch avg query | #{format_ms(entry.dig("metrics", "search", "metrics", "minisearch", "avg_query_ms"))} |
      | ElasticLunr avg query | #{format_ms(entry.dig("metrics", "search", "metrics", "elasticlunr", "avg_query_ms"))} |
      | Semantic cosine search | #{format_ms(entry.dig("metrics", "search", "metrics", "semantic", "avg_query_ms"))} |
      | Semantic query embedding | #{format_ms(entry.dig("metrics", "query_embedding_avg_ms"))} |
    SECTION
  end.join("\n")
end

template = <<~ERB
  # Performance Benchmarks

  This file is **auto-generated** by `benchmarks/generate_perf_readme.rb`.
  Do not edit manually — run the benchmark script to update.

  ## Methodology

  - **Fixture site**: 80 source posts (40 Wikipedia + 40 unique arXiv papers)
  - **Ruby**: <%= latest["ruby_version"] %>
  - **LLM model**: <%= latest["ollama_model"] || "not used" %>
  - **Measurements**: cold, warm, and incremental Jekyll build time;
    index/cache size; embedding dimensions; and average engine-core query
    latency using the same search options as the runtime adapters

  Build and query timings are environment-sensitive, especially cold Ollama
  runs. Compare measurements from equivalent hardware, model state, and system
  load; index and cache sizes are deterministic for the same fixture/model.

  Run the benchmarks:

  ```bash
  bundle exec ruby benchmarks/run_benchmarks.rb
  bundle exec ruby benchmarks/generate_perf_readme.rb
  ```

  ## Baseline vs Current

  The baseline is the first measurement for the current benchmark schema. The
  current is the latest measurement. Compare only rows with the same schema;
  fixture or methodology changes increment the schema, and older rows may show
  `N/A` for metrics that did not exist yet.

  | Metric | Baseline | Current | Change |
  | --- | --- | --- | --- |
  | Build time (no LLM) | <%= format_ms(baseline&.dig("metrics", "build_time_without_llm_ms")) %> | <%= format_ms(latest&.dig("metrics", "build_time_without_llm_ms")) %> | <%= delta_ms(latest&.dig("metrics", "build_time_without_llm_ms"), baseline&.dig("metrics", "build_time_without_llm_ms")) %> |
  | Cold build time (with LLM) | <%= format_ms(baseline&.dig("metrics", "build_time_with_llm_ms")) %> | <%= format_ms(latest&.dig("metrics", "build_time_with_llm_ms")) %> | <%= delta_ms(latest&.dig("metrics", "build_time_with_llm_ms"), baseline&.dig("metrics", "build_time_with_llm_ms")) %> |
  | Warm build time (with LLM) | <%= format_ms(baseline&.dig("metrics", "warm_build_time_with_llm_ms")) %> | <%= format_ms(latest&.dig("metrics", "warm_build_time_with_llm_ms")) %> | <%= delta_ms(latest&.dig("metrics", "warm_build_time_with_llm_ms"), baseline&.dig("metrics", "warm_build_time_with_llm_ms")) %> |
  | Incremental build time (with LLM) | <%= format_ms(baseline&.dig("metrics", "incremental_build_time_with_llm_ms")) %> | <%= format_ms(latest&.dig("metrics", "incremental_build_time_with_llm_ms")) %> | <%= delta_ms(latest&.dig("metrics", "incremental_build_time_with_llm_ms"), baseline&.dig("metrics", "incremental_build_time_with_llm_ms")) %> |
  | Index size (no LLM) | <%= format_bytes(baseline&.dig("metrics", "index_size_without_llm_bytes")) %> | <%= format_bytes(latest&.dig("metrics", "index_size_without_llm_bytes")) %> | <%= delta(latest&.dig("metrics", "index_size_without_llm_bytes"), baseline&.dig("metrics", "index_size_without_llm_bytes")) %> |
  | Index size (with LLM) | <%= format_bytes(baseline&.dig("metrics", "index_size_with_llm_bytes")) %> | <%= format_bytes(latest&.dig("metrics", "index_size_with_llm_bytes")) %> | <%= delta(latest&.dig("metrics", "index_size_with_llm_bytes"), baseline&.dig("metrics", "index_size_with_llm_bytes")) %> |
  | Document count | <%= baseline&.dig("metrics", "document_count") || "N/A" %> | <%= latest&.dig("metrics", "document_count") || "N/A" %> | — |
  | Embedding dimensions | <%= baseline&.dig("metrics", "embedding_dimensions") || "N/A" %> | <%= latest&.dig("metrics", "embedding_dimensions") || "N/A" %> | — |
  | Cache size | <%= format_bytes(baseline&.dig("metrics", "cache_size_bytes")) %> | <%= format_bytes(latest&.dig("metrics", "cache_size_bytes")) %> | <%= delta(latest&.dig("metrics", "cache_size_bytes"), baseline&.dig("metrics", "cache_size_bytes")) %> |
  | MiniSearch avg query | <%= format_ms(baseline&.dig("metrics", "search", "metrics", "minisearch", "avg_query_ms")) %> | <%= format_ms(latest&.dig("metrics", "search", "metrics", "minisearch", "avg_query_ms")) %> | <%= delta_ms(latest&.dig("metrics", "search", "metrics", "minisearch", "avg_query_ms"), baseline&.dig("metrics", "search", "metrics", "minisearch", "avg_query_ms")) %> |
  | ElasticLunr avg query | <%= format_ms(baseline&.dig("metrics", "search", "metrics", "elasticlunr", "avg_query_ms")) %> | <%= format_ms(latest&.dig("metrics", "search", "metrics", "elasticlunr", "avg_query_ms")) %> | <%= delta_ms(latest&.dig("metrics", "search", "metrics", "elasticlunr", "avg_query_ms"), baseline&.dig("metrics", "search", "metrics", "elasticlunr", "avg_query_ms")) %> |
  | Semantic cosine search | <%= format_ms(baseline&.dig("metrics", "search", "metrics", "semantic", "avg_query_ms")) %> | <%= format_ms(latest&.dig("metrics", "search", "metrics", "semantic", "avg_query_ms")) %> | <%= delta_ms(latest&.dig("metrics", "search", "metrics", "semantic", "avg_query_ms"), baseline&.dig("metrics", "search", "metrics", "semantic", "avg_query_ms")) %> |
  | Semantic query embedding | <%= format_ms(baseline&.dig("metrics", "query_embedding_avg_ms")) %> | <%= format_ms(latest&.dig("metrics", "query_embedding_avg_ms")) %> | <%= delta_ms(latest&.dig("metrics", "query_embedding_avg_ms"), baseline&.dig("metrics", "query_embedding_avg_ms")) %> |

  ## History

  <%= history_section(history, baseline) %>
ERB

output = ERB.new(template, trim_mode: "-").result(binding)
File.write(OUTPUT_PATH, output)
puts "Generated #{OUTPUT_PATH}"
