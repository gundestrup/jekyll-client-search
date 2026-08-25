(function () {
    "use strict";

    /**
     * Semantic adapter — vector similarity search against pre-computed
     * embeddings in the JSON index.
     *
     * This adapter expects each document to have an `embedding` field
     * (a float vector) generated at Jekyll build time by the
     * OllamaEmbeddingAdapter. At search time it calls
     * ClientSearchQueryEmbedder, provided by a packaged query embedder or the
     * consuming site, then ranks documents by cosine similarity.
     *
     * The base runtime's two-stage AND/OR strategy does not apply to
     * vector search. This adapter implements its own ranking: it computes
     * cosine similarity between the query embedding and every document
     * embedding, returns those above a threshold, sorted by similarity.
     *
     * To use this adapter:
     *   1. Configure embedding.enabled: true in _config.yml
     *   2. Load the generated config and selected query-embedder script first
     *   3. Use the same model and preprocessing at build and query time
     *
     * The embedder may return an array, typed array, or Promise of either.
     */
    var SIMILARITY_THRESHOLD = 0.3;
    var MAX_QUERY_CACHE_ENTRIES = 100;
    var queryEmbeddingCache = new Map();

    function cacheQueryEmbedding(query, value) {
        queryEmbeddingCache.delete(query);
        queryEmbeddingCache.set(query, value);
        if (queryEmbeddingCache.size > MAX_QUERY_CACHE_ENTRIES) {
            queryEmbeddingCache.delete(queryEmbeddingCache.keys().next().value);
        }
    }

    function normalizeVector(value) {
        var vector = null;
        if (Array.isArray(value)) {
            vector = value;
        } else if (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView(value)) {
            vector = Array.from(value);
        }
        if (!vector || vector.length === 0 || !vector.every(function (entry) {
            return typeof entry === "number" && Number.isFinite(entry);
        })) {
            return null;
        }
        return vector;
    }

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
            return typeof window.ClientSearchQueryEmbedder === "function";
        },

        buildIndex: function (documents) {
            var expectedDimension = null;
            return documents.filter(function (doc) {
                var embedding = normalizeVector(doc.embedding);
                if (!embedding) {
                    return false;
                }
                if (expectedDimension === null) {
                    expectedDimension = embedding.length;
                } else if (embedding.length !== expectedDimension) {
                    throw new RangeError("Document embedding dimensions do not match");
                }
                return true;
            });
        },

        search: function (index, query, _options) {
            if (typeof window.ClientSearchQueryEmbedder !== "function" || index.length === 0) {
                return [];
            }

            var cached = queryEmbeddingCache.get(query);
            if (cached) {
                cacheQueryEmbedding(query, cached);
                return cached && typeof cached.then === "function"
                    ? cached.then(function (embedding) { return rank(index, embedding); })
                    : rank(index, cached);
            }

            var result = window.ClientSearchQueryEmbedder(query);
            if (result && typeof result.then === "function") {
                var pending = result.then(function (queryEmbedding) {
                    var normalized = normalizeVector(queryEmbedding);
                    if (!normalized) {
                        throw new TypeError("Query embedding must contain finite numeric values");
                    }
                    cacheQueryEmbedding(query, normalized);
                    return normalized;
                }).catch(function (error) {
                    queryEmbeddingCache.delete(query);
                    throw error;
                });
                cacheQueryEmbedding(query, pending);
                return pending.then(function (embedding) { return rank(index, embedding); });
            }
            var normalized = normalizeVector(result);
            if (!normalized) {
                throw new TypeError("Query embedding must contain finite numeric values");
            }
            cacheQueryEmbedding(query, normalized);
            return rank(index, normalized);
        }
    };

    function rank(index, queryEmbedding) {
        var expectedDimension = index[0] && index[0].embedding.length;
        if (expectedDimension && queryEmbedding.length !== expectedDimension) {
            throw new RangeError(
                "Query embedding dimension " + queryEmbedding.length +
                " does not match document dimension " + expectedDimension
            );
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

    if (window.ClientSearch) {
        window.ClientSearch.run(window.ClientSearchAdapters.semantic);
    }
}());
