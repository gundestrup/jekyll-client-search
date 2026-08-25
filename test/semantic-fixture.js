"use strict";

const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const baselinePath = path.join(root, "spec", "fixtures", "baseline", "search-index-baseline.json");
const goldPath = path.join(root, "spec", "fixtures", "baseline", "semantic-embeddings.json");

function loadJson(filePath) {
    if (!fs.existsSync(filePath)) {
        throw new Error(`Required test fixture is missing: ${filePath}`);
    }
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function loadSemanticFixture() {
    var baseline = loadJson(baselinePath);
    var gold = loadJson(goldPath);
    return {
        model: gold.model,
        documents: baseline.map(function (entry) {
            var embedding = gold.document_embeddings[entry.id];
            if (!embedding) {
                throw new Error(`Semantic embedding missing for document: ${entry.id}`);
            }
            return Object.assign({}, entry, { embedding: embedding });
        }),
        query_embeddings: gold.query_embeddings
    };
}

module.exports = { loadSemanticFixture: loadSemanticFixture };
