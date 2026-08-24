# frozen_string_literal: true

require "json"
require "digest"

module Jekyll
  module ClientSearch
    # Persists content hashes and cached embeddings across Jekyll builds so
    # that unchanged documents are not re-embedded. The cache file lives in
    # the site source directory as +.jekyll-client-search-cache.json+ and
    # should be git-ignored.
    class IndexCache
      CACHE_FILE = ".jekyll-client-search-cache.json"

      attr_reader :path

      def initialize(site_source)
        @path = File.join(site_source, CACHE_FILE)
        @entries = load
      end

      # Returns the cached entry for +id+ if the content hash matches,
      # nil otherwise (or if not cached).
      def lookup(id, content_hash)
        entry = @entries[id]
        return nil unless entry

        entry["content_hash"] == content_hash ? entry : nil
      end

      # Stores or updates a cache entry for +id+.
      def store(id, content_hash, embedding = nil)
        @entries[id] = {
          "content_hash" => content_hash,
          "embedding" => embedding
        }.compact
      end

      # Removes entries for IDs that are no longer present.
      def prune(known_ids)
        @entries.select! { |id, _| known_ids.include?(id) }
      end

      # Writes the cache to disk if any entries have changed.
      def save
        return unless dirty?

        File.write(@path, JSON.pretty_generate(@entries))
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
