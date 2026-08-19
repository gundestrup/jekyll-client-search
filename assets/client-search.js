(function () {
    "use strict";

    const options = Object.assign({
        form: "#search-form",
        input: "#search-query",
        status: "#search-status",
        results: "#search-results",
        indexUrl: window.searchIndexUrl
    }, window.clientSearchConfig || {});
    const form = document.querySelector(options.form);
    const input = document.querySelector(options.input);
    const status = document.querySelector(options.status);
    const results = document.querySelector(options.results);
    let miniSearch = null;
    let documentsById = new Map();

    if (!form || !input || !status || !results || !options.indexUrl) {
        return;
    }
    if (typeof window.MiniSearch === "undefined") {
        status.textContent = "Search is temporarily unavailable.";
        return;
    }

    function normalize(document) {
        const id = document.id || document.url;
        if (!id) {
            return null;
        }
        const categories = Array.isArray(document.categories) ? document.categories : [];
        const tags = Array.isArray(document.tags) ? document.tags : [];
        return {
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
    }

    function buildIndex(data) {
        if (!Array.isArray(data)) {
            throw new TypeError("Search index must be an array");
        }

        const documents = data.map(normalize).filter(Boolean);
        documentsById = new Map(documents.map(function (document) {
            return [document.id, document];
        }));

        miniSearch = new window.MiniSearch({
            fields: ["title", "excerpt", "content", "categoriesText", "tagsText"],
            storeFields: ["title", "url", "excerpt", "categories", "tags"],
            idField: "id",
            searchOptions: {
                combineWith: "AND",
                prefix: true,
                boost: {
                    title: 10,
                    categoriesText: 5,
                    tagsText: 4,
                    excerpt: 2,
                    content: 1
                }
            }
        });
        miniSearch.addAll(documents);
    }

    function search(query) {
        if (!miniSearch) {
            return [];
        }
        try {
            const exact = miniSearch.search(query);
            if (exact.length > 0) {
                return exact;
            }
            return miniSearch.search(query, {
                combineWith: "OR",
                fuzzy: 0.2,
                prefix: true
            });
        } catch (error) {
            return [];
        }
    }

    function safeUrl(value) {
        try {
            const url = new URL(value, window.location.origin);
            if (url.origin === window.location.origin && ["http:", "https:"].includes(url.protocol)) {
                return url.pathname + url.search + url.hash;
            }
        } catch (error) {
            return "#";
        }
        return "#";
    }

    function resultElement(match) {
        const entry = documentsById.get(match.id);
        if (!entry) {
            return null;
        }
        const article = document.createElement("article");
        const heading = document.createElement("h2");
        const titleLink = document.createElement("a");
        const excerpt = document.createElement("p");
        const readMore = document.createElement("a");
        const url = safeUrl(entry.url);

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
        const query = input.value.trim();
        if (!query) {
            status.textContent = "Search articles by title, text, category, or tag.";
            results.replaceChildren();
            return;
        }

        const matches = search(query);
        status.textContent = matches.length + " result" + (matches.length === 1 ? "" : "s");
        if (matches.length === 0) {
            const empty = document.createElement("div");
            empty.className = "notification is-info";
            empty.textContent = "No articles found.";
            results.replaceChildren(empty);
            return;
        }
        results.replaceChildren(...matches.map(resultElement).filter(Boolean));
    }

    form.addEventListener("submit", function (event) {
        event.preventDefault();
        const url = new URL(window.location.href);
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
}());
