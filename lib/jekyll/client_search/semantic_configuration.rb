# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Validates semantic-engine index settings: which Ollama model's vectors
    # are written into the search index and must match the browser query
    # embedder's vector space.
    class SemanticConfiguration
      def initialize(config)
        unless config.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search semantic configuration must be a mapping"
        end

        @values = config
        validate!
      end

      # Ollama model embedded into the search index. nil means the site uses
      # the general embedding.model.
      def index_model
        value = @values["index_model"]
        value&.to_s
      end

      def document_prefix
        value = @values["document_prefix"]
        value&.to_s
      end

      def query_prefix
        value = @values["query_prefix"]
        value&.to_s
      end

      private

      def validate!
        return if index_model.nil? || !index_model.empty?

        raise Jekyll::Errors::FatalException,
              "client_search semantic index_model must not be empty"
      end
    end
  end
end
