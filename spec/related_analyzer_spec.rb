# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::RelatedAnalyzer, :unit do
  let(:configuration) do
    Jekyll::ClientSearch::RelatedConfiguration.new(
      "enabled" => true,
      "minimum_similarity" => 0.75
    )
  end

  let(:documents) do
    [
      {
        "id" => "/diabetes/",
        "title" => "Diabetes",
        "url" => "/diabetes/",
        "categories" => ["medicine/endocrinology"],
        "tags" => %w[insulin pancreas],
        "embedding" => [1.0, 0.0],
        "date" => "2026-01-01T00:00:00+00:00",
        "date_timestamp" => 1
      },
      {
        "id" => "/pancreatic-cancer/",
        "title" => "Pancreatic cancer",
        "url" => "/pancreatic-cancer/",
        "categories" => ["medicine/oncology"],
        "tags" => %w[pancreas cancer],
        "embedding" => [0.8, 0.6],
        "date" => "2026-02-01T00:00:00+00:00",
        "date_timestamp" => 2
      },
      {
        "id" => "/oncology/",
        "title" => "Oncology",
        "url" => "/oncology/",
        "categories" => ["medicine/oncology"],
        "tags" => ["cancer"],
        "embedding" => [0.7, 0.7],
        "date" => "2026-03-01T00:00:00+00:00",
        "date_timestamp" => 3
      },
      {
        "id" => "/bread/",
        "title" => "Bread",
        "url" => "/bread/",
        "categories" => ["food"],
        "tags" => ["baking"],
        "embedding" => [0.0, 1.0],
        "date" => "2026-04-01T00:00:00+00:00",
        "date_timestamp" => 4
      }
    ]
  end

  def semantic_only_config
    Jekyll::ClientSearch::RelatedConfiguration.new(
      "enabled" => true,
      "semantic" => true,
      "minimum_similarity" => 0.1,
      "shared_tags" => false,
      "same_category" => false,
      "include_parent_domains" => false
    )
  end

  def doc(id, title, embedding)
    {
      "id" => id,
      "title" => title,
      "url" => id,
      "categories" => [],
      "tags" => [],
      "embedding" => embedding,
      "date" => "2026-01-01T00:00:00+00:00",
      "date_timestamp" => 1
    }
  end

  it "combines semantic similarity with shared tags and parent domains" do
    result = described_class.new(configuration).analyze(documents)
    diabetes_relations = result.fetch("relations").fetch("/diabetes/")

    expect(diabetes_relations.map { |relation| relation["id"] })
      .to contain_exactly("/pancreatic-cancer/", "/oncology/")
    pancreatic = diabetes_relations.find { |relation| relation["id"] == "/pancreatic-cancer/" }
    expect(pancreatic["shared_tags"]).to eq(["pancreas"])
    expect(pancreatic["shared_domains"]).to eq(["medicine"])
    expect(pancreatic["reasons"]).to include("semantic-similarity", "shared-domain: medicine", "shared-tag: pancreas")
    expect(pancreatic["date_timestamp"]).to eq(2)
  end

  it "uses the similarity cutoff without imposing a fixed relation count" do
    result = described_class.new(configuration).analyze(documents)
    relations = result.fetch("relations").fetch("/bread/")

    expect(relations).to be_empty
    expect(result.fetch("relations").values).to all(be_an(Array))
  end

  it "supports disabling individual metadata relation sources" do
    config = Jekyll::ClientSearch::RelatedConfiguration.new(
      "enabled" => true,
      "shared_tags" => false,
      "include_parent_domains" => false,
      "minimum_similarity" => 0.99
    )
    result = described_class.new(config).analyze(documents)

    expect(result.fetch("relations").fetch("/diabetes/")).to be_empty
  end

  it "supports an explicit optional maximum after applying the cutoff" do
    config = Jekyll::ClientSearch::RelatedConfiguration.new(
      "enabled" => true,
      "minimum_similarity" => -1,
      "max_items" => 1
    )
    relations = described_class.new(config).analyze(documents).fetch("relations").fetch("/diabetes/")

    expect(relations.length).to eq(1)
  end

  it "returns all relations when max_items is nil" do
    config = Jekyll::ClientSearch::RelatedConfiguration.new(
      "enabled" => true,
      "minimum_similarity" => -1,
      "max_items" => nil
    )
    relations = described_class.new(config).analyze(documents).fetch("relations").fetch("/diabetes/")
    expect(relations.length).to be > 1
  end

  it "ignores invalid, mismatched, and zero-length vectors" do
    config = Jekyll::ClientSearch::RelatedConfiguration.new(
      "enabled" => true,
      "minimum_similarity" => 0.1,
      "shared_tags" => false,
      "same_category" => false,
      "include_parent_domains" => false
    )
    invalid_documents = [
      documents.first.merge("embedding" => nil),
      documents[1].merge("embedding" => [1.0, 0.0, 0.0]),
      documents[2].merge("embedding" => [0.0, 0.0]),
      documents[3].merge("embedding" => [Float::NAN, 0.0]),
      documents[2].merge("id" => "/zero-copy/", "embedding" => [0.0, 0.0]),
      documents[3].merge("id" => "/empty/", "embedding" => [])
    ]

    result = described_class.new(config).analyze(invalid_documents)

    expect(result.fetch("relations").values).to all(be_empty)
  end

  it "computes semantic similarity for documents with embeddings" do
    config = semantic_only_config
    embedded_documents = [
      doc("/alpha/", "Alpha", [1.0, 0.0, 0.0]),
      doc("/beta/", "Beta", [0.0, 1.0, 0.0]),
      doc("/gamma/", "Gamma", [1.0, 1.0, 0.0])
    ]

    result = described_class.new(config).analyze(embedded_documents)
    alpha_relations = result.fetch("relations").fetch("/alpha/")

    # Alpha and Beta are orthogonal (similarity 0) — excluded by cutoff 0.1
    # Alpha and Gamma are 45° apart (similarity ~0.707) — included
    expect(alpha_relations.map { |relation| relation["id"] }).to contain_exactly("/gamma/")
    gamma = alpha_relations.find { |relation| relation["id"] == "/gamma/" }
    expect(gamma["reasons"]).to include("semantic-similarity")
    expect(gamma["semantic_similarity"]).to eq((1.0 / Math.sqrt(2)).round(6))
    expect(gamma["score"]).to eq(gamma["semantic_similarity"])
  end

  it "skips semantic relation when vectors have different lengths" do
    documents = [
      doc("/alpha/", "Alpha", [1.0, 0.0]),
      doc("/beta/", "Beta", [1.0, 0.0, 0.0])
    ]

    result = described_class.new(semantic_only_config).analyze(documents)
    expect(result.fetch("relations").values).to all(be_empty)
  end

  it "skips semantic relation when embedding is not an array" do
    documents = [
      doc("/alpha/", "Alpha", "not a vector"),
      doc("/beta/", "Beta", [1.0, 0.0])
    ]

    result = described_class.new(semantic_only_config).analyze(documents)
    expect(result.fetch("relations").values).to all(be_empty)
  end

  it "skips semantic relation when embedding is empty array" do
    documents = [
      doc("/alpha/", "Alpha", []),
      doc("/beta/", "Beta", [1.0, 0.0])
    ]

    result = described_class.new(semantic_only_config).analyze(documents)
    expect(result.fetch("relations").values).to all(be_empty)
  end

  it "skips semantic relation when embedding contains non-numeric values" do
    documents = [
      doc("/alpha/", "Alpha", %w[a b]),
      doc("/beta/", "Beta", [1.0, 0.0])
    ]

    result = described_class.new(semantic_only_config).analyze(documents)
    expect(result.fetch("relations").values).to all(be_empty)
  end

  it "still matches valid pair when one document has invalid embedding" do
    documents = [
      doc("/alpha/", "Alpha", [1.0, 0.0, 0.0]),
      doc("/beta/", "Beta", "not a vector"),
      doc("/gamma/", "Gamma", [1.0, 1.0, 0.0])
    ]

    result = described_class.new(semantic_only_config).analyze(documents)
    alpha_relations = result.fetch("relations").fetch("/alpha/")
    # Alpha-Gamma should still match; Beta is skipped due to invalid embedding
    expect(alpha_relations.map { |relation| relation["id"] }).to contain_exactly("/gamma/")
  end
end
