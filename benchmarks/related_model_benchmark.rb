#!/usr/bin/env ruby
# frozen_string_literal: true

# Related-article embedding model comparison.
#
# Embeds a real site's documents with each Ollama model — timed, so the run
# doubles as the embedding speed benchmark — then runs the real
# RelatedAnalyzer per model and reports how the related-article output
# differs from the baseline model (embeddinggemma-2:570m).
#
# Usage:
#   bundle exec ruby benchmarks/related_model_benchmark.rb ../gundestrup.dk
#
# Optional environment (same as embedding_model_benchmark.rb, plus):
#   BASELINE_MODEL=embeddinggemma-2:570m   comparison baseline
#   RELATED_MIN_SIMILARITY=0.55          semantic cutoff (site default)
#   RELATED_MAX_ITEMS=5                  related entries per document
#
# Raw embeddings are cached under benchmarks/.related-embeddings/ so re-runs
# skip the expensive Ollama calls; delete the cache to re-embed.

require "benchmark"
require "fileutils"
require "json"
require "time"
require_relative "embedding_model_benchmark"

CACHE_DIR = File.join(__dir__, ".related-embeddings")
RELATED_RESULTS_PATH = File.join(__dir__, "related-model-results.json")
BASELINE = ENV["BASELINE_MODEL"] || "embeddinggemma-2:570m"
RELATED_CONFIG = {
  "enabled" => true,
  "minimum_similarity" => (ENV["RELATED_MIN_SIMILARITY"] || 0.55).to_f,
  "max_items" => ENV["RELATED_MAX_ITEMS"] ? ENV["RELATED_MAX_ITEMS"].to_i : 5
}.freeze

def embedding_cache_path(model)
  File.join(CACHE_DIR, "#{model.gsub(/[^a-z0-9.-]/i, "_")}.json")
end

# Embeds every document (timed) or loads cached vectors. Returns per-call
# milliseconds, or nil when all embeddings came from cache.
def embed_documents(model, documents)
  cache_path = embedding_cache_path(model)
  stored = File.exist?(cache_path) ? JSON.parse(File.read(cache_path)) : {}
  adapter = Jekyll::ClientSearch::OllamaEmbeddingAdapter.new(model: model, base_url: BASE_URL)
  prefix = PREFIXES.fetch(model.split(":").first, {}).fetch("document", "")

  times = []
  documents.each do |document|
    document["embedding"] = stored[document["id"]]
    next if document["embedding"]

    text = "#{prefix}#{[document["title"], document["excerpt"], document["content"]].compact.join(" ")}"
    elapsed = Benchmark.realtime { document["embedding"] = adapter.embed(text) }
    times << (elapsed * 1000).round(1)
    stored[document["id"]] = document["embedding"]
  end
  return nil if times.empty?

  FileUtils.mkdir_p(CACHE_DIR)
  File.write(cache_path, JSON.generate(stored))
  times
end

def timing_stats(times)
  return nil unless times

  sorted = times.sort
  {
    "total_ms" => times.sum.round,
    "mean_ms" => (times.sum / times.length).round(1),
    "median_ms" => percentile(sorted, 0.5),
    "p95_ms" => percentile(sorted, 0.95),
    "first_call_ms" => times.first
  }
end

def relation_metrics(relations)
  edges = relations.values.flatten
  semantic = edges.select { |edge| edge.fetch("reasons", []).include?("semantic-similarity") }
  scores = semantic.filter_map { |edge| edge["semantic_similarity"] }.sort
  {
    "documents_with_relations" => relations.count { |_, list| list.any? },
    "total_relations" => edges.length,
    "semantic_relations" => semantic.length,
    "semantic_score_median" => percentile(scores, 0.5),
    "semantic_score_min" => scores.first,
    "semantic_score_max" => scores.last
  }
end

# Mean count of shared IDs between the baseline's and the model's related
# list per document (lists are already capped at max_items).
def overlap_with(baseline_relations, relations)
  per_document = relations.filter_map do |id, list|
    base_ids = (baseline_relations[id] || []).map { |edge| edge["id"] }
    next if base_ids.empty? && list.empty?

    model_ids = list.map { |edge| edge["id"] }
    (base_ids & model_ids).length
  end
  (per_document.sum.to_f / per_document.length).round(3)
end

def differing_examples(baseline_relations, relations, limit = 5)
  relations.filter_map do |id, list|
    base_ids = (baseline_relations[id] || []).map { |edge| edge["id"] }
    model_ids = list.map { |edge| edge["id"] }
    added = model_ids - base_ids
    removed = base_ids - model_ids
    next if added.empty? && removed.empty?

    { "id" => id, "added" => added, "removed" => removed }
  end.first(limit)
end

if __FILE__ == $PROGRAM_NAME
  installed = available_models(BASE_URL)
  abort "Ollama is not reachable at #{BASE_URL}" unless installed

  puts "Reading site from #{SITE_DIR}..."
  documents = load_documents(SITE_DIR)
  documents = documents.first(LIMIT) if LIMIT
  configuration = Jekyll::ClientSearch::RelatedConfiguration.new(RELATED_CONFIG)
  analyzer = Jekyll::ClientSearch::RelatedAnalyzer.new(configuration)
  puts "#{documents.length} documents, related config: #{RELATED_CONFIG.inspect}"

  per_model = {}
  MODELS.each do |model|
    unless installed.include?(model)
      puts "  #{model}: skipped (not pulled)"
      next
    end

    print "  #{model}: embedding... "
    times = embed_documents(model, documents)
    puts times ? "#{times.sum.round}ms" : "cached"

    result = analyzer.analyze(documents)
    relations = result.fetch("relations")
    # Full relation lists are large — keep them next to the embedding cache
    # (gitignored); the JSON history stores metrics and example diffs only.
    FileUtils.mkdir_p(CACHE_DIR)
    File.write(embedding_cache_path("relations-#{model}"), JSON.generate(relations))
    per_model[model] = {
      "timing" => timing_stats(times),
      "metrics" => relation_metrics(relations),
      "relations" => relations
    }
  end

  abort "Baseline #{BASELINE} was not measured" unless per_model[BASELINE]

  baseline_relations = per_model.fetch(BASELINE).fetch("relations")
  per_model.each do |model, data|
    next if model == BASELINE

    data["vs_baseline"] = {
      "mean_shared_related_ids" => overlap_with(baseline_relations, data.fetch("relations")),
      "examples" => differing_examples(baseline_relations, data.fetch("relations"))
    }
  end

  puts "\nPer-model summary"
  per_model.each do |model, data|
    timing = data["timing"] || {}
    metrics = data["metrics"]
    puts "  #{model}"
    puts "    embed: total #{timing["total_ms"]}ms, mean #{timing["mean_ms"]}ms, " \
         "p95 #{timing["p95_ms"]}ms" if data["timing"]
    puts "    relations: #{metrics["total_relations"]} total, " \
         "#{metrics["semantic_relations"]} semantic-driven, " \
         "#{metrics["documents_with_relations"]}/#{documents.length} docs linked"
    comparison = data["vs_baseline"]
    puts "    vs #{BASELINE}: mean #{comparison["mean_shared_related_ids"]} shared IDs/doc" if comparison
  end

  history = File.exist?(RELATED_RESULTS_PATH) ? JSON.parse(File.read(RELATED_RESULTS_PATH)) : { "history" => [] }
  history["history"] << {
    "timestamp" => Time.now.utc.iso8601,
    "site" => SITE_DIR,
    "related_config" => RELATED_CONFIG,
    "results" => per_model.transform_values { |data| data.except("relations") }
  }
  File.write(RELATED_RESULTS_PATH, JSON.pretty_generate(history))
  puts "\nResults appended to #{RELATED_RESULTS_PATH}"
end
