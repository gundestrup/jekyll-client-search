# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::DocumentBuilder, :unit do
  let(:builder) { described_class.new }

  def document(url: "/family/travel/greenland/", data: {}, content: "", date: nil)
    instance_double(Jekyll::Document, data: data, url: url, content: content, date: date)
  end

  it "builds a normalized search document" do
    source = document(
      data: {
        "title" => "Greenland &amp; Ice",
        "categories" => ["family", "travel", "travel", nil],
        "tags" => ["ice"],
        "excerpt" => "<p>A short excerpt.</p>"
      },
      content: <<~CONTENT
        <script>ignore()</script><style>.hidden {}</style>
        A {% imgflow "photo.jpg" %} story about **Greenland** and {{ page.secret }}.
      CONTENT
    )

    expect(builder.from_document(source)).to eq(
      "id" => "/family/travel/greenland/",
      "title" => "Greenland & Ice",
      "url" => "/family/travel/greenland/",
      "excerpt" => "A short excerpt.",
      "content" => "A story about Greenland and.",
      "categories" => %w[family travel],
      "tags" => ["ice"]
    )
  end

  it "includes an ISO date and timestamp when a document has a date" do
    result = builder.from_document(document(date: Time.utc(2026, 1, 2, 3, 4, 5)))

    expect(result).to include(
      "date" => "2026-01-02T03:04:05Z",
      "date_timestamp" => 1_767_323_045
    )
  end

  it "preserves a string date and omits an invalid timestamp" do
    result = builder.from_document(document(data: { "date" => "not-a-date" }))

    expect(result["date"]).to eq("not-a-date")
    expect(result).not_to have_key("date_timestamp")
  end

  it "returns nil when a document has no URL" do
    expect(builder.from_document(document(url: nil, data: { "title" => "Missing" }))).to be_nil
  end

  it "uses an Untitled fallback and empty arrays" do
    expect(builder.from_document(document(data: {}, content: "Body"))).to include(
      "title" => "Untitled",
      "categories" => [],
      "tags" => []
    )
  end
end
