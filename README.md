# jekyll-client-search

![jekyll-client-search logo](docs/assets/icon-256.png)

[![CI](https://github.com/gundestrup/jekyll-client-search/actions/workflows/ci.yml/badge.svg)](https://github.com/gundestrup/jekyll-client-search/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-%E2%89%A5%203.2-red.svg)](https://www.ruby-lang.org/)
[![Jekyll](https://img.shields.io/badge/jekyll-4.x-blue.svg)](https://jekyllrb.com/)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](LICENSE)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-docs-7B68EE.svg)](https://deepwiki.com/gundestrup/jekyll-client-search)
[![Coverage](https://img.shields.io/badge/coverage-100%25%20branches-brightgreen.svg)](#testing-strategy)

A Jekyll plugin that generates a JSON document index for client-side search.
Supports lexical search ([MiniSearch](https://lucaong.github.io/minisearch/),
[ElasticLunr](https://github.com/weixsong/elasticlunr.js)) and semantic search
via pre-computed embeddings from a local [Ollama](https://ollama.ai) server.
Related articles can be generated at build time from shared tags, categories,
and vector similarity.

## Table of contents

- [Lightning start](#lightning-start)
- [Quick start](#quick-start)
  - [Choose an engine](#choose-an-engine)
  - [Live search](#live-search)
  - [Related articles](#related-articles)
  - [Semantic search (embeddings)](#semantic-search-embeddings)
- [The search form](#the-search-form)
- [Rake tasks](#rake-tasks)
- [Configuration reference](#configuration-reference)
- [Architecture](#architecture)
- [Embeddings and incremental indexing](#embeddings-and-incremental-indexing)
- [Related articles reference](#related-articles-reference)
- [Browser usage reference](#browser-usage-reference)
- [Keeping the search engine current](#keeping-the-search-engine-current)
- [License](#license)
- [Development](#development)
- [Build and version tasks](#build-and-version-tasks)
- [CI and release process](#ci-and-release-process)
- [Documentation](#documentation)

## Lightning start

Three steps. No configuration needed — the defaults work out of the box.

**1. Add the gem:**

```ruby
# Gemfile
group :jekyll_plugins do
  gem "jekyll-client-search", "~> 0.1"
end
```

```yaml
# _config.yml
plugins:
  - jekyll-client-search
```

**2. Add the search form to any page or layout:**

```liquid
{% search_form %}
```

That's it. The tag outputs the form, results container, and all scripts —
config-driven, so you never need to touch template HTML when changing engines.

**3. (Optional) Add related articles to your post layout:**

```liquid
{% related_articles %}
```

Run `bundle install && bundle exec jekyll build` and search works at
`/search-index.json` with MiniSearch + live search enabled by default.

> **What you get by default:** MiniSearch engine, live search on (results
> update as you type), related articles off, embeddings off. No Ollama or
> external services required. See [Quick start](#quick-start) to customize.

## Quick start

The defaults are designed for zero-config lexical search. Customize by
adding a `client_search:` section to `_config.yml`.

### Choose an engine

| Engine | Type | Default? | Needs Ollama? | Good for |
| --- | --- | --- | --- | --- |
| `minisearch` | Lexical | Yes | No | Most sites — fast, prefix search, fuzzy fallback |
| `elasticlunr` | Lexical | No | No | Sites already using ElasticLunr |
| `semantic` | Vector | No | Yes (build time) | Concept search across dissimilar vocabulary |

```yaml
client_search:
  engine: minisearch    # default — change to elasticlunr or semantic
```

The `{% search_form %}` tag automatically loads the right CDN URL and
adapter for the selected engine. See [Configuration reference](#configuration-reference)
for `engine_url`, `engine_sri`, and self-hosting options.

### Live search

Live search (results update as the visitor types) is **on by default** for
lexical engines and **off by default** for semantic (to avoid embedding
every keystroke). Form submission always works regardless.

```yaml
client_search:
  live_search:
    enabled: true       # default: true for lexical, false for semantic
    min_chars: 2        # minimum query length before live search fires
    debounce_ms: 150    # lexical debounce
    semantic_debounce_ms: 500  # semantic debounce
    update_url: true    # sync ?q= in the URL
```

See [Configuration reference](#configuration-reference) for all options.

### Related articles

Related articles are **off by default** (they require a separate build-time
analysis pass). Enable them to generate a `search-relations.json` file and
use the `{% related_articles %}` tag:

```yaml
client_search:
  related:
    enabled: true
    minimum_similarity: 0.55  # cosine cutoff for semantic relations
```

Then add one line to any post layout:

```liquid
{% related_articles %}
```

Without embeddings, relations are based on shared tags, categories, and
hierarchical parent domains. With embeddings enabled, vector similarity
above the cutoff is also included. See
[Related articles reference](#related-articles-reference) for rendering
options, custom callbacks, and filtering.

### Semantic search (embeddings)

Semantic search requires a local [Ollama](https://ollama.ai/) server during
Jekyll build to generate document embeddings. The browser query model runs
via transformers.js (default) or an Ollama-compatible API endpoint.

```yaml
client_search:
  engine: semantic
  embedding:
    enabled: true
    model: embeddinggemma:300m
    base_url: http://localhost:11434
```

See [Embeddings and incremental indexing](#embeddings-and-incremental-indexing)
for setup, model choices, caching, and browser embedder configuration.

## The search form

The `{% search_form %}` Liquid tag is the simplest way to add search. It
outputs the form HTML, status/results containers, and all runtime scripts
in the correct order — config-driven, so changing engines in `_config.yml`
requires zero template changes.

```liquid
---
title: Search
permalink: /search/
---

{% search_form %}
```

Tag modes:

| Syntax | Effect |
| --- | --- |
| `{% search_form %}` | Form HTML + all scripts (default) |
| `{% search_form scripts_only %}` | Just the scripts — use with custom form HTML |
| `{% search_form no_scripts %}` | Just the form HTML — load scripts yourself |

When `client_search.enabled` is false the tag renders nothing, so it is safe
to leave in a layout even when the plugin is off.

**Custom form with config-driven scripts:**

```liquid
<form id="search-form" class="my-search" role="search">
  <input id="search-query" type="search" name="q" placeholder="Search articles">
  <button type="submit">Search</button>
</form>
<div id="search-status" aria-live="polite"></div>
<div id="search-results"></div>

{% search_form scripts_only %}
```

**Self-hosting the engine library:**

```yaml
client_search:
  engine: minisearch
  engine_url: /assets/vendor/minisearch.min.js
  engine_sri: sha384-...        # optional integrity hash
  engine_crossorigin: anonymous  # optional
```

For manual `<script>` setup (engine-specific HTML), see
[Browser usage reference](#browser-usage-reference).

## Rake tasks

The gem ships reference layouts and includes that you can copy into your
site as starting points. Two rake tasks make this easy:

```bash
# List reference files, show status, and diff against installed copies:
bundle exec rake jekyll_client_search:reference_files

# Install or update reference files (skips modified copies):
bundle exec rake jekyll_client_search:install

# Overwrite modified copies with the latest gem versions:
bundle exec rake 'jekyll_client_search:install[true]'
```

The `reference_files` task shows whether each file is `up to date`,
`modified or outdated`, or `not installed`, and prints a diff when copies
differ. The `install` task copies the latest versions from the gem, but
**skips files you have modified** unless you pass `overwrite=true`.

After `bundle update jekyll-client-search`, run `reference_files` to check
if your copies are outdated, then `install` to update unmodified copies.

> **Upgrade-safe alternative:** the `{% search_form %}` and
> `{% related_articles %}` Liquid tags live in the gem and auto-update with
> zero user action. The reference files are for users who want full control
> over the HTML.

## Configuration reference

```yaml
client_search:
  enabled: true
  engine: minisearch
  engine_url: null              # null = per-engine CDN default
  engine_sri: null              # optional Subresource Integrity hash
  engine_crossorigin: null      # optional crossorigin attribute
  output: search-index.json
  collections:
    - posts
  include_pages: false
  copy_runtime: true
  live_search:
    enabled: true               # default: true for lexical, false for semantic
    min_chars: 2
    debounce_ms: 150
    semantic_debounce_ms: 500
    update_url: true
  related:
    enabled: false
    output: search-relations.json
    minimum_similarity: 0.55
    max_items: null
  embedding:
    enabled: false
    model: embeddinggemma:300m
    base_url: http://localhost:11434
    connect_timeout: 5
    read_timeout: 120
    fail_on_error: true
    query_embedder:
      type: transformers
```

All options:

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `true` | Enable or disable index generation. |
| `engine` | `minisearch` | Search engine: `minisearch`, `elasticlunr`, or `semantic`. |
| `engine_url` | Per-engine CDN | Browser engine library URL. Override to self-host or pin a version. `null` for semantic. |
| `engine_sri` | `null` | Optional Subresource Integrity hash for the engine library. |
| `engine_crossorigin` | `null` | Optional `crossorigin` attribute for the engine library. |
| `output` | `search-index.json` | Output path for the generated JSON index. |
| `collections` | `[posts]` | Jekyll collections to index. |
| `include_pages` | `false` | Include titled Jekyll pages in the index. |
| `copy_runtime` | `true` | Copy the base runtime and engine adapter into the site. |
| `live_search.enabled` | `true` (lexical) / `false` (semantic) | Search while the user types. Form submission always remains available. |
| `live_search.min_chars` | `2` | Minimum trimmed query length before live search runs. |
| `live_search.debounce_ms` | `150` | MiniSearch/ElasticLunr input debounce. |
| `live_search.semantic_debounce_ms` | `500` | Semantic input debounce. |
| `live_search.update_url` | `true` | Keep the `q` URL parameter synchronized while typing. |
| `related.enabled` | `false` | Generate a separate related-article JSON file. |
| `related.output` | `search-relations.json` | Output path for related-article data. |
| `related.same_category` | `true` | Link articles sharing an exact category. |
| `related.shared_tags` | `true` | Link articles sharing one or more tags. |
| `related.include_parent_domains` | `true` | Link articles sharing parent paths in hierarchical categories. |
| `related.semantic` | `true` | Include vector relations when document embeddings are available. |
| `related.minimum_similarity` | `0.55` | Cosine cutoff for semantic relations; no fixed relation count. |
| `related.max_items` | `null` | Optional safety cap after cutoff; `null` keeps every matching relation. |
| `embedding.enabled` | `false` | Generate embedding vectors at build time via Ollama. |
| `embedding.model` | `embeddinggemma:300m` | Ollama model name for embedding generation. |
| `embedding.base_url` | `http://localhost:11434` | Ollama server URL. |
| `embedding.connect_timeout` | `5` | Ollama connection timeout in seconds. |
| `embedding.read_timeout` | `120` | Ollama response timeout in seconds. |
| `embedding.fail_on_error` | `true` | Fail the build when an embedding cannot be generated. |
| `embedding.include_in_index` | Semantic engine only | Keep document vectors in `search-index.json`; lexical related-analysis builds can omit them. |
| `embedding.document_prefix` | Model-specific | Prefix applied to document text before build-time embedding. |
| `embedding.query_prefix` | Model-specific | Prefix applied to browser queries before embedding. |
| `embedding.query_embedder.type` | `transformers` | Query embedder: `transformers`, `ollama_api`, or `none`. |
| `embedding.query_embedder.model` | Model-specific | Browser model ID or Ollama API model. Required when no safe mapping exists. |
| `embedding.query_embedder.api_url` | `<base_url>/api/embed` | Ollama-compatible query API endpoint. |
| `embedding.query_embedder.library_url` | jsDelivr `3.8.1` | Exact transformers.js ESM URL; set to self-host. |
| `embedding.query_embedder.model_base_url` | Hugging Face Hub | Self-hosted transformers.js model base URL. |
| `embedding.query_embedder.wasm_base_url` | ONNX default CDN | Self-hosted ONNX Runtime WASM directory. |
| `embedding.query_embedder.worker_url` | Packaged worker | Override the Transformers Web Worker URL. |
| `embedding.query_embedder.device` | WASM default | Optional device such as `webgpu` or `wasm`. |
| `embedding.query_embedder.dtype` | `q8` | Browser model data type. |
| `embedding.query_embedder.worker` | `true` | Run tokenization and model inference off the main UI thread. |
| `embedding.query_embedder.timeout_ms` | `300000` / `30000` | Transformers / Ollama API timeout. |
| `embedding.query_embedder.retry_attempts` | `1` | Model/runtime load retries after the initial attempt. |
| `embedding.query_embedder.max_tokens` | `512` | Maximum browser query token count. |

Each document in the index contains:

```json
{
  "id": "/article/",
  "title": "Article title",
  "url": "/article/",
  "excerpt": "Short excerpt",
  "content": "Searchable article content",
  "categories": ["family", "travel"],
  "tags": ["greenland"]
}
```

## Architecture

The plugin uses a base runtime + adapter architecture where the base owns
the search strategy and each adapter is a pure translator:

- **`assets/client-search-base.js`** — engine-agnostic shell that handles form
  wiring, index fetching, document normalization, DOM rendering, same-origin
  URL safety, optional debounced live search, status updates, and the two-stage
  search strategy (AND first, fuzzy OR fallback).
- **`assets/adapters/minisearch.js`** — translates the uniform query into
  MiniSearch's native API.
- **`assets/adapters/elasticlunr.js`** — translates the uniform query into
  ElasticLunr's native API.
- **`assets/adapters/semantic.js`** — validates vectors and ranks document
  embeddings by cosine similarity.
- **`assets/query-embedders/transformers.js`** and
  **`transformers-worker.js`** — load and run the browser query model outside
  the main UI thread.
- **`assets/query-embedders/ollama-api.js`** — calls a remote
  Ollama-compatible endpoint with timeout and stale-request cancellation.

Each adapter implements a small translator interface:

| Method | Description |
| --- | --- |
| `name` | Engine identifier string. |
| `available()` | Returns `true` when the engine library is loaded. |
| `buildIndex(documents)` | Builds and returns an engine-specific index. |
| `search(index, query, options)` | Translates the uniform query `{ combineWith, fuzzy, prefix }` into the engine's native call and returns `[{ ref, score }]`. |

The base runtime owns the strategy. The adapter only translates. The
`semantic` adapter is a working example — it uses cosine similarity against
pre-computed embeddings rather than the AND/OR text strategy.

## Embeddings and incremental indexing

When `embedding.enabled: true`, the plugin generates embedding vectors at
Jekyll build time using a local [Ollama](https://ollama.ai/) server and the
[`ollama-ruby`](https://github.com/flori/ollama-ruby) gem.

### Setup

1. Install [Ollama](https://ollama.ai/) and pull an embedding model:
   ```bash
   ollama pull embeddinggemma:300m
   ```
2. Add `ollama-ruby` to your site's Gemfile (optional dependency):
   ```ruby
   gem "ollama-ruby", "~> 1.23"
   ```
3. Enable embeddings in `_config.yml`:
   ```yaml
   client_search:
     engine: semantic
     embedding:
       enabled: true
       model: embeddinggemma:300m
       base_url: http://localhost:11434
   ```

### How it works

- At build time, the `OllamaEmbeddingAdapter` sends each document's text
  (title + excerpt + content) to the Ollama server and receives a float
  vector. Model-specific document prefixes are applied automatically.
- The vector is stored in the `embedding` field of the JSON document.
- At search time, either transformers.js runs the compatible model in the
  browser or the browser calls an Ollama-compatible `/api/embed` endpoint.
  The matching model-specific query prefix is applied automatically.
- A content-hash cache (`.jekyll-client-search-cache.json` in the site
  source) tracks which documents have already been embedded. Unchanged
  documents reuse the cached embedding — only new or modified documents
  are sent to the model.
- Cache entries include the provider, model, endpoint, and cache schema. A
  model or embedding configuration change automatically invalidates old
  vectors and re-embeds the documents.
- Cache writes are atomic. The cache file is git-ignored and safe to delete
  (it will be rebuilt on the next `jekyll build`).
- By default, an embedding failure fails the build rather than silently
  producing an unusable semantic index. Set `embedding.fail_on_error: false`
  only when warning-only behavior is intentional.

### Choosing a model

Any Ollama-compatible embedding model works. Common choices:

| Model | Dimensions | Good for |
| --- | --- | --- |
| `embeddinggemma:300m` | 768 | Default, multilingual, good quality |
| `nomic-embed-text` | 768 | Multilingual, good quality |
| `bge-m3` | 1024 | Multilingual, high quality |
| `all-minilm` | 384 | English, fast, lightweight |

The model used at build time must match the query model's weights, vector
space, dimensions, and preprocessing. Cross-runtime compatibility is verified
for the default `embeddinggemma:300m` mapping. An `all-minilm` mapping is also
provided, but sites should independently verify ranking when changing models.
For any other Ollama model, set `embedding.query_embedder.model` to a
compatible Transformers.js model explicitly or use `ollama_api` so both paths
call the same Ollama model.

## Related articles reference

Set `related.enabled: true` to generate a separate `search-relations.json`
file. The file contains all matching relations for each article, excluding
the article itself. Exact shared tags, categories, and hierarchical parent
domains are included without an arbitrary count limit. When document
embeddings are available, vector relations are added when their cosine score
meets `related.minimum_similarity`. If `embedding.enabled` is also true
for a MiniSearch build, embeddings are used during analysis and omitted from
the public search index by default. Set `embedding.include_in_index: true` if
the vectors are needed by another consumer.

Relations include their score, shared tags, shared categories, shared parent
domains, reasons, title, URL, and publication timestamp. The relation score
indicates relatedness; it does not assert a causal or factual relationship.

A working demo page exercising every adoption path lives in the fixture site
at `spec/fixtures/site/related-test.html` (built at `/related-test/`). The
fixture site also has `_layouts/post.html` showing the `{% related_articles %}`
tag in a real post layout. See [README.developer.md](README.developer.md) for
fixture site setup instructions.

### Liquid tag

The `{% related_articles %}` tag renders the container, sort control, and
runtime scripts in one line:

```liquid
{{ content }}

{% related_articles %}
```

When `related.enabled` is false the tag renders nothing, so it is safe to
leave in a layout even when the feature is off.

| Syntax | Effect |
| --- | --- |
| `{% related_articles %}` | Default sort (relevance), includes scripts |
| `{% related_articles sort:date %}` | Default sort is newest-first |
| `{% related_articles no_scripts %}` | Render only the container; load scripts yourself |

### Include file and drop-in layout

The gem ships reference files you can copy via
[rake tasks](#rake-tasks):

```bash
bundle exec rake jekyll_client_search:install
```

This copies `_includes/related-articles.html` and
`_layouts/post-with-related.html` into your site. Then use either:

```liquid
{% include related-articles.html %}
```

or set `layout: post-with-related` in a post's front matter. Most sites
already have a post layout they like — in that case, just add the
`{% related_articles %}` tag to your existing layout instead.

### Default rendering

The packaged `client-search-related.js` helper renders each relation as a
list item with a link, publication date, shared tags, shared categories, and
excerpt (when those fields are present in the JSON):

```html
<h2>Related articles</h2>
<ul class="related-articles-list">
  <li class="related-article-item">
    <a class="related-article-link" href="/article/">Article title</a>
    <div class="related-article-meta">
      <span class="related-article-date">Jan 1, 2026</span>
      <span class="related-article-tags">greenland, travel</span>
    </div>
    <p class="related-article-excerpt">Short excerpt...</p>
  </li>
</ul>
```

### Custom render callback

Pass a `renderItem` function to override the default list item rendering.
The callback receives the relation object and the global `document`, and
must return a DOM node (or `null` to skip the item):

```html
<div id="related-articles"></div>
<script src="/assets/search-runtime-config.js"></script>
<script src="/assets/client-search-related.js"></script>
<script>
  ClientSearchRelated.run({
    renderItem: function (item, document) {
      var li = document.createElement("li");
      li.innerHTML = '<a href="' + item.url + '">' + item.title + "</a>" +
        '<span class="score">' + (item.score * 100).toFixed(0) + "%</span>";
      return li;
    }
  });
</script>
```

### Filtering relations

Pass a `filter` function to narrow which relations appear. The callback
follows `Array.prototype.filter` semantics — return truthy to keep, falsy
to drop:

```html
<script>
  // Only show relations with a semantic similarity above 0.7
  ClientSearchRelated.run({
    filter: function (item) {
      return item.semantic_similarity && item.semantic_similarity > 0.7;
    }
  });
</script>
```

### Reading the raw JSON from Liquid

The `search-relations.json` file is a static Jekyll page. You can read it
at build time with a small generator if you need server-side rendering. The
file is written to the site destination, so it is available as a static file
after the build:

```ruby
# _plugins/related_renderer.rb
module RelatedRenderer
  class Generator < Jekyll::Generator
    priority :low
    def generate(site)
      related_page = site.pages.find { |p| p.url == "/search-relations.json" }
      return unless related_page

      data = JSON.parse(related_page.content)
      site.posts.docs.each do |doc|
        relations = data["relations"] && data["relations"][doc.url]
        next unless relations

        doc.data["related_articles"] = relations.first(5)
      end
    end
  end
end
```

Then in a layout:

```liquid
{% if page.related_articles and page.related_articles.size > 0 %}
<aside class="related">
  <h2>Related articles</h2>
  <ul>
    {% for item in page.related_articles %}
    <li>
      <a href="{{ item.url }}">{{ item.title }}</a>
      {% if item.shared_tags %}<span>{{ item.shared_tags | join: ", " }}</span>{% endif %}
    </li>
    {% endfor %}
  </ul>
</aside>
{% endif %}
```

Note: this approach requires a custom generator plugin in the consuming
site, and the related data is baked into the HTML at build time (no
client-side sort switching). For client-side sorting, use the JS helper
instead.

### Manual HTML setup

If you prefer not to use the Liquid tag or include file, add the container
and scripts directly:

```html
<label for="related-sort">Sort related articles</label>
<select id="related-sort">
  <option value="relevance">Most related</option>
  <option value="date">Newest</option>
</select>
<div id="related-articles"></div>
<script src="/assets/search-runtime-config.js"></script>
<script src="/assets/client-search-related.js"></script>
```

The helper sorts by relevance by default. A site can request newest-first
before loading the helper:

```html
<script>
  window.clientSearchConfig = Object.assign(window.clientSearchConfig || {}, {
    relatedSort: "date"
  });
</script>
<script src="/assets/client-search-related.js"></script>
```

## Browser usage reference

The generated JSON is engine-neutral. A consuming site can either use the
packaged runtime or build its own index directly from the JSON. Add a
`#search-sort` select with `relevance` and `date` values if visitors should
choose between highest search relation and newest publication date; the base
runtime sorts either lexical or semantic results consistently.

For the simplest setup, use the [`{% search_form %}` tag](#the-search-form).
The sections below show the manual `<script>` setup for each engine.

### MiniSearch

```html
<form id="search-form">
  <input id="search-query" type="search" name="q">
  <button type="submit">Search</button>
</form>
<div id="search-status" aria-live="polite"></div>
<div id="search-results"></div>
<script src="https://cdn.jsdelivr.net/npm/minisearch@7.2.0/dist/umd/index.min.js"
        crossorigin="anonymous"></script>
<script src="/assets/search-runtime-config.js"></script>
<script src="/assets/client-search-base.js"></script>
<script src="/assets/adapters/minisearch.js"></script>
```

### ElasticLunr

```html
<form id="search-form">
  <input id="search-query" type="search" name="q">
  <button type="submit">Search</button>
</form>
<div id="search-status" aria-live="polite"></div>
<div id="search-results"></div>
<script src="https://cdn.jsdelivr.net/npm/elasticlunr@0.9.5/elasticlunr.min.js"
        crossorigin="anonymous"></script>
<script src="/assets/search-runtime-config.js"></script>
<script src="/assets/client-search-base.js"></script>
<script src="/assets/adapters/elasticlunr.js"></script>
```

### Semantic

With the default `query_embedder.type: transformers`, the query model runs
entirely in the visitor's browser through transformers.js. Ollama is needed
only while Jekyll builds the document vectors. The first query downloads the
q8 browser model (about 325 MB for EmbeddingGemma); the browser caches it.

```html
<script src="/assets/search-runtime-config.js"></script>
<script src="/assets/search-embedder-config.js"></script>
<script src="/assets/query-embedders/transformers.js"></script>
<script src="/assets/client-search-base.js"></script>
<script src="/assets/adapters/semantic.js"></script>
```

The default library is loaded from jsDelivr and the model from Hugging Face.
To keep all runtime files on the static site, self-host both:

```yaml
client_search:
  engine: semantic
  embedding:
    enabled: true
    model: embeddinggemma:300m
    query_embedder:
      type: transformers
      library_url: /assets/vendor/transformers.min.js
      model_base_url: /assets/models/
      wasm_base_url: /assets/vendor/onnx-wasm/
      model: onnx-community/embeddinggemma-300m-ONNX
      dtype: q8
      worker: true
```

Self-hosting still requires no application server or background LLM. The
static web server delivers JavaScript, WASM, and ONNX files; inference runs
inside the packaged Web Worker. WASM is the compatibility-first default; set
`device: webgpu` explicitly to request WebGPU. Preserve the Hugging Face model
directory layout below `model_base_url`. Model weights retain their own
license. The default EmbeddingGemma model is subject to the Gemma Terms of
Use.

The CDN default is pinned to transformers.js `3.8.1`. Strict production CSP
or offline deployments should self-host all three dependencies: the ESM
library, ONNX model, and ONNX Runtime WASM files. Configure `script-src`,
`worker-src`, and `connect-src` for their actual origins; WASM execution may
also require `'wasm-unsafe-eval'`. Multi-threaded WASM requires compatible
COOP/COEP and CORP headers. Without cross-origin isolation, ONNX Runtime uses
a compatible single-threaded path.

To call a running Ollama-compatible API instead:

```yaml
client_search:
  engine: semantic
  embedding:
    enabled: true
    model: embeddinggemma:300m
    query_embedder:
      type: ollama_api
      api_url: https://embeddings.example.com/api/embed
```

Then load `/assets/query-embedders/ollama-api.js` in place of the
transformers script. The endpoint must support CORS. Obsolete live-search
requests are aborted, and requests time out after 30 seconds by default. Do
not expose an unauthenticated Ollama server directly to the public internet.
A localhost URL refers to each visitor's computer, so it only works when that
visitor is running Ollama locally.

Set `query_embedder.type: none` to continue providing a custom
`window.ClientSearchQueryEmbedder`. The function may be synchronous or
asynchronous. Up to 100 recent query embeddings are cached for the lifetime
of the page. Rejected or invalid vectors make search unavailable rather than
presenting a false zero-result response.

### Two-stage search strategy

The base runtime owns the two-stage strategy, applied uniformly across all
text adapters:

1. **Exact AND search** with prefix matching and field boosting — returns only
   documents matching all query terms.
2. **Fuzzy OR fallback** — if the AND search returns no results, retries with
   relaxed matching for typo tolerance.

## Keeping the search engine current

The gem deliberately does not bundle or build the search engine library. The
consuming site owns the browser dependency and loads a pinned version. This
keeps the Ruby gem independent from the JavaScript release cycle.

Recommended policy:

1. Pin an exact engine version in the consuming site.
2. Add a Subresource Integrity hash when loading from a CDN.
3. Review the engine's release notes and documentation before upgrading.
4. Run the consuming site's search and integration checks after an upgrade.
5. Prefer a local copy when a site needs offline builds or a strict CSP.

## License

This project is licensed under the GNU Affero General Public License v3.0 or
later (`AGPL-3.0-or-later`). See [LICENSE](LICENSE).

## Development

Development uses Ruby 3.4.10 through rbenv, while the gem supports Ruby 3.2
and newer. The development version is stored in `.ruby-version`, and CI tests
Ruby 3.2, 3.3, and 3.4.

```bash
rbenv install 3.4.10       # if not already installed
rbenv local 3.4.10
bundle install
npm ci
bundle exec rake ci
```

### Testing strategy

The test suite uses **80 real-world source posts** as fixture content to ensure
realistic search behavior testing:

- **40 Wikipedia articles** (CC BY-SA 3.0) covering arctic/geography,
  climbing/sports, photography/optics, food/cooking, and technology topics.
  Downloaded via the Wikipedia API with source attribution, download date,
  and license recorded in each post's frontmatter.
- **40 unique arXiv papers** (arXiv non-exclusive license) covering information
  retrieval, NLP, computer vision, recommendation systems, and knowledge
  graphs. The regeneration script deduplicates paper IDs across category
  queries.

The articles have deliberate cross-topic vocabulary overlap (e.g., "ice"
appears in both glacier articles and climbing articles; "embeddings" appears
in both IR and NLP papers) to test search discrimination between related but
distinct topics.

**Test layers:**

| Layer | What it tests | Command |
| --- | --- | --- |
| Ruby unit specs | Configuration, cache, adapter, document builder | `bundle exec rspec --tag unit` |
| Ruby system specs | Jekyll build generates correct JSON from 80 posts | `bundle exec rspec --tag system` |
| JS unit tests | Adapter, query-embedder, and related-renderer behavior in jsdom | `node --test test/runtime.test.js test/query-embedders.test.js test/related.test.js` |
| JS system tests | Search results against the committed 80-post baseline in jsdom | `node --test test/system.test.js` |
| Ollama integration | Real embedding generation + cache reuse against local Ollama | `OLLAMA_INTEGRATION=1 bundle exec rspec --tag ollama_integration` |

**Test boundaries:**

- Normal CI executes Ruby unit/system tests and all lexical/semantic browser
  tests using committed baselines.
- Real Ollama generation remains opt-in because it requires a local service and
  model; committed vectors keep semantic ranking deterministic in normal CI.
- The packaged transformers.js and Ollama API query embedders are tested with
  controlled runtimes. The default q8 Transformers.js EmbeddingGemma vectors
  were also compared with Ollama vectors for the same prefixed inputs; both
  query and document vectors had cross-runtime cosine similarity above 0.995.
- Custom `ClientSearchQueryEmbedder` implementations remain the consuming
  site's integration responsibility.
- Fixture downloader scripts are syntax-checked but are not run in CI because
  they perform network requests and replace local fixture posts.

**Regenerating fixture posts:**

```bash
ruby spec/fixtures/download_wikipedia.rb   # 40 Wikipedia articles
ruby spec/fixtures/download_arxiv.rb        # 40 unique arXiv papers
bundle exec ruby spec/fixtures/generate_baseline.rb
OLLAMA_INTEGRATION=1 bundle exec rspec spec/ollama_integration_spec.rb
bundle exec ruby spec/fixtures/generate_semantic_gold.rb
```

Each post includes `source`, `source_url`, `download_date`, and `license`
fields in its frontmatter for attribution. The committed semantic fixture stores
only document/query vectors and model metadata; tests inject those vectors into
the committed non-LLM baseline JSON so semantic quality runs on every CI job.

The Gundestrup.dk repository is the integration test platform. Its `Gemfile`
uses this gem through a local path dependency:

```ruby
gem "jekyll-client-search", path: "../jekyll-client-search"
```

Run the integration build with:

```bash
cd ../gundestrup.dk
bundle install
bundle exec jekyll build --incremental
```

The integration build may take a long time when jekyll-imgflow regenerates
image versions. That processing is independent of this plugin.

## Build and version tasks

Show the current version:

```bash
bundle exec rake version:show
```

Bump a release component:

```bash
bundle exec rake "version:bump[patch]"
bundle exec rake "version:bump[minor]"
bundle exec rake "version:bump[major]"
```

The bump task changes only the version constant. Update `CHANGELOG.md`, run
the checks, and review the diff before committing.

Install or update reference files in a consuming site:

```bash
bundle exec rake jekyll_client_search:reference_files
bundle exec rake jekyll_client_search:install
bundle exec rake 'jekyll_client_search:install[true]'  # overwrite modified copies
```

Run the complete local validation and build the gem:

```bash
bundle exec rake ci
```

## CI and release process

GitHub Actions are configured in `.github/workflows/`:

- `ci.yml` runs the test and gem build checks on pushes and pull requests.
- `release.yml` runs on `v*` tags or manual dispatch, verifies the gem, and
  publishes it using RubyGems trusted publishing.

Before enabling releases:

1. Configure the GitHub repository as a RubyGems trusted publisher.
2. Create the `rubygems` GitHub environment and protect it as appropriate.
3. Confirm the gem name and repository metadata in the gemspec.
4. Run `bundle exec rake ci` locally.
5. Bump the version and update `CHANGELOG.md`.
6. Create a matching tag such as `v0.1.0`.
7. Review the GitHub Actions release run before announcing the release.

## Documentation

- [DeepWiki](https://deepwiki.com/gundestrup/jekyll-client-search) —
  auto-generated architecture documentation and code walkthroughs.
- [CHANGELOG.md](CHANGELOG.md) — release history and changes.
- [README.developer.md](README.developer.md) — fixture setup and LLM/vector
  testing instructions for contributors.
- [README.performance.md](README.performance.md) — benchmark methodology
  and results.
- [AGENTS.md](AGENTS.md) — AI assistant guide with architecture, commands,
  and coding conventions.
- [NOTICE](NOTICE) — source attribution and licensing for test fixtures.
