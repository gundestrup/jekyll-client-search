# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Reads the +client_search+ section of the Jekyll site config and exposes
    # validated, normalized values to the generator.
    class Configuration
      ENGINES = %w[minisearch elasticlunr semantic].freeze

      DEFAULTS = {
        "enabled" => true,
        "engine" => "minisearch",
        "output" => "search-index.json",
        "collections" => ["posts"],
        "include_pages" => false,
        "copy_runtime" => true,
        "embedding" => { "enabled" => false, "model" => "embeddinggemma:300m", "base_url" => "http://localhost:11434" }
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
        @values["embedding"] = DEFAULTS.fetch("embedding").merge(configured["embedding"] || {})
        validate_engine!
      end

      def enabled?
        @values["enabled"] != false
      end

      def engine
        @values.fetch("engine").to_s
      end

      def runtime_assets
        ["assets/client-search-base.js", "assets/adapters/#{engine}.js"]
      end

      def output
        normalize_output(@values.fetch("output"))
      end

      def collections
        Array(@values["collections"])
          .compact
          .map(&:to_s)
          .reject(&:empty?)
          .uniq
      end

      def include_pages?
        @values["include_pages"] == true
      end

      def copy_runtime?
        @values["copy_runtime"] != false
      end

      def embedding_enabled?
        @values.fetch("embedding").fetch("enabled") == true
      end

      def embedding_model
        @values.fetch("embedding").fetch("model").to_s
      end

      def embedding_base_url
        @values.fetch("embedding").fetch("base_url").to_s
      end

      private

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
