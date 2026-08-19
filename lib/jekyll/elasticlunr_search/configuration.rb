# frozen_string_literal: true

module Jekyll
  module ElasticlunrSearch
    class Configuration
      DEFAULTS = {
        "enabled" => true,
        "output" => "search-index.json",
        "collections" => ["posts"],
        "include_pages" => false
      }.freeze

      def initialize(site)
        values = site.config.fetch("elasticlunr_search", {})
        @values = DEFAULTS.merge(values)
      end

      def enabled?
        @values["enabled"] != false
      end

      def output
        @values.fetch("output").to_s.sub(%r{^/}, "")
      end

      def collections
        Array(@values["collections"]).map(&:to_s)
      end

      def include_pages?
        @values["include_pages"] == true
      end
    end
  end
end
