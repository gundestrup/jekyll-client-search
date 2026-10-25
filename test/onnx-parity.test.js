"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

/**
 * Cross-runtime parity check (opt-in).
 *
 * Verifies that the transformers.js ONNX twin produces vectors that match
 * the Ollama build model closely enough that browser queries rank the
 * Ollama-embedded index correctly. Covers the packaged
 * `query_embedder_configuration.rb` MODEL_MAP entry:
 *
 *   embeddinggemma-2(:270m|:570m) → onnx-community/embeddinggemma-2-ONNX
 *
 * Requirements:
 *   - npm i -D @huggingface/transformers@3.8.1 (same pin as the CDN default)
 *   - a running Ollama server with the build model pulled
 *
 * Run:
 *   ONNX_PARITY=1 node --test test/onnx-parity.test.js
 *   OLLAMA_MODEL=embeddinggemma-2:270m ONNX_PARITY=1 node --test test/onnx-parity.test.js
 */

const OLLAMA_URL = process.env.OLLAMA_BASE_URL || "http://127.0.0.1:11434";
const OLLAMA_MODEL = process.env.OLLAMA_MODEL || "embeddinggemma-2:570m";
const ONNX_MODEL = process.env.ONNX_MODEL || "onnx-community/embeddinggemma-2-ONNX";
const ONNX_DTYPE = process.env.ONNX_DTYPE || "q8";
const DOCUMENT_PREFIX = "title: none | text: ";
const QUERY_PREFIX = "task: search result | query: ";

const DOCUMENTS = [
    "Greenland travel journal with ice fjords and northern lights",
    "Fresh pasta recipe with flour, eggs, and a rolling pin",
    "Ice climbing on frozen waterfalls in the arctic winter",
    "Family birthday celebration with cake and candles"
];
const QUERY = "climbing ice walls in cold weather";

function cosineSimilarity(a, b) {
    assert.equal(a.length, b.length, "vector dimensions must match");
    var dot = 0;
    var normA = 0;
    var normB = 0;
    for (var i = 0; i < a.length; i += 1) {
        dot += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

async function ollamaEmbed(text) {
    const response = await fetch(`${OLLAMA_URL}/api/embed`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: OLLAMA_MODEL, input: text })
    });
    if (!response.ok) {
        throw new Error(`Ollama /api/embed returned ${response.status}`);
    }
    const data = await response.json();
    return data.embeddings[0];
}

async function loadExtractor(t) {
    let transformers;
    try {
        transformers = await import("@huggingface/transformers");
    } catch {
        t.skip("@huggingface/transformers is not installed — run: npm i -D @huggingface/transformers@3.8.1");
        return null;
    }
    return transformers.pipeline("feature-extraction", ONNX_MODEL, { dtype: ONNX_DTYPE });
}

test("ONNX and Ollama embeddingsgemma-2 vectors agree", { skip: process.env.ONNX_PARITY ? false : "set ONNX_PARITY=1" }, async function (t) {
    const extractor = await loadExtractor(t);
    if (!extractor) {
        return;
    }

    let ollamaQuery;
    try {
        ollamaQuery = await ollamaEmbed(`${QUERY_PREFIX}${QUERY}`);
    } catch (error) {
        t.skip(`Ollama not reachable or ${OLLAMA_MODEL} not pulled: ${error.message}`);
        return;
    }

    // Per-text vector parity — q8 quantization allows small drift.
    for (const document of DOCUMENTS) {
        const ollamaVector = await ollamaEmbed(`${DOCUMENT_PREFIX}${document}`);
        const onnxOutput = await extractor(`${DOCUMENT_PREFIX}${document}`, { pooling: "mean", normalize: true });
        const similarity = cosineSimilarity(ollamaVector, Array.from(onnxOutput.data));
        assert.ok(
            similarity > 0.95,
            `${ONNX_MODEL} vs ${OLLAMA_MODEL} cosine ${similarity.toFixed(4)} < 0.95 for "${document}"`
        );
    }

    // Ranking parity — the browser-embedded query must pick the same
    // best document as the Ollama-embedded query.
    const onnxQuery = await extractor(`${QUERY_PREFIX}${QUERY}`, { pooling: "mean", normalize: true });
    const onnxQueryVector = Array.from(onnxQuery.data);

    for (const [label, queryVector] of [["ollama", ollamaQuery], ["onnx", onnxQueryVector]]) {
        const scored = [];
        for (const document of DOCUMENTS) {
            const ollamaVector = await ollamaEmbed(`${DOCUMENT_PREFIX}${document}`);
            scored.push([cosineSimilarity(queryVector, ollamaVector), document]);
        }
        scored.sort(function (a, b) { return b[0] - a[0]; });
        assert.equal(
            scored[0][1], DOCUMENTS[2],
            `${label} query ranked "${scored[0][1]}" first, expected "${DOCUMENTS[2]}"`
        );
    }
});
