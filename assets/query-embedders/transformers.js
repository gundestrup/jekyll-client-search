(function () {
    "use strict";

    var config = window.ClientSearchEmbedderConfig || {};
    var modelId = config.model || "onnx-community/embeddinggemma-300m-ONNX";
    var runtimePromise = null;
    var modelPromise = null;
    var worker = null;
    var workerUnavailable = false;
    var workerRequests = new Map();
    var nextWorkerRequestId = 1;
    var currentScriptUrl = document.currentScript && document.currentScript.src;

    function reportStatus(message) {
        window.dispatchEvent(new CustomEvent("client-search:status", {
            detail: { message: message }
        }));
    }

    function configureRuntime(runtime) {
        if (config.modelBaseUrl && runtime.env) {
            runtime.env.localModelPath = config.modelBaseUrl;
            runtime.env.allowRemoteModels = false;
        }
        if (config.wasmBaseUrl && runtime.env && runtime.env.backends &&
            runtime.env.backends.onnx && runtime.env.backends.onnx.wasm) {
            runtime.env.backends.onnx.wasm.wasmPaths = config.wasmBaseUrl;
        }
        return runtime;
    }

    function retry(operation) {
        var attempts = Number.isInteger(config.retryAttempts) ? config.retryAttempts : 1;
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

    function withTimeout(promise) {
        var timeoutMs = Number.isInteger(config.timeoutMs) ? config.timeoutMs : 300000;
        return new Promise(function (resolve, reject) {
            var timer = setTimeout(function () {
                reject(new Error("Transformers model loading timed out"));
            }, timeoutMs);
            promise.then(function (value) {
                clearTimeout(timer);
                resolve(value);
            }, function (error) {
                clearTimeout(timer);
                reject(error);
            });
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
        if (window.ClientSearchTransformers) {
            return Promise.resolve(configureRuntime(window.ClientSearchTransformers));
        }
        if (!runtimePromise) {
            runtimePromise = retry(function () {
                return import(
                    config.libraryUrl ||
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
                    var tokenizer = await runtime.AutoTokenizer.from_pretrained(modelId, {
                        progress_callback: progress
                    });
                    var options = {
                        dtype: config.dtype || "q8",
                        progress_callback: progress
                    };
                    if (config.device) {
                        options.device = config.device;
                    }
                    var model = await runtime.AutoModel.from_pretrained(modelId, options);
                    return { tokenizer: tokenizer, model: model };
                });
            }).catch(function (error) {
                modelPromise = null;
                throw error;
            });
        }
        return withTimeout(modelPromise);
    }

    async function embedInline(query) {
        var loaded = await loadModel();
        reportStatus("Embedding query…");
        var input = (config.queryPrefix || "") + query;
        var tokens = await loaded.tokenizer([input], {
            padding: true,
            truncation: true,
            max_length: Number.isInteger(config.maxTokens) ? config.maxTokens : 512
        });
        var output = await loaded.model(tokens);
        var embedding = output.sentence_embedding;
        if (!embedding || !embedding.data) {
            throw new Error("Transformers model returned no sentence embedding");
        }
        return Array.from(embedding.data);
    }

    function workerUrl() {
        if (config.workerUrl) {
            return config.workerUrl;
        }
        if (currentScriptUrl) {
            return new URL("transformers-worker.js", currentScriptUrl).href;
        }
        return "/assets/query-embedders/transformers-worker.js";
    }

    function rejectWorkerRequests(error, useFallback) {
        workerRequests.forEach(function (request) {
            clearTimeout(request.timer);
            if (useFallback) {
                embedInline(request.query).then(request.resolve, request.reject);
            } else {
                request.reject(error);
            }
        });
        workerRequests.clear();
    }

    function createWorker() {
        if (worker || workerUnavailable || config.worker === false || typeof Worker !== "function") {
            return worker;
        }
        try {
            worker = new Worker(workerUrl(), { type: "module" });
            worker.addEventListener("message", function (event) {
                var message = event.data || {};
                if (message.type === "status") {
                    reportStatus(message.message);
                    return;
                }
                var request = workerRequests.get(message.id);
                if (!request) {
                    return;
                }
                clearTimeout(request.timer);
                workerRequests.delete(message.id);
                if (message.type === "result") {
                    request.resolve(message.embedding);
                } else {
                    request.reject(new Error(message.error || "Transformers worker failed"));
                }
            });
            worker.addEventListener("error", function () {
                workerUnavailable = true;
                worker.terminate();
                worker = null;
                rejectWorkerRequests(new Error("Transformers worker failed"), true);
            });
        } catch (_error) {
            workerUnavailable = true;
            worker = null;
        }
        return worker;
    }

    function abortObsoleteWorkerRequests() {
        workerRequests.forEach(function (request) {
            clearTimeout(request.timer);
            var error = new Error("Obsolete semantic query");
            error.name = "AbortError";
            request.reject(error);
        });
        workerRequests.clear();
    }

    function embedWithWorker(query) {
        var activeWorker = createWorker();
        if (!activeWorker) {
            return embedInline(query);
        }
        abortObsoleteWorkerRequests();
        return new Promise(function (resolve, reject) {
            var id = nextWorkerRequestId++;
            var timeoutMs = Number.isInteger(config.timeoutMs) ? config.timeoutMs : 300000;
            var timer = setTimeout(function () {
                workerRequests.delete(id);
                reject(new Error("Transformers worker timed out"));
            }, timeoutMs);
            workerRequests.set(id, {
                query: query,
                resolve: resolve,
                reject: reject,
                timer: timer
            });
            activeWorker.postMessage({ id: id, query: query, config: config });
        });
    }

    window.ClientSearchQueryEmbedder = embedWithWorker;
}());
