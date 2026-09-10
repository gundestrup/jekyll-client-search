(function () {
    "use strict";

    /**
     * ClientSearch shared utilities — used by the base runtime and the
     * dropdown runtime to normalize search index entries into a uniform
     * document format.
     *
     * Loaded before client-search-base.js and client-search-dropdown.js.
     * Exposes window.ClientSearchShared.normalize(entry).
     */

    var CORE_FIELDS = [
        "id", "title", "url", "excerpt", "content",
        "categories", "tags", "categoriesText", "tagsText",
        "date", "date_timestamp", "embedding"
    ];

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
        if (entry.source) {
            normalized.source = entry.source;
        }
        if (Array.isArray(entry.embedding) && entry.embedding.length > 0) {
            normalized.embedding = entry.embedding;
        }
        Object.keys(entry).forEach(function (key) {
            if (CORE_FIELDS.indexOf(key) === -1 && key !== "source" && !(key in normalized)) {
                var value = entry[key];
                if (value !== null && value !== undefined && value !== "") {
                    normalized[key] = value;
                }
            }
        });
        return normalized;
    }

    window.ClientSearchShared = { normalize: normalize, coreFields: CORE_FIELDS };
})();
