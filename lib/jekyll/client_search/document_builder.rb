# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Normalizes Jekyll documents and pages into the flat hash shape that the
    # search index JSON emits.
    class DocumentBuilder
      def from_document(document)
        url = document.url.to_s
        return if url.empty?

        data = document.data
        {
          "id" => url,
          "title" => clean(data["title"] || "Untitled"),
          "url" => url,
          "excerpt" => clean(data["excerpt"] || excerpt_for(document)),
          "content" => clean(document.content),
          "categories" => normalize_list(data["categories"]),
          "tags" => normalize_list(data["tags"])
        }
      end

      private

      def excerpt_for(document)
        document.excerpt if document.respond_to?(:excerpt)
      end

      def normalize_list(value)
        Array(value).compact.map { |item| clean(item) }.reject(&:empty?).uniq
      end

      def clean(value)
        cleaned = value.to_s
                       .gsub(%r{<script\b[^>]*>.*?</script>}mi, " ")
                       .gsub(%r{<style\b[^>]*>.*?</style>}mi, " ")
                       .gsub(/\{%.*?%\}/m, " ")
                       .gsub(/\{\{.*?\}\}/m, " ")
                       .gsub(/!\[[^\]]*\]\([^)]*\)/, " ")
                       .gsub(/<[^>]+>/, " ")
                       .gsub(/[`*_>#\[\]()]/, " ")
                       .gsub(/\s+/, " ")
                       .gsub(/\s+([,.!?;:])/, '\\1')
                       .strip
        CGI.unescapeHTML(cleaned)
      end
    end
  end
end
