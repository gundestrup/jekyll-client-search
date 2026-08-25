(function () {
    "use strict";

    /**
     * ClientSearch base runtime — engine-agnostic shell.
     *
     * Owns the uniform query model and the two-stage search strategy:
     *   1. Exact AND search with prefix matching.
     *   2. Fuzzy OR fallback when AND yields no results.
     *
     * The search engine itself is supplied by an adapter that translates
     * the uniform query into the engine's native format and translates
     * results back. The adapter interface is:
     *
     *   adapter.name        — string identifier
     *   adapter.available() — returns true when the engine library is loaded
     *   adapter.buildIndex(documents) — returns an engine-specific index
     *   adapter.search(index, query, options) — translates the uniform
     *       query { combineWith: "AND"|"OR", fuzzy: bool, prefix: bool }
     *       into the engine's native call and returns [{ ref, score }] or a
     *       Promise of that array in descending score order
     *
     * This keeps the invocation contract and rendering uniform across adapters.
     */
    window.ClientSearch = {
        run: function (adapter) {
            var options = Object.assign({
                form: "#search-form",
                input: "#search-query",
                status: "#search-status",
                results: "#search-results",
                sortControl: "#search-sort",
                sort: "relevance",
                indexUrl: window.searchIndexUrl
            }, window.clientSearchConfig || {});
            options.liveSearch = Object.assign({
                enabled: false,
                minChars: 2,
                debounceMs: 150,
                updateUrl: true
            }, options.liveSearch || {});

            var form = document.querySelector(options.form);
            var input = document.querySelector(options.input);
            var status = document.querySelector(options.status);
            var results = document.querySelector(options.results);
            var index = null;
            var documentsById = new Map();
            var liveSearchTimer = null;
            var renderVersion = 0;
            var activeStatusVersion = 0;

            if (!form || !input || !status || !results || !options.indexUrl) {
                return;
            }
            if (!adapter.available()) {
                status.textContent = "Search is temporarily unavailable.";
                return;
            }

            function normalize(entry) {
                var id = entry.id || entry.url;
                if (!id) {
                    return null;
                }
                var categories = Array.isArray(entry.categories) ? entry.categories : [];
                var tags = Array.isArray(entry.tags) ? entry.tags : [];
                var normalized = {
                    id: id,
                    title: entry.title || "Untitled",
                    url: entry.url || "#",
                    excerpt: entry.excerpt || "",
                    content: entry.content || "",
                    date: entry.date || "",
                    date_timestamp: Number(entry.date_timestamp) || 0,
                    categories: categories,
                    tags: tags,
                    categoriesText: categories.join(" "),
                    tagsText: tags.join(" ")
                };
                if (Array.isArray(entry.embedding) && entry.embedding.length > 0) {
                    normalized.embedding = entry.embedding;
                }
                return normalized;
            }

            function buildIndex(data) {
                if (!Array.isArray(data)) {
                    throw new TypeError("Search index must be an array");
                }

                var documents = data.map(normalize).filter(Boolean);
                documentsById = new Map(documents.map(function (entry) {
                    return [entry.id, entry];
                }));
                index = adapter.buildIndex(documents);
            }

            async function search(query) {
                if (!index) {
                    return [];
                }
                var exact = await adapter.search(index, query, {
                    combineWith: "AND",
                    fuzzy: false,
                    prefix: true
                });
                if (exact.length > 0) {
                    return exact;
                }
                return await adapter.search(index, query, {
                    combineWith: "OR",
                    fuzzy: true,
                    prefix: true
                });
            }

            function safeUrl(value) {
                if (value === "#") {
                    return "#";
                }
                try {
                    var url = new URL(value, window.location.origin);
                    if (url.origin === window.location.origin && ["http:", "https:"].includes(url.protocol)) {
                        return url.pathname + url.search + url.hash;
                    }
                } catch (_error) {
                    return "#";
                }
                return "#";
            }

            function resultElement(match) {
                var entry = documentsById.get(match.ref);
                if (!entry) {
                    return null;
                }
                var article = document.createElement("article");
                var heading = document.createElement("h2");
                var titleLink = document.createElement("a");
                var excerpt = document.createElement("p");
                var readMore = document.createElement("a");
                var url = safeUrl(entry.url);

                article.className = "box client-search-result";
                heading.className = "title is-4";
                titleLink.href = url;
                titleLink.textContent = entry.title;
                excerpt.textContent = entry.excerpt;
                readMore.href = url;
                readMore.textContent = "Read more";
                heading.appendChild(titleLink);
                article.append(heading, excerpt, readMore);
                return article;
            }

            function sortMatches(matches) {
                var sortControl = document.querySelector(options.sortControl);
                var sortOrder = sortControl ? sortControl.value : options.sort;
                if (sortOrder !== "date") {
                    return matches;
                }
                return matches.slice().sort(function (a, b) {
                    var first = documentsById.get(a.ref);
                    var second = documentsById.get(b.ref);
                    return (second ? second.date_timestamp : 0) - (first ? first.date_timestamp : 0) ||
                        (b.score || 0) - (a.score || 0);
                });
            }

            function updateUrl() {
                var url = new URL(window.location.href);
                if (input.value.trim()) {
                    url.searchParams.set("q", input.value.trim());
                } else {
                    url.searchParams.delete("q");
                }
                window.history.replaceState({}, "", url);
            }

            function showSearchError() {
                status.textContent = "Search is temporarily unavailable.";
                results.replaceChildren();
            }

            async function render() {
                var query = input.value.trim();
                var version = ++renderVersion;
                activeStatusVersion = version;
                if (!query) {
                    activeStatusVersion = 0;
                    status.textContent = "Search articles by title, text, category, or tag.";
                    results.replaceChildren();
                    return;
                }

                status.textContent = "Searching…";
                var matches;
                try {
                    matches = await search(query);
                } catch (error) {
                    if (version !== renderVersion) {
                        return;
                    }
                    activeStatusVersion = 0;
                    throw error;
                }
                if (version !== renderVersion) {
                    return;
                }
                activeStatusVersion = 0;
                matches = sortMatches(matches);
                status.textContent = matches.length + " result" + (matches.length === 1 ? "" : "s");
                if (matches.length === 0) {
                    var empty = document.createElement("div");
                    empty.className = "notification is-info";
                    empty.textContent = "No articles found.";
                    results.replaceChildren(empty);
                    return;
                }
                results.replaceChildren.apply(
                    results,
                    matches.map(resultElement).filter(Boolean)
                );
            }

            function runRender() {
                render().catch(showSearchError);
            }

            window.addEventListener("client-search:status", function (event) {
                if (activeStatusVersion === renderVersion && event.detail && event.detail.message) {
                    status.textContent = event.detail.message;
                }
            });

            input.addEventListener("input", function () {
                renderVersion += 1;
                activeStatusVersion = 0;
                clearTimeout(liveSearchTimer);
                if (!options.liveSearch.enabled || !index) {
                    return;
                }

                var query = input.value.trim();
                if (options.liveSearch.updateUrl) {
                    updateUrl();
                }
                if (!query) {
                    runRender();
                    return;
                }
                if (query.length < options.liveSearch.minChars) {
                    status.textContent = "Type at least " + options.liveSearch.minChars + " characters.";
                    results.replaceChildren();
                    return;
                }

                status.textContent = "Waiting to search…";
                liveSearchTimer = setTimeout(runRender, options.liveSearch.debounceMs);
            });

            form.addEventListener("submit", function (event) {
                event.preventDefault();
                clearTimeout(liveSearchTimer);
                updateUrl();
                runRender();
            });

            var sortControl = document.querySelector(options.sortControl);
            if (sortControl) {
                sortControl.addEventListener("change", runRender);
            }

            status.textContent = "Loading search index…";
            fetch(options.indexUrl, { headers: { Accept: "application/json" } })
                .then(function (response) {
                    if (!response.ok) {
                        throw new Error("Unable to load search index");
                    }
                    return response.json();
                })
                .then(function (data) {
                    buildIndex(data);
                    input.value = new URLSearchParams(window.location.search).get("q") || "";
                    return render();
                })
                .catch(function () {
                    status.textContent = "Search is temporarily unavailable.";
                    results.replaceChildren();
                });
        }
    };
}());
