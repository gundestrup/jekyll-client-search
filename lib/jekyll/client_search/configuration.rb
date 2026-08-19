# frozen_string_literal: true

module Jekyll
  module ClientSearch
    class Configuration
      DEFAULTS = {
        "enabled" => true,
        "output" => "search-index.json",
        "collections" => ["posts"],
        "include_pages" => false,
        "copy_runtime" => true
      }.freeze

      def initialize(site)
        configured = site.config["client_search"]
        configured = { "enabled" => false } if configured == false
        configured ||= {}
        unless configured.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search configuration must be a mapping or false"
        end

        @values = DEFAULTS.merge(configured)
      end

      def enabled?
        @values["enabled"] != false
      end

      def output
        normalize_output(@values.fetch("output"))
      end

      def collections
        Array(@values["collections"])
          .compact
          .map(&:to_s)
          .reject(&:empty?)
          .uniq
      end

      def include_pages?
        @values["include_pages"] == true
      end

      def copy_runtime?
        @values["copy_runtime"] != false
      end

      private

      def normalize_output(value)
        output = value.to_s.sub(%r{\A/+}, "")
        normalized = Pathname.new(output).cleanpath.to_s
        return normalized unless output.empty? || normalized == "." || normalized.start_with?("../")

        raise Jekyll::Errors::FatalException,
              "client_search output must be a relative file path inside the destination"
      end
    end
  end
end
