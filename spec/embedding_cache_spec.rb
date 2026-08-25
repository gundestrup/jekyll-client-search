# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"
require "yaml"
require_relative "support/mock_embedding_adapter"

# Comprehensive tests for the embedding + cache system using a mock
# embedding adapter (no real Ollama server needed). These tests verify:
#
# 1. Config with LLM (embeddings enabled) → embedding fields added to JSON
# 2. Config without LLM (embeddings disabled) → no embedding fields
# 3. Changed file content → only that file gets re-embedded
# 4. New file added → only the new file gets embedded
# 5. Deleted file → pruned from cache
# 6. Restart scenario (rebuild with existing cache) → unchanged files reuse cache
# 7. Mixed scenario — changed + new + deleted + unchanged
RSpec.describe Jekyll::ClientSearch::Generator, :system do
  def create_site(source_dir, posts, embedding_config = nil)
    FileUtils.mkdir_p(File.join(source_dir, "_posts"))

    posts.each do |post|
      File.write(File.join(source_dir, "_posts", post[:filename]), <<~MD)
        ---
        title: "#{post[:title]}"
        ---
        #{post[:content]}
      MD
    end

    config = { "plugins" => ["jekyll-client-search"], "client_search" => { "engine" => "semantic" } }
    config["client_search"]["embedding"] = embedding_config if embedding_config

    File.write(File.join(source_dir, "_config.yml"), YAML.dump(config))
  end

  def build_site(source_dir, mock_adapter = nil)
    dest = Dir.mktmpdir("embedding-test-dest")
    config = Jekyll.configuration(
      "source" => source_dir,
      "destination" => dest,
      "quiet" => true
    )

    stub_embedding_adapter(mock_adapter) if mock_adapter

    site = Jekyll::Site.new(config)
    site.process

    index_json = File.join(dest, "search-index.json")
    documents = File.exist?(index_json) ? JSON.parse(File.read(index_json)) : []

    { dest: dest, documents: documents }
  rescue StandardError
    FileUtils.remove_entry(dest) if dest && Dir.exist?(dest)
    raise
  end

  def stub_embedding_adapter(mock_adapter)
    allow(Jekyll::ClientSearch::Generator).to receive(:new).and_wrap_original do |method, *args|
      instance = method.call(*args)
      allow(instance).to receive(:build_embedding_adapter).and_return(mock_adapter)
      instance
    end
  end

  def cleanup(dest)
    FileUtils.remove_entry(dest) if dest && Dir.exist?(dest)
  end

  def rewrite_config(source_dir, embedding_config)
    config = { "plugins" => ["jekyll-client-search"], "client_search" => { "engine" => "semantic" } }
    config["client_search"]["embedding"] = embedding_config if embedding_config
    File.write(File.join(source_dir, "_config.yml"), YAML.dump(config))
  end

  let(:embedding_config) do
    {
      "enabled" => true,
      "model" => "test-model",
      "base_url" => "http://localhost:1",
      "query_embedder" => { "type" => "none" }
    }
  end

  # --- Test 1: Config with LLM (embeddings enabled) ---
  #
  it "adds embedding fields to documents when embeddings are enabled" do
    Dir.mktmpdir("embedding-enabled") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers and ice." },
                    { filename: "2026-01-02-post-b.md", title: "Post B", content: "Content about pasta and cooking." }
                  ], embedding_config.merge("model" => "embeddinggemma:300m"))

      mock = MockEmbeddingAdapter.new
      result = build_site(source, mock)

      begin
        with_embeddings = result[:documents].select { |d| d["embedding"] }
        expect(with_embeddings.length).to eq(2)
        expect(mock.embedded_texts.length).to eq(2)
        expect(mock.embedded_texts).to all(start_with("title: none | text: "))
      ensure
        cleanup(result[:dest])
      end
    end
  end

  # --- Test 2: Config without LLM (embeddings disabled) ---
  #
  it "does not add embedding fields when embeddings are disabled" do
    Dir.mktmpdir("embedding-disabled") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ])

      result = build_site(source)

      begin
        with_embeddings = result[:documents].select { |d| d["embedding"] }
        expect(with_embeddings.length).to eq(0)
      ensure
        cleanup(result[:dest])
      end
    end
  end

  it "fails the build when embedding generation fails by default" do
    Dir.mktmpdir("embedding-failure") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ], embedding_config)

      failing_adapter = instance_double(Jekyll::ClientSearch::OllamaEmbeddingAdapter, embed: nil)
      expect { build_site(source, failing_adapter) }
        .to raise_error(Jekyll::Errors::FatalException, /embedding generation failed/)
    end
  end

  it "can continue without an embedding when fail_on_error is disabled" do
    Dir.mktmpdir("embedding-warning") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ], embedding_config.merge("fail_on_error" => false))

      failing_adapter = instance_double(Jekyll::ClientSearch::OllamaEmbeddingAdapter, embed: nil)
      result = build_site(source, failing_adapter)
      begin
        expect(result[:documents].first).not_to have_key("embedding")
      ensure
        cleanup(result[:dest])
      end
    end
  end

  it "re-embeds all documents when the embedding model changes" do
    Dir.mktmpdir("embedding-model-change") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ], embedding_config.merge("model" => "model-a"))

      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        expect(mock1.embedded_texts.length).to eq(1)
        mock2 = MockEmbeddingAdapter.new
        result2 = build_site(source, mock2)

        begin
          expect(mock2.embedded_texts.length).to eq(0)
          rewrite_config(source, embedding_config.merge("model" => "model-b"))
          mock3 = MockEmbeddingAdapter.new
          result3 = build_site(source, mock3)

          begin
            expect(mock3.embedded_texts.length).to eq(1)
            expect(result3[:documents].first["embedding"]).not_to be_nil
          ensure
            cleanup(result3[:dest])
          end
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 3: Changed file content → only that file gets re-embedded ---
  #
  it "re-embeds only the changed file on second build" do
    Dir.mktmpdir("embedding-changed") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers and ice." },
                    { filename: "2026-01-02-post-b.md", title: "Post B", content: "Content about pasta and cooking." }
                  ], embedding_config)

      # First build — both files get embedded
      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        expect(mock1.embedded_texts.length).to eq(2), "first build should embed both files"

        # Change post A's content
        File.write(File.join(source, "_posts", "2026-01-01-post-a.md"), <<~MD)
          ---
          title: "Post A"
          ---
          Content about glaciers and ice and NEW information.
        MD

        # Second build — only post A should be re-embedded
        mock2 = MockEmbeddingAdapter.new
        result2 = build_site(source, mock2)

        begin
          expect(mock2.embedded_texts.length).to eq(1), "second build should only embed the changed file"
          expect(mock2.embedded_texts.first).to include("NEW information")
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 4: New file added → only the new file gets embedded ---
  #
  it "embeds only the new file when a file is added" do
    Dir.mktmpdir("embedding-added") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ], embedding_config)

      # First build — one file
      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        expect(mock1.embedded_texts.length).to eq(1)

        # Add a new post
        File.write(File.join(source, "_posts", "2026-01-02-post-b.md"), <<~MD)
          ---
          title: "Post B"
          ---
          Content about pasta and cooking.
        MD

        # Second build — only the new file should be embedded
        mock2 = MockEmbeddingAdapter.new
        result2 = build_site(source, mock2)

        begin
          expect(mock2.embedded_texts.length).to eq(1), "second build should only embed the new file"
          expect(mock2.embedded_texts.first).to include("pasta")
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 5: Deleted file → pruned from cache ---
  #
  it "prunes deleted files from the cache" do
    Dir.mktmpdir("embedding-deleted") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." },
                    { filename: "2026-01-02-post-b.md", title: "Post B", content: "Content about pasta." }
                  ], embedding_config)

      # First build
      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        cache_file = File.join(source, ".jekyll-client-search-cache.json")
        expect(File.exist?(cache_file)).to be(true)
        cache_data = JSON.parse(File.read(cache_file))
        expect(cache_data.keys.length).to eq(2)

        # Delete post B
        File.delete(File.join(source, "_posts", "2026-01-02-post-b.md"))

        # Second build
        mock2 = MockEmbeddingAdapter.new
        result2 = build_site(source, mock2)

        begin
          cache_data2 = JSON.parse(File.read(cache_file))
          expect(cache_data2.keys.length).to eq(1), "deleted file should be pruned from cache"
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 6: Restart scenario (rebuild with existing cache) ---
  #
  it "reuses all cached embeddings on restart with no changes" do
    Dir.mktmpdir("embedding-restart") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." },
                    { filename: "2026-01-02-post-b.md", title: "Post B", content: "Content about pasta." }
                  ], embedding_config)

      # First build
      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        expect(mock1.embedded_texts.length).to eq(2)
        first_embeddings = result1[:documents].sort_by { |d| d["id"] }.map { |d| d["embedding"] }

        # Second build — no changes, simulating a server restart
        mock2 = MockEmbeddingAdapter.new
        result2 = build_site(source, mock2)

        begin
          expect(mock2.embedded_texts.length).to eq(0), "restart with no changes should not call the adapter"

          second_embeddings = result2[:documents].sort_by { |d| d["id"] }.map { |d| d["embedding"] }
          expect(second_embeddings).to eq(first_embeddings), "embeddings should be identical from cache"
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 7: Mixed scenario — changed + new + deleted + unchanged ---
  #
  it "handles mixed changes: re-embeds changed, embeds new, prunes deleted, caches unchanged" do
    Dir.mktmpdir("embedding-mixed") do |source|
      create_site(source, [
                    { filename: "2026-01-01-unchanged.md", title: "Unchanged", content: "Stays the same." },
                    { filename: "2026-01-02-changed.md", title: "Changed", content: "Original content." },
                    { filename: "2026-01-03-deleted.md", title: "Deleted", content: "Will be removed." }
                  ], embedding_config)

      # First build — 3 files
      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        expect(mock1.embedded_texts.length).to eq(3)

        # Change one, add one, delete one
        File.write(File.join(source, "_posts", "2026-01-02-changed.md"), <<~MD)
          ---
          title: "Changed"
          ---
          Modified content that is different.
        MD
        File.write(File.join(source, "_posts", "2026-01-04-new.md"), <<~MD)
          ---
          title: "New"
          ---
          Brand new content.
        MD
        File.delete(File.join(source, "_posts", "2026-01-03-deleted.md"))

        # Second build
        mock2 = MockEmbeddingAdapter.new
        result2 = build_site(source, mock2)

        begin
          # Should embed only the changed file + the new file (2 calls)
          expect(mock2.embedded_texts.length).to eq(2), "should embed changed + new, not unchanged or deleted"

          # Verify the right texts were embedded
          embedded_content = mock2.embedded_texts.join(" ")
          expect(embedded_content).to include("Modified content"), "should embed changed file"
          expect(embedded_content).to include("Brand new"), "should embed new file"
          expect(embedded_content).not_to include("Stays the same"), "should NOT re-embed unchanged file"

          # Verify cache has 3 entries (unchanged + changed + new, deleted pruned)
          cache_file = File.join(source, ".jekyll-client-search-cache.json")
          cache_data = JSON.parse(File.read(cache_file))
          expect(cache_data.keys.length).to eq(3), "cache should have 3 entries (deleted pruned)"

          # Verify all 3 documents in the output have embeddings
          with_embeddings = result2[:documents].select { |d| d["embedding"] }
          expect(with_embeddings.length).to eq(3)
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 8: Config transition — no LLM → enable LLM ---
  #
  it "embeds all documents when LLM is enabled after an initial build without embeddings" do
    Dir.mktmpdir("config-transition-on") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." },
                    { filename: "2026-01-02-post-b.md", title: "Post B", content: "Content about pasta." }
                  ])

      # First build — no embeddings
      result1 = build_site(source)

      begin
        expect(result1[:documents].select { |d| d["embedding"] }).to be_empty

        # Second build — enable embeddings (simulating config change + restart)
        rewrite_config(source, embedding_config)
        mock = MockEmbeddingAdapter.new
        result2 = build_site(source, mock)

        begin
          # All documents should now have embeddings
          with_embeddings = result2[:documents].select { |d| d["embedding"] }
          expect(with_embeddings.length).to eq(2), "all documents should be embedded after enabling LLM"
          expect(mock.embedded_texts.length).to eq(2), "adapter should be called for all documents"
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 9: Config transition — LLM → disable LLM ---
  #
  it "does not include embedding fields when LLM is disabled after an initial build with embeddings" do
    Dir.mktmpdir("config-transition-off") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ], embedding_config)

      # First build — with embeddings
      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        expect(result1[:documents].select { |d| d["embedding"] }.length).to eq(1)

        # Second build — disable embeddings (simulating config change + restart)
        rewrite_config(source, nil)
        result2 = build_site(source)

        begin
          # No documents should have embedding fields
          with_embeddings = result2[:documents].select { |d| d["embedding"] }
          expect(with_embeddings).to be_empty, "no embedding fields after disabling LLM"
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 10: Dev mode — add article, rebuild, verify it's in the search index ---
  #
  it "automatically indexes a newly added article on rebuild (dev mode workflow)" do
    Dir.mktmpdir("dev-mode-add") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ])

      # Initial build
      result1 = build_site(source)

      begin
        expect(result1[:documents].length).to eq(1)

        # Add a new article (simulating dev mode: save file → Jekyll rebuilds)
        File.write(File.join(source, "_posts", "2026-01-02-new-article.md"), <<~MD)
          ---
          title: "New Article About Photography"
          ---
          This is a new article about photography techniques and camera settings.
        MD

        # Rebuild
        result2 = build_site(source)

        begin
          # The new article should be in the search index
          expect(result2[:documents].length).to eq(2), "new article should be indexed"
          new_doc = result2[:documents].find { |d| d["title"] == "New Article About Photography" }
          expect(new_doc).not_to be_nil, "new article should appear in search index"
          expect(new_doc["content"]).to include("photography techniques")
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 11: Dev mode + LLM — add article, rebuild, verify indexed + embedded ---
  #
  it "automatically indexes and embeds a newly added article when LLM is enabled (dev mode workflow)" do
    Dir.mktmpdir("dev-mode-add-llm") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." }
                  ], embedding_config)

      # Initial build with LLM
      mock1 = MockEmbeddingAdapter.new
      result1 = build_site(source, mock1)

      begin
        expect(mock1.embedded_texts.length).to eq(1)
        expect(result1[:documents].select { |d| d["embedding"] }.length).to eq(1)

        # Add a new article (simulating dev mode: save file → Jekyll rebuilds)
        File.write(File.join(source, "_posts", "2026-01-02-new-article.md"), <<~MD)
          ---
          title: "New Article About Photography"
          ---
          This is a new article about photography techniques and camera settings.
        MD

        # Rebuild with LLM
        mock2 = MockEmbeddingAdapter.new
        result2 = build_site(source, mock2)

        begin
          # The new article should be in the search index
          expect(result2[:documents].length).to eq(2), "new article should be indexed"

          # The new article should have an embedding
          new_doc = result2[:documents].find { |d| d["title"] == "New Article About Photography" }
          expect(new_doc).not_to be_nil, "new article should appear in search index"
          expect(new_doc["embedding"]).not_to be_nil, "new article should have an embedding"

          # Only the new article should have been embedded (cache reuse for existing)
          expect(mock2.embedded_texts.length).to eq(1), "only the new article should be embedded"
          expect(mock2.embedded_texts.first).to include("photography techniques")

          # The existing article should still have its embedding from the cache
          existing_doc = result2[:documents].find { |d| d["title"] == "Post A" }
          expect(existing_doc["embedding"]).not_to be_nil, "existing article should retain cached embedding"
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 12: Dev mode — delete article, rebuild, verify it's gone from search index ---
  #
  it "removes a deleted article from the search index on rebuild (dev mode workflow)" do
    Dir.mktmpdir("dev-mode-delete") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Content about glaciers." },
                    { filename: "2026-01-02-post-b.md", title: "Post B", content: "Content about pasta." }
                  ])

      # Initial build
      result1 = build_site(source)

      begin
        expect(result1[:documents].length).to eq(2)

        # Delete an article (simulating dev mode: delete file → Jekyll rebuilds)
        File.delete(File.join(source, "_posts", "2026-01-02-post-b.md"))

        # Rebuild
        result2 = build_site(source)

        begin
          # The deleted article should NOT be in the search index
          expect(result2[:documents].length).to eq(1), "deleted article should be removed from index"
          titles = result2[:documents].map { |d| d["title"] }
          expect(titles).not_to include("Post B"), "deleted article should not appear in search index"
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end

  # --- Test 13: Dev mode — modify article content, rebuild, verify updated content in index ---
  #
  it "updates article content in the search index on rebuild (dev mode workflow)" do
    Dir.mktmpdir("dev-mode-modify") do |source|
      create_site(source, [
                    { filename: "2026-01-01-post-a.md", title: "Post A", content: "Original content about glaciers." }
                  ])

      # Initial build
      result1 = build_site(source)

      begin
        doc = result1[:documents].first
        expect(doc["content"]).to include("Original content")

        # Modify the article (simulating dev mode: edit file → Jekyll rebuilds)
        File.write(File.join(source, "_posts", "2026-01-01-post-a.md"), <<~MD)
          ---
          title: "Post A"
          ---
          Updated content about glaciers and new ice formations.
        MD

        # Rebuild
        result2 = build_site(source)

        begin
          doc2 = result2[:documents].first
          expect(doc2["content"]).to include("Updated content"), "index should reflect modified content"
          expect(doc2["content"]).to include("new ice formations")
          expect(doc2["content"]).not_to include("Original content"), "old content should be replaced"
        ensure
          cleanup(result2[:dest])
        end
      ensure
        cleanup(result1[:dest])
      end
    end
  end
end
