(function () {
    "use strict";

    const form = document.getElementById("search-form");
    const input = document.getElementById("search-query");
    const status = document.getElementById("search-status");
    const results = document.getElementById("search-results");
    let documents = [];
    let documentsById = new Map();
    let elasticlunrIndex;

    if (!form || !input || !status || !results) {
        return;
    }
    if (typeof elasticlunr === "undefined") {
        status.textContent = "Search is temporarily unavailable.";
        return;
    }

    function escapeHtml(value) {
        return String(value).replace(/[&<>\"']/g, function (character) {
            return {
                "&": "&amp;",
                "<": "&lt;",
                ">": "&gt;",
                "\"": "&quot;",
                "'": "&#39;"
            }[character];
        });
    }

    function normalize(document) {
        return {
            id: document.id || document.url,
            title: document.title || "Untitled",
            url: document.url || "#",
            excerpt: document.excerpt || "",
            content: document.content || "",
            categories: document.categories || [],
            tags: document.tags || []
        };
    }

    function searchableDocument(document) {
        return {
            id: document.id,
            title: document.title,
            excerpt: document.excerpt,
            content: document.content,
            categories: document.categories.join(" "),
            tags: document.tags.join(" ")
        };
    }

    function buildIndex(data) {
        documents = data.map(normalize);
        documentsById = new Map(documents.map(function (document) {
            return [document.id, document];
        }));

        elasticlunrIndex = elasticlunr(function () {
            this.setRef("id");
            this.addField("title");
            this.addField("categories");
            this.addField("tags");
            this.addField("excerpt");
            this.addField("content");
            this.saveDocument(false);
        });
        documents.forEach(function (document) {
            elasticlunrIndex.addDoc(searchableDocument(document));
        });
    }

    function search(query) {
        let searchResults = [];
        try {
            searchResults = elasticlunrIndex.search(query, {
                expand: true,
                fields: {
                    title: { boost: 10 },
                    categories: { boost: 5 },
                    tags: { boost: 4 },
                    content: { boost: 1 },
                    excerpt: { boost: 2 }
                }
            });
        } catch (error) {
            return [];
        }

        return searchResults
            .sort(function (left, right) { return right.score - left.score; })
            .map(function (result) { return documentsById.get(result.ref); })
            .filter(Boolean);
    }

    function render() {
        const query = input.value.trim();
        if (!query) {
            status.textContent = "Search articles by title, text, category, or tag.";
            results.innerHTML = "";
            return;
        }

        const matches = search(query);
        status.textContent = matches.length + " result" + (matches.length === 1 ? "" : "s");
        results.innerHTML = matches.map(function (document) {
            return "<article class=\"box\">" +
                "<h2 class=\"title is-4\"><a href=\"" + escapeHtml(document.url) + "\">" +
                escapeHtml(document.title) + "</a></h2>" +
                "<p>" + escapeHtml(document.excerpt) + "</p>" +
                "<a href=\"" + escapeHtml(document.url) + "\">Read more</a>" +
                "</article>";
        }).join("") || "<div class=\"notification is-info\">No articles found.</div>";
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

    fetch(window.searchIndexUrl)
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
