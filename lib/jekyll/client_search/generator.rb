# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Jekyll generator that emits the search index JSON and copies browser
    # runtime assets (base + selected engine adapter) for client-side
    # JavaScript search engines. Optionally enhances documents with
    # embeddings from a local Ollama server, using a content-hash cache to
    # avoid re-embedding unchanged documents.
    class Generator < Jekyll::Generator
      safe true
      priority :low

      def generate(site)
        configuration = Configuration.new(site)
        return unless configuration.enabled?

        documents = build_documents(site, configuration)
        documents = enhance_with_embeddings(site, documents, configuration) if configuration.embedding_enabled?
        site.pages << SearchIndexPage.new(site, configuration.output, documents)
        add_runtime_asset(site, configuration) if configuration.copy_runtime?
      end

      private

      def build_documents(site, configuration)
        builder = DocumentBuilder.new
        documents = collection_documents(site, configuration, builder)
        documents.concat(page_documents(site, builder, configuration)) if configuration.include_pages?
        documents.compact.uniq { |document| document["id"] }
      end

      def enhance_with_embeddings(site, documents, configuration)
        cache = IndexCache.new(site.source)
        adapter = build_embedding_adapter(configuration)

        documents.each { |document| embed_document(document, cache, adapter) }
        cache.prune(documents.map { |doc| doc["id"] })
        cache.save
        documents
      end

      def build_embedding_adapter(configuration)
        OllamaEmbeddingAdapter.new(
          model: configuration.embedding_model,
          base_url: configuration.embedding_base_url
        )
      end

      def embed_document(document, cache, adapter)
        hash = IndexCache.content_hash(document)
        cached = cache.lookup(document["id"], hash)
        if cached
          document["embedding"] = cached["embedding"] if cached["embedding"]
        else
          embedding = adapter.embed(embedding_text(document))
          document["embedding"] = embedding if embedding
          cache.store(document["id"], hash, embedding)
        end
      end

      def embedding_text(document)
        [document["title"], document["excerpt"], document["content"]].compact.join(" ")
      end

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

      def add_runtime_asset(site, configuration)
        root = File.expand_path("../../..", __dir__)
        configuration.runtime_assets.each do |asset|
          relative = asset.sub(%r{\A/}, "")
          next if site.static_files.any? { |file| normalized_path(file.relative_path) == relative }

          base = File.dirname(asset)
          name = File.basename(asset)
          site.static_files << Jekyll::StaticFile.new(site, root, base, name)
        end
      end

      def normalized_path(path)
        path.to_s.sub(%r{\A/}, "")
      end
    end
  end
end
