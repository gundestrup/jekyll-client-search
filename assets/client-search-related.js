(function () {
    "use strict";

    function safeUrl(value) {
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

    function formatDate(timestamp) {
        if (!timestamp) {
            return "";
        }
        try {
            return new Date(timestamp * 1000).toLocaleDateString(undefined, {
                year: "numeric", month: "short", day: "numeric"
            });
        } catch (_error) {
            return "";
        }
    }

    function appendMeta(parent, className, text) {
        if (!text) {
            return;
        }
        var span = document.createElement("span");
        span.className = className;
        span.textContent = text;
        parent.appendChild(span);
    }

    function defaultRenderItem(item) {
        var entry = document.createElement("li");
        entry.className = "related-article-item";

        var link = document.createElement("a");
        link.href = safeUrl(item.url);
        link.textContent = item.title || item.url;
        link.className = "related-article-link";
        entry.appendChild(link);

        var metaParts = [];
        if (item.date_timestamp) {
            var dateSpan = document.createElement("span");
            dateSpan.className = "related-article-date";
            dateSpan.textContent = formatDate(item.date_timestamp);
            metaParts.push(dateSpan);
        }
        if (Array.isArray(item.shared_tags) && item.shared_tags.length) {
            appendMeta(entry, "related-article-tags", item.shared_tags.join(", "));
        }
        if (Array.isArray(item.shared_categories) && item.shared_categories.length) {
            appendMeta(entry, "related-article-categories", item.shared_categories.join(", "));
        }
        if (metaParts.length) {
            var meta = document.createElement("div");
            meta.className = "related-article-meta";
            metaParts.forEach(function (el) { meta.appendChild(el); });
            entry.appendChild(meta);
        }

        if (item.excerpt) {
            var excerpt = document.createElement("p");
            excerpt.className = "related-article-excerpt";
            excerpt.textContent = item.excerpt;
            entry.appendChild(excerpt);
        }

        return entry;
    }

    function sortItems(items, sortOrder) {
        if (sortOrder === "date") {
            items.sort(function (a, b) {
                return (b.date_timestamp || 0) - (a.date_timestamp || 0) ||
                    String(a.title).localeCompare(String(b.title));
            });
        } else {
            items.sort(function (a, b) {
                return (b.score || 0) - (a.score || 0) ||
                    String(a.title).localeCompare(String(b.title));
            });
        }
    }

    function render(container, relations, sortOrder, options) {
        var items = relations.slice();
        if (typeof options.filter === "function") {
            items = items.filter(function (item, index, array) {
                return options.filter(item, index, array);
            });
        }
        sortItems(items, sortOrder);

        var maxItems = options.maxItems || 0;
        if (maxItems && maxItems > 0) {
            items = items.slice(0, maxItems);
        }

        container.replaceChildren();
        if (items.length === 0) {
            return;
        }

        var heading = document.createElement("h2");
        heading.textContent = "Related articles";
        var list = document.createElement("ul");
        list.className = "related-articles-list";

        var renderItem = options.renderItem || defaultRenderItem;
        items.forEach(function (item) {
            var entry = renderItem(item, document);
            if (entry) {
                list.appendChild(entry);
            }
        });
        container.append(heading, list);
    }

    function resolveSort(container, sortControl, fallback) {
        if (sortControl) {
            return sortControl.value || fallback;
        }
        if (container.dataset.relatedSort) {
            return container.dataset.relatedSort;
        }
        return fallback;
    }

    window.ClientSearchRelated = {
        run: function (options) {
            options = Object.assign({
                container: "#related-articles",
                sortControl: "#related-sort",
                relationsUrl: window.clientSearchConfig && window.clientSearchConfig.relatedUrl,
                currentUrl: window.location.pathname,
                sort: (window.clientSearchConfig && window.clientSearchConfig.relatedSort) || "relevance",
                maxItems: 0,
                renderItem: null,
                filter: null
            }, options || {});
            var container = document.querySelector(options.container);
            if (!container || !options.relationsUrl) {
                return Promise.resolve();
            }

            if (container.dataset.relatedMax) {
                options.maxItems = parseInt(container.dataset.relatedMax, 10) || 0;
            }

            return fetch(options.relationsUrl, { headers: { Accept: "application/json" } })
                .then(function (response) {
                    if (!response.ok) {
                        throw new Error("Unable to load related articles");
                    }
                    return response.json();
                })
                .then(function (data) {
                    var relations = (data.relations && data.relations[options.currentUrl]) || [];
                    var sortControl = document.querySelector(options.sortControl);
                    var sort = resolveSort(container, sortControl, options.sort);
                    render(container, relations, sort, options);
                    if (sortControl) {
                        sortControl.addEventListener("change", function () {
                            render(container, relations, sortControl.value, options);
                        });
                    }
                })
                .catch(function () {
                    container.replaceChildren();
                });
        }
    };

    if (document.querySelector("#related-articles")) {
        window.ClientSearchRelated.run();
    }
}());
