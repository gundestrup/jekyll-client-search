(function () {
    "use strict";

    /**
     * ClientSearch dropdown runtime — compact live-search dropdown for
     * navbars and headers. Framework-agnostic: emits semantic HTML with
     * data attributes, no CSS classes from any framework.
     *
     * Features:
     *   - Lazy index loading (fetches search-index.json on first keystroke)
     *   - Two-stage search (AND first, fuzzy OR fallback) via engine adapter
     *   - Compact <li><a> items with optional icon rendering
     *   - Keyboard navigation (Arrow Up/Down, Enter, Escape)
     *   - Enter with no selection → redirect to redirect_url (?q=...)
     *   - Click outside or Escape → close dropdown
     *   - Multi-instance via [data-client-search-dropdown] attributes
     *   - Shared index cache with the base runtime when present
     */

    var sharedIndex = null;
    var sharedDocuments = null;
    var indexLoadPromise = null;

    function safeUrl(value) {
        if (value === "#") {
            return "#";
        }
        try {
            var url = new URL(value, window.location.origin);
            if (url.origin === window.location.origin &&
                ["http:", "https:"].includes(url.protocol)) {
                return url.pathname + url.search + url.hash;
            }
        } catch (_error) {
            return "#";
        }
        return "#";
    }

    function toCamelCase(key) {
        return key.replace(/_([a-z])/g, function (_, char) { return char.toUpperCase(); });
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
        if (entry.source) {
            normalized.source = entry.source;
        }
        Object.keys(entry).forEach(function (key) {
            if (!(key in normalized) && key !== "embedding") {
                var value = entry[key];
                if (value !== null && value !== undefined && value !== "") {
                    normalized[key] = value;
                }
            }
        });
        return normalized;
    }

    function loadIndex(config) {
        if (sharedIndex && sharedDocuments) {
            return Promise.resolve({ index: sharedIndex, documents: sharedDocuments });
        }
        if (indexLoadPromise) {
            return indexLoadPromise;
        }

        var indexUrl = config.indexUrl;
        if (!indexUrl) {
            return Promise.reject(new Error("No index URL configured"));
        }

        indexLoadPromise = fetch(indexUrl, { headers: { Accept: "application/json" } })
            .then(function (response) {
                if (!response.ok) {
                    throw new Error("Unable to load search index");
                }
                return response.json();
            })
            .then(function (data) {
                if (!Array.isArray(data)) {
                    throw new TypeError("Search index must be an array");
                }
                var documents = data.map(normalize).filter(Boolean);
                var adapter = window.ClientSearchAdapters &&
                    (window.ClientSearchAdapters[config.engine] ||
                     window.ClientSearchAdapters.minisearch);
                if (!adapter) {
                    throw new Error("Search adapter not loaded");
                }
                sharedDocuments = new Map(documents.map(function (entry) {
                    return [entry.id, entry];
                }));
                sharedIndex = adapter.buildIndex(documents);
                return { index: sharedIndex, documents: sharedDocuments };
            })
            .catch(function (error) {
                indexLoadPromise = null;
                throw error;
            });

        return indexLoadPromise;
    }

    function search(index, query, adapter) {
        var exact = adapter.search(index, query, {
            combineWith: "AND",
            fuzzy: false,
            prefix: true
        });
        if (exact && typeof exact.then === "function") {
            return exact.then(function (results) {
                if (results && results.length > 0) {
                    return results;
                }
                return adapter.search(index, query, {
                    combineWith: "OR",
                    fuzzy: true,
                    prefix: true
                });
            });
        }
        if (exact && exact.length > 0) {
            return exact;
        }
        return adapter.search(index, query, {
            combineWith: "OR",
            fuzzy: true,
            prefix: true
        });
    }

    function createResultItem(match, documents, iconField) {
        var entry = documents.get(match.ref);
        if (!entry) {
            return null;
        }

        var li = document.createElement("li");
        li.setAttribute("role", "option");
        li.className = "client-search-dropdown-item";
        li.dataset.url = safeUrl(entry.url);

        if (entry.source) {
            li.dataset.source = entry.source;
        }
        if (entry.categories && entry.categories.length) {
            li.dataset.categories = entry.categories.join(" ");
        }
        if (entry.tags && entry.tags.length) {
            li.dataset.tags = entry.tags.join(" ");
        }
        Object.keys(entry).forEach(function (key) {
            var skip = ["id", "title", "url", "excerpt", "content",
                "categories", "tags", "source", "embedding",
                "date_timestamp"];
            if (skip.indexOf(key) !== -1) {
                return;
            }
            var value = entry[key];
            if (typeof value === "string" || typeof value === "number") {
                li.dataset[toCamelCase(key)] = String(value);
            }
        });

        if (iconField && entry[iconField]) {
            var icon = document.createElement("img");
            icon.className = "client-search-dropdown-icon";
            icon.src = safeUrl(entry[iconField]);
            icon.alt = entry.file_type || entry.source || "";
            icon.loading = "lazy";
            icon.style.width = "1em";
            icon.style.height = "1em";
            icon.style.verticalAlign = "middle";
            icon.style.marginRight = "0.3em";
            li.appendChild(icon);
        }

        var link = document.createElement("a");
        link.href = safeUrl(entry.url);
        link.textContent = entry.title;
        link.className = "client-search-dropdown-link";
        li.appendChild(link);

        return li;
    }

    function DropdownInstance(root, config) {
        this.root = root;
        this.form = root.querySelector("[data-cs-dropdown-form]");
        this.input = root.querySelector("[data-cs-dropdown-input]");
        this.results = root.querySelector("[data-cs-dropdown-results]");
        this.config = config;
        this.maxItems = parseInt(this.results.dataset.maxItems, 10) || config.maxItems || 5;
        this.selectedIndex = -1;
        this.currentItems = [];
        this.debounceTimer = null;
        this.renderVersion = 0;
        this.adapter = null;
    }

    DropdownInstance.prototype.init = function () {
        if (!this.form || !this.input || !this.results) {
            return;
        }

        var self = this;

        this.input.addEventListener("input", function () {
            self.onInput();
        });

        this.input.addEventListener("keydown", function (event) {
            self.onKeydown(event);
        });

        this.form.addEventListener("submit", function (event) {
            event.preventDefault();
            self.onSubmit();
        });

        document.addEventListener("click", function (event) {
            if (!self.root.contains(event.target)) {
                self.hide();
            }
        });

        this.results.addEventListener("click", function (event) {
            var li = event.target.closest("li");
            if (li && li.dataset.url && li.dataset.url !== "#") {
                window.location.href = li.dataset.url;
            }
        });
    };

    DropdownInstance.prototype.onInput = function () {
        var self = this;
        this.renderVersion += 1;
        clearTimeout(this.debounceTimer);

        var query = this.input.value.trim();
        if (!query || query.length < this.config.minChars) {
            this.hide();
            return;
        }

        this.debounceTimer = setTimeout(function () {
            self.performSearch(query);
        }, this.config.debounceMs);
    };

    DropdownInstance.prototype.onKeydown = function (event) {
        if (this.results.getAttribute("aria-hidden") === "true") {
            return;
        }
        var visible = this.results.children.length > 0;
        if (!visible) {
            return;
        }

        switch (event.key) {
            case "ArrowDown":
                event.preventDefault();
                this.selectItem(Math.min(this.selectedIndex + 1, this.currentItems.length - 1));
                break;
            case "ArrowUp":
                event.preventDefault();
                this.selectItem(Math.max(this.selectedIndex - 1, 0));
                break;
            case "Enter":
                if (this.selectedIndex >= 0 && this.currentItems[this.selectedIndex]) {
                    event.preventDefault();
                    var url = this.currentItems[this.selectedIndex].dataset.url;
                    if (url && url !== "#") {
                        window.location.href = url;
                    }
                }
                break;
            case "Escape":
                this.hide();
                this.input.blur();
                break;
            case "Tab":
                this.hide();
                break;
        }
    };

    DropdownInstance.prototype.onSubmit = function () {
        var query = this.input.value.trim();
        if (!query) {
            return;
        }
        var redirectUrl = this.config.redirectUrl || "/search/";
        var separator = redirectUrl.indexOf("?") !== -1 ? "&" : "?";
        window.location.href = redirectUrl + separator + "q=" + encodeURIComponent(query);
    };

    DropdownInstance.prototype.performSearch = function (query) {
        var self = this;
        var version = this.renderVersion;

        var config = this.config;
        var engineName = config.engine || "minisearch";

        loadIndex(config).then(function (loaded) {
            if (version !== self.renderVersion) {
                return;
            }

            var adapter = window.ClientSearchAdapters &&
                (window.ClientSearchAdapters[engineName] ||
                 window.ClientSearchAdapters.minisearch);
            if (!adapter || !adapter.available()) {
                return;
            }

            var results = search(loaded.index, query, adapter);
            return Promise.resolve(results).then(function (matches) {
                if (version === self.renderVersion) {
                    self.renderResults(matches, loaded.documents);
                }
            });
        }).catch(function () {
            if (version === self.renderVersion) {
                self.hide();
            }
        });
    };

    DropdownInstance.prototype.renderResults = function (matches, documents) {
        this.results.replaceChildren();
        this.currentItems = [];
        this.selectedIndex = -1;

        if (!matches || matches.length === 0) {
            this.hide();
            return;
        }

        var iconField = this.config.iconField || null;
        var count = Math.min(matches.length, this.maxItems);

        for (var i = 0; i < count; i++) {
            var item = createResultItem(matches[i], documents, iconField);
            if (item) {
                this.results.appendChild(item);
                this.currentItems.push(item);
            }
        }

        if (this.currentItems.length === 0) {
            this.hide();
            return;
        }

        this.show();
    };

    DropdownInstance.prototype.selectItem = function (index) {
        this.selectedIndex = index;
        for (var i = 0; i < this.currentItems.length; i++) {
            if (i === index) {
                this.currentItems[i].setAttribute("aria-selected", "true");
            } else {
                this.currentItems[i].removeAttribute("aria-selected");
            }
        }
        if (this.currentItems[index]) {
            this.currentItems[index].scrollIntoView({ block: "nearest" });
        }
    };

    DropdownInstance.prototype.show = function () {
        this.results.setAttribute("aria-hidden", "false");
        this.input.setAttribute("aria-expanded", "true");
    };

    DropdownInstance.prototype.hide = function () {
        this.results.setAttribute("aria-hidden", "true");
        this.input.setAttribute("aria-expanded", "false");
        this.results.replaceChildren();
        this.currentItems = [];
        this.selectedIndex = -1;
    };

    function initAll() {
        var config = window.clientSearchConfig || {};
        var dropdownConfig = config.dropdown || {};
        if (dropdownConfig.enabled === false) {
            return;
        }

        var mergedConfig = {
            indexUrl: config.indexUrl,
            engine: config.engine || "minisearch",
            iconField: config.iconField || null,
            minChars: typeof dropdownConfig.minChars === "number" ? dropdownConfig.minChars : 2,
            debounceMs: typeof dropdownConfig.debounceMs === "number" ? dropdownConfig.debounceMs : 150,
            maxItems: typeof dropdownConfig.maxItems === "number" ? dropdownConfig.maxItems : 5,
            redirectUrl: dropdownConfig.redirectUrl || "/search/"
        };

        var roots = document.querySelectorAll("[data-client-search-dropdown]");
        roots.forEach(function (root) {
            var instance = new DropdownInstance(root, mergedConfig);
            instance.init();
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initAll);
    } else {
        initAll();
    }
}());
