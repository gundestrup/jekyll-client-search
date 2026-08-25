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
        "nomic-embed-text" => {
          "document" => "search_document: ",
          "query" => "search_query: "
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

      def embedding_document_prefix
        configured_prefix("document_prefix", "document")
      end

      def embedding_query_prefix
        configured_prefix("query_prefix", "query")
      end

      def embedding_identity
        {
          "provider" => "ollama",
          "model" => embedding_model,
          "base_url" => embedding_base_url,
          "document_prefix" => embedding_document_prefix,
          "query_prefix" => embedding_query_prefix,
          "schema" => 2
        }
      end

      private

      def configured_prefix(config_key, role)
        embedding = @values.fetch("embedding")
        return embedding.fetch(config_key).to_s if embedding.key?(config_key)

        model_name = embedding_model.split(":").first
        PREFIXES.fetch(model_name, {}).fetch(role, "")
      end

      def positive_timeout(key)
        value = @values.fetch("embedding").fetch(key).to_f
        unless value.positive? && value.finite?
          raise Jekyll::Errors::FatalException,
                "embedding #{key} must be a finite value greater than zero"
        end

        value
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
