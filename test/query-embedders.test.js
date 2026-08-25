"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { JSDOM } = require("jsdom");

const TRANSFORMERS_SOURCE = fs.readFileSync(
    path.join(__dirname, "..", "assets", "query-embedders", "transformers.js"),
    "utf8"
);
const OLLAMA_SOURCE = fs.readFileSync(
    path.join(__dirname, "..", "assets", "query-embedders", "ollama-api.js"),
    "utf8"
);
const TRANSFORMERS_WORKER_SOURCE = fs.readFileSync(
    path.join(__dirname, "..", "assets", "query-embedders", "transformers-worker.js"),
    "utf8"
);

function createWindow() {
    return new JSDOM("<!doctype html>", { url: "https://example.com/", runScripts: "outside-only" }).window;
}

test("transformers embedder loads the configured model and prefixes queries", async function () {
    const window = createWindow();
    const calls = {};
    const statuses = [];
    window.addEventListener("client-search:status", function (event) {
        statuses.push(event.detail.message);
    });
    const model = async function (tokens) {
        calls.tokens = tokens;
        return { sentence_embedding: { data: new Float32Array([0.1, 0.2, 0.3]) } };
    };
    window.ClientSearchEmbedderConfig = {
        model: "onnx-community/embeddinggemma-300m-ONNX",
        queryPrefix: "task: search result | query: ",
        dtype: "q8",
        modelBaseUrl: "/assets/models/",
        wasmBaseUrl: "/assets/wasm/",
        maxTokens: 128,
        worker: false
    };
    window.ClientSearchTransformers = {
        env: { backends: { onnx: { wasm: {} } } },
        AutoTokenizer: {
            from_pretrained: async function (modelId, options) {
                calls.tokenizerModel = modelId;
                calls.tokenizerLoadOptions = options;
                options.progress_callback({ progress: 25 });
                return async function (input, options) {
                    calls.input = input;
                    calls.tokenizerOptions = options;
                    return { input_ids: [1, 2, 3] };
                };
            }
        },
        AutoModel: {
            from_pretrained: async function (modelId, options) {
                calls.modelId = modelId;
                calls.modelOptions = options;
                return model;
            }
        }
    };

    window.eval(TRANSFORMERS_SOURCE);
    const vector = await window.ClientSearchQueryEmbedder("glacier search");

    assert.deepEqual(Array.from(vector), Array.from(new Float32Array([0.1, 0.2, 0.3])));
    assert.equal(calls.tokenizerModel, "onnx-community/embeddinggemma-300m-ONNX");
    assert.equal(calls.modelId, "onnx-community/embeddinggemma-300m-ONNX");
    assert.equal(calls.modelOptions.dtype, "q8");
    assert.deepEqual(Array.from(calls.input), ["task: search result | query: glacier search"]);
    assert.equal(typeof calls.tokenizerLoadOptions.progress_callback, "function");
    assert.equal(typeof calls.modelOptions.progress_callback, "function");
    assert.equal(calls.tokenizerOptions.padding, true);
    assert.equal(calls.tokenizerOptions.truncation, true);
    assert.equal(calls.tokenizerOptions.max_length, 128);
    assert.deepEqual(calls.tokens, { input_ids: [1, 2, 3] });
    assert.equal(window.ClientSearchTransformers.env.localModelPath, "/assets/models/");
    assert.equal(window.ClientSearchTransformers.env.allowRemoteModels, false);
    assert.equal(window.ClientSearchTransformers.env.backends.onnx.wasm.wasmPaths, "/assets/wasm/");
    assert.ok(statuses.includes("Loading semantic model… 25%"));
    assert.ok(statuses.includes("Embedding query…"));
});

test("transformers embedder caches the loaded model", async function () {
    const window = createWindow();
    let loads = 0;
    const model = async function () {
        return { sentence_embedding: { data: new Float32Array([1, 0]) } };
    };
    window.ClientSearchTransformers = {
        AutoTokenizer: {
            from_pretrained: async function () {
                loads += 1;
                return async function () { return {}; };
            }
        },
        AutoModel: {
            from_pretrained: async function () {
                loads += 1;
                return model;
            }
        }
    };

    window.eval(TRANSFORMERS_SOURCE);
    await window.ClientSearchQueryEmbedder("one");
    await window.ClientSearchQueryEmbedder("two");

    assert.equal(loads, 2);
});

test("transformers embedder rejects a response without a sentence embedding", async function () {
    const window = createWindow();
    window.ClientSearchTransformers = {
        AutoTokenizer: { from_pretrained: async function () { return async function () { return {}; }; } },
        AutoModel: { from_pretrained: async function () { return async function () { return {}; }; } }
    };

    window.eval(TRANSFORMERS_SOURCE);

    await assert.rejects(
        window.ClientSearchQueryEmbedder("query"),
        /returned no sentence embedding/
    );
});

test("transformers embedder retries after a failed model load", async function () {
    const window = createWindow();
    let attempts = 0;
    const model = async function () {
        return { sentence_embedding: { data: new Float32Array([1, 0]) } };
    };
    window.ClientSearchEmbedderConfig = { worker: false, retryAttempts: 0 };
    window.ClientSearchTransformers = {
        AutoTokenizer: {
            from_pretrained: async function () {
                attempts += 1;
                if (attempts === 1) {
                    throw new Error("temporary failure");
                }
                return async function () { return {}; };
            }
        },
        AutoModel: { from_pretrained: async function () { return model; } }
    };

    window.eval(TRANSFORMERS_SOURCE);
    await assert.rejects(window.ClientSearchQueryEmbedder("first"), /temporary failure/);
    const vector = await window.ClientSearchQueryEmbedder("second");

    assert.deepEqual(Array.from(vector), [1, 0]);
    assert.equal(attempts, 2);
});

test("transformers embedder uses the packaged worker when available", async function () {
    const window = createWindow();
    const created = [];
    class FakeWorker {
        constructor(url, options) {
            this.listeners = {};
            this.url = url;
            this.options = options;
            created.push(this);
        }
        addEventListener(type, listener) {
            this.listeners[type] = listener;
        }
        postMessage(message) {
            this.message = message;
            setTimeout(() => {
                this.listeners.message({
                    data: { type: "result", id: message.id, embedding: [0.4, 0.6] }
                });
            }, 0);
        }
        terminate() {}
    }
    window.Worker = FakeWorker;
    window.ClientSearchEmbedderConfig = {
        worker: true,
        workerUrl: "/assets/query-embedders/transformers-worker.js"
    };

    window.eval(TRANSFORMERS_SOURCE);
    const obsolete = window.ClientSearchQueryEmbedder("obsolete query");
    const current = window.ClientSearchQueryEmbedder("worker query");

    await assert.rejects(obsolete, /Obsolete semantic query/);
    const vector = await current;
    assert.deepEqual(vector, [0.4, 0.6]);
    assert.equal(created.length, 1);
    assert.equal(created[0].url, "/assets/query-embedders/transformers-worker.js");
    assert.equal(created[0].options.type, "module");
    assert.equal(created[0].message.query, "worker query");
});

test("transformers worker coalesces queued queries and runs only the latest", async function () {
    const window = createWindow();
    const outputs = [];
    let active = 0;
    let maxActive = 0;
    window.postMessage = function (message) { outputs.push(message); };
    window.ClientSearchTransformers = {
        AutoTokenizer: {
            from_pretrained: async function () {
                return async function (input) { return { input: input }; };
            }
        },
        AutoModel: {
            from_pretrained: async function () {
                return async function () {
                    active += 1;
                    maxActive = Math.max(maxActive, active);
                    await new Promise(function (resolve) { setTimeout(resolve, 5); });
                    active -= 1;
                    return { sentence_embedding: { data: new Float32Array([0.3, 0.7]) } };
                };
            }
        }
    };

    window.eval(TRANSFORMERS_WORKER_SOURCE);
    window.dispatchEvent(new window.MessageEvent("message", {
        data: { id: 1, query: "first", config: { retryAttempts: 0 } }
    }));
    window.dispatchEvent(new window.MessageEvent("message", {
        data: { id: 2, query: "second", config: { retryAttempts: 0 } }
    }));
    await new Promise(function (resolve) { setTimeout(resolve, 20); });

    const results = outputs.filter(function (message) { return message.type === "result"; });
    assert.equal(results.length, 1);
    assert.deepEqual(results.map(function (message) { return message.id; }), [2]);
    assert.equal(maxActive, 1);
});

test("Ollama API embedder posts the prefixed query and returns the vector", async function () {
    const window = createWindow();
    let request;
    window.ClientSearchEmbedderConfig = {
        model: "embeddinggemma:300m",
        apiUrl: "https://ollama.example/api/embed",
        queryPrefix: "task: search result | query: "
    };
    window.fetch = async function (url, options) {
        request = { url: url, options: options };
        return {
            ok: true,
            json: async function () { return { embeddings: [[0.2, 0.4]] }; }
        };
    };

    window.eval(OLLAMA_SOURCE);
    const vector = await window.ClientSearchQueryEmbedder("glacier");

    assert.deepEqual(vector, [0.2, 0.4]);
    assert.equal(request.url, "https://ollama.example/api/embed");
    assert.equal(request.options.method, "POST");
    assert.deepEqual(JSON.parse(request.options.body), {
        model: "embeddinggemma:300m",
        input: "task: search result | query: glacier"
    });
});

test("Ollama API embedder rejects failed and empty responses", async function () {
    const failedWindow = createWindow();
    failedWindow.fetch = async function () { return { ok: false, status: 503 }; };
    failedWindow.eval(OLLAMA_SOURCE);
    await assert.rejects(failedWindow.ClientSearchQueryEmbedder("query"), /returned 503/);

    const emptyWindow = createWindow();
    emptyWindow.fetch = async function () {
        return { ok: true, json: async function () { return { embeddings: [] }; } };
    };
    emptyWindow.eval(OLLAMA_SOURCE);
    await assert.rejects(emptyWindow.ClientSearchQueryEmbedder("query"), /empty embedding/);
});

test("Ollama API embedder aborts an obsolete query", async function () {
    const window = createWindow();
    let requestNumber = 0;
    window.fetch = function (_url, options) {
        requestNumber += 1;
        if (requestNumber === 2) {
            return Promise.resolve({
                ok: true,
                json: async function () { return { embeddings: [[1, 0]] }; }
            });
        }
        return new Promise(function (_resolve, reject) {
            options.signal.addEventListener("abort", function () {
                reject(new window.DOMException("Aborted", "AbortError"));
            });
        });
    };

    window.eval(OLLAMA_SOURCE);
    const obsolete = window.ClientSearchQueryEmbedder("old query");
    const current = window.ClientSearchQueryEmbedder("new query");

    await assert.rejects(obsolete, /Aborted/);
    assert.deepEqual(await current, [1, 0]);
});

test("Ollama API embedder times out a stalled request", async function () {
    const window = createWindow();
    window.ClientSearchEmbedderConfig = { timeoutMs: 1 };
    window.fetch = function (_url, options) {
        return new Promise(function (_resolve, reject) {
            options.signal.addEventListener("abort", function () {
                reject(new window.DOMException("Aborted", "AbortError"));
            });
        });
    };

    window.eval(OLLAMA_SOURCE);

    await assert.rejects(window.ClientSearchQueryEmbedder("query"), /request timed out/);
});
