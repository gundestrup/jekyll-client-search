# frozen_string_literal: true

module Jekyll
  module ClientSearch
    # Builds deterministic related-article records from metadata and vectors.
    class RelatedAnalyzer
      def initialize(configuration)
        @configuration = configuration
      end

      def analyze(documents)
        relations = documents.each_with_index.to_h do |source, index|
          candidates = documents.each_with_index.filter_map do |target, target_index|
            next if index == target_index

            build_relation(source, target)
          end
          [source.fetch("id"), sort_relations(candidates)]
        end

        {
          "version" => 1,
          "minimum_similarity" => @configuration.minimum_similarity,
          "relations" => relations
        }
      end

      private

      def build_relation(source, target)
        metadata = metadata_relation(source, target)
        semantic_similarity = similarity(source["embedding"], target["embedding"])
        return unless metadata || semantic_match?(semantic_similarity)

        relation = base_relation(target, metadata, semantic_similarity)
        add_semantic_relation(relation, semantic_similarity) if semantic_match?(semantic_similarity)
        add_metadata_relation(relation, metadata)
        relation
      end

      def semantic_match?(similarity)
        @configuration.semantic? && similarity && similarity >= @configuration.minimum_similarity
      end

      def base_relation(target, metadata, semantic_similarity)
        metadata_score = metadata ? metadata.fetch(:score) : 0.0
        score = [metadata_score, semantic_similarity || 0.0].max
        reasons = metadata ? metadata.fetch(:reasons).dup : []
        reasons << "semantic-similarity" if semantic_match?(semantic_similarity)
        {
          "id" => target.fetch("id"),
          "title" => target.fetch("title"),
          "url" => target.fetch("url"),
          "date" => target["date"],
          "date_timestamp" => target["date_timestamp"],
          "score" => score.round(6),
          "reasons" => reasons.uniq.sort
        }.compact
      end

      def add_semantic_relation(relation, similarity)
        relation["semantic_similarity"] = similarity.round(6)
      end

      def add_metadata_relation(relation, metadata)
        return unless metadata

        relation["shared_tags"] = metadata.fetch(:tags) if metadata.fetch(:tags).any?
        relation["shared_categories"] = metadata.fetch(:categories) if metadata.fetch(:categories).any?
        relation["shared_domains"] = metadata.fetch(:domains) if metadata.fetch(:domains).any?
      end

      def metadata_relation(source, target)
        shared_tags = configured_intersection(source["tags"], target["tags"], @configuration.shared_tags?)
        shared_categories = configured_intersection(
          source["categories"], target["categories"], @configuration.same_category?
        )
        shared_domains = configured_intersection(
          domain_paths(source), domain_paths(target), @configuration.include_parent_domains?
        ) - shared_categories
        return if shared_tags.empty? && shared_categories.empty? && shared_domains.empty?

        {
          score: metadata_score(source, target, shared_tags, shared_categories, shared_domains),
          tags: shared_tags,
          categories: shared_categories,
          domains: shared_domains,
          reasons: metadata_reasons(shared_tags, shared_categories, shared_domains)
        }
      end

      def configured_intersection(first, second, enabled)
        enabled ? intersection(first, second) : []
      end

      def metadata_score(source, target, tags, categories, domains)
        tag_score = tags.empty? ? 0.0 : 0.25 * tags.length.to_f / union(source["tags"], target["tags"]).length
        [tag_score + (categories.any? ? 0.5 : 0.0) + (domains.any? ? 0.25 : 0.0), 0.01].max
      end

      def metadata_reasons(tags, categories, domains)
        tags.map { |tag| "shared-tag: #{tag}" } +
          categories.map { |category| "shared-category: #{category}" } +
          domains.map { |domain| "shared-domain: #{domain}" }
      end

      def sort_relations(relations)
        sorted = relations.sort_by do |relation|
          [-relation.fetch("score"), relation.fetch("title"), relation.fetch("id")]
        end
        maximum = @configuration.max_items
        maximum ? sorted.first(maximum) : sorted
      end

      def similarity(first, second)
        return unless valid_vector?(first)
        return unless valid_vector?(second)
        return unless first.length == second.length

        dot = first.zip(second).sum { |a, b| a * b }
        denominator = vector_norm(first) * vector_norm(second)
        denominator.zero? ? 0.0 : dot / denominator
      end

      def vector_norm(vector)
        Math.sqrt(vector.sum { |value| value * value })
      end

      def valid_vector?(vector)
        return false unless vector.is_a?(Array)
        return false if vector.empty?

        vector.all? { |value| value.is_a?(Numeric) && value.finite? }
      end

      def intersection(first, second)
        (Array(first).map(&:to_s) & Array(second).map(&:to_s)).sort
      end

      def union(first, second)
        (Array(first).map(&:to_s) | Array(second).map(&:to_s))
      end

      def domain_paths(document)
        Array(document["categories"]).flat_map do |category|
          parts = category.to_s.split("/").reject(&:empty?)
          parts.each_index.map { |index| parts.first(index + 1).join("/") }
        end.uniq
      end
    end
  end
end
