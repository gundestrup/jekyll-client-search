# frozen_string_literal: true

require "uri"

module Jekyll
  module ClientSearch
    # Validates optional compact dropdown live-search settings.
    class DropdownConfiguration
      DEFAULTS = {
        "enabled" => true,
        "max_items" => 5,
        "min_chars" => 2,
        "debounce_ms" => 150,
        "redirect_url" => "/search/"
      }.freeze

      def initialize(config)
        unless config.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search dropdown configuration must be a mapping"
        end

        @values = DEFAULTS.merge(config)
        validate!
      end

      def enabled?
        @values.fetch("enabled") != false
      end

      def max_items
        @values.fetch("max_items")
      end

      def min_chars
        @values.fetch("min_chars")
      end

      def debounce_ms
        @values.fetch("debounce_ms")
      end

      def redirect_url
        @values.fetch("redirect_url").to_s
      end

      def to_h
        {
          "enabled" => enabled?,
          "maxItems" => max_items,
          "minChars" => min_chars,
          "debounceMs" => debounce_ms,
          "redirectUrl" => redirect_url
        }
      end

      private

      def validate!
        validate_boolean!("enabled")
        validate_integer!("max_items", minimum: 1)
        validate_integer!("min_chars", minimum: 0)
        validate_integer!("debounce_ms", minimum: 0)
        if redirect_url.empty?
          raise Jekyll::Errors::FatalException,
                "client_search dropdown redirect_url must not be empty"
        end

        uri = URI.parse(redirect_url)
        return if uri.scheme.nil? && uri.host.nil? && !redirect_url.start_with?("//")

        raise Jekyll::Errors::FatalException,
              "client_search dropdown redirect_url must be a relative path"
      end

      def validate_boolean!(key)
        return if [true, false].include?(@values[key])

        raise Jekyll::Errors::FatalException,
              "client_search dropdown.#{key} must be true or false"
      end

      def validate_integer!(key, minimum:)
        value = @values.fetch(key)
        return if value.is_a?(Integer) && value >= minimum

        raise Jekyll::Errors::FatalException,
              "client_search dropdown.#{key} must be an integer greater than or equal to #{minimum}"
      end
    end
  end
end
