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
 * that adding an engine only requires registering it here, not duplicating
 * the shared behavior tests.
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

function createWindow(suite, index, query = "greenland", clientConfig = null) {
    var effectiveIndex = suite.makeIndex ? suite.makeIndex(index) : index;
    const dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <select id="search-sort"><option value="relevance">Relevant</option><option value="date">Newest</option></select>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: `https://example.com/search/?q=${encodeURIComponent(query)}`, runScripts: "outside-only" }
    );
    suite.setupWindow(dom);
    dom.window.searchIndexUrl = "/search-index.json";
    if (clientConfig) {
        dom.window.clientSearchConfig = Object.assign({ indexUrl: "/search-index.json" }, clientConfig);
    }
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

    test(`[${suite.name}] performs debounced live search while typing`, async function () {
        const window = createWindow(suite, sampleIndex, "", {
            liveSearch: { enabled: true, minChars: 2, debounceMs: 5, updateUrl: true }
        });
        await settle();
        const input = window.document.querySelector("#search-query");

        input.value = "greenland";
        input.dispatchEvent(new window.Event("input", { bubbles: true }));
        assert.equal(window.document.querySelector("#search-status").textContent, "Waiting to search…");
        await new Promise(function (resolve) { setTimeout(resolve, 15); });
        await settle();

        assert.equal(window.document.querySelector("#search-status").textContent, "1 result");
        assert.equal(window.document.querySelector(".client-search-result h2").textContent, "Greenland");
        assert.equal(new window.URL(window.location.href).searchParams.get("q"), "greenland");
    });
});

test("search results can be sorted newest-first by publication date", async function () {
    const suite = adapterSuites()[0];
    const window = createWindow(suite, [
        { id: "/old/", title: "Old", url: "/old/", content: "shared", date_timestamp: 1 },
        { id: "/new/", title: "New", url: "/new/", content: "shared", date_timestamp: 2 }
    ], "shared");
    await settle();
    const sort = window.document.querySelector("#search-sort");
    sort.value = "date";
    sort.dispatchEvent(new window.Event("change", { bubbles: true }));
    await settle();

    assert.deepEqual(
        Array.from(window.document.querySelectorAll(".client-search-result h2"))
            .map(function (heading) { return heading.textContent; }),
        ["New", "Old"]
    );
});

test("live search enforces minimum characters without updating the URL when disabled", async function () {
    const suite = adapterSuites()[0];
    const window = createWindow(suite, sampleIndex, "", {
        liveSearch: { enabled: true, minChars: 3, debounceMs: 0, updateUrl: false }
    });
    await settle();
    const input = window.document.querySelector("#search-query");

    input.value = "gr";
    input.dispatchEvent(new window.Event("input", { bubbles: true }));
    await settle();

    assert.equal(window.document.querySelector("#search-status").textContent, "Type at least 3 characters.");
    assert.equal(window.document.querySelector("#search-results").children.length, 0);
    assert.equal(new window.URL(window.location.href).searchParams.get("q"), "");
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
    assert.equal(adapter.available(), false, "should be unavailable without a query embedder");
});

test("[semantic] available() remains false when only a model library is loaded", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.transformers = {};
    dom.window.eval(semanticAdapterSource);

    assert.equal(dom.window.ClientSearchAdapters.semantic.available(), false);
});

test("[semantic] available() returns true when ClientSearchQueryEmbedder is set", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");

    const dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () { return [1, 0]; };
    dom.window.eval(semanticAdapterSource);

    var adapter = dom.window.ClientSearchAdapters.semantic;
    assert.equal(adapter.available(), true);
});

test("[semantic] supports async query embeddings and caches repeated queries", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var calls = 0;
    var index = [{ id: "/a/", title: "A", embedding: [1, 0] }];
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () {
        calls += 1;
        return Promise.resolve([1, 0]);
    };
    dom.window.eval(semanticAdapterSource);

    var adapter = dom.window.ClientSearchAdapters.semantic;
    var first = await adapter.search(index, "same query", {});
    var second = await adapter.search(index, "same query", {});

    assert.deepEqual(JSON.parse(JSON.stringify(first)), [{ ref: "/a/", score: 1 }]);
    assert.deepEqual(JSON.parse(JSON.stringify(second)), JSON.parse(JSON.stringify(first)));
    assert.equal(calls, 1, "repeated query should use the cached embedding");
});

test("[semantic] bounds the query embedding cache", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var calls = 0;
    var index = [{ id: "/a/", title: "A", embedding: [1, 0] }];
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () {
        calls += 1;
        return [1, 0];
    };
    dom.window.eval(semanticAdapterSource);

    var adapter = dom.window.ClientSearchAdapters.semantic;
    for (var i = 0; i <= 100; i++) {
        adapter.search(index, `query-${i}`, {});
    }
    adapter.search(index, "query-0", {});

    assert.equal(calls, 102, "oldest query should be re-embedded after cache eviction");
});

test("[semantic] retries a query after an async embedder rejection", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var attempts = 0;
    var index = [{ id: "/a/", title: "A", embedding: [1, 0] }];
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () {
        attempts += 1;
        return attempts === 1 ? Promise.reject(new Error("model failed")) : Promise.resolve([1, 0]);
    };
    dom.window.eval(semanticAdapterSource);

    var adapter = dom.window.ClientSearchAdapters.semantic;
    await assert.rejects(adapter.search(index, "retry", {}), /model failed/);
    var matches = await adapter.search(index, "retry", {});

    assert.deepEqual(JSON.parse(JSON.stringify(matches)), [{ ref: "/a/", score: 1 }]);
    assert.equal(attempts, 2, "a rejected query embedding must not remain cached");
});

test("[semantic] rejects an invalid synchronous query embedding", function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () { return null; };
    dom.window.eval(semanticAdapterSource);

    assert.throws(
        function () {
            dom.window.ClientSearchAdapters.semantic.search(
                [{ id: "/a/", embedding: [1, 0] }], "invalid", {}
            );
        },
        /finite numeric values/
    );
});

test("[semantic] rejects non-finite and mismatched query embeddings", function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () { return [Number.NaN, 0]; };
    dom.window.eval(semanticAdapterSource);
    var adapter = dom.window.ClientSearchAdapters.semantic;
    var index = [{ id: "/a/", embedding: [1, 0] }];

    assert.throws(function () { adapter.search(index, "invalid", {}); }, /finite numeric values/);

    dom.window.ClientSearchQueryEmbedder = function () { return [1, 0, 0]; };
    assert.throws(function () { adapter.search(index, "mismatch", {}); }, /does not match document dimension/);
});

test("[semantic] rejects inconsistent document embedding dimensions", function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () { return [1, 0]; };
    dom.window.eval(semanticAdapterSource);

    assert.throws(function () {
        dom.window.ClientSearchAdapters.semantic.buildIndex([
            { id: "/a/", embedding: [1, 0] },
            { id: "/b/", embedding: [1, 0, 0] }
        ]);
    }, /dimensions do not match/);
});

test("[semantic] accepts typed-array query embeddings", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var index = [{ id: "/a/", title: "A", embedding: [1, 0] }];
    var dom = new JSDOM("<!doctype html><body></body>", { runScripts: "outside-only" });
    dom.window.ClientSearchQueryEmbedder = function () { return new dom.window.Float32Array([1, 0]); };
    dom.window.eval(semanticAdapterSource);

    var matches = await dom.window.ClientSearchAdapters.semantic.search(index, "typed", {});
    assert.deepEqual(JSON.parse(JSON.stringify(matches)), [{ ref: "/a/", score: 1 }]);
});

test("base runtime displays query-embedder progress status", async function () {
    var dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: "https://example.com/search/?q=query", runScripts: "outside-only" }
    );
    var resolveSearch;
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return [{ id: "/a/", title: "A", url: "/a/" }]; } };
    };
    dom.window.eval(baseRuntime);
    dom.window.ClientSearch.run({
        available: function () { return true; },
        buildIndex: function (documents) { return documents; },
        search: function () {
            dom.window.dispatchEvent(new dom.window.CustomEvent("client-search:status", {
                detail: { message: "Loading semantic model… 50%" }
            }));
            return new Promise(function (resolve) { resolveSearch = resolve; });
        }
    });
    await settle();

    assert.equal(
        dom.window.document.querySelector("#search-status").textContent,
        "Loading semantic model… 50%"
    );
    resolveSearch([{ ref: "/a/", score: 1 }]);
    await settle();
    assert.equal(dom.window.document.querySelector("#search-status").textContent, "1 result");
});

test("base runtime reports async adapter failures as unavailable", async function () {
    var semanticAdapterSource = fs.readFileSync(path.join(adapterDir, "semantic.js"), "utf8");
    var dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: "https://example.com/search/?q=broken", runScripts: "outside-only" }
    );
    dom.window.ClientSearchQueryEmbedder = function () {
        return Promise.reject(new Error("model failed"));
    };
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return {
            ok: true,
            json: async function () {
                return [{ id: "/a/", title: "A", url: "/a/", embedding: [1, 0] }];
            }
        };
    };
    dom.window.eval(baseRuntime);
    dom.window.eval(semanticAdapterSource);
    await settle();

    assert.equal(
        dom.window.document.querySelector("#search-status").textContent,
        "Search is temporarily unavailable."
    );
    assert.equal(dom.window.document.querySelectorAll(".client-search-result").length, 0);
});

test("base runtime ignores stale async failures after a newer query", async function () {
    var dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: "https://example.com/search/?q=old", runScripts: "outside-only" }
    );
    var index = [
        { id: "/new/", title: "New", url: "/new/", excerpt: "new", content: "new" }
    ];
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return index; } };
    };
    dom.window.eval(baseRuntime);
    dom.window.ClientSearch.run({
        available: function () { return true; },
        buildIndex: function (documents) { return documents; },
        search: function (_documents, query) {
            if (query === "old") {
                return new Promise(function (_resolve, reject) {
                    setTimeout(function () { reject(new Error("obsolete")); }, 20);
                });
            }
            return Promise.resolve([{ ref: "/new/", score: 1 }]);
        }
    });

    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    var input = dom.window.document.querySelector("#search-query");
    input.value = "new";
    input.dispatchEvent(new dom.window.Event("input", { bubbles: true }));
    dom.window.document.querySelector("#search-form").dispatchEvent(
        new dom.window.Event("submit", { bubbles: true, cancelable: true })
    );
    await new Promise(function (resolve) { setTimeout(resolve, 30); });

    assert.equal(dom.window.document.querySelector("#search-status").textContent, "1 result");
    assert.equal(dom.window.document.querySelector(".client-search-result h2").textContent, "New");
});

test("base runtime ignores stale async search results", async function () {
    var dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: "https://example.com/search/?q=old", runScripts: "outside-only" }
    );
    var index = [
        { id: "/old/", title: "Old", url: "/old/", excerpt: "old", content: "old" },
        { id: "/new/", title: "New", url: "/new/", excerpt: "new", content: "new" }
    ];
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return index; } };
    };
    dom.window.eval(baseRuntime);
    dom.window.ClientSearchAdapters = {};
    dom.window.ClientSearchAdapters.test = {
        available: function () { return true; },
        buildIndex: function (documents) { return documents; },
        search: function (documents, query) {
            return new Promise(function (resolve) {
                setTimeout(function () {
                    resolve([{ ref: query === "old" ? "/old/" : "/new/", score: 1 }]);
                }, query === "old" ? 30 : 0);
            });
        }
    };
    dom.window.ClientSearch.run(dom.window.ClientSearchAdapters.test);

    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    var input = dom.window.document.querySelector("#search-query");
    input.value = "new";
    dom.window.document.querySelector("#search-form").dispatchEvent(
        new dom.window.Event("submit", { bubbles: true, cancelable: true })
    );
    await new Promise(function (resolve) { setTimeout(resolve, 10); });

    assert.deepEqual(
        Array.from(dom.window.document.querySelectorAll(".client-search-result h2"))
            .map(function (heading) { return heading.textContent; }),
        ["New"]
    );
});
