(function () {
    "use strict";

    /**
     * MiniSearch adapter — translates the uniform ClientSearch query model
     * into MiniSearch's native API.
     *
     * The base runtime owns the two-stage strategy (AND first, fuzzy OR
     * fallback). This adapter only translates each stage's uniform options
     * into MiniSearch's options and normalises results to { ref, score }.
     */
    var FIELDS = ["title", "excerpt", "content", "categoriesText", "tagsText"];
    var BOOST = {
        title: 10,
        categoriesText: 5,
        tagsText: 4,
        excerpt: 2,
        content: 1
    };

    window.ClientSearchAdapters = window.ClientSearchAdapters || {};
    window.ClientSearchAdapters.minisearch = {
        name: "minisearch",

        available: function () {
            return typeof window.MiniSearch !== "undefined";
        },

        buildIndex: function (documents) {
            var miniSearch = new window.MiniSearch({
                fields: FIELDS,
                storeFields: ["title", "url", "excerpt", "categories", "tags"],
                idField: "id"
            });
            miniSearch.addAll(documents);
            return miniSearch;
        },

        search: function (index, query, options) {
            var nativeOptions = {
                combineWith: options.combineWith,
                prefix: options.prefix,
                boost: BOOST
            };
            if (options.fuzzy) {
                nativeOptions.fuzzy = 0.2;
            }
            return index.search(query, nativeOptions).map(function (match) {
                return { ref: match.id, score: match.score };
            });
        }
    };

    if (window.ClientSearch) {
        window.ClientSearch.run(window.ClientSearchAdapters.minisearch);
    }
}());
