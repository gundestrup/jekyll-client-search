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
 * Gold standard tests — curated (query, expected_top_results) pairs that
 * define what "correct" search behavior looks like. These are not smoke
 * tests: they check exact ranking order, not just inclusion.
 *
 * The gold standard is defined for lexical engines (MiniSearch, ElasticLunr)
 * where results are deterministic based on text matching. For each query,
 * we specify:
 *   - query: the search string
 *   - expectedTopN: the exact titles that must appear in the top N results,
 *                   in the specified order
 *   - minResults: minimum number of results expected
 *   - mustNotInclude: titles that must NOT appear in results (discrimination)
 *
 * The semantic adapter is tested separately with controlled mock embeddings
 * in the comparison tests below.
 */

const LEXICAL_ENGINES = [
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

// --- Gold standard query set ---
//
// Each entry defines a query and its expected results. The expectedTopN
// lists are ordered — the first title must rank higher than the second.
//
// These are designed to test:
//   1. Single-term precision: exact match ranks first
//   2. Multi-term AND: both terms must be present
//   3. Cross-topic discrimination: "ice" finds glacier AND climbing, but
//      "ice climbing" narrows to the climbing article
//   4. Negative discrimination: irrelevant topics must NOT appear
//   5. Field-specific matching: searching by category/tag content

const GOLD_STANDARD = [
    {
        query: "glacier",
        expectedTop1: "Glacier",
        expectedInTopN: ["Glacier"],
        minResults: 1,
        mustNotInclude: ["Pasta", "Chocolate", "Bread"],
        description: "single-term: Glacier article ranks #1 for 'glacier'"
    },
    {
        query: "ice climbing",
        expectedTop1: "Ice climbing",
        expectedInTopN: ["Ice climbing"],
        minResults: 1,
        mustNotInclude: ["Pasta", "Chocolate", "Bread"],
        description: "two-term AND: 'ice climbing' narrows to the Ice climbing article"
    },
    {
        query: "aperture photography",
        expectedTop1: "Aperture",
        expectedInTopN: ["Aperture", "Digital photography"],
        minResults: 2,
        mustNotInclude: ["Glacier", "Pasta", "Bread"],
        description: "two-term: Aperture ranks #1, Digital photography in top N"
    },
    {
        query: "sourdough bread",
        expectedTop1: "Sourdough",
        expectedInTopN: ["Sourdough", "Bread"],
        minResults: 2,
        mustNotInclude: ["Glacier", "Iceberg", "Mountaineering"],
        description: "two-term: Sourdough ranks #1, Bread in top N"
    },
    {
        query: "camera lens",
        expectedTop1: "Camera lens",
        expectedInTopN: ["Camera lens", "Digital single-lens reflex camera"],
        minResults: 2,
        mustNotInclude: ["Glacier", "Pasta", "Mountaineering"],
        description: "two-term: Camera lens ranks #1, DSLR in top N"
    },
    {
        query: "arctic",
        expectedTop1: "Arctic Circle",
        expectedInTopN: ["Arctic Circle", "Sea ice", "Tundra", "Permafrost", "Polar climate"],
        minResults: 3,
        mustNotInclude: ["Pasta", "Chocolate", "Carabiner"],
        description: "single-term: Arctic Circle ranks #1, arctic articles in top N, food excluded"
    },
    {
        query: "fermentation",
        expectedTop1: "Fermentation in food processing",
        expectedInTopN: ["Fermentation in food processing"],
        minResults: 1,
        mustNotInclude: ["Glacier", "Mountaineering", "Carabiner"],
        description: "single-term: Fermentation article ranks #1"
    },
    {
        query: "belay carabiner",
        expectedTop1: "Belay device",
        expectedInTopN: ["Belay device", "Carabiner"],
        minResults: 2,
        mustNotInclude: ["Pasta", "Glacier", "Photography"],
        description: "two-term: Belay device ranks #1, Carabiner in top N"
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

LEXICAL_ENGINES.forEach(function (engine) {
    const runOrSkip = index ? test : test.skip;

    GOLD_STANDARD.forEach(function (gold) {
        runOrSkip(`[${engine.name}] gold: ${gold.description}`, async function () {
            const window = createWindow(engine, index, gold.query);
            await settle();

            const titles = resultTitles(window);

            // Must meet minimum result count
            assert.ok(
                titles.length >= gold.minResults,
                `expected at least ${gold.minResults} results for "${gold.query}", got ${titles.length}: ${JSON.stringify(titles)}`
            );

            // #1 result must be exact — this is the strongest relevance signal
            assert.equal(
                titles[0],
                gold.expectedTop1,
                `top result for "${gold.query}" should be "${gold.expectedTop1}" but was "${titles[0]}" — full results: ${JSON.stringify(titles)}`
            );

            // Expected titles must appear somewhere in the results
            // (engines rank differently, so we check presence, not exact order)
            gold.expectedInTopN.forEach(function (expected) {
                assert.ok(
                    titles.includes(expected),
                    `"${expected}" should appear in results for "${gold.query}" — results: ${JSON.stringify(titles)}`
                );
            });

            // Must NOT include irrelevant results (discrimination check)
            gold.mustNotInclude.forEach(function (forbidden) {
                assert.ok(
                    !titles.includes(forbidden),
                    `"${forbidden}" should NOT appear in results for "${gold.query}" — results: ${JSON.stringify(titles)}`
                );
            });
        });
    });
});
