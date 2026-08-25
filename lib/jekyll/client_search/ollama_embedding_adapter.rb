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
      attr_reader :model, :base_url, :connect_timeout, :read_timeout

      def initialize(model:, base_url: "http://localhost:11434", connect_timeout: 5, read_timeout: 120)
        @model = model
        @base_url = base_url
        @connect_timeout = connect_timeout
        @read_timeout = read_timeout
      end

      # Returns a float vector for the given text. Raises a clear error if
      # the ollama-ruby gem is not installed or the server is unreachable.
      def embed(text)
        embedding = client.embed(model: @model, input: text).embeddings&.first
        return embedding if valid_embedding?(embedding)

        Jekyll.logger.warn "ClientSearch:", "embedding response was empty or invalid"
        nil
      rescue LoadError, NameError
        raise Jekyll::Errors::FatalException,
              "Add gem \"ollama-ruby\" to your Gemfile to use embedding features"
      rescue StandardError => e
        Jekyll.logger.warn "ClientSearch:", "embedding failed for text: #{e.message}"
        nil
      end

      private

      def valid_embedding?(embedding)
        embedding.is_a?(Array) && !embedding.empty? &&
          embedding.all? { |value| value.is_a?(Numeric) && value.finite? }
      end

      def client
        @client ||= begin
          require "ollama"
          Ollama::Client.new(
            base_url: @base_url,
            connect_timeout: @connect_timeout,
            read_timeout: @read_timeout
          )
        end
      end
    end
  end
end
