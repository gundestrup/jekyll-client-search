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
end
