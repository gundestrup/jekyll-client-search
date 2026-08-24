(function () {
    "use strict";

    /**
     * Semantic adapter — vector similarity search against pre-computed
     * embeddings in the JSON index.
     *
     * This adapter expects each document to have an `embedding` field
     * (a float vector) generated at Jekyll build time by the
     * OllamaEmbeddingAdapter. At search time it embeds the query using
     * the same model loaded via transformers.js in the browser, then
     * ranks documents by cosine similarity.
     *
     * The base runtime's two-stage AND/OR strategy does not apply to
     * vector search. This adapter implements its own ranking: it computes
     * cosine similarity between the query embedding and every document
     * embedding, returns those above a threshold, sorted by similarity.
     *
     * To use this adapter, the consuming site must:
     *   1. Configure embedding.enabled: true in _config.yml
     *   2. Load transformers.js in the browser
     *   3. Set window.clientSearchEmbeddingModel to the same model name
     *
     * Future enhancement: cache the query embedding model across searches.
     */
    var SIMILARITY_THRESHOLD = 0.3;

    function cosineSimilarity(a, b) {
        if (!a || !b || a.length !== b.length) {
            return 0;
        }
        var dot = 0;
        var normA = 0;
        var normB = 0;
        for (var i = 0; i < a.length; i++) {
            dot += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }
        var denom = Math.sqrt(normA) * Math.sqrt(normB);
        return denom === 0 ? 0 : dot / denom;
    }

    window.ClientSearchAdapters = window.ClientSearchAdapters || {};
    window.ClientSearchAdapters.semantic = {
        name: "semantic",

        available: function () {
            return typeof window.transformers !== "undefined" ||
                   typeof window.ClientSearchQueryEmbedder === "function";
        },

        buildIndex: function (documents) {
            return documents.filter(function (doc) {
                return Array.isArray(doc.embedding) && doc.embedding.length > 0;
            });
        },

        search: function (index, query, _options) {
            var queryEmbedding = window.ClientSearchQueryEmbedder
                ? window.ClientSearchQueryEmbedder(query)
                : null;
            if (!queryEmbedding) {
                return [];
            }
            return index.map(function (doc) {
                return {
                    ref: doc.id,
                    score: cosineSimilarity(queryEmbedding, doc.embedding)
                };
            }).filter(function (match) {
                return match.score >= SIMILARITY_THRESHOLD;
            }).sort(function (a, b) {
                return b.score - a.score;
            });
        }
    };

    if (window.ClientSearch) {
        window.ClientSearch.run(window.ClientSearchAdapters.semantic);
    }
}());
