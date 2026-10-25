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
        add_generated_pages(site, documents, configuration)
        add_runtime_asset(site, configuration) if configuration.copy_runtime?
      end

      private

      def add_generated_pages(site, documents, configuration)
        add_related_page(site, documents, configuration) if configuration.related_enabled?
        documents.each { |document| document.delete("related_embedding") }
        remove_embeddings(documents) unless configuration.embedding_include_in_index?
        site.pages << SearchIndexPage.new(site, configuration.output, documents)
        site.pages << RuntimeConfigPage.new(site, configuration) if configuration.copy_runtime?
        add_embedder_config(site, configuration) if semantic_query_embedder?(configuration)
      end

      def build_documents(site, configuration)
        builder = DocumentBuilder.new
        documents = collection_documents(site, configuration, builder)
        documents.concat(page_documents(site, builder, configuration)) if configuration.include_pages?
        documents.compact.uniq { |document| document["id"] }
      end

      def enhance_with_embeddings(site, documents, configuration)
        embedding_jobs(configuration).each do |job|
          cache = IndexCache.new(site.source, embedding_identity: job[:identity],
                                              file_name: job[:cache_file])
          adapter = build_embedding_adapter(configuration, model: job[:model])

          documents.each { |entry| embed_document(entry, cache, adapter, configuration, job) }
          cache.prune(documents.map { |doc| doc["id"] })
          cache.save
        end
        documents
      end

      # Each job embeds every document once per model into a target field.
      # The index model writes "embedding" (kept when include_in_index); a
      # divergent related model writes "related_embedding" (stripped before
      # the index is emitted). Identical models share a single pass.
      def embedding_jobs(configuration)
        jobs = []
        jobs << index_embedding_job(configuration) if configuration.embedding_include_in_index?
        jobs.concat(related_embedding_jobs(configuration)) if configuration.related_enabled?
        jobs
      end

      def index_embedding_job(configuration)
        {
          model: configuration.embedding_index_model,
          field: "embedding",
          document_prefix: configuration.embedding_document_prefix,
          identity: configuration.embedding_identity,
          cache_file: IndexCache::CACHE_FILE
        }
      end

      def related_embedding_jobs(configuration)
        return [related_embedding_job("embedding", IndexCache::CACHE_FILE, configuration)] unless
          configuration.embedding_include_in_index?
        return [] if configuration.embedding_related_model == configuration.embedding_index_model

        [related_embedding_job("related_embedding", IndexCache::RELATED_CACHE_FILE, configuration)]
      end

      def related_embedding_job(field, cache_file, configuration)
        {
          model: configuration.embedding_related_model,
          field: field,
          document_prefix: configuration.embedding_related_document_prefix,
          identity: configuration.embedding_related_identity,
          cache_file: cache_file
        }
      end

      def build_embedding_adapter(configuration, model: configuration.embedding_model)
        OllamaEmbeddingAdapter.new(
          model: model,
          base_url: configuration.embedding_base_url,
          connect_timeout: configuration.embedding_connect_timeout,
          read_timeout: configuration.embedding_read_timeout
        )
      end

      def add_related_page(site, documents, configuration)
        relation_data = RelatedAnalyzer.new(configuration.related_configuration).analyze(documents)
        site.pages << RelatedPage.new(site, configuration.related_output, relation_data)
      end

      def remove_embeddings(documents)
        documents.each { |document| document.delete("embedding") }
      end

      def embed_document(document, cache, adapter, configuration, job)
        hash = IndexCache.content_hash(document.except("embedding", "related_embedding"))
        return if embedding_restored?(document, cache, hash, job[:field])

        embedding = adapter.embed(embedding_text(document, job[:document_prefix]))
        if embedding
          document[job[:field]] = embedding
          cache.store(document["id"], hash, embedding)
        elsif configuration.embedding_fail_on_error?
          raise Jekyll::Errors::FatalException,
                "embedding generation failed for document #{document['id'].inspect}"
        end
      end

      def embedding_restored?(document, cache, hash, field)
        cached = cache.lookup(document["id"], hash)
        return false unless cached && cached["embedding"]

        document[field] = cached["embedding"]
        true
      end

      def embedding_text(document, document_prefix)
        text = [document["title"], document["excerpt"], document["content"]].compact.join(" ")
        "#{document_prefix}#{text}"
      end

      def collection_documents(site, configuration, builder)
        fields = configuration.passthrough_fields
        configuration.collections.flat_map do |label|
          collection = label == "posts" ? site.posts : site.collections[label]
          next [] unless collection

          collection.docs.filter_map do |document|
            builder.from_document(document, source: label, passthrough_fields: fields)
          end
        end
      end

      def page_documents(site, builder, configuration)
        fields = configuration.passthrough_fields
        site.pages
            .reject { |page| page.url == "/#{configuration.output}" }
            .select { |page| page.data["title"] }
            .filter_map { |page| builder.from_document(page, source: "pages", passthrough_fields: fields) }
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

      def add_embedder_config(site, configuration)
        site.pages << EmbedderConfigPage.new(site, configuration)
      end

      def semantic_query_embedder?(configuration)
        configuration.engine == "semantic" && configuration.embedding_enabled? &&
          configuration.query_embedder_type != "none"
      end

      def normalized_path(path)
        path.to_s.sub(%r{\A/}, "")
      end
    end
  end
end
