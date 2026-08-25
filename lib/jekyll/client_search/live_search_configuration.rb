# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Normalizes optional browser live-search behavior.
    class LiveSearchConfiguration
      DEFAULTS = {
        "min_chars" => 2,
        "debounce_ms" => 150,
        "semantic_debounce_ms" => 500,
        "update_url" => true
      }.freeze

      def initialize(config, engine: "minisearch")
        unless config.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search live_search configuration must be a mapping"
        end

        @engine = engine
        @values = DEFAULTS.merge(config)
        @values["enabled"] = default_enabled?(engine) unless config.key?("enabled")
        validate!
      end

      def to_h(engine:)
        {
          "enabled" => @values.fetch("enabled"),
          "minChars" => @values.fetch("min_chars"),
          "debounceMs" => debounce_ms(engine),
          "updateUrl" => @values.fetch("update_url")
        }
      end

      private

      def default_enabled?(engine)
        engine != "semantic"
      end

      def debounce_ms(engine)
        key = engine == "semantic" ? "semantic_debounce_ms" : "debounce_ms"
        @values.fetch(key)
      end

      def validate!
        validate_boolean!("enabled")
        validate_boolean!("update_url")
        validate_integer!("min_chars", minimum: 0)
        validate_integer!("debounce_ms", minimum: 0)
        validate_integer!("semantic_debounce_ms", minimum: 0)
      end

      def validate_boolean!(key)
        return if [true, false].include?(@values[key])

        raise Jekyll::Errors::FatalException,
              "client_search live_search.#{key} must be true or false"
      end

      def validate_integer!(key, minimum:)
        value = @values.fetch(key)
        return if value.is_a?(Integer) && value >= minimum

        raise Jekyll::Errors::FatalException,
              "client_search live_search.#{key} must be an integer greater than or equal to #{minimum}"
      end
    end
  end
end
