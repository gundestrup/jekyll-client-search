# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jekyll::ClientSearch::Configuration, :unit do
  def configuration(value = nil)
    site = instance_double(Jekyll::Site, config: value.nil? ? {} : { "client_search" => value })
    described_class.new(site)
  end

  it "uses safe defaults" do
    settings = configuration

    expect(settings).to be_enabled
    expect(settings.engine).to eq("minisearch")
    expect(settings.runtime_assets).to eq(["assets/client-search-base.js", "assets/adapters/minisearch.js"])
    expect(settings.output).to eq("search-index.json")
    expect(settings.collections).to eq(["posts"])
    expect(settings).not_to be_include_pages
    expect(settings).to be_copy_runtime
    expect(settings.passthrough_fields).to eq([])
    expect(settings.icon_field).to eq("icon_url")
  end

  it "accepts passthrough_fields and icon_field configuration" do
    settings = configuration(
      "passthrough_fields" => %w[file_type icon_url icon_set],
      "icon_field" => "icon_url"
    )
    expect(settings.passthrough_fields).to eq([%w[file_type file_type],
                                               %w[icon_url icon_url],
                                               %w[icon_set icon_set]])
    expect(settings.icon_field).to eq("icon_url")
    expect(settings.runtime_icon_field).to eq("icon_url")
  end

  it "supports field renaming via hash entries in passthrough_fields" do
    settings = configuration(
      "passthrough_fields" => [{ "file_type" => "doctype" }, { "icon_url" => "thumbnail" }, "icon_set"]
    )
    expect(settings.passthrough_fields).to eq([%w[file_type doctype],
                                               %w[icon_url thumbnail],
                                               %w[icon_set icon_set]])
  end

  it "resolves runtime_icon_field using target names" do
    settings = configuration(
      "passthrough_fields" => [{ "icon_url" => "thumbnail" }],
      "icon_field" => "thumbnail"
    )
    expect(settings.runtime_icon_field).to eq("thumbnail")
  end

  it "returns nil icon_field when disabled" do
    settings = configuration("icon_field" => nil)
    expect(settings.icon_field).to be_nil
    expect(settings.runtime_icon_field).to be_nil
  end

  it "returns nil runtime_icon_field when icon_field is not in passthrough_fields" do
    settings = configuration(
      "passthrough_fields" => %w[file_type],
      "icon_field" => "icon_url"
    )
    expect(settings.runtime_icon_field).to be_nil
  end

  it "accepts and normalizes site configuration overrides" do
    settings = configuration(
      "engine" => "elasticlunr",
      "output" => "/custom/../custom/index.json",
      "collections" => ["posts", "categories", "posts", nil],
      "include_pages" => true,
      "copy_runtime" => false
    )

    expect(settings.engine).to eq("elasticlunr")
    expect(settings.runtime_assets).to eq(["assets/client-search-base.js", "assets/adapters/elasticlunr.js"])
    expect(settings.output).to eq("custom/index.json")
    expect(settings.collections).to eq(%w[posts categories])
    expect(settings).to be_include_pages
    expect(settings).not_to be_copy_runtime
  end

  it "rejects an unknown engine" do
    expect { configuration("engine" => "pagefind") }
      .to raise_error(Jekyll::Errors::FatalException, /engine must be one of/)
    expect { configuration("engine" => "algolia") }
      .to raise_error(Jekyll::Errors::FatalException, /engine must be one of/)
  end

  it "accepts the semantic engine" do
    settings = configuration("engine" => "semantic")
    expect(settings.engine).to eq("semantic")
    expect(settings.runtime_assets).to eq(["assets/client-search-base.js", "assets/adapters/semantic.js"])
  end

  it "enables live search by default for lexical engines" do
    expect(configuration.live_search_config).to eq(
      "enabled" => true,
      "minChars" => 2,
      "debounceMs" => 150,
      "updateUrl" => true
    )
  end

  it "disables live search by default for semantic engine" do
    settings = configuration("engine" => "semantic")
    expect(settings.live_search_config).to eq(
      "enabled" => false,
      "minChars" => 2,
      "debounceMs" => 500,
      "updateUrl" => true
    )
  end

  it "uses a disabled cutoff-based related analysis by default" do
    expect(configuration.related_enabled?).to be(false)
    expect(configuration.related_output).to eq("search-relations.json")
    expect(configuration.related_configuration.minimum_similarity).to eq(0.55)
    expect(configuration.related_configuration.max_items).to be_nil
  end

  it "accepts related analysis configuration" do
    settings = configuration(
      "related" => {
        "enabled" => true,
        "output" => "data/relations.json",
        "minimum_similarity" => 0.7,
        "max_items" => 10,
        "same_category" => false
      }
    )
    expect(settings.related_enabled?).to be(true)
    expect(settings.related_output).to eq("data/relations.json")
    expect(settings.related_configuration.minimum_similarity).to eq(0.7)
    expect(settings.related_configuration.max_items).to eq(10)
    expect(settings.related_configuration.same_category?).to be(false)
  end

  it "rejects invalid related analysis configuration" do
    expect { configuration("related" => "invalid") }
      .to raise_error(Jekyll::Errors::FatalException, /related configuration must be a mapping/)
    expect { configuration("related" => { "minimum_similarity" => 2 }) }
      .to raise_error(Jekyll::Errors::FatalException, /between -1 and 1/)
    expect { configuration("related" => { "max_items" => 0 }) }
      .to raise_error(Jekyll::Errors::FatalException, /positive integer or null/)
    expect { configuration("related" => { "output" => "../relations.json" }).related_output }
      .to raise_error(Jekyll::Errors::FatalException, /related output must be a relative file path/)
    expect { configuration("related" => { "same_category" => "yes" }) }
      .to raise_error(Jekyll::Errors::FatalException, /same_category must be true or false/)
  end

  it "uses the semantic live-search debounce and accepts overrides" do
    settings = configuration(
      "engine" => "semantic",
      "live_search" => {
        "enabled" => true,
        "min_chars" => 3,
        "semantic_debounce_ms" => 600,
        "update_url" => false
      }
    )
    expect(settings.live_search_config).to eq(
      "enabled" => true,
      "minChars" => 3,
      "debounceMs" => 600,
      "updateUrl" => false
    )
  end

  it "rejects invalid live-search configuration" do
    expect { configuration("live_search" => "invalid") }
      .to raise_error(Jekyll::Errors::FatalException, /live_search configuration must be a mapping/)
    expect { configuration("live_search" => { "enabled" => "yes" }) }
      .to raise_error(Jekyll::Errors::FatalException, /enabled must be true or false/)
    expect { configuration("live_search" => { "debounce_ms" => -1 }) }
      .to raise_error(Jekyll::Errors::FatalException, /debounce_ms must be an integer/)
  end

  it "has embedding disabled by default" do
    settings = configuration
    expect(settings).not_to be_embedding_enabled
    expect(settings.embedding_model).to eq("embeddinggemma:300m")
    expect(settings.embedding_base_url).to eq("http://localhost:11434")
    expect(settings.embedding_connect_timeout).to eq(5.0)
    expect(settings.embedding_read_timeout).to eq(120.0)
    expect(settings).to be_embedding_fail_on_error
  end

  it "accepts embedding configuration overrides" do
    settings = configuration(
      "embedding" => {
        "enabled" => true,
        "model" => "bge-m3",
        "base_url" => "http://gpu-box:11434"
      }
    )
    expect(settings).to be_embedding_enabled
    expect(settings.embedding_model).to eq("bge-m3")
    expect(settings.embedding_base_url).to eq("http://gpu-box:11434")
  end

  it "accepts timeout and failure policy overrides" do
    settings = configuration(
      "embedding" => {
        "connect_timeout" => 2,
        "read_timeout" => 30,
        "fail_on_error" => false
      }
    )
    expect(settings.embedding_connect_timeout).to eq(2.0)
    expect(settings.embedding_read_timeout).to eq(30.0)
    expect(settings).not_to be_embedding_fail_on_error
  end

  it "rejects non-mapping embedding configuration" do
    expect { configuration("embedding" => "invalid") }
      .to raise_error(Jekyll::Errors::FatalException, /embedding configuration must be a mapping/)
  end

  it "rejects non-positive embedding timeouts" do
    expect { configuration("embedding" => { "enabled" => true, "read_timeout" => 0 }) }
      .to raise_error(Jekyll::Errors::FatalException, /greater than zero/)
  end

  it "exposes a stable embedding identity" do
    settings = configuration("embedding" => { "model" => "model-a", "base_url" => "http://ollama" })
    expect(settings.embedding_identity).to eq(
      "provider" => "ollama", "model" => "model-a", "base_url" => "http://ollama",
      "document_prefix" => "", "query_prefix" => "", "schema" => 2
    )
  end

  it "can be disabled with false" do
    expect(configuration(false)).not_to be_enabled
  end

  it "rejects non-mapping configuration" do
    expect { configuration("invalid") }
      .to raise_error(Jekyll::Errors::FatalException, /must be a mapping/)
  end

  it "rejects output paths outside the destination" do
    expect { configuration("output" => "../search.json").output }
      .to raise_error(Jekyll::Errors::FatalException, /relative file path/)
  end

  it "rejects an empty output path" do
    expect { configuration("output" => "").output }
      .to raise_error(Jekyll::Errors::FatalException, /relative file path/)
  end

  it "rejects an empty embedding model name when embeddings are enabled" do
    expect { configuration("embedding" => { "enabled" => true, "model" => "" }) }
      .to raise_error(Jekyll::Errors::FatalException, /embedding model must not be empty/)
  end

  it "rejects an empty embedding base_url when embeddings are enabled" do
    expect { configuration("embedding" => { "enabled" => true, "base_url" => "" }) }
      .to raise_error(Jekyll::Errors::FatalException, /embedding base_url must not be empty/)
  end

  it "defaults query_embedder to a pinned Transformers worker" do
    settings = configuration("embedding" => { "enabled" => true })
    config = JSON.parse(settings.query_embedder_config_json)
    expect(settings.query_embedder_type).to eq("transformers")
    expect(config["libraryUrl"]).to eq(
      "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1"
    )
    expect(config["worker"]).to be(true)
  end

  it "maps the Ollama model name to a transformers.js model by default" do
    settings = configuration("embedding" => { "enabled" => true, "model" => "embeddinggemma:300m" })
    expect(settings.query_embedder_model).to eq("onnx-community/embeddinggemma-300m-ONNX")
    expect(settings.embedding_document_prefix).to eq("title: none | text: ")
    expect(settings.embedding_query_prefix).to eq("task: search result | query: ")
  end

  it "allows overriding model-specific embedding prefixes" do
    settings = configuration(
      "embedding" => {
        "enabled" => true,
        "document_prefix" => "document: ",
        "query_prefix" => "query: "
      }
    )
    expect(settings.embedding_document_prefix).to eq("document: ")
    expect(settings.embedding_query_prefix).to eq("query: ")
  end

  it "allows overriding the transformers.js model name" do
    settings = configuration(
      "embedding" => { "enabled" => true, "query_embedder" => { "model" => "custom/model" } }
    )
    expect(settings.query_embedder_model).to eq("custom/model")
  end

  it "requires an explicit transformers.js model when no compatible mapping is known" do
    expect do
      configuration("engine" => "semantic", "embedding" => { "enabled" => true, "model" => "custom-model" })
    end
      .to raise_error(Jekyll::Errors::FatalException, /query_embedder.model is required/)
  end

  it "derives the Ollama API URL from base_url by default" do
    settings = configuration("embedding" => { "enabled" => true, "base_url" => "http://gpu-box:11434" })
    expect(settings.query_embedder_api_url).to eq("http://gpu-box:11434/api/embed")
  end

  it "allows overriding the query embedder API URL" do
    settings = configuration(
      "embedding" => { "enabled" => true, "query_embedder" => { "api_url" => "https://api.example.com/embed" } }
    )
    expect(settings.query_embedder_api_url).to eq("https://api.example.com/embed")
  end

  it "supports ollama_api query embedder type" do
    settings = configuration(
      "embedding" => { "enabled" => true, "query_embedder" => { "type" => "ollama_api" } }
    )
    expect(settings.query_embedder_type).to eq("ollama_api")
    expect(settings.query_embedder_model).to eq("embeddinggemma:300m")
    expect(settings.query_embedder_asset).to eq("assets/query-embedders/ollama-api.js")
  end

  it "rejects non-mapping query embedder configuration" do
    expect { configuration("embedding" => { "enabled" => true, "query_embedder" => "invalid" }) }
      .to raise_error(Jekyll::Errors::FatalException, /query_embedder configuration must be a mapping/)
  end

  it "supports none query embedder type for sites providing their own" do
    settings = configuration(
      "embedding" => { "enabled" => true, "query_embedder" => { "type" => "none" } }
    )
    expect(settings.query_embedder_type).to eq("none")
    expect(settings.query_embedder_asset).to be_nil
  end

  it "includes the query embedder assets in runtime_assets for semantic engine" do
    settings = configuration(
      "engine" => "semantic",
      "embedding" => { "enabled" => true }
    )
    expect(settings.runtime_assets).to include(
      "assets/query-embedders/transformers.js",
      "assets/query-embedders/transformers-worker.js"
    )
  end

  it "keeps embeddings in a lexical index when explicitly requested" do
    settings = configuration(
      "engine" => "minisearch",
      "embedding" => { "enabled" => true, "include_in_index" => true }
    )
    expect(settings.embedding_include_in_index?).to be(true)
  end

  it "omits the Transformers worker asset when worker mode is disabled" do
    settings = configuration(
      "engine" => "semantic",
      "embedding" => { "enabled" => true, "query_embedder" => { "worker" => false } }
    )
    expect(settings.runtime_assets).to include("assets/query-embedders/transformers.js")
    expect(settings.runtime_assets).not_to include("assets/query-embedders/transformers-worker.js")
  end

  it "rejects an unknown query embedder type" do
    expect { configuration("embedding" => { "enabled" => true, "query_embedder" => { "type" => "invalid" } }) }
      .to raise_error(Jekyll::Errors::FatalException, /query_embedder type must be one of/)
  end

  it "rejects invalid query embedder runtime controls" do
    expect do
      configuration("embedding" => { "enabled" => true, "query_embedder" => { "worker" => "yes" } })
    end.to raise_error(Jekyll::Errors::FatalException, /worker must be true or false/)
    expect do
      configuration("embedding" => { "enabled" => true, "query_embedder" => { "timeout_ms" => 0 } })
    end.to raise_error(Jekyll::Errors::FatalException, /timeout_ms must be an integer/)
    expect do
      configuration("embedding" => { "enabled" => true, "query_embedder" => { "max_tokens" => 0 } })
    end.to raise_error(Jekyll::Errors::FatalException, /max_tokens must be an integer/)
  end

  it "generates embedder config JSON with model and API info" do
    settings = configuration(
      "embedding" => {
        "enabled" => true,
        "model" => "embeddinggemma:300m",
        "query_embedder" => {
          "library_url" => "/assets/vendor/transformers.min.js",
          "model_base_url" => "/assets/models/",
          "dtype" => "q8"
        }
      }
    )
    config = JSON.parse(settings.query_embedder_config_json)
    expect(config["type"]).to eq("transformers")
    expect(config["model"]).to eq("onnx-community/embeddinggemma-300m-ONNX")
    expect(config["queryPrefix"]).to eq("task: search result | query: ")
    expect(config["buildModel"]).to eq("embeddinggemma:300m")
    expect(config["apiUrl"]).to eq("http://localhost:11434/api/embed")
    expect(config["libraryUrl"]).to eq("/assets/vendor/transformers.min.js")
    expect(config["modelBaseUrl"]).to eq("/assets/models/")
    expect(config["dtype"]).to eq("q8")
    expect(config["worker"]).to be(true)
    expect(config["timeoutMs"]).to eq(300_000)
    expect(config["retryAttempts"]).to eq(1)
    expect(config["maxTokens"]).to eq(512)
  end
end
