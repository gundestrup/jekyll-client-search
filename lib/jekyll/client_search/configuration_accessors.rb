# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Exposes auxiliary generated-runtime settings through Configuration.
    module ConfigurationAccessors
      def live_search_config
        @live_search.to_h(engine: engine)
      end

      def related_enabled?
        @related.enabled?
      end

      def related_output
        @related.output
      end

      def related_configuration
        @related
      end

      def query_embedder_type
        @query_embedder.type
      end

      def query_embedder_model
        @query_embedder.model
      end

      def query_embedder_api_url
        @query_embedder.api_url
      end

      def query_embedder_asset
        @query_embedder.asset
      end

      def query_embedder_assets
        @query_embedder.assets
      end

      def query_embedder_config_json
        @query_embedder.to_json
      end
    end
  end
end
