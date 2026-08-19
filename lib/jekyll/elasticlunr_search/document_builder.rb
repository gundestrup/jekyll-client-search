# frozen_string_literal: true

module Jekyll
  module ElasticlunrSearch
    class DocumentBuilder
      def from_document(document)
        data = document.data
        {
          "id" => document.url,
          "title" => data["title"] || "Untitled",
          "url" => document.url,
          "excerpt" => clean(data["excerpt"] || excerpt_for(document)),
          "content" => clean(document.content),
          "categories" => Array(data["categories"]),
          "tags" => Array(data["tags"])
        }
      end

      private

      def excerpt_for(document)
        document.excerpt if document.respond_to?(:excerpt)
      end

      def clean(value)
        value.to_s
          .gsub(/\{%.*?%\}/m, " ")
          .gsub(/!\[[^\]]*\]\([^)]*\)/, " ")
          .gsub(/<[^>]+>/, " ")
          .gsub(/[`*_>#\[\]()]/, " ")
          .gsub(/\s+/, " ")
          .gsub(/\s+([,.!?;:])/, '\\1')
          .strip
      end
    end
  end
end
