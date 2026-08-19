# frozen_string_literal: true

module Jekyll
  module ElasticlunrSearch
    class Generator < Jekyll::Generator
      safe true
      priority :low

      def generate(site)
        configuration = Configuration.new(site)
        return unless configuration.enabled?

        builder = DocumentBuilder.new
        documents = collection_documents(site, configuration, builder)
        documents.concat(page_documents(site, builder, configuration)) if configuration.include_pages?
        site.pages << SearchIndexPage.new(site, configuration.output, documents)
        add_runtime_asset(site)
      end

      private

      def collection_documents(site, configuration, builder)
        configuration.collections.flat_map do |label|
          collection = label == "posts" ? site.posts : site.collections[label]
          next [] unless collection

          collection.docs.map { |document| builder.from_document(document) }
        end
      end

      def page_documents(site, builder, configuration)
        site.pages
          .reject { |page| page.url == "/#{configuration.output}" }
          .select { |page| page.data["title"] }
          .map { |page| builder.from_document(page) }
      end

      def add_runtime_asset(site)
        root = File.expand_path("../../..", __dir__)
        asset = Jekyll::StaticFile.new(site, root, "assets", "elasticlunr-search.js")
        site.static_files << asset unless site.static_files.any? do |file|
          file.relative_path == "assets/elasticlunr-search.js"
        end
      end
    end
  end
end
