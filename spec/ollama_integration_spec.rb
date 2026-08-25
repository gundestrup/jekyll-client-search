# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "json"
require "tmpdir"

# Integration test that calls a real local Ollama server. Skipped
# automatically when the server is unreachable or the model is not
# installed. Run with:
#
#   OLLAMA_INTEGRATION=1 bundle exec rspec spec/ollama_integration_spec.rb
#
OLLAMA_MODEL = "embeddinggemma:300m"
OLLAMA_BASE_URL = "http://localhost:11434"

RSpec.describe Jekyll::ClientSearch::OllamaEmbeddingAdapter, :ollama_integration do
  before(:all) do
    skip "Set OLLAMA_INTEGRATION=1 to run Ollama integration tests" unless ENV["OLLAMA_INTEGRATION"]

    fixture_site = File.expand_path("fixtures/site", __dir__)
    arxiv_present = Dir.glob(File.join(fixture_site, "_posts", "*-arxiv-*.md")).any?
    unless arxiv_present
      skip "arXiv fixture posts not found — run `ruby spec/fixtures/download_arxiv.rb` first (see README.developer.md)"
    end

    uri = URI("#{OLLAMA_BASE_URL}/api/tags")
    response = Net::HTTP.get_response(uri)
    models = JSON.parse(response.body).fetch("models", []).map { |m| m["name"] }
    skip "Model #{OLLAMA_MODEL} not installed in Ollama" unless models.include?(OLLAMA_MODEL)
  rescue Errno::ECONNREFUSED, SocketError
    skip "Ollama server not reachable at #{OLLAMA_BASE_URL}"
  end

  # Path where the semantic index with real embeddings is saved for
  # the JS comparison test to load.
  let(:semantic_index_path) do
    File.expand_path("fixtures/site/_site/search-index-semantic.json", __dir__)
  end

  # Concept queries with expected results. These use synonyms and
  # paraphrases that don't appear literally in the target articles,
  # so lexical search would not rank them #1.
  let(:semantic_queries) do
    [
      # Concept queries (synonyms/paraphrases)
      {
        query: "preserving food without refrigeration",
        expectedInTop5: ["Fermentation in food processing"],
        description: "concept query → Fermentation article"
      },
      {
        query: "capturing images of the night sky",
        expectedInTop5: ["Astrophotography"],
        description: "concept query → Astrophotography article"
      },
      {
        query: "rope safety device for climbing",
        expectedInTop5: ["Belay device"],
        description: "concept query → Belay device article"
      },
      {
        query: "flatbread made with flour and water",
        expectedInTop5: %w[Bread Pasta],
        description: "concept query → Bread and Pasta articles"
      },
      # Exact-match queries (also embedded for the JS meta-tests)
      {
        query: "glacier",
        expectedInTop5: ["Glacier"],
        description: "exact match → Glacier article"
      },
      {
        query: "ice climbing",
        expectedInTop5: ["Ice climbing"],
        description: "exact match → Ice climbing article"
      },
      {
        query: "sourdough bread",
        expectedInTop5: %w[Sourdough Bread],
        description: "exact match → Sourdough and Bread articles"
      },
      {
        query: "fermentation",
        expectedInTop5: ["Fermentation in food processing"],
        description: "exact match → Fermentation article"
      },
      {
        query: "belay carabiner",
        expectedInTop5: ["Belay device"],
        description: "exact match → Belay device article"
      },
      {
        query: "arctic",
        expectedInTop5: ["Arctic Circle"],
        description: "exact match → Arctic Circle article"
      },
      {
        query: "aperture photography",
        expectedInTop5: ["Aperture"],
        description: "exact match → Aperture article"
      },
      {
        query: "camera lens",
        expectedInTop5: ["Camera lens"],
        description: "exact match → Camera lens article"
      }
    ]
  end

  it "generates a 768-dimensional embedding for a short text" do
    adapter = described_class.new(model: OLLAMA_MODEL, base_url: OLLAMA_BASE_URL)
    embedding = adapter.embed("Greenland travel journal ice fjords northern lights")
    expect(embedding).not_to be_nil
    expect(embedding.length).to eq(768)
    expect(embedding).to all(be_a(Float))
  end

  it "generates different embeddings for semantically different texts" do
    adapter = described_class.new(model: OLLAMA_MODEL, base_url: OLLAMA_BASE_URL)
    travel = adapter.embed("Traveling through Greenland with family, ice fjords and northern lights")
    pasta = adapter.embed("Making fresh pasta at home with flour, eggs, and a rolling pin")
    expect(travel).not_to be_nil
    expect(pasta).not_to be_nil

    # Cosine similarity between semantically different texts should be low
    dot = travel.each_with_index.sum { |v, i| v * pasta[i] }
    norm_travel = Math.sqrt(travel.sum { |v| v * v })
    norm_pasta = Math.sqrt(pasta.sum { |v| v * v })
    similarity = dot / (norm_travel * norm_pasta)
    expect(similarity).to be < 0.7
  end

  it "generates similar embeddings for semantically related texts" do
    adapter = described_class.new(model: OLLAMA_MODEL, base_url: OLLAMA_BASE_URL)
    text_a = adapter.embed("Ice climbing in the arctic, frozen waterfalls and glaciers")
    text_b = adapter.embed("Climbing ice walls in Greenland during winter")
    expect(text_a).not_to be_nil
    expect(text_b).not_to be_nil

    dot = text_a.each_with_index.sum { |v, i| v * text_b[i] }
    norm_a = Math.sqrt(text_a.sum { |v| v * v })
    norm_b = Math.sqrt(text_b.sum { |v| v * v })
    similarity = dot / (norm_a * norm_b)
    expect(similarity).to be > 0.4
  end

  it "builds a search index with embeddings via the generator" do
    Dir.mktmpdir("ollama-integration") do |dest|
      fixture_site = File.expand_path("fixtures/site", __dir__)
      config = Jekyll.configuration(
        "source" => fixture_site,
        "destination" => dest,
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "model" => OLLAMA_MODEL, "base_url" => OLLAMA_BASE_URL }
        },
        "quiet" => true
      )
      site = Jekyll::Site.new(config)
      site.process

      index_json = File.join(dest, "search-index.json")
      expect(File.exist?(index_json)).to be(true)

      documents = JSON.parse(File.read(index_json))
      with_embeddings = documents.select { |doc| doc["embedding"] }
      expect(with_embeddings.length).to be > 0
      with_embeddings.each do |doc|
        expect(doc["embedding"].length).to eq(768)
      end

      # Verify the cache file was written
      cache_file = File.join(fixture_site, ".jekyll-client-search-cache.json")
      expect(File.exist?(cache_file)).to be(true)
      FileUtils.rm_f(cache_file)
    end
  end

  it "reuses cached embeddings on second build without re-calling Ollama" do
    Dir.mktmpdir("ollama-cache-test") do |dest|
      fixture_site = File.expand_path("fixtures/site", __dir__)
      cache_file = File.join(fixture_site, ".jekyll-client-search-cache.json")

      # First build — populates the cache
      config1 = Jekyll.configuration(
        "source" => fixture_site, "destination" => dest,
        "client_search" => { "engine" => "semantic",
                             "embedding" => { "enabled" => true, "model" => OLLAMA_MODEL,
                                              "base_url" => OLLAMA_BASE_URL } },
        "quiet" => true
      )
      Jekyll::Site.new(config1).process
      first_json = File.read(File.join(dest, "search-index.json"))

      # Second build — should reuse cache (content unchanged)
      Dir.mktmpdir("ollama-cache-test-2") do |dest2|
        config2 = Jekyll.configuration(
          "source" => fixture_site, "destination" => dest2,
          "client_search" => { "engine" => "semantic",
                               "embedding" => { "enabled" => true, "model" => OLLAMA_MODEL,
                                                "base_url" => OLLAMA_BASE_URL } },
          "quiet" => true
        )
        Jekyll::Site.new(config2).process
        second_json = File.read(File.join(dest2, "search-index.json"))

        # The embeddings should be identical (cache hit)
        first_docs = JSON.parse(first_json).sort_by { |d| d["id"] }
        second_docs = JSON.parse(second_json).sort_by { |d| d["id"] }
        first_docs.each_with_index do |doc, i|
          expect(second_docs[i]["embedding"]).to eq(doc["embedding"])
        end
      end

      FileUtils.rm_f(cache_file)
    end
  end

  # --- Real semantic search quality test ---
  #
  # Builds the full 80-post index with real Ollama embeddings, embeds
  # concept queries (using synonyms/paraphrases that don't appear literally
  # in the target articles), and verifies that semantic search ranks the
  # correct articles in the top results.
  #
  # This is the test that proves the LLM/vector search adds real value:
  # it uses the actual generated embeddings and actual article content,
  # not hand-crafted vectors.
  #
  # The built index + query embeddings are saved to a gitignored location
  # so the JS comparison test can verify the browser-side adapter produces
  # the same ranking.

  it "semantic search ranks correct articles for concept queries using real embeddings" do
    fixture_site = File.expand_path("fixtures/site", __dir__)
    cache_file = File.join(fixture_site, ".jekyll-client-search-cache.json")

    Dir.mktmpdir("ollama-semantic-quality") do |dest|
      config = Jekyll.configuration(
        "source" => fixture_site,
        "destination" => dest,
        "client_search" => {
          "engine" => "semantic",
          "embedding" => { "enabled" => true, "model" => OLLAMA_MODEL, "base_url" => OLLAMA_BASE_URL }
        },
        "quiet" => true
      )
      site = Jekyll::Site.new(config)
      site.process

      index_json = File.join(dest, "search-index.json")
      documents = JSON.parse(File.read(index_json))
      adapter = described_class.new(model: OLLAMA_MODEL, base_url: OLLAMA_BASE_URL)
      settings = Jekyll::ClientSearch::Configuration.new(site)

      # Pre-compute query embeddings and save for JS test
      query_embeddings = {}
      semantic_queries.each do |sq|
        query_text = "#{settings.embedding_query_prefix}#{sq[:query]}"
        query_embeddings[sq[:query]] = adapter.embed(query_text)
      end

      # Save the index + query embeddings for the JS comparison test
      FileUtils.mkdir_p(File.dirname(semantic_index_path))
      File.write(semantic_index_path, JSON.generate({
                                                      "model" => OLLAMA_MODEL,
                                                      "document_prefix" => settings.embedding_document_prefix,
                                                      "query_prefix" => settings.embedding_query_prefix,
                                                      "schema" => 2,
                                                      "documents" => documents,
                                                      "query_embeddings" => query_embeddings
                                                    }))

      # Compute cosine similarity ranking for each concept query
      semantic_queries.each do |sq|
        query_embedding = query_embeddings[sq[:query]]
        ranked = documents.filter_map do |doc|
          next unless doc["embedding"]

          doc_embedding = doc["embedding"]
          dot = query_embedding.each_with_index.sum { |v, i| v * doc_embedding[i] }
          norm_q = Math.sqrt(query_embedding.sum { |v| v * v })
          norm_d = Math.sqrt(doc_embedding.sum { |v| v * v })
          similarity = norm_q > 0 && norm_d > 0 ? dot / (norm_q * norm_d) : 0

          { "title" => doc["title"], "similarity" => similarity }
        end
        ranked.sort_by! { |r| -r["similarity"] }

        top5_titles = ranked.first(5).map { |r| r["title"] }

        sq[:expectedInTop5].each do |expected|
          expect(top5_titles).to include(expected),
                                 "Query '#{sq[:query]}' should rank '#{expected}' in top 5 — " \
                                 "got: #{top5_titles.inspect}"
        end
      end

      FileUtils.rm_f(cache_file)
    end
  end
end
