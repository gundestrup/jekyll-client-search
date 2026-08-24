"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const MiniSearch = require("minisearch");
const elasticlunr = require("elasticlunr");
const { JSDOM } = require("jsdom");

const baseRuntime = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search-base.js"),
    "utf8"
);
const adapterDir = path.join(__dirname, "..", "assets", "adapters");

/**
 * Uniform test suite — the same assertions run against every JS adapter so
 * that adding a new engine (e.g. a future vector/semantic adapter) only
 * requires registering it here, not writing a new test file.
 */
function adapterSuites() {
    return [
        {
            name: "minisearch",
            adapterSource: fs.readFileSync(path.join(adapterDir, "minisearch.js"), "utf8"),
            setupWindow: function (dom) {
                dom.window.MiniSearch = MiniSearch;
            }
        },
        {
            name: "elasticlunr",
            adapterSource: fs.readFileSync(path.join(adapterDir, "elasticlunr.js"), "utf8"),
            setupWindow: function (dom) {
                dom.window.elasticlunr = elasticlunr;
            }
        },
        {
            name: "semantic",
            adapterSource: fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8"),
            setupWindow: function (dom) {
                // Provide a mock query embedder that maps known queries to
                // pre-defined vectors. This lets us test the semantic adapter's
                // cosine similarity ranking without a real model.
                dom.window.ClientSearchQueryEmbedder = function (query) {
                    var embeddings = {
                        "greenland": [1.0, 0.0, 0.0],
                        "ice": [0.0, 1.0, 0.0],
                        "other": [0.0, 0.0, 1.0]
                    };
                    return embeddings[query] || [0.1, 0.1, 0.1];
                };
            },
            // Semantic adapter needs documents with embedding fields.
            // Only add mock embeddings to documents that don't already have
            // them — tests that provide their own embeddings should pass through.
            makeIndex: function (baseIndex) {
                if (!Array.isArray(baseIndex)) {
                    return baseIndex;
                }
                return baseIndex.map(function (doc) {
                    if (doc.embedding) {
                        return doc;
                    }
                    var embeddings = {
                        "/greenland/": [1.0, 0.1, 0.0],
                        "/other/": [0.0, 0.0, 1.0]
                    };
                    return Object.assign({}, doc, { embedding: embeddings[doc.id] || [0.1, 0.1, 0.1] });
                });
            }
        }
    ];
}

function createWindow(suite, index, query = "greenland") {
    var effectiveIndex = suite.makeIndex ? suite.makeIndex(index) : index;
    const dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: `https://example.com/search/?q=${encodeURIComponent(query)}`, runScripts: "outside-only" }
    );
    suite.setupWindow(dom);
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return effectiveIndex; } };
    };
    dom.window.eval(baseRuntime);
    dom.window.eval(suite.adapterSource);
    return dom.window;
}

async function settle() {
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
}

const sampleIndex = [
    {
        id: "/greenland/",
        title: "Greenland",
        url: "/greenland/",
        excerpt: "A Greenland article",
        content: "Ice and travel",
        categories: ["travel"],
        tags: ["ice"]
    },
    {
        id: "/other/",
        title: "Other",
        url: "/other/",
        excerpt: "Unrelated",
        content: "Other content",
        categories: [],
        tags: []
    }
];

adapterSuites().forEach(function (suite) {
    test(`[${suite.name}] loads the generated index and renders ranked results`, async function () {
        const window = createWindow(suite, sampleIndex);

        await settle();

        assert.equal(window.document.querySelector("#search-status").textContent, "1 result");
        const result = window.document.querySelector(".client-search-result");
        assert.equal(result.querySelector("h2").textContent, "Greenland");
        assert.equal(result.querySelector("a").getAttribute("href"), "/greenland/");
    });

    // The AND→OR fallback is a lexical search strategy. The semantic adapter
    // uses cosine similarity ranking instead, so this test only applies to
    // the lexical adapters.
    if (suite.name !== "semantic") {
        test(`[${suite.name}] falls back to OR search when AND returns no results`, async function () {
            const window = createWindow(suite, [sampleIndex[0]], "greenland missingword");

            await settle();

            assert.equal(window.document.querySelector("#search-status").textContent, "1 result");
            assert.equal(window.document.querySelector(".client-search-result h2").textContent, "Greenland");
        });
    }

    test(`[${suite.name}] does not allow unsafe result URLs`, async function () {
        const window = createWindow(suite, [
            {
                id: "unsafe",
                title: "Unsafe",
                url: "javascript:alert(1)",
                excerpt: "unsafe result",
                content: "unsafe",
                categories: [],
                tags: []
            }
        ], "unsafe");

        await settle();

        assert.equal(window.document.querySelector(".client-search-result a").getAttribute("href"), "#");
    });

    test(`[${suite.name}] reports invalid index data without rendering results`, async function () {
        const window = createWindow(suite, { invalid: true });

        await settle();

        assert.equal(window.document.querySelector("#search-status").textContent, "Search is temporarily unavailable.");
        assert.equal(window.document.querySelector("#search-results").children.length, 0);
    });

    test(`[${suite.name}] clears results when the query is empty`, async function () {
        const window = createWindow(suite, sampleIndex, "");

        await settle();

        assert.equal(window.document.querySelector("#search-results").children.length, 0);
    });
});

// --- Semantic adapter specific tests ---
//
// These tests verify the semantic adapter's cosine similarity math, threshold
// filtering, index building, and ranking behavior using controlled mock
// embeddings where the expected similarity values can be computed by hand.

test("[semantic] cosine similarity ranks by relevance", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");

    // Documents with known embeddings:
    //   doc A: [1, 0, 0] — identical to query "greenland" → similarity 1.0
    //   doc B: [0.7, 0.7, 0] — 45 degrees from query → similarity ~0.707
    //   doc C: [0, 0, 1] — orthogonal to query → similarity 0.0 (below threshold)
    var index = [
        { id: "/a/", title: "A", url: "/a/", excerpt: "a", content: "a", categories: [], tags: [], embedding: [1, 0, 0] },
        { id: "/b/", title: "B", url: "/b/", excerpt: "b", content: "b", categories: [], tags: [], embedding: [0.7, 0.7, 0] },
        { id: "/c/", title: "C", url: "/c/", excerpt: "c", content: "c", categories: [], tags: [], embedding: [0, 0, 1] }
    ];

    const dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: "https://example.com/search/?q=greenland", runScripts: "outside-only" }
    );
    dom.window.ClientSearchQueryEmbedder = function (query) {
        var embeddings = { "greenland": [1.0, 0.0, 0.0] };
        return embeddings[query] || null;
    };
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return index; } };
    };
    dom.window.eval(baseRuntime);
    dom.window.eval(semanticAdapterSource);

    await settle();

    var titles = Array.from(dom.window.document.querySelectorAll(".client-search-result h2"))
        .map(function (h2) { return h2.textContent; });

    // A should be first (similarity 1.0), B second (similarity ~0.707)
    // C should be filtered out (similarity 0.0 < threshold 0.3)
    assert.deepEqual(titles, ["A", "B"], "should rank by cosine similarity and filter below threshold");
});

test("[semantic] buildIndex filters documents without embeddings", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");

    var index = [
        { id: "/with-emb/", title: "With", url: "/with-emb/", excerpt: "x", content: "x", categories: [], tags: [], embedding: [1, 0, 0] },
        { id: "/no-emb/", title: "NoEmb", url: "/no-emb/", excerpt: "y", content: "y", categories: [], tags: [] }
    ];

    const dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: "https://example.com/search/?q=greenland", runScripts: "outside-only" }
    );
    dom.window.ClientSearchQueryEmbedder = function () { return [1.0, 0.0, 0.0]; };
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return index; } };
    };
    dom.window.eval(baseRuntime);
    dom.window.eval(semanticAdapterSource);

    await settle();

    var titles = Array.from(dom.window.document.querySelectorAll(".client-search-result h2"))
        .map(function (h2) { return h2.textContent; });

    assert.ok(titles.includes("With"), "document with embedding should be searchable");
    assert.ok(!titles.includes("NoEmb"), "document without embedding should be filtered out");
});

test("[semantic] returns empty results when no query embedder is available", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");

    const dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: "https://example.com/search/?q=test", runScripts: "outside-only" }
    );
    // Do NOT set ClientSearchQueryEmbedder or window.transformers
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return [{ id: "/a/", title: "A", url: "/a/", embedding: [1, 0] }]; } };
    };
    dom.window.eval(baseRuntime);
    dom.window.eval(semanticAdapterSource);

    await settle();

    assert.equal(dom.window.document.querySelector("#search-status").textContent, "Search is temporarily unavailable.");
});

test("[semantic] available() returns false when no embedder is loaded", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");

    const dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.eval(semanticAdapterSource);

    var adapter = dom.window.ClientSearchAdapters.semantic;
    assert.equal(adapter.available(), false, "should be unavailable without transformers.js or embedder");
});

test("[semantic] available() returns true when ClientSearchQueryEmbedder is set", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");

    const dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () { return [1, 0]; };
    dom.window.eval(semanticAdapterSource);

    var adapter = dom.window.ClientSearchAdapters.semantic;
    assert.equal(adapter.available(), true);
});
