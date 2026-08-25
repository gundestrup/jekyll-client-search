"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { performance } = require("node:perf_hooks");
const MiniSearch = require("minisearch");
const elasticlunr = require("elasticlunr");

const root = path.join(__dirname, "..");
const baselinePath = path.join(root, "spec", "fixtures", "baseline", "search-index-baseline.json");
const generatedSemanticPath = path.join(__dirname, "semantic-benchmark.json");
const fixtureSemanticPath = path.join(root, "spec", "fixtures", "site", "_site", "search-index-semantic.json");
const semanticPath = fs.existsSync(generatedSemanticPath) ? generatedSemanticPath : fixtureSemanticPath;
const queries = ["glacier", "ice climbing", "sourdough bread", "fermentation", "camera lens"];
const iterations = 100;
const fields = ["title", "excerpt", "content", "categoriesText", "tagsText"];
const boost = { title: 10, categoriesText: 5, tagsText: 4, excerpt: 2, content: 1 };
const fieldOptions = {
    title: { boost: 10 },
    categoriesText: { boost: 5 },
    tagsText: { boost: 4 },
    excerpt: { boost: 2 },
    content: { boost: 1 }
};
const documents = JSON.parse(fs.readFileSync(baselinePath, "utf8")).map(function (entry) {
    var categories = Array.isArray(entry.categories) ? entry.categories : [];
    var tags = Array.isArray(entry.tags) ? entry.tags : [];
    return Object.assign({}, entry, {
        categoriesText: categories.join(" "),
        tagsText: tags.join(" ")
    });
});

function measure(search) {
    queries.forEach(search);
    var start = performance.now();
    var resultCount = 0;
    for (var i = 0; i < iterations; i++) {
        queries.forEach(function (query) {
            resultCount += search(query).length;
        });
    }
    var elapsed = performance.now() - start;
    return {
        "avg_query_ms": Number((elapsed / (iterations * queries.length)).toFixed(3)),
        "queries_per_second": Number((iterations * queries.length / (elapsed / 1000)).toFixed(1)),
        "result_count": resultCount / iterations
    };
}

var miniSearch = new MiniSearch({ fields: fields, idField: "id" });
miniSearch.addAll(documents);

var elasticIndex = elasticlunr(function () {
    this.setRef("id");
    Object.keys(fieldOptions).forEach(function (field) {
        this.addField(field, fieldOptions[field]);
    }, this);
});
documents.forEach(function (entry) { elasticIndex.addDoc(entry); });

var metrics = {
    "minisearch": measure(function (query) {
        var exact = miniSearch.search(query, { combineWith: "AND", prefix: true, boost: boost });
        return exact.length > 0
            ? exact
            : miniSearch.search(query, { combineWith: "OR", prefix: true, fuzzy: 0.2, boost: boost });
    }),
    "elasticlunr": measure(function (query) {
        var exact = elasticIndex.search(query, { fields: fieldOptions, bool: "AND", expand: true });
        return exact.length > 0
            ? exact
            : elasticIndex.search(query, { fields: fieldOptions, bool: "OR", expand: true, fuzzy: true });
    })
};

if (fs.existsSync(semanticPath)) {
    var semanticData = JSON.parse(fs.readFileSync(semanticPath, "utf8"));
    var semanticDocuments = semanticData.documents.filter(function (entry) {
        return Array.isArray(entry.embedding) && entry.embedding.length > 0;
    });
    var queryEmbeddings = semanticData.query_embeddings;
    metrics.semantic = measure(function (query) {
        var queryEmbedding = queryEmbeddings[query];
        if (!queryEmbedding) return [];
        return semanticDocuments.map(function (entry) {
            var dot = 0;
            var normQuery = 0;
            var normDocument = 0;
            for (var i = 0; i < queryEmbedding.length; i++) {
                dot += queryEmbedding[i] * entry.embedding[i];
                normQuery += queryEmbedding[i] * queryEmbedding[i];
                normDocument += entry.embedding[i] * entry.embedding[i];
            }
            var denominator = Math.sqrt(normQuery) * Math.sqrt(normDocument);
            return denominator === 0 ? 0 : dot / denominator;
        }).filter(function (score) { return score >= 0.3; });
    });
}

process.stdout.write(JSON.stringify({ iterations: iterations, queries: queries.length, metrics: metrics }));
