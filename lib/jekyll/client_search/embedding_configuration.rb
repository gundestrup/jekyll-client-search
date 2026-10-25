# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Provides build-time embedding settings and model-specific prefixes.
    module EmbeddingConfiguration
      PREFIXES = {
        "embeddinggemma" => {
          "document" => "title: none | text: ",
          "query" => "task: search result | query: "
        },
        "embeddinggemma-2" => {
          "document" => "title: none | text: ",
          "query" => "task: search result | query: "
        },
        "nomic-embed-text" => {
          "document" => "search_document: ",
          "query" => "search_query: "
        },
        "voyage-4-nano" => {
          "document" => "Represent the document for retrieval: ",
          "query" => "Represent the query for retrieving supporting documents: "
        },
        "qwen3-embedding" => {
          "document" => "",
          "query" => "Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery: "
        },
        "bge-large" => {
          "document" => "",
          "query" => "Represent this sentence for searching relevant passages: "
        }
      }.freeze

      def embedding_enabled?
        @values.fetch("embedding").fetch("enabled") == true
      end

      def embedding_model
        @values.fetch("embedding").fetch("model").to_s
      end

      def embedding_base_url
        @values.fetch("embedding").fetch("base_url").to_s
      end

      def embedding_connect_timeout
        positive_timeout("connect_timeout")
      end

      def embedding_read_timeout
        positive_timeout("read_timeout")
      end

      def embedding_fail_on_error?
        @values.fetch("embedding").fetch("fail_on_error") != false
      end

      def embedding_include_in_index?
        configured = @values.fetch("embedding")["include_in_index"]
        configured.nil? ? engine == "semantic" : configured == true
      end

      # Document prefix for the index model (semantic.index_model).
      def embedding_document_prefix
        configured_prefix("document", model: embedding_index_model, override: @semantic.document_prefix)
      end

      # Query prefix for the index model — must match the browser query
      # embedder's vector space.
      def embedding_query_prefix
        configured_prefix("query", model: embedding_index_model, override: @semantic.query_prefix)
      end

      # Document prefix for the related-analysis model (related.index_model).
      def embedding_related_document_prefix
        configured_prefix("document", model: embedding_related_model)
      end

      def embedding_identity
        embedding_identity_for(model: embedding_index_model,
                               document_prefix: embedding_document_prefix,
                               query_prefix: embedding_query_prefix)
      end

      def embedding_related_identity
        embedding_identity_for(model: embedding_related_model,
                               document_prefix: embedding_related_document_prefix,
                               query_prefix: configured_prefix("query", model: embedding_related_model))
      end

      private

      def embedding_identity_for(model:, document_prefix:, query_prefix:)
        {
          "provider" => "ollama",
          "model" => model,
          "base_url" => embedding_base_url,
          "document_prefix" => document_prefix,
          "query_prefix" => query_prefix,
          "schema" => 2
        }
      end

      def configured_prefix(role, model:, override: nil)
        return override.to_s if override

        embedding = @values.fetch("embedding")
        config_key = "#{role}_prefix"
        return embedding[config_key].to_s if model == embedding_model && embedding.key?(config_key)

        PREFIXES.fetch(model.split(":").first, {}).fetch(role, "")
      end

      def positive_timeout(key)
        value = @values.fetch("embedding").fetch(key).to_f
        return value if value.positive? && value.finite?

        raise Jekyll::Errors::FatalException,
              "embedding #{key} must be a finite value greater than zero"
      end

      def validate_embedding!
        raise Jekyll::Errors::FatalException, "embedding model must not be empty" if embedding_model.empty?
        raise Jekyll::Errors::FatalException, "embedding base_url must not be empty" if embedding_base_url.empty?

        embedding_connect_timeout
        embedding_read_timeout
      end
    end
  end
end
