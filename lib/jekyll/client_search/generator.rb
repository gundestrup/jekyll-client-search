# frozen_string_literal: true

module Jekyll
  module ClientSearch
    class Generator < Jekyll::Generator
      RUNTIME_PATH = "assets/client-search.js"

      safe true
      priority :low

      def generate(site)
        configuration = Configuration.new(site)
        return unless configuration.enabled?

        builder = DocumentBuilder.new
        documents = collection_documents(site, configuration, builder)
        documents.concat(page_documents(site, builder, configuration)) if configuration.include_pages?
        documents = documents.compact.uniq { |document| document["id"] }

        site.pages << SearchIndexPage.new(site, configuration.output, documents)
        add_runtime_asset(site) if configuration.copy_runtime?
      end

      private

      def collection_documents(site, configuration, builder)
        configuration.collections.flat_map do |label|
          collection = label == "posts" ? site.posts : site.collections[label]
          next [] unless collection

          collection.docs.filter_map { |document| builder.from_document(document) }
        end
      end

      def page_documents(site, builder, configuration)
        site.pages
          .reject { |page| page.url == "/#{configuration.output}" }
          .select { |page| page.data["title"] }
          .filter_map { |page| builder.from_document(page) }
      end

      def add_runtime_asset(site)
        return if site.static_files.any? { |file| normalized_path(file.relative_path) == RUNTIME_PATH }

        root = File.expand_path("../../..", __dir__)
        site.static_files << Jekyll::StaticFile.new(site, root, "assets", "client-search.js")
      end

      def normalized_path(path)
        path.to_s.sub(%r{\A/}, "")
      end
    end
  end
end
