(function () {
    "use strict";

    var config = window.ClientSearchEmbedderConfig || {};
    var model = config.model || config.buildModel || "embeddinggemma:300m";
    var apiUrl = config.apiUrl || "http://localhost:11434/api/embed";
    var activeController = null;

    function reportStatus(message) {
        window.dispatchEvent(new CustomEvent("client-search:status", {
            detail: { message: message }
        }));
    }

    window.ClientSearchQueryEmbedder = async function (query) {
        if (activeController) {
            activeController.abort();
        }
        var controller = new AbortController();
        var timeoutMs = Number.isInteger(config.timeoutMs) ? config.timeoutMs : 30000;
        var timedOut = false;
        var timer = setTimeout(function () {
            timedOut = true;
            controller.abort();
        }, timeoutMs);
        activeController = controller;
        reportStatus("Contacting semantic search…");

        try {
            var response = await fetch(apiUrl, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    model: model,
                    input: (config.queryPrefix || "") + query
                }),
                signal: controller.signal
            });

            if (!response.ok) {
                throw new Error("Ollama API returned " + response.status);
            }

            var data = await response.json();
            var embedding = data.embeddings && data.embeddings[0];
            if (!embedding || embedding.length === 0) {
                throw new Error("Ollama API returned empty embedding");
            }

            return embedding;
        } catch (error) {
            if (timedOut) {
                throw new Error("Ollama API request timed out");
            }
            throw error;
        } finally {
            clearTimeout(timer);
            if (activeController === controller) {
                activeController = null;
            }
        }
    };
}());
