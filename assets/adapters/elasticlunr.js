(function () {
    "use strict";

    /**
     * ElasticLunr adapter — translates the uniform ClientSearch query model
     * into ElasticLunr's native API.
     *
     * The base runtime owns the two-stage strategy (AND first, fuzzy OR
     * fallback). This adapter only translates each stage's uniform options
     * into ElasticLunr's search options and normalises results to
     * { ref, score }. ElasticLunr already returns { ref, score } so the
     * result translation is a pass-through.
     */
    var FIELD_OPTIONS = {
        title: { boost: 10 },
        categoriesText: { boost: 5 },
        tagsText: { boost: 4 },
        excerpt: { boost: 2 },
        content: { boost: 1 }
    };

    window.ClientSearchAdapters = window.ClientSearchAdapters || {};
    window.ClientSearchAdapters.elasticlunr = {
        name: "elasticlunr",

        available: function () {
            return typeof window.elasticlunr !== "undefined";
        },

        buildIndex: function (documents) {
            var index = window.elasticlunr(function () {
                this.setRef("id");
                Object.keys(FIELD_OPTIONS).forEach(function (field) {
                    this.addField(field, FIELD_OPTIONS[field]);
                }, this);
            });
            documents.forEach(function (document) {
                index.addDoc(document);
            });
            return index;
        },

        search: function (index, query, options) {
            var nativeOptions = {
                fields: FIELD_OPTIONS,
                bool: options.combineWith,
                expand: options.prefix
            };
            if (options.fuzzy) {
                nativeOptions.fuzzy = true;
            }
            return index.search(query, nativeOptions);
        }
    };

    if (window.ClientSearch) {
        window.ClientSearch.run(window.ClientSearchAdapters.elasticlunr);
    }
}());
