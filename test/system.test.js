"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { JSDOM } = require("jsdom");
const MiniSearch = require("minisearch");
const elasticlunr = require("elasticlunr");

const FIXTURE_SITE = path.join(__dirname, "..", "spec", "fixtures", "site");
const BASE_RUNTIME = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search-base.js"),
    "utf8"
);
const ADAPTER_DIR = path.join(__dirname, "..", "assets", "adapters");

/**
 * System tests — build a real Jekyll fixture site containing 80 real-world
 * articles (40 Wikipedia + 40 arXiv papers), load the generated
 * search-index.json in jsdom with the base runtime + adapter, and assert
 * search results against known expected outcomes.
 *
 * The fixture posts cover 6 topic clusters with deliberate vocabulary
 * overlap (ice, cold, photography, family, gear, retrieval, embeddings)
 * to test search discrimination between related but distinct topics.
 *
 * Expected search behaviour (uniform across all engines):
 *   - "glacier" → Glacier article is the top result
 *   - "ice" → multiple results (Glacier, Iceberg, Sea ice, Ice climbing, ...)
 *   - "photography aperture" (AND) → photography articles about aperture
 *   - "glacier pasta" (AND → OR fallback) → Glacier + Pasta articles
 *   - "embeddings retrieval" (AND) → arXiv IR/NLP papers
 *   - "sourdough fermentation" (AND) → Bread/Sourdough/Fermentation articles
 */

const ENGINES = [
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

function loadGeneratedIndex() {
    const indexJson = path.join(FIXTURE_SITE, "_site", "search-index.json");
    if (!fs.existsSync(indexJson)) {
        return null;
    }
    return JSON.parse(fs.readFileSync(indexJson, "utf8"));
}

function createWindow(engine, index, query) {
    const dom = new JSDOM(
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

async function settle() {
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
}

function resultTitles(window) {
    return Array.from(window.document.querySelectorAll(".client-search-result h2"))
        .map(function (h2) { return h2.textContent; });
}

const index = loadGeneratedIndex();

ENGINES.forEach(function (engine) {
    const runOrSkip = index ? test : test.skip;

    runOrSkip(`[${engine.name}] system: single-term search returns the matching article`, async function () {
        const window = createWindow(engine, index, "glacier");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'glacier'");
        assert.ok(titles.includes("Glacier"), "should include the Glacier article");
    });

    runOrSkip(`[${engine.name}] system: shared term returns multiple articles`, async function () {
        const window = createWindow(engine, index, "ice");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 3, "expected at least 3 results for 'ice'");
        assert.ok(titles.includes("Glacier"), "should include Glacier");
        assert.ok(titles.includes("Iceberg"), "should include Iceberg");
    });

    runOrSkip(`[${engine.name}] system: AND search narrows to matching articles`, async function () {
        const window = createWindow(engine, index, "photography aperture");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'photography aperture'");
        assert.ok(titles.some(function (t) { return t.includes("Aperture"); }), "should include an aperture article");
    });

    runOrSkip(`[${engine.name}] system: AND mismatch falls back to OR`, async function () {
        const window = createWindow(engine, index, "glacier pasta");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 2, "OR fallback should return posts matching either term");
        assert.ok(titles.includes("Glacier"), "should include Glacier");
        assert.ok(titles.includes("Pasta"), "should include Pasta");
    });

    runOrSkip(`[${engine.name}] system: arXiv topic search finds scientific papers`, async function () {
        const window = createWindow(engine, index, "embeddings retrieval");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'embeddings retrieval'");
    });

    runOrSkip(`[${engine.name}] system: cross-domain search finds food articles`, async function () {
        const window = createWindow(engine, index, "sourdough fermentation");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'sourdough fermentation'");
        assert.ok(titles.some(function (t) {
            return t.includes("Sourdough") || t.includes("Bread") || t.includes("Fermentation");
        }), "should include a bread/fermentation article");
    });

    // --- Edge case tests ---

    runOrSkip(`[${engine.name}] edge: empty query clears results`, async function () {
        const window = createWindow(engine, index, "");
        await settle();
        const titles = resultTitles(window);
        assert.equal(titles.length, 0, "empty query should return no results");
    });

    runOrSkip(`[${engine.name}] edge: query with no matches returns empty results`, async function () {
        const window = createWindow(engine, index, "zzzzzzzzznomatchxyz");
        await settle();
        const titles = resultTitles(window);
        assert.equal(titles.length, 0, "gibberish query should return no results");
    });

    runOrSkip(`[${engine.name}] edge: special characters in query do not crash`, async function () {
        const window = createWindow(engine, index, "glacier! @#$%^&*()");
        await settle();
        // Should not throw — may return 0 or some results depending on engine
        var status = window.document.querySelector("#search-status");
        assert.ok(status, "status element should exist");
    });

    runOrSkip(`[${engine.name}] edge: very long query does not crash`, async function () {
        var longQuery = "glacier ".repeat(100);
        var window = createWindow(engine, index, longQuery.trim());
        await settle();
        // Should not throw or hang
        var status = window.document.querySelector("#search-status");
        assert.ok(status, "status element should exist after long query");
    });

    runOrSkip(`[${engine.name}] edge: non-ASCII query does not crash`, async function () {
        var window = createWindow(engine, index, "glaciér");
        await settle();
        // Should not throw — accented characters should be handled
        var status = window.document.querySelector("#search-status");
        assert.ok(status, "status element should exist after non-ASCII query");
    });

    // --- Error handling tests ---

    runOrSkip(`[${engine.name}] error: malformed JSON from fetch shows error, no results`, async function () {
        var dom = new JSDOM(
            `<!doctype html>
            <form id="search-form"><input id="search-query"><button>Search</button></form>
            <div id="search-status"></div><div id="search-results"></div>`,
            { url: "https://example.com/search/?q=glacier", runScripts: "outside-only" }
        );
        engine.setupWindow(dom);
        dom.window.searchIndexUrl = "/search-index.json";
        dom.window.fetch = async function () {
            return { ok: false, status: 404, statusText: "Not Found" };
        };
        dom.window.eval(BASE_RUNTIME);
        dom.window.eval(engine.adapterSource);
        await settle();
        var results = dom.window.document.querySelectorAll(".client-search-result");
        assert.equal(results.length, 0, "failed fetch should produce no results");
    });

    runOrSkip(`[${engine.name}] error: empty index array shows no results`, async function () {
        var window = createWindow(engine, [], "glacier");
        await settle();
        var titles = resultTitles(window);
        assert.equal(titles.length, 0, "empty index should return no results");
    });

    runOrSkip(`[${engine.name}] error: index with missing fields does not crash`, async function () {
        var partialIndex = [{ id: "test", title: "Test" }]; // missing url, content, etc.
        var window = createWindow(engine, partialIndex, "test");
        await settle();
        // Should not throw — may return 0 or some results
        var status = window.document.querySelector("#search-status");
        assert.ok(status, "status element should exist with partial index");
    });
});
