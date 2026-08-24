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
     *       into the engine's native call and returns [{ ref, score }]
     *       in descending score order
     *
     * This keeps the strategy uniform across engines. Adding a new engine
     * (e.g. a future vector/semantic adapter) only requires implementing
     * the translator — the strategy and rendering do not change.
     */
    window.ClientSearch = {
        run: function (adapter) {
            var options = Object.assign({
                form: "#search-form",
                input: "#search-query",
                status: "#search-status",
                results: "#search-results",
                indexUrl: window.searchIndexUrl
            }, window.clientSearchConfig || {});

            var form = document.querySelector(options.form);
            var input = document.querySelector(options.input);
            var status = document.querySelector(options.status);
            var results = document.querySelector(options.results);
            var index = null;
            var documentsById = new Map();

            if (!form || !input || !status || !results || !options.indexUrl) {
                return;
            }
            if (!adapter.available()) {
                status.textContent = "Search is temporarily unavailable.";
                return;
            }

            function normalize(document) {
                var id = document.id || document.url;
                if (!id) {
                    return null;
                }
                var categories = Array.isArray(document.categories) ? document.categories : [];
                var tags = Array.isArray(document.tags) ? document.tags : [];
                var normalized = {
                    id: id,
                    title: document.title || "Untitled",
                    url: document.url || "#",
                    excerpt: document.excerpt || "",
                    content: document.content || "",
                    categories: categories,
                    tags: tags,
                    categoriesText: categories.join(" "),
                    tagsText: tags.join(" ")
                };
                if (Array.isArray(document.embedding) && document.embedding.length > 0) {
                    normalized.embedding = document.embedding;
                }
                return normalized;
            }

            function buildIndex(data) {
                if (!Array.isArray(data)) {
                    throw new TypeError("Search index must be an array");
                }

                var documents = data.map(normalize).filter(Boolean);
                documentsById = new Map(documents.map(function (document) {
                    return [document.id, document];
                }));
                index = adapter.buildIndex(documents);
            }

            function search(query) {
                if (!index) {
                    return [];
                }
                try {
                    var exact = adapter.search(index, query, {
                        combineWith: "AND",
                        fuzzy: false,
                        prefix: true
                    });
                    if (exact.length > 0) {
                        return exact;
                    }
                    return adapter.search(index, query, {
                        combineWith: "OR",
                        fuzzy: true,
                        prefix: true
                    });
                } catch (_error) {
                    return [];
                }
            }

            function safeUrl(value) {
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

            function render() {
                var query = input.value.trim();
                if (!query) {
                    status.textContent = "Search articles by title, text, category, or tag.";
                    results.replaceChildren();
                    return;
                }

                var matches = search(query);
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

            form.addEventListener("submit", function (event) {
                event.preventDefault();
                var url = new URL(window.location.href);
                if (input.value.trim()) {
                    url.searchParams.set("q", input.value.trim());
                } else {
                    url.searchParams.delete("q");
                }
                window.history.replaceState({}, "", url);
                render();
            });

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
                    render();
                })
                .catch(function () {
                    status.textContent = "Search is temporarily unavailable.";
                });
        }
    };
}());
