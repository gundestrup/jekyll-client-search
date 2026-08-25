"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { JSDOM } = require("jsdom");

const source = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search-related.js"),
    "utf8"
);

function createWindow(withContainer = false) {
    return new JSDOM(
        withContainer ? "<!doctype html><div id=related-articles></div>" : "<!doctype html>",
        { url: "https://example.com/articles/current/", runScripts: "outside-only" }
    ).window;
}

function mockFetch(relations) {
    return async function () {
        return {
            ok: true,
            json: async function () {
                return { relations: relations };
            }
        };
    };
}

const sampleRelations = {
    "/articles/current/": [
        {
            title: "Older", url: "/older/", score: 0.8, date_timestamp: 1,
            date: "2026-01-01", shared_tags: ["greenland"], excerpt: "An older article"
        },
        {
            title: "Newer", url: "/newer/", score: 0.7, date_timestamp: 2,
            date: "2026-02-01", shared_tags: ["travel"], excerpt: "A newer article"
        }
    ]
};

test("related runtime renders the current article's relations", async function () {
    const window = createWindow();
    window.clientSearchConfig = { relatedUrl: "/search-relations.json" };
    window.fetch = mockFetch(sampleRelations);

    window.eval(source);
    const container = window.document.createElement("div");
    container.id = "related-articles";
    const sort = window.document.createElement("select");
    sort.id = "related-sort";
    const relevance = window.document.createElement("option");
    relevance.value = "relevance";
    const newest = window.document.createElement("option");
    newest.value = "date";
    sort.append(relevance, newest);
    sort.value = "date";
    window.document.body.append(container, sort);
    await window.ClientSearchRelated.run({ sort: "date" });

    assert.equal(container.querySelector("h2").textContent, "Related articles");
    assert.deepEqual(
        Array.from(container.querySelectorAll("li a.related-article-link"))
            .map(function (item) { return item.textContent; }),
        ["Newer", "Older"]
    );
    assert.equal(container.querySelector("a").getAttribute("href"), "/newer/");
});

test("related runtime leaves the container empty when no relations exist", async function () {
    const window = createWindow(true);
    window.fetch = mockFetch({});

    window.eval(source);
    await window.ClientSearchRelated.run({ relationsUrl: "/relations.json" });

    assert.equal(window.document.querySelector("#related-articles").children.length, 0);
});

test("default rendering includes date, shared tags, and excerpt when present", async function () {
    const window = createWindow(true);
    window.fetch = mockFetch(sampleRelations);

    window.eval(source);
    await window.ClientSearchRelated.run({ relationsUrl: "/relations.json" });

    const container = window.document.querySelector("#related-articles");
    const firstItem = container.querySelector("li");
    assert.ok(firstItem.querySelector(".related-article-date"), "date span should exist");
    assert.ok(firstItem.querySelector(".related-article-tags"), "tags span should exist");
    assert.ok(firstItem.querySelector(".related-article-excerpt"), "excerpt should exist");
    assert.equal(firstItem.querySelector(".related-article-tags").textContent, "greenland");
});

test("renderItem callback overrides default rendering", async function () {
    const window = createWindow(true);
    window.fetch = mockFetch(sampleRelations);

    window.eval(source);
    await window.ClientSearchRelated.run({
        relationsUrl: "/relations.json",
        renderItem: function (item) {
            var li = window.document.createElement("li");
            li.className = "custom-item";
            li.textContent = item.title + " (" + item.score + ")";
            return li;
        }
    });

    var items = window.document.querySelectorAll("#related-articles li.custom-item");
    assert.equal(items.length, 2);
    assert.equal(items[0].textContent, "Older (0.8)");
});

test("filter callback excludes matching relations", async function () {
    const window = createWindow(true);
    window.fetch = mockFetch(sampleRelations);

    window.eval(source);
    await window.ClientSearchRelated.run({
        relationsUrl: "/relations.json",
        filter: function (item) { return item.score >= 0.75; }
    });

    var items = window.document.querySelectorAll("#related-articles li");
    assert.equal(items.length, 1);
    assert.equal(items[0].querySelector("a").textContent, "Older");
});

test("data-related-sort attribute on container sets sort order", async function () {
    const window = createWindow(true);
    window.fetch = mockFetch(sampleRelations);

    window.eval(source);
    var container = window.document.querySelector("#related-articles");
    container.dataset.relatedSort = "date";
    await window.ClientSearchRelated.run({ relationsUrl: "/relations.json" });

    var links = Array.from(container.querySelectorAll("li a.related-article-link"))
        .map(function (a) { return a.textContent; });
    assert.deepEqual(links, ["Newer", "Older"]);
});

test("renderItem returning null skips the item", async function () {
    const window = createWindow(true);
    window.fetch = mockFetch(sampleRelations);

    window.eval(source);
    await window.ClientSearchRelated.run({
        relationsUrl: "/relations.json",
        renderItem: function (item) {
            return item.title === "Newer" ? null : window.document.createElement("li");
        }
    });

    assert.equal(window.document.querySelectorAll("#related-articles li").length, 1);
});
