# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Reads the +client_search+ section of the Jekyll site config and exposes
    # validated, normalized values to the generator.
    class Configuration
      include ConfigurationAccessors
      include EmbeddingConfiguration

      ENGINES = %w[minisearch elasticlunr semantic].freeze

      ENGINE_CDN_URLS = {
        "minisearch" => "https://cdn.jsdelivr.net/npm/minisearch@7.2.0/dist/umd/index.min.js",
        "elasticlunr" => "https://cdn.jsdelivr.net/npm/elasticlunr@0.9.5/elasticlunr.min.js",
        "semantic" => nil
      }.freeze

      DEFAULTS = {
        "enabled" => true,
        "engine" => "minisearch",
        "output" => "search-index.json",
        "collections" => ["posts"],
        "include_pages" => false,
        "copy_runtime" => true,
        "passthrough_fields" => [],
        "icon_field" => "icon_url",
        "embedding" => {
          "enabled" => false,
          "model" => "embeddinggemma:300m",
          "base_url" => "http://localhost:11434",
          "connect_timeout" => 5,
          "read_timeout" => 120,
          "fail_on_error" => true,
          "query_embedder" => {
            "type" => "transformers"
          }
        }
      }.freeze

      def initialize(site)
        configured = site.config["client_search"]
        configured = { "enabled" => false } if configured == false
        configured ||= {}
        unless configured.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search configuration must be a mapping or false"
        end

        @values = DEFAULTS.merge(configured)
        @live_search = LiveSearchConfiguration.new(configured["live_search"] || {}, engine: engine)
        @related = RelatedConfiguration.new(configured["related"] || {})
        merge_embedding_config(configured["embedding"])
        validate_engine!
        return unless embedding_enabled?

        validate_embedding!
        validate_query_embedder!
      end

      private

      def merge_embedding_config(configured_embedding)
        embedding = configured_embedding || {}
        unless embedding.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search embedding configuration must be a mapping"
        end
        @values["embedding"] = DEFAULTS.fetch("embedding").merge(embedding)
        merge_query_embedder_config(embedding["query_embedder"])
      end

      def merge_query_embedder_config(configured_query_embedder)
        @query_embedder = QueryEmbedderConfiguration.new(
          configured_query_embedder || {},
          build_model: embedding_model,
          build_base_url: embedding_base_url,
          query_prefix: embedding_query_prefix
        )
      end

      public

      def enabled?
        @values["enabled"] != false
      end

      def engine
        @values.fetch("engine").to_s
      end

      def engine_url
        @values.key?("engine_url") ? @values.fetch("engine_url") : ENGINE_CDN_URLS.fetch(engine)
      end

      def engine_sri
        @values.fetch("engine_sri", nil)
      end

      def engine_crossorigin
        @values.fetch("engine_crossorigin", nil)
      end

      def runtime_assets
        assets = ["assets/client-search-base.js", "assets/adapters/#{engine}.js"]
        assets.concat(query_embedder_assets) if engine == "semantic" && embedding_enabled?
        assets << "assets/client-search-related.js" if related_enabled?
        assets
      end

      def output
        normalize_output(@values.fetch("output"))
      end

      def collections
        Array(@values["collections"]).compact.map(&:to_s).reject(&:empty?).uniq
      end

      def include_pages?
        @values["include_pages"] == true
      end

      def copy_runtime?
        @values["copy_runtime"] != false
      end

      def passthrough_fields
        Array(@values["passthrough_fields"]).compact.each_with_object([]) do |e, f|
          e.is_a?(Hash) ? add_hash_fields(e, f) : add_string_field(e, f)
        end.uniq
      end

      def add_hash_fields(hash, fields)
        hash.each do |s, t|
          fields << [s.to_s, t.to_s] unless s.to_s.empty? || t.to_s.empty?
        end
      end

      def add_string_field(entry, fields)
        fields << [entry.to_s, entry.to_s] unless entry.to_s.empty?
      end

      def icon_field
        v = @values["icon_field"]
        v.nil? || v == false ? nil : v.to_s
      end

      def runtime_icon_field
        icon_field if passthrough_fields.map(&:last).include?(icon_field)
      end

      private

      def validate_query_embedder!
        query_embedder_model if engine == "semantic" && query_embedder_type == "transformers"
      end

      def validate_engine!
        return if ENGINES.include?(engine)

        raise Jekyll::Errors::FatalException,
              "client_search engine must be one of #{ENGINES.join(', ')} (got #{engine.inspect})"
      end

      def normalize_output(value)
        output = value.to_s.sub(%r{\A/+}, "")
        normalized = Pathname.new(output).cleanpath.to_s
        return normalized unless output.empty? || normalized == "." || normalized.start_with?("../")

        raise Jekyll::Errors::FatalException,
              "client_search output must be a relative file path inside the destination"
      end
    end
  end
end
