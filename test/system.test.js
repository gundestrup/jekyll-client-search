"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { JSDOM } = require("jsdom");
const MiniSearch = require("minisearch");
const elasticlunr = require("elasticlunr");

const BASELINE_PATH = path.join(__dirname, "..", "spec", "fixtures", "baseline", "search-index-baseline.json");
const BASE_RUNTIME = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search-base.js"),
    "utf8"
);
const ADAPTER_DIR = path.join(__dirname, "..", "assets", "adapters");

/**
 * System tests — load the committed baseline search-index JSON (generated
 * from 80 source posts: 40 Wikipedia + 40 unique arXiv papers) in jsdom
 * with the base runtime + adapter, and assert search results against known
 * expected outcomes.
 *
 * The baseline JSON is a committed test artifact. The arXiv .md source
 * posts are NOT committed (mixed/restrictive licenses) — developers run
 * download_arxiv.rb to regenerate them. See README.developer.md.
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

function loadBaselineIndex() {
    if (!fs.existsSync(BASELINE_PATH)) {
        return null;
    }
    return JSON.parse(fs.readFileSync(BASELINE_PATH, "utf8"));
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

const index = loadBaselineIndex();

ENGINES.forEach(function (engine) {
    test(`[${engine.name}] system: single-term search returns the matching article`, async function () {
        const window = createWindow(engine, index, "glacier");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'glacier'");
        assert.ok(titles.includes("Glacier"), "should include the Glacier article");
    });

    test(`[${engine.name}] system: shared term returns multiple articles`, async function () {
        const window = createWindow(engine, index, "ice");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 3, "expected at least 3 results for 'ice'");
        assert.ok(titles.includes("Glacier"), "should include Glacier");
        assert.ok(titles.includes("Iceberg"), "should include Iceberg");
    });

    test(`[${engine.name}] system: AND search narrows to matching articles`, async function () {
        const window = createWindow(engine, index, "photography aperture");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'photography aperture'");
        assert.ok(titles.some(function (t) { return t.includes("Aperture"); }), "should include an aperture article");
    });

    test(`[${engine.name}] system: AND mismatch falls back to OR`, async function () {
        const window = createWindow(engine, index, "glacier pasta");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 2, "OR fallback should return posts matching either term");
        assert.ok(titles.includes("Glacier"), "should include Glacier");
        assert.ok(titles.includes("Pasta"), "should include Pasta");
    });

    test(`[${engine.name}] system: arXiv topic search finds scientific papers`, async function () {
        const window = createWindow(engine, index, "embeddings retrieval");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'embeddings retrieval'");
    });

    test(`[${engine.name}] system: cross-domain search finds food articles`, async function () {
        const window = createWindow(engine, index, "sourdough fermentation");
        await settle();
        const titles = resultTitles(window);
        assert.ok(titles.length >= 1, "expected at least 1 result for 'sourdough fermentation'");
        assert.ok(titles.some(function (t) {
            return t.includes("Sourdough") || t.includes("Bread") || t.includes("Fermentation");
        }), "should include a bread/fermentation article");
    });

    // --- Edge case tests ---

    test(`[${engine.name}] edge: empty query clears results`, async function () {
        const window = createWindow(engine, index, "");
        await settle();
        const titles = resultTitles(window);
        assert.equal(titles.length, 0, "empty query should return no results");
    });

    test(`[${engine.name}] edge: query with no matches returns empty results`, async function () {
        const window = createWindow(engine, index, "zzzzzzzzznomatchxyz");
        await settle();
        const titles = resultTitles(window);
        assert.equal(titles.length, 0, "gibberish query should return no results");
    });

    test(`[${engine.name}] edge: special-character query completes`, async function () {
        const window = createWindow(engine, index, "glacier! @#$%^&*()");
        await settle();
        assert.match(window.document.querySelector("#search-status").textContent, /^\d+ results?$/);
    });

    test(`[${engine.name}] edge: very long repeated query completes`, async function () {
        var longQuery = "glacier ".repeat(100);
        var window = createWindow(engine, index, longQuery.trim());
        await settle();
        assert.ok(resultTitles(window).includes("Glacier"), "long repeated query should find Glacier");
        assert.match(window.document.querySelector("#search-status").textContent, /^\d+ results?$/);
    });

    test(`[${engine.name}] edge: non-ASCII query completes`, async function () {
        var window = createWindow(engine, index, "glaciér");
        await settle();
        assert.match(window.document.querySelector("#search-status").textContent, /^\d+ results?$/);
    });

    // --- Error handling tests ---

    test(`[${engine.name}] error: failed index request shows unavailable, no results`, async function () {
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
        assert.equal(
            dom.window.document.querySelector("#search-status").textContent,
            "Search is temporarily unavailable."
        );
    });

    test(`[${engine.name}] error: empty index array shows no results`, async function () {
        var window = createWindow(engine, [], "glacier");
        await settle();
        var titles = resultTitles(window);
        assert.equal(titles.length, 0, "empty index should return no results");
    });

    test(`[${engine.name}] error: index with optional fields missing uses safe defaults`, async function () {
        var partialIndex = [{ id: "test", title: "Test" }];
        var window = createWindow(engine, partialIndex, "test");
        await settle();
        assert.deepEqual(resultTitles(window), ["Test"]);
        assert.equal(window.document.querySelector(".client-search-result a").getAttribute("href"), "#");
        assert.equal(window.document.querySelector("#search-status").textContent, "1 result");
    });
});
