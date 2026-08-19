"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const MiniSearch = require("minisearch");
const { JSDOM } = require("jsdom");

const runtime = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search.js"),
    "utf8"
);

function createWindow(index, query = "greenland") {
    const dom = new JSDOM(
        `<!doctype html>
        <form id="search-form"><input id="search-query"><button>Search</button></form>
        <div id="search-status"></div><div id="search-results"></div>`,
        { url: `https://example.com/search/?q=${encodeURIComponent(query)}`, runScripts: "outside-only" }
    );
    dom.window.MiniSearch = MiniSearch;
    dom.window.searchIndexUrl = "/search-index.json";
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return index; } };
    };
    dom.window.eval(runtime);
    return dom.window;
}

async function settle() {
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
}

test("loads the generated index and renders ranked results", async function () {
    const window = createWindow([
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
    ]);

    await settle();

    assert.equal(window.document.querySelector("#search-status").textContent, "1 result");
    const result = window.document.querySelector(".client-search-result");
    assert.equal(result.querySelector("h2").textContent, "Greenland");
    assert.equal(result.querySelector("a").getAttribute("href"), "/greenland/");
});

test("falls back to fuzzy OR search when AND returns no results", async function () {
    const window = createWindow([
        {
            id: "/greenland/",
            title: "Greenland",
            url: "/greenland/",
            excerpt: "A Greenland article",
            content: "Ice and travel",
            categories: ["travel"],
            tags: ["ice"]
        }
    ], "greenlad");

    await settle();

    assert.equal(window.document.querySelector("#search-status").textContent, "1 result");
    assert.equal(window.document.querySelector(".client-search-result h2").textContent, "Greenland");
});

test("does not allow unsafe result URLs", async function () {
    const window = createWindow([
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

test("reports invalid index data without rendering results", async function () {
    const window = createWindow({ invalid: true });

    await settle();

    assert.equal(window.document.querySelector("#search-status").textContent, "Search is temporarily unavailable.");
    assert.equal(window.document.querySelector("#search-results").children.length, 0);
});
