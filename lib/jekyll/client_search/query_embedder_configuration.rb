# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Normalizes browser query-embedder settings.
    class QueryEmbedderConfiguration
      TYPES = %w[transformers ollama_api none].freeze

      MODEL_MAP = {
        "embeddinggemma:300m" => "onnx-community/embeddinggemma-300m-ONNX",
        "all-minilm" => "Xenova/all-MiniLM-L6-v2"
      }.freeze

      DEFAULT_LIBRARY_URL = "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1"

      DEFAULTS = {
        "type" => "transformers",
        "library_url" => DEFAULT_LIBRARY_URL,
        "dtype" => "q8",
        "worker" => true,
        "timeout_ms" => 300_000,
        "retry_attempts" => 1,
        "max_tokens" => 512
      }.freeze

      JSON_KEYS = {
        "library_url" => "libraryUrl",
        "model_base_url" => "modelBaseUrl",
        "wasm_base_url" => "wasmBaseUrl",
        "worker_url" => "workerUrl",
        "device" => "device",
        "dtype" => "dtype",
        "worker" => "worker",
        "timeout_ms" => "timeoutMs",
        "retry_attempts" => "retryAttempts",
        "max_tokens" => "maxTokens"
      }.freeze

      def initialize(config, build_model:, build_base_url:, query_prefix:)
        unless config.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search embedding.query_embedder configuration must be a mapping"
        end

        @values = DEFAULTS.merge(config)
        @values["timeout_ms"] = 30_000 if @values["type"] == "ollama_api" && !config.key?("timeout_ms")
        @build_model = build_model
        @build_base_url = build_base_url
        @query_prefix = query_prefix
        validate!
      end

      def type
        @values.fetch("type")
      end

      def model
        return @values.fetch("model") if @values.key?("model")
        return @build_model unless type == "transformers"
        return MODEL_MAP.fetch(@build_model) if MODEL_MAP.key?(@build_model)

        raise Jekyll::Errors::FatalException,
              "embedding query_embedder.model is required for #{@build_model.inspect}"
      end

      def api_url
        @values.fetch("api_url", "#{@build_base_url}/api/embed")
      end

      def assets
        case type
        when "transformers"
          files = ["assets/query-embedders/transformers.js"]
          files << "assets/query-embedders/transformers-worker.js" if @values["worker"]
          files
        when "ollama_api"
          ["assets/query-embedders/ollama-api.js"]
        else
          []
        end
      end

      def asset
        assets.first
      end

      def to_json(*)
        config = {
          "type" => type,
          "model" => model,
          "apiUrl" => api_url,
          "buildModel" => @build_model,
          "queryPrefix" => @query_prefix
        }
        JSON_KEYS.each do |source, target|
          config[target] = @values[source] if @values.key?(source)
        end
        config.to_json
      end

      private

      def validate!
        unless TYPES.include?(type)
          valid = TYPES.join(", ")
          raise Jekyll::Errors::FatalException,
                "embedding query_embedder type must be one of #{valid} (got #{type.inspect})"
        end
        validate_integer!("timeout_ms", minimum: 1)
        validate_integer!("retry_attempts", minimum: 0)
        validate_integer!("max_tokens", minimum: 1)
        return if [true, false].include?(@values["worker"])

        raise Jekyll::Errors::FatalException,
              "embedding query_embedder.worker must be true or false"
      end

      def validate_integer!(key, minimum:)
        value = @values.fetch(key)
        return if value.is_a?(Integer) && value >= minimum

        raise Jekyll::Errors::FatalException,
              "embedding query_embedder.#{key} must be an integer greater than or equal to #{minimum}"
      end
    end
  end
end
