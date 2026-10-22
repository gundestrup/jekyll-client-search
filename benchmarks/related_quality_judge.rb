#!/usr/bin/env ruby
# frozen_string_literal: true

# Judged relevance for related-article benchmark output.
#
# `related_model_benchmark.rb` measures agreement between models, not whether
# a suggested article is actually relevant. This script fixes that: for every
# document it presents the deduplicated union of all models' related picks to
# a judge model — blind, alphabetical order, no model names — and scores each
# candidate 0 (unrelated), 1 (somewhat related) or 2 (clearly related).
# Per-model precision@5 falls out of those judgments.
#
# Usage:
#   bundle exec ruby benchmarks/related_quality_judge.rb ../gundestrup.dk
#
# Optional environment:
#   JUDGE_MODEL=gpt-oss:120b-cloud   Ollama model used as judge
#   OLLAMA_BASE_URL=...              default http://localhost:11434
#
# Requires relations-<model>.json files from a related_model_benchmark.rb run.
# Judgments are cached under benchmarks/.related-embeddings/ so re-runs are
# cheap; delete the judge cache to re-judge.

require "json"
require "net/http"
require "uri"
require "fileutils"
require_relative "embedding_model_benchmark"

JUDGE_MODEL = ENV["JUDGE_MODEL"] || "gpt-oss:120b-cloud"
CACHE_DIR = File.join(__dir__, ".related-embeddings")
JUDGE_CACHE = File.join(CACHE_DIR, "judge-#{JUDGE_MODEL.gsub(/[^a-z0-9.-]/i, '_')}.json")
EXCERPT_CHARS = 300

def judge_prompt(source, candidates)
  listing = candidates.each_with_index.map do |cand, i|
    "#{i + 1}. \"#{cand['title']}\" — #{cand['excerpt'].to_s[0, EXCERPT_CHARS]}"
  end.join("\n")
  <<~PROMPT
    You are rating related-article suggestions for a personal website.
    Source article: "#{source['title']}" — #{source['excerpt'].to_s[0, EXCERPT_CHARS]}

    Candidate articles:
    #{listing}

    For each candidate, rate topical relatedness to the source article:
    2 = clearly related (same topic, event, person, or place)
    1 = somewhat related (shares a theme, would interest the same reader)
    0 = unrelated

    Reply with JSON only: {"scores": [<n1>, <n2>, ...]} with one integer
    per candidate, in order. No other text.
  PROMPT
end

def judge_batch(base_url, source, candidates)
  # Acceptable risk: base_url defaults to http://localhost:11434 (local Ollama).
  uri = URI("#{base_url}/api/generate") # nosemgrep: problem-based-packs.insecure-transport.ruby-stdlib.net-http-request
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 180
  response = http.post(uri, JSON.generate(
                              "model" => JUDGE_MODEL, "prompt" => judge_prompt(source, candidates),
                              "stream" => false, "think" => false, "format" => "json"
                            ))
  scores = JSON.parse(JSON.parse(response.body).fetch("response")).fetch("scores")
  scores.length == candidates.length ? scores : nil
rescue StandardError
  nil
end

if __FILE__ == $PROGRAM_NAME
  abort "Ollama is not reachable at #{BASE_URL}" unless available_models(BASE_URL)

  relation_files = Dir.glob(File.join(CACHE_DIR, "relations-*.json"))
  abort "No relations-*.json found; run related_model_benchmark.rb first" if relation_files.empty?

  puts "Reading site from #{SITE_DIR}..."
  documents = load_documents(SITE_DIR)
  documents = documents.first(LIMIT) if LIMIT
  by_id = documents.to_h { |document| [document["id"], document] }

  relations = relation_files.to_h do |path|
    model = File.basename(path, ".json").sub("relations-", "").tr("_", ":")
    model = model.sub("nomic-embed:text", "nomic-embed-text")
                 .sub("voyage-4:nano", "voyage-4-nano").sub("bge:m3", "bge-m3")
                 .sub("mxbai-embed:large", "mxbai-embed-large")
                 .sub("snowflake-arctic:embed2", "snowflake-arctic-embed2")
    [model, JSON.parse(File.read(path))]
  end
  puts "#{documents.length} documents, #{relations.length} models, judge: #{JUDGE_MODEL}"

  judged = File.exist?(JUDGE_CACHE) ? JSON.parse(File.read(JUDGE_CACHE)) : {}
  documents.each_with_index do |document, index|
    candidate_ids = relations.values.filter_map { |r| r[document["id"]] }
                             .flatten.map { |edge| edge["id"] }.uniq.sort
                             .select { |id| by_id[id] }
    entry = judged[document["id"]] ||= {}
    missing_ids = candidate_ids - entry.keys
    next if missing_ids.empty?

    candidates = missing_ids.map { |id| by_id[id] }
    scores = judge_batch(BASE_URL, document, candidates)
    unless scores
      puts "  [#{index + 1}/#{documents.length}] #{document['id']}: judge failed, retrying next run"
      next
    end

    entry.merge!(missing_ids.zip(scores).to_h)
    File.write(JUDGE_CACHE, JSON.generate(judged))
    print "." if (index % 10).zero?
  end

  puts "\n\nJudged precision@5 (mean judge score, max 2.00)"
  relations.each do |model, rels|
    per_doc = rels.filter_map do |id, list|
      next if list.empty?

      scores = list.filter_map { |edge| judged.dig(id, edge["id"]) }
      scores.empty? ? nil : scores.sum.to_f / scores.length
    end
    mean = per_doc.sum / per_doc.length
    puts "  #{model.ljust(28)} #{(mean / 2 * 100).round(1).to_s.rjust(6)} (mean #{mean.round(3)})"
  end
end
