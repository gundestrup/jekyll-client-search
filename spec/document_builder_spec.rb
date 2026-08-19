# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ElasticlunrSearch::DocumentBuilder do
  let(:builder) { described_class.new }
  let(:document) do
    instance_double(
      Jekyll::Document,
      data: {
        "title" => "Greenland",
        "categories" => ["family", "travel"],
        "tags" => ["ice"],
        "excerpt" => "<p>A short excerpt.</p>"
      },
      url: "/family/travel/greenland/",
      content: "A {% imgflow \"photo.jpg\" %} story about **Greenland**."
    )
  end

  it "builds an Elasticlunr document with searchable content" do
    expect(builder.from_document(document)).to eq(
      "id" => "/family/travel/greenland/",
      "title" => "Greenland",
      "url" => "/family/travel/greenland/",
      "excerpt" => "A short excerpt.",
      "content" => "A story about Greenland.",
      "categories" => ["family", "travel"],
      "tags" => ["ice"]
    )
  end
end
