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
          "tags" => normalize_list(data["tags"]),
          "date" => normalized_date(document),
          "date_timestamp" => normalized_timestamp(document)
        }.compact
      end

      private

      def excerpt_for(document)
        document.excerpt if document.respond_to?(:excerpt)
      end

      def normalize_list(value)
        Array(value).compact.map { |item| clean(item) }.reject(&:empty?).uniq
      end

      def normalized_date(document)
        value = document.data["date"] || document.date if document.respond_to?(:date)
        return if value.nil? || value.to_s.empty?

        value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
      end

      def normalized_timestamp(document)
        date = normalized_date(document)
        date ? Time.iso8601(date).to_i : nil
      rescue ArgumentError
        nil
      end

      def clean(value)
        cleaned = value.to_s
                       .gsub(%r{<script\b[^>]*>.*?</script\s*>}mi, " ")
                       .gsub(%r{<style\b[^>]*>.*?</style\s*>}mi, " ")
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
