# frozen_string_literal: true

require "json"

fixture_root = __dir__
source_path = File.join(fixture_root, "site", "_site", "search-index-semantic.json")
baseline_path = File.join(fixture_root, "baseline", "search-index-baseline.json")
output_path = File.join(fixture_root, "baseline", "semantic-embeddings.json")

abort "Run the Ollama integration spec first: missing #{source_path}" unless File.exist?(source_path)

semantic = JSON.parse(File.read(source_path))
baseline = JSON.parse(File.read(baseline_path))
semantic_by_id = semantic.fetch("documents").to_h { |entry| [entry.fetch("id"), entry] }
baseline_ids = baseline.map { |entry| entry.fetch("id") }
abort "Semantic and baseline document IDs differ" unless semantic_by_id.keys.sort == baseline_ids.sort

fixture = {
  "model" => semantic.fetch("model"),
  "document_prefix" => semantic.fetch("document_prefix"),
  "query_prefix" => semantic.fetch("query_prefix"),
  "schema" => semantic.fetch("schema"),
  "document_embeddings" => baseline_ids.to_h do |id|
    [id, semantic_by_id.fetch(id).fetch("embedding")]
  end,
  "query_embeddings" => semantic.fetch("query_embeddings")
}
File.write(output_path, JSON.generate(fixture))
puts "Wrote #{output_path} (#{File.size(output_path)} bytes)"
