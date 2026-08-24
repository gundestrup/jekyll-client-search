# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Generates embeddings via a local Ollama server using the +ollama-ruby+
    # gem. The gem is required lazily so that users who do not enable
    # embeddings never need to install it.
    #
    # Configuration:
    #   embedding:
    #     enabled: true
    #     model: all-minilm          # or nomic-embed-text, bge-m3, etc.
    #     base_url: http://localhost:11434
    class OllamaEmbeddingAdapter
      attr_reader :model, :base_url

      def initialize(model:, base_url: "http://localhost:11434")
        @model = model
        @base_url = base_url
      end

      # Returns a float vector for the given text. Raises a clear error if
      # the ollama-ruby gem is not installed or the server is unreachable.
      def embed(text)
        client.embed(model: @model, input: text).embeddings&.first
      rescue LoadError, NameError
        raise Jekyll::Errors::FatalException,
              "Add gem \"ollama-ruby\" to your Gemfile to use embedding features"
      rescue StandardError => e
        Jekyll.logger.warn "ClientSearch:", "embedding failed for text: #{e.message}"
        nil
      end

      private

      def client
        @client ||= begin
          require "ollama"
          Ollama::Client.new(base_url: @base_url)
        end
      end
    end
  end
end
