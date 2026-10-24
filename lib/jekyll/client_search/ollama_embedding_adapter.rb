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
    #
    # A +localhost+ base_url is resolved once to the loopback literal
    # (127.0.0.1 or ::1) that accepts a TCP connection, because Excon
    # does not fall back across address families when the DNS name maps
    # to a family the server is not listening on.
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
            base_url: resolved_base_url,
            connect_timeout: @connect_timeout,
            read_timeout: @read_timeout
          )
        end
      end

      # "localhost" may resolve to ::1 while the server only listens on
      # 127.0.0.1, or the reverse. Excon does not fall back across
      # address families, so probe both loopback literals once and use
      # the one that accepts a TCP connection. Any other host name is
      # used exactly as configured.
      def resolved_base_url
        @resolved_base_url ||= resolve_localhost(@base_url)
      end

      def resolve_localhost(base_url)
        require "uri"
        uri = URI.parse(base_url)
        return base_url unless uri.host.to_s.chomp(".").casecmp("localhost").zero?

        resolved = loopback_base_url(uri)
        return base_url unless resolved

        Jekyll.logger.info "ClientSearch:", "resolved localhost to #{resolved}"
        resolved
      rescue URI::InvalidURIError
        base_url
      end

      def loopback_base_url(uri)
        %w[127.0.0.1 ::1].each do |address|
          next unless tcp_reachable?(address, uri.port)

          resolved = uri.dup
          resolved.host = address.include?(":") ? "[#{address}]" : address
          return resolved.to_s
        end
        nil
      end

      def tcp_reachable?(address, port)
        require "socket"
        Socket.tcp(address, port, connect_timeout: @connect_timeout) { true }
      rescue SystemCallError, SocketError
        false
      end
    end
  end
end
