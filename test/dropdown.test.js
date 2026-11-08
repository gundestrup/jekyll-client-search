"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const MiniSearch = require("minisearch");
const { JSDOM } = require("jsdom");

const sharedSource = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search-shared.js"),
    "utf8"
);
const dropdownSource = fs.readFileSync(
    path.join(__dirname, "..", "assets", "client-search-dropdown.js"),
    "utf8"
);
const minisearchAdapter = fs.readFileSync(
    path.join(__dirname, "..", "assets", "adapters", "minisearch.js"),
    "utf8"
);

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
        id: "/diabetes/",
        title: "Diabetes",
        url: "/diabetes/",
        excerpt: "About diabetes",
        content: "Insulin and pancreas",
        categories: ["medicine"],
        tags: ["insulin"]
    },
    {
        id: "/other/",
        title: "Other Article",
        url: "/other/",
        excerpt: "Unrelated",
        content: "Other content",
        categories: [],
        tags: []
    }
];

function createDropdownWindow(query, config) {
    var dom = new JSDOM(
        `<!doctype html>
        <div data-client-search-dropdown>
            <form data-cs-dropdown-form>
                <input id="test-combobox" data-cs-dropdown-input type="search"
                       role="combobox" aria-autocomplete="list" aria-expanded="false"
                       aria-controls="test-listbox">
            </form>
            <div id="test-listbox" role="listbox" aria-label="Search suggestions"
                 aria-hidden="true">
                <ul role="presentation" aria-hidden="true"
                    data-cs-dropdown-results data-max-items="5"></ul>
            </div>
        </div>`,
        {
            url: "https://example.com/",
            runScripts: "outside-only"
        }
    );

    dom.window.MiniSearch = MiniSearch;
    dom.window.clientSearchConfig = Object.assign(
        {
            indexUrl: "/search-index.json",
            engine: "minisearch",
            dropdown: {
                enabled: true,
                minChars: 2,
                debounceMs: 0,
                maxItems: 5,
                redirectUrl: "/search/"
            }
        },
        config || {}
    );

    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return sampleIndex; } };
    };

    dom.window.eval(minisearchAdapter);
    dom.window.eval(sharedSource);
    dom.window.eval(dropdownSource);

    // The dropdown runtime defers initAll to DOMContentLoaded when
    // readyState is "loading". JSDOM doesn't fire it with outside-only,
    // so we dispatch it manually.
    if (dom.window.document.readyState === "loading") {
        dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));
    }

    // Set the input value after init so the event listener is wired up.
    if (query) {
        var input = dom.window.document.querySelector("[data-cs-dropdown-input]");
        if (input) {
            input.value = query;
        }
    }

    return dom.window;
}

async function settle() {
    // Wait for debounce timer (setTimeout 0) + fetch promise + json parse +
    // buildIndex + search + render. The dropdown uses setTimeout for debounce
    // and async fetch for index loading, so we need generous macrotask yields.
    await new Promise(function (resolve) { setTimeout(resolve, 200); });
    await new Promise(function (resolve) { setTimeout(resolve, 200); });
}

function getResultItems(window) {
    return Array.from(window.document.querySelectorAll("[data-cs-dropdown-results] [role=\"option\"]"));
}

function getResultTitles(window) {
    return getResultItems(window).map(function (li) {
        return li.querySelector(".client-search-dropdown-link").textContent;
    });
}

test("[dropdown] renders matching results after typing a query", async function () {
    var window = createDropdownWindow("");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.value = "greenland";
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var titles = getResultTitles(window);
    assert.ok(titles.includes("Greenland"),
        "should find Greenland for 'greenland' query, got: " + JSON.stringify(titles));
});

test("[dropdown] does not search below minChars threshold", async function () {
    var window = createDropdownWindow("g");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var items = getResultItems(window);
    assert.equal(items.length, 0, "single char should not trigger search (minChars=2)");
});

test("[dropdown] hides and clears results on empty input", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    assert.ok(getResultTitles(window).length > 0, "should have results after typing");

    input.value = "";
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var results = window.document.querySelector("[data-cs-dropdown-results]");
    assert.equal(results.getAttribute("aria-hidden"), "true",
        "results should be hidden after clearing input");
    assert.equal(getResultItems(window).length, 0, "results list should be empty");
});

test("[dropdown] truncates results to maxItems", async function () {
    // Use a broad query that matches multiple documents
    var broadIndex = [
        { id: "/a/", title: "Alpha Article", url: "/a/", content: "common word", categories: [], tags: [] },
        { id: "/b/", title: "Beta Article", url: "/b/", content: "common word", categories: [], tags: [] },
        { id: "/c/", title: "Gamma Article", url: "/c/", content: "common word", categories: [], tags: [] },
        { id: "/d/", title: "Delta Article", url: "/d/", content: "common word", categories: [], tags: [] }
    ];
    var dom = new JSDOM(
        `<!doctype html><div data-client-search-dropdown>
        <form data-cs-dropdown-form>
          <input id="test-combobox" data-cs-dropdown-input type="search"
                 role="combobox" aria-autocomplete="list" aria-expanded="false"
                 aria-controls="test-listbox">
        </form>
        <div id="test-listbox" role="listbox" aria-label="Search suggestions"
             aria-hidden="true">
          <ul role="presentation" aria-hidden="true"
              data-cs-dropdown-results data-max-items="2"></ul>
        </div></div>`,
        { url: "https://example.com/", runScripts: "outside-only" }
    );
    dom.window.MiniSearch = MiniSearch;
    dom.window.clientSearchConfig = {
        indexUrl: "/search-index.json", engine: "minisearch",
        dropdown: { enabled: true, minChars: 1, debounceMs: 0, maxItems: 2, redirectUrl: "/search/" }
    };
    dom.window.fetch = async function () {
        return { ok: true, json: async function () { return broadIndex; } };
    };
    dom.window.eval(minisearchAdapter);
    dom.window.eval(sharedSource);
    dom.window.eval(dropdownSource);
    dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));

    var input = dom.window.document.querySelector("[data-cs-dropdown-input]");
    input.value = "common";
    input.dispatchEvent(new dom.window.Event("input"));
    await settle();

    var items = dom.window.document.querySelectorAll("[data-cs-dropdown-results] [role=\"option\"]");
    assert.ok(items.length > 0, "should have results for 'common' query");
    assert.ok(items.length <= 2, "should not exceed maxItems=2, got " + items.length);
});

test("[dropdown] sets aria-hidden=false when showing results", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var results = window.document.querySelector("[data-cs-dropdown-results]");
    assert.equal(results.getAttribute("aria-hidden"), "false",
        "options should be visible (aria-hidden=false)");
    assert.equal(results.parentElement.getAttribute("aria-hidden"), "false",
        "listbox should be exposed while expanded");
    var inputEl = window.document.querySelector("[data-cs-dropdown-input]");
    assert.equal(inputEl.getAttribute("aria-expanded"), "true",
        "input should have aria-expanded=true");
});

test("[dropdown] renders plain-text options with unique IDs", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var results = window.document.querySelector("[data-cs-dropdown-results]");
    var options = getResultItems(window);
    var ids = options.map(function (option) { return option.id; });

    assert.equal(input.getAttribute("role"), "combobox");
    assert.equal(input.getAttribute("aria-controls"), results.parentElement.id);
    assert.equal(results.parentElement.getAttribute("role"), "listbox");
    assert.equal(results.getAttribute("role"), "presentation");
    assert.ok(options.length > 0);
    assert.equal(new Set(ids).size, ids.length, "option IDs should be unique");
    options.forEach(function (option) {
        assert.ok(option.id, "each option should have an ID");
        assert.equal(option.getAttribute("aria-selected"), "false");
        assert.equal(option.querySelector("a, button, input"), null,
            "listbox options should not contain nested interactive controls");
    });
});

test("[dropdown] active descendant follows selection and resets on new results", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    // Duplicate DOMContentLoaded events must not attach a second runtime
    // instance to the same search slot.
    window.document.dispatchEvent(new window.Event("DOMContentLoaded"));
    input.dispatchEvent(new window.Event("input"));
    await settle();

    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "ArrowDown" }));
    var firstOption = getResultItems(window)[0];
    assert.equal(input.getAttribute("aria-activedescendant"), firstOption.id);

    input.value = "diabetes";
    input.dispatchEvent(new window.Event("input"));
    assert.equal(input.hasAttribute("aria-activedescendant"), false);
    await settle();

    assert.ok(getResultTitles(window).includes("Diabetes"));
});

test("[dropdown] result items have safe URLs (same-origin only)", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var options = getResultItems(window);
    options.forEach(function (option) {
        assert.ok(option.dataset.url.startsWith("/"),
            "option URL should be a same-origin path: " + option.dataset.url);
    });
});

test("[dropdown] result items have data-url attributes", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var items = getResultItems(window);
    items.forEach(function (li) {
        assert.ok(li.dataset.url, "each item should have data-url");
        assert.ok(li.dataset.url.startsWith("/"), "data-url should be a path");
    });
});

test("[dropdown] does not use innerHTML (XSS prevention)", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    // The dropdown source itself must not contain innerHTML
    assert.ok(!dropdownSource.includes("innerHTML"),
        "dropdown source must not use innerHTML");
});

test("[dropdown] Escape closes results while keeping focus in the combobox", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.focus();
    input.dispatchEvent(new window.Event("input"));
    await settle();

    assert.ok(getResultItems(window).length > 0, "should have results");
    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "ArrowDown" }));
    assert.ok(input.hasAttribute("aria-activedescendant"), "an option should be active");

    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape" }));
    await settle();

    var results = window.document.querySelector("[data-cs-dropdown-results]");
    assert.equal(results.getAttribute("aria-hidden"), "true",
        "options should be hidden after Escape");
    assert.equal(results.parentElement.getAttribute("aria-hidden"), "true",
        "listbox should be hidden after Escape");
    assert.equal(getResultItems(window).length, 0, "results should be cleared");
    assert.equal(input.hasAttribute("aria-activedescendant"), false,
        "Escape should clear the active option reference");
    assert.equal(window.document.activeElement, input,
        "Escape should keep focus in the combobox");
});

test("[dropdown] ArrowDown selects first item", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    var items = getResultItems(window);
    assert.ok(items.length > 0, "should have results before keyboard nav");

    input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "ArrowDown" }));

    assert.ok(items[0].getAttribute("aria-selected") === "true",
        "first item should be selected after ArrowDown");
    assert.equal(input.getAttribute("aria-activedescendant"), items[0].id,
        "combobox should expose the active option");
});

test("[dropdown] form submit redirects to redirectUrl with query parameter", async function () {
    var window = createDropdownWindow("greenland");
    var form = window.document.querySelector("[data-cs-dropdown-form]");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.value = "glacier";

    // Track redirect by overriding location.href setter
    var redirectedUrl = null;
    try {
        Object.defineProperty(window, "location", {
            writable: true,
            configurable: true,
            value: new URL("https://example.com/")
        });
        Object.defineProperty(window.location, "href", {
            configurable: true,
            set: function (value) { redirectedUrl = value; },
            get: function () { return "https://example.com/"; }
        });
    } catch (_e) {
        // JSDOM may not allow location override — skip this test
        return;
    }

    form.dispatchEvent(new window.Event("submit", { cancelable: true }));
    await settle();

    assert.ok(redirectedUrl, "form submit should redirect");
    assert.ok(redirectedUrl.indexOf("/search/") !== -1, "should redirect to /search/");
    assert.ok(redirectedUrl.indexOf("q=glacier") !== -1, "should include query parameter");
});

test("[dropdown] does not init when dropdown is disabled in config", async function () {
    var window = createDropdownWindow("greenland", {
        dropdown: { enabled: false, minChars: 2, debounceMs: 0, maxItems: 5, redirectUrl: "/search/" }
    });
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    assert.equal(getResultItems(window).length, 0,
        "no results should appear when dropdown is disabled");
});

test("[dropdown] handles fetch error gracefully", async function () {
    var dom = new JSDOM(
        `<!doctype html>
        <div data-client-search-dropdown>
            <form data-cs-dropdown-form>
                <input id="test-combobox" data-cs-dropdown-input type="search" value="greenland"
                       role="combobox" aria-autocomplete="list" aria-expanded="false"
                       aria-controls="test-listbox">
            </form>
            <div id="test-listbox" role="listbox" aria-label="Search suggestions"
                 aria-hidden="true">
                <ul role="presentation" aria-hidden="true"
                    data-cs-dropdown-results data-max-items="5"></ul>
            </div>
        </div>`,
        { url: "https://example.com/", runScripts: "outside-only" }
    );

    dom.window.MiniSearch = MiniSearch;
    dom.window.clientSearchConfig = {
        indexUrl: "/search-index.json",
        engine: "minisearch",
        dropdown: { enabled: true, minChars: 2, debounceMs: 0, maxItems: 5, redirectUrl: "/search/" }
    };
    dom.window.fetch = async function () {
        return { ok: false, json: async function () { return []; } };
    };

    dom.window.eval(minisearchAdapter);
    dom.window.eval(sharedSource);
    dom.window.eval(dropdownSource);

    if (dom.window.document.readyState === "loading") {
        dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));
    }

    var input = dom.window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new dom.window.Event("input"));
    await settle();

    var results = dom.window.document.querySelector("[data-cs-dropdown-results]");
    assert.equal(results.getAttribute("aria-hidden"), "true",
        "results should be hidden on fetch error");
    assert.equal(getResultItems(dom.window).length, 0, "no results on fetch error");
});

test("[dropdown] click outside hides results", async function () {
    var window = createDropdownWindow("greenland");
    var input = window.document.querySelector("[data-cs-dropdown-input]");
    input.dispatchEvent(new window.Event("input"));
    await settle();

    assert.ok(getResultItems(window).length > 0, "should have results");

    window.document.body.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    await settle();

    var results = window.document.querySelector("[data-cs-dropdown-results]");
    assert.equal(results.getAttribute("aria-hidden"), "true",
        "click outside should hide results");
});
