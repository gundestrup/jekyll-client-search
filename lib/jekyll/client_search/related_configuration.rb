# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Validates related-article output and matching rules.
    class RelatedConfiguration
      DEFAULTS = {
        "enabled" => false,
        "output" => "search-relations.json",
        "same_category" => true,
        "shared_tags" => true,
        "include_parent_domains" => true,
        "semantic" => true,
        "minimum_similarity" => 0.55,
        "max_items" => 5
      }.freeze

      def initialize(config)
        unless config.is_a?(Hash)
          raise Jekyll::Errors::FatalException,
                "client_search related configuration must be a mapping"
        end

        @values = DEFAULTS.merge(config)
        validate!
      end

      def enabled?
        @values.fetch("enabled") == true
      end

      def output
        value = @values.fetch("output").to_s.sub(%r{\A/+}, "")
        normalized = Pathname.new(value).cleanpath.to_s
        return normalized unless value.empty? || normalized == "." || normalized.start_with?("../")

        raise Jekyll::Errors::FatalException,
              "client_search related output must be a relative file path inside the destination"
      end

      def same_category?
        @values.fetch("same_category") == true
      end

      def shared_tags?
        @values.fetch("shared_tags") == true
      end

      def include_parent_domains?
        @values.fetch("include_parent_domains") == true
      end

      def semantic?
        @values.fetch("semantic") == true
      end

      def minimum_similarity
        @values.fetch("minimum_similarity").to_f
      end

      def max_items
        @values.fetch("max_items")
      end

      private

      def validate!
        validate_booleans!
        validate_similarity!
        validate_max_items!
      end

      def validate_booleans!
        %w[enabled same_category shared_tags include_parent_domains semantic].each do |key|
          validate_boolean!(key)
        end
      end

      def validate_similarity!
        similarity = @values.fetch("minimum_similarity")
        return if similarity.is_a?(Numeric) && similarity.finite? && similarity.between?(-1, 1)

        raise Jekyll::Errors::FatalException,
              "client_search related minimum_similarity must be finite and between -1 and 1"
      end

      def validate_max_items!
        maximum = max_items
        return if maximum.nil? || (maximum.is_a?(Integer) && maximum.positive?)

        raise Jekyll::Errors::FatalException,
              "client_search related max_items must be a positive integer or null"
      end

      def validate_boolean!(key)
        return if [true, false].include?(@values[key])

        raise Jekyll::Errors::FatalException,
              "client_search related #{key} must be true or false"
      end
    end
  end
end
