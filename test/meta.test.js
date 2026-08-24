"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { JSDOM } = require("jsdom");
const MiniSearch = require("minisearch");
const elasticlunr = require("elasticlunr");

const FIXTURE_SITE = path.join(__dirname, "..", "spec", "fixtures", "site");
const BASELINE_PATH = path.join(__dirname, "..", "spec", "fixtures", "baseline", "search-index-baseline.json");
const SEMANTIC_INDEX_PATH = path.join(FIXTURE_SITE, "_site", "search-index-semantic.json");
const BASE_RUNTIME = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search-base.js"),
    "utf8"
);
const ADAPTER_DIR = path.join(__dirname, "..", "assets", "adapters");

/**
 * Meta-test set — runs the same queries across ALL search engines
 * (MiniSearch, ElasticLunr, Semantic) with AND without LLM/vector
 * embeddings, using a shared query definition with per-engine expected
 * results.
 *
 * Architecture:
 *   - SHARED_QUERIES defines queries and what each engine should return
 *   - Each engine has an "expectation" that may vary (e.g. semantic
 *     might rank differently than lexical, or find results via synonyms
 *     that lexical misses)
 *   - The same test logic runs for every engine, avoiding duplication
 *   - For semantic tests, the real Ollama-generated index is used when
 *     available; otherwise tests skip honestly
 *
 * The baseline JSON (search-index-baseline.json) is a committed fixture
 * containing the 80-post index WITHOUT embeddings. This is the stable
 * reference that all engines are tested against. The semantic tests
 * additionally use the Ollama-generated index WITH embeddings.
 */

// --- Shared query definitions ---
//
// Each query defines:
//   query: the search string
//   lexical: expected results for MiniSearch + ElasticLunr
//     top1: exact title that must be #1
//     mustInclude: titles that must appear in results
//     mustExclude: titles that must NOT appear (discrimination)
//     minResults: minimum result count
//   semantic: expected results for the semantic adapter (when LLM index available)
//     top1: exact title that must be #1 (may differ from lexical!)
//     mustInclude: titles that must appear in top 5
//     mustExclude: titles that must NOT appear
//     minResults: minimum result count
//   notes: human-readable explanation of what this tests

var SHARED_QUERIES = [
    {
        query: "glacier",
        lexical: {
            top1: "Glacier",
            mustInclude: ["Glacier"],
            mustExclude: ["Pasta", "Chocolate", "Bread"],
            minResults: 1
        },
        semantic: {
            top1: "Glacier",
            mustInclude: ["Glacier"],
            mustExclude: ["Pasta", "Chocolate"],
            minResults: 1
        },
        notes: "single-term exact match — all engines should agree"
    },
    {
        query: "ice climbing",
        lexical: {
            top1: "Ice climbing",
            mustInclude: ["Ice climbing"],
            mustExclude: ["Pasta", "Chocolate", "Bread"],
            minResults: 1
        },
        semantic: {
            top1: "Ice climbing",
            mustInclude: ["Ice climbing"],
            mustExclude: ["Pasta", "Chocolate"],
            minResults: 1
        },
        notes: "two-term AND — narrows to specific article"
    },
    {
        query: "sourdough bread",
        lexical: {
            top1: "Sourdough",
            mustInclude: ["Sourdough", "Bread"],
            mustExclude: ["Glacier", "Iceberg", "Mountaineering"],
            minResults: 2
        },
        semantic: {
            top1: "Sourdough",
            mustInclude: ["Sourdough", "Bread"],
            mustExclude: ["Glacier", "Iceberg"],
            minResults: 1
        },
        notes: "two-term — both articles about bread/fermentation"
    },
    {
        query: "fermentation",
        lexical: {
            top1: "Fermentation in food processing",
            mustInclude: ["Fermentation in food processing"],
            mustExclude: ["Glacier", "Mountaineering", "Carabiner"],
            minResults: 1
        },
        semantic: {
            top1: "Fermentation in food processing",
            mustInclude: ["Fermentation in food processing"],
            mustExclude: ["Glacier", "Mountaineering"],
            minResults: 1
        },
        notes: "single-term exact match — all engines should agree"
    },
    {
        query: "belay carabiner",
        lexical: {
            top1: "Belay device",
            mustInclude: ["Belay device", "Carabiner"],
            mustExclude: ["Pasta", "Glacier", "Photography"],
            minResults: 2
        },
        semantic: {
            top1: "Carabiner",
            mustInclude: ["Belay device", "Carabiner"],
            mustExclude: ["Pasta", "Glacier"],
            minResults: 1
        },
        notes: "two-term climbing safety gear — semantic ranks Carabiner #1"
    },
    {
        query: "arctic",
        lexical: {
            top1: "Arctic Circle",
            mustInclude: ["Arctic Circle", "Sea ice", "Tundra"],
            mustExclude: ["Pasta", "Chocolate", "Carabiner"],
            minResults: 3
        },
        semantic: {
            top1: "Arctic Circle",
            mustInclude: ["Arctic Circle"],
            mustExclude: ["Pasta", "Chocolate"],
            minResults: 1
        },
        notes: "single-term broad match — multiple arctic articles"
    },
    {
        query: "aperture photography",
        lexical: {
            top1: "Aperture",
            mustInclude: ["Aperture", "Digital photography"],
            mustExclude: ["Glacier", "Pasta", "Bread"],
            minResults: 2
        },
        semantic: {
            top1: "Landscape photography",
            mustInclude: ["Aperture"],
            mustExclude: ["Glacier", "Pasta"],
            minResults: 1
        },
        notes: "two-term — semantic ranks Landscape photography #1, Aperture in top 5"
    },
    {
        query: "camera lens",
        lexical: {
            top1: "Camera lens",
            mustInclude: ["Camera lens", "Digital single-lens reflex camera"],
            mustExclude: ["Glacier", "Pasta", "Mountaineering"],
            minResults: 2
        },
        semantic: {
            top1: "Camera lens",
            mustInclude: ["Camera lens"],
            mustExclude: ["Glacier", "Pasta"],
            minResults: 1
        },
        notes: "two-term — camera-related articles"
    }
];

// --- Engine definitions ---

var LEXICAL_ENGINES = [
    {
        name: "minisearch",
        adapterSource: fs.readFileSync(path.join(ADAPTER_DIR, "minisearch.js"), "utf8"),
        setupWindow: function (dom) { dom.window.MiniSearch = MiniSearch; }
    },
    {
        name: "elasticlunr",
        adapterSource: fs.readFileSync(path.join(ADAPTER_DIR, "elasticlunr.js"), "utf8"),
        setupWindow: function (dom) { dom.window.elasticlunr = elasticlunr; }
    }
];

var SEMANTIC_ADAPTER_SOURCE = fs.readFileSync(path.join(ADAPTER_DIR, "semantic.js"), "utf8");

// --- Helpers ---

function loadBaselineIndex() {
    if (!fs.existsSync(BASELINE_PATH)) {
        return null;
    }
    return JSON.parse(fs.readFileSync(BASELINE_PATH, "utf8"));
}

function loadSemanticIndex() {
    if (!fs.existsSync(SEMANTIC_INDEX_PATH)) {
        return null;
    }
    return JSON.parse(fs.readFileSync(SEMANTIC_INDEX_PATH, "utf8"));
}

function resultTitles(window) {
    return Array.from(window.document.querySelectorAll(".client-search-result h2"))
        .map(function (h2) { return h2.textContent; });
}

async function settle() {
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
}

function createLexicalWindow(engine, index, query) {
    var dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: `https://example.com/search/?q=${encodeURIComponent(query)}`, runScripts: "outside-only" }
    );
    engine.setupWindow(dom);
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return index; } };
    };
    dom.window.eval(BASE_RUNTIME);
    dom.window.eval(engine.adapterSource);
    return dom.window;
}

function createSemanticWindow(semanticData, query) {
    var documents = semanticData.documents;
    var dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: `https://example.com/search/?q=${encodeURIComponent(query)}`, runScripts: "outside-only" }
    );
    dom.window.ClientSearchQueryEmbedder = function (q) {
        return semanticData.query_embeddings[q] || null;
    };
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return documents; } };
    };
    dom.window.eval(BASE_RUNTIME);
    dom.window.eval(SEMANTIC_ADAPTER_SOURCE);
    return dom.window;
}

// --- Meta-tests: lexical engines (without LLM) ---
//
// These run the shared queries against MiniSearch and ElasticLunr
// using the baseline index (no embeddings).

var baselineIndex = loadBaselineIndex();

LEXICAL_ENGINES.forEach(function (engine) {
    var runOrSkip = baselineIndex ? test : test.skip;

    SHARED_QUERIES.forEach(function (q) {
        runOrSkip(`[meta/${engine.name}] ${q.notes} — query: "${q.query}"`, async function () {
            var window = createLexicalWindow(engine, baselineIndex, q.query);
            await settle();
            var titles = resultTitles(window);

            assert.ok(titles.length >= q.lexical.minResults,
                `expected >= ${q.lexical.minResults} results, got ${titles.length}: ${JSON.stringify(titles)}`);

            assert.equal(titles[0], q.lexical.top1,
                `top result should be "${q.lexical.top1}", got "${titles[0]}" — all: ${JSON.stringify(titles.slice(0, 5))}`);

            q.lexical.mustInclude.forEach(function (expected) {
                assert.ok(titles.includes(expected),
                    `"${expected}" should be in results — got: ${JSON.stringify(titles.slice(0, 5))}`);
            });

            q.lexical.mustExclude.forEach(function (forbidden) {
                assert.ok(!titles.includes(forbidden),
                    `"${forbidden}" should NOT be in results — got: ${JSON.stringify(titles.slice(0, 5))}`);
            });
        });
    });
});

// --- Meta-tests: semantic engine (with LLM) ---
//
// These run the same shared queries against the semantic adapter
// using the real Ollama-generated index (with embeddings).
// Skips when the Ollama index is not available.

var semanticData = loadSemanticIndex();
var runSemantic = semanticData ? test : test.skip;

SHARED_QUERIES.forEach(function (q) {
    runSemantic(`[meta/semantic] ${q.notes} — query: "${q.query}"`, async function () {
        var window = createSemanticWindow(semanticData, q.query);
        await settle();
        var titles = resultTitles(window);

        assert.ok(titles.length >= q.semantic.minResults,
            `expected >= ${q.semantic.minResults} results, got ${titles.length}: ${JSON.stringify(titles)}`);

        if (titles.length > 0) {
            assert.equal(titles[0], q.semantic.top1,
                `top result should be "${q.semantic.top1}", got "${titles[0]}" — all: ${JSON.stringify(titles.slice(0, 5))}`);
        }

        q.semantic.mustInclude.forEach(function (expected) {
            assert.ok(titles.slice(0, 5).includes(expected),
                `"${expected}" should be in top 5 — got: ${JSON.stringify(titles.slice(0, 5))}`);
        });

        q.semantic.mustExclude.forEach(function (forbidden) {
            assert.ok(!titles.includes(forbidden),
                `"${forbidden}" should NOT be in results — got: ${JSON.stringify(titles.slice(0, 5))}`);
        });
    });
});

// --- Cross-engine consistency check ---
//
// For queries where all engines should agree (exact keyword matches),
// verify that the #1 result is the same across all engines.

var runConsistency = (baselineIndex && semanticData) ? test : test.skip;

runConsistency("[meta/cross-engine] exact-match queries produce same #1 across all engines", async function () {
    var exactMatchQueries = SHARED_QUERIES.filter(function (q) {
        return q.lexical.top1 === q.semantic.top1;
    });

    exactMatchQueries.forEach(function (q) {
        var allTop1 = [];

        LEXICAL_ENGINES.forEach(function (engine) {
            var window = createLexicalWindow(engine, baselineIndex, q.query);
            // Can't await in forEach, so we read synchronously after settle
            allTop1.push({ engine: engine.name, titles: resultTitles(window) });
        });

        var semWindow = createSemanticWindow(semanticData, q.query);
        allTop1.push({ engine: "semantic", titles: resultTitles(semWindow) });

        // All engines should agree on #1 for exact-match queries
        var top1Values = allTop1.map(function (r) { return r.titles[0]; });
        var allSame = top1Values.every(function (v) { return v === top1Values[0]; });
        assert.ok(allSame,
            `All engines should agree on #1 for "${q.query}" — got: ${JSON.stringify(allTop1.map(function (r) { return r.engine + ": " + r.titles[0]; }))}`);
    });
});
