# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Jekyll::ClientSearch::IndexCache, :unit do
  let(:dir) { Dir.mktmpdir("index-cache") }
  let(:cache) { described_class.new(dir) }

  after { FileUtils.remove_entry(dir) }

  it "starts empty when no cache file exists" do
    expect(cache.lookup("/post/", "abc123")).to be_nil
  end

  it "stores and looks up entries by content hash" do
    cache.store("/post/", "hash1", [0.1, 0.2])
    expect(cache.lookup("/post/", "hash1")).to eq("content_hash" => "hash1", "embedding" => [0.1, 0.2])
  end

  it "returns nil when the content hash has changed" do
    cache.store("/post/", "hash1", [0.1, 0.2])
    expect(cache.lookup("/post/", "hash2")).to be_nil
  end

  it "invalidates entries when the embedding identity changes" do
    identity_a = { "provider" => "ollama", "model" => "model-a", "schema" => 1 }
    identity_b = { "provider" => "ollama", "model" => "model-b", "schema" => 1 }
    cache = described_class.new(dir, embedding_identity: identity_a)
    cache.store("/post/", "hash1", [0.1, 0.2])
    cache.save

    same_identity = described_class.new(dir, embedding_identity: identity_a)
    different_identity = described_class.new(dir, embedding_identity: identity_b)
    expect(same_identity.lookup("/post/", "hash1")).not_to be_nil
    expect(different_identity.lookup("/post/", "hash1")).to be_nil
  end

  it "writes cache entries atomically" do
    cache.store("/post/", "hash1", [0.1, 0.2])
    cache.save

    expect(File.exist?(cache.path)).to be(true)
    expect(Dir.glob("#{cache.path}.tmp.*")).to be_empty
    expect(JSON.parse(File.read(cache.path))).to have_key("/post/")
  end

  it "stores entries without embeddings" do
    cache.store("/post/", "hash1")
    expect(cache.lookup("/post/", "hash1")).to eq("content_hash" => "hash1")
  end

  it "prunes entries for removed documents" do
    cache.store("/a/", "h1")
    cache.store("/b/", "h2")
    cache.prune(["/a/"])
    expect(cache.lookup("/a/", "h1")).not_to be_nil
    expect(cache.lookup("/b/", "h2")).to be_nil
  end

  it "persists to disk and reloads" do
    cache.store("/post/", "hash1", [0.5])
    cache.save

    reloaded = described_class.new(dir)
    expect(reloaded.lookup("/post/", "hash1")).to eq("content_hash" => "hash1", "embedding" => [0.5])
  end

  it "does not write when nothing changed" do
    cache.store("/post/", "hash1")
    cache.save
    mtime = File.mtime(cache.path)
    sleep 0.01

    same_cache = described_class.new(dir)
    same_cache.store("/post/", "hash1")
    same_cache.save
    expect(File.mtime(cache.path)).to eq(mtime)
  end

  it "computes a deterministic content hash" do
    doc = { "id" => "/x/", "title" => "Test" }
    hash1 = described_class.content_hash(doc)
    hash2 = described_class.content_hash(doc)
    expect(hash1).to eq(hash2)
    expect(hash1).not_to eq(described_class.content_hash({ "id" => "/y/", "title" => "Test" }))
  end

  it "handles a corrupt cache file gracefully" do
    File.write(File.join(dir, described_class::CACHE_FILE), "{ invalid json")
    cache = described_class.new(dir)
    expect(cache.lookup("/post/", "hash1")).to be_nil
  end

  it "handles a cache file containing valid JSON that is not a Hash" do
    File.write(File.join(dir, described_class::CACHE_FILE), "[1, 2, 3]")
    cache = described_class.new(dir)
    expect(cache.lookup("/post/", "hash1")).to be_nil
  end

  it "cleans up the temporary file when File.rename fails" do
    cache.store("/post/", "hash1", [0.1])
    allow(File).to receive(:rename).and_raise(Errno::ENOENT, "mocked rename failure")

    expect { cache.save }.to raise_error(Errno::ENOENT)
    # The temp file should have been cleaned up by the ensure block
    expect(Dir.glob("#{cache.path}.tmp.*")).to be_empty
  end
end
