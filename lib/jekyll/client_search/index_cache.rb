# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"

module Jekyll
  module ClientSearch
    # Persists content hashes and cached embeddings across Jekyll builds so
    # that unchanged documents are not re-embedded. The cache file lives in
    # the site source directory as +.jekyll-client-search-cache.json+ and
    # should be git-ignored.
    class IndexCache
      CACHE_FILE = ".jekyll-client-search-cache.json"

      attr_reader :path

      def initialize(site_source, embedding_identity: nil)
        @path = File.join(site_source, CACHE_FILE)
        @embedding_identity = embedding_identity
        @entries = load
      end

      # Returns the cached entry for +id+ if the content hash and embedding
      # identity match, nil otherwise (or if not cached).
      def lookup(id, content_hash)
        entry = @entries[id]
        return nil unless entry
        return nil unless entry["content_hash"] == content_hash
        return nil if @embedding_identity && entry["embedding_identity"] != @embedding_identity

        entry
      end

      # Stores or updates a cache entry for +id+.
      def store(id, content_hash, embedding = nil)
        @entries[id] = {
          "content_hash" => content_hash,
          "embedding" => embedding,
          "embedding_identity" => @embedding_identity
        }.compact
      end

      # Removes entries for IDs that are no longer present.
      def prune(known_ids)
        @entries.select! { |id, _| known_ids.include?(id) }
      end

      # Writes the cache to disk if any entries have changed.
      def save
        return unless dirty?

        temporary_path = "#{@path}.tmp.#{Process.pid}.#{Thread.current.object_id}"
        File.write(temporary_path, JSON.pretty_generate(@entries))
        File.rename(temporary_path, @path)
      ensure
        FileUtils.rm_f(temporary_path) if temporary_path && File.exist?(temporary_path)
      end

      def self.content_hash(document)
        Digest::SHA256.hexdigest(document.to_json)
      end

      private

      def load
        return {} unless File.exist?(@path)

        data = JSON.parse(File.read(@path))
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end

      def dirty?
        return true unless File.exist?(@path)

        File.read(@path) != JSON.pretty_generate(@entries)
      end
    end
  end
end
