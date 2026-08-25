"use strict";

var runtimePromise = null;
var modelPromise = null;
var activeConfig = null;
var inferenceQueue = Promise.resolve();
var latestRequestId = null;

function reportStatus(message) {
    self.postMessage({ type: "status", message: message });
}

function configureRuntime(runtime) {
    if (activeConfig.modelBaseUrl && runtime.env) {
        runtime.env.localModelPath = activeConfig.modelBaseUrl;
        runtime.env.allowRemoteModels = false;
    }
    if (activeConfig.wasmBaseUrl && runtime.env && runtime.env.backends &&
        runtime.env.backends.onnx && runtime.env.backends.onnx.wasm) {
        runtime.env.backends.onnx.wasm.wasmPaths = activeConfig.wasmBaseUrl;
    }
    return runtime;
}

function retry(operation) {
    var attempts = Number.isInteger(activeConfig.retryAttempts) ? activeConfig.retryAttempts : 1;
    return operation().catch(function retryAfterFailure(error) {
        if (attempts <= 0) {
            throw error;
        }
        attempts -= 1;
        return new Promise(function (resolve) {
            setTimeout(resolve, 1000);
        }).then(operation).catch(retryAfterFailure);
    });
}

function progress(update) {
    if (update && Number.isFinite(update.progress)) {
        reportStatus("Loading semantic model… " + Math.round(update.progress) + "%");
    } else {
        reportStatus("Loading semantic model…");
    }
}

function loadRuntime() {
    if (self.ClientSearchTransformers) {
        return Promise.resolve(configureRuntime(self.ClientSearchTransformers));
    }
    if (!runtimePromise) {
        runtimePromise = retry(function () {
            return import(
                activeConfig.libraryUrl ||
                "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1"
            ).then(configureRuntime);
        }).catch(function (error) {
            runtimePromise = null;
            throw error;
        });
    }
    return runtimePromise;
}

function loadModel() {
    if (!modelPromise) {
        reportStatus("Loading semantic model…");
        modelPromise = retry(function () {
            return loadRuntime().then(async function (runtime) {
                var modelId = activeConfig.model || "onnx-community/embeddinggemma-300m-ONNX";
                var tokenizer = await runtime.AutoTokenizer.from_pretrained(modelId, {
                    progress_callback: progress
                });
                var options = {
                    dtype: activeConfig.dtype || "q8",
                    progress_callback: progress
                };
                if (activeConfig.device) {
                    options.device = activeConfig.device;
                }
                var model = await runtime.AutoModel.from_pretrained(modelId, options);
                return { tokenizer: tokenizer, model: model };
            });
        }).catch(function (error) {
            modelPromise = null;
            throw error;
        });
    }
    return modelPromise;
}

async function embed(query) {
    var loaded = await loadModel();
    reportStatus("Embedding query…");
    var input = (activeConfig.queryPrefix || "") + query;
    var tokens = await loaded.tokenizer([input], {
        padding: true,
        truncation: true,
        max_length: Number.isInteger(activeConfig.maxTokens) ? activeConfig.maxTokens : 512
    });
    var output = await loaded.model(tokens);
    var embedding = output.sentence_embedding;
    if (!embedding || !embedding.data) {
        throw new Error("Transformers model returned no sentence embedding");
    }
    return Array.from(embedding.data);
}

self.addEventListener("message", function (event) {
    var message = event.data || {};
    activeConfig = activeConfig || message.config || {};
    latestRequestId = message.id;
    inferenceQueue = inferenceQueue.then(function () {
        if (message.id !== latestRequestId) {
            return null;
        }
        return embed(message.query);
    }).then(function (embedding) {
        if (embedding && message.id === latestRequestId) {
            self.postMessage({ type: "result", id: message.id, embedding: embedding });
        }
    }, function (error) {
        if (message.id === latestRequestId) {
            self.postMessage({
                type: "error",
                id: message.id,
                error: error && error.message ? error.message : String(error)
            });
        }
    });
});
