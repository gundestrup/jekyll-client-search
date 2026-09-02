# AGENTS.md — jekyll-client-search

> **Architecture and conventions for coding agents.**
> For development setup, commands, testing, fixtures, and release process,
> see [README.developer.md](README.developer.md) — it is the single source
> of truth for all developer-facing information.
> For user-facing configuration and usage, see [README.md](README.md).

## Project overview

This repository contains the `jekyll-client-search` Ruby gem. It provides a
Jekyll generator that creates a JSON document index for client-side search
using [MiniSearch](https://lucaong.github.io/minisearch/),
[ElasticLunr](https://github.com/weixong/elasticlunr.js), or a semantic
cosine-similarity adapter over pre-computed embeddings.

The integration test platform is `/Users/svend/workspace/gundestrup.dk`,
which uses this gem through a local Bundler path dependency.

## Architecture

- `lib/jekyll/client_search/generator.rb` — Jekyll generator entry point
- `lib/jekyll/client_search/configuration.rb` — site configuration and defaults
- `lib/jekyll/client_search/configuration_accessors.rb` — exposes auxiliary
  runtime settings (related, query embedder, dropdown) through Configuration
- `lib/jekyll/client_search/document_builder.rb` — normalized search documents
- `lib/jekyll/client_search/search_index_page.rb` — generated JSON page
- `lib/jekyll/client_search/index_cache.rb` — content-hash cache for
  incremental indexing (avoids re-embedding unchanged documents)
- `lib/jekyll/client_search/ollama_embedding_adapter.rb` — generates
  embeddings via a local Ollama server (lazy-loads `ollama-ruby`)
- `lib/jekyll/client_search/related_analyzer.rb` — build-time metadata/vector
  relation analysis with a similarity cutoff
- `lib/jekyll/client_search/related_configuration.rb` — validates related
  analysis settings
- `lib/jekyll/client_search/related_tag.rb` — `{% related_articles %}` Liquid
  tag for one-line adoption in post layouts (supports `max:N`, `sort:date`,
  `no_scripts` params)
- `lib/jekyll/client_search/search_tag.rb` — `{% search_form %}` Liquid tag
  for config-driven search form + scripts (engine-agnostic)
- `lib/jekyll/client_search/dropdown_tag.rb` — `{% search_dropdown %}` Liquid
  tag for compact navbar live-search dropdown (supports `max:N`,
  `scripts_only`, `no_scripts` params)
- `lib/jekyll/client_search/dropdown_configuration.rb` — validates optional
  compact dropdown settings (max_items, min_chars, debounce_ms, redirect_url)
- `lib/jekyll/client_search/runtime_config_page.rb` — generates the
  `search-runtime-config.js` page with engine + live search + dropdown config
- `lib/jekyll/client_search/tasks.rb` — rake tasks for inspecting and
  installing reference files (`jekyll_client_search:reference_files`,
  `jekyll_client_search:install`)
- `assets/client-search-base.js` — engine-agnostic browser runtime shell
  (owns the two-stage search strategy)
- `assets/client-search-dropdown.js` — compact navbar live-search dropdown
  runtime (lazy-loads index on first keystroke, keyboard navigation,
  framework-agnostic semantic HTML with data attributes)
- `assets/client-search-related.js` — related-article renderer with
  relevance/newest sorting, `renderItem` callback, `filter` callback, and
  richer default rendering (date, shared tags, categories, excerpt)
- `assets/adapters/minisearch.js` — MiniSearch translator adapter
- `assets/adapters/elasticlunr.js` — ElasticLunr translator adapter
- `assets/adapters/semantic.js` — cosine similarity adapter for
  pre-computed embeddings
- `assets/query-embedders/transformers.js` — browser-side Transformers.js
  query embedder and Web Worker client
- `assets/query-embedders/transformers-worker.js` — off-main-thread
  tokenization and WebGPU/WASM inference
- `assets/query-embedders/ollama-api.js` — cancellable Ollama-compatible HTTP
  query embeddings
- `assets/includes/related-articles.html` — reference include file for
  copy-paste adoption
- `assets/layouts/post-with-related.html` — reference drop-in post layout

The generator creates `search-index.json` and copies the base runtime + the
selected engine adapter. When embeddings are enabled, it also generates
embedding vectors via Ollama and stores them in the JSON. The browser
runtime uses a base + adapter architecture: the base shell owns form
wiring, fetching, DOM rendering, URL safety, and the two-stage search
strategy (AND first, fuzzy OR fallback). Each adapter is a pure translator
that converts the uniform query `{ combineWith, fuzzy, prefix }` into the
engine's native API and returns `[{ ref, score }]`. The semantic adapter
is an exception — it uses cosine similarity instead of the AND/OR strategy.

For Pagefind, use the `jekyll-pagefind` gem directly — it is a different
approach (HTML crawling + own UI) that does not fit this plugin's
JSON-index + adapter model.

## Configuration reference

```yaml
client_search:
  enabled: true
  engine: minisearch
  engine_url: null              # null = per-engine CDN default; set to self-host
  engine_sri: null              # optional Subresource Integrity hash
  engine_crossorigin: null      # optional crossorigin attribute
  output: search-index.json
  collections:
    - posts
  include_pages: false
  copy_runtime: true
  passthrough_fields: []        # strings (same name) or {source: target} hashes
  icon_field: icon_url          # field name for <img> icon rendering
  live_search:
    enabled: true               # default: true for lexical, false for semantic
    min_chars: 2
    debounce_ms: 150
    semantic_debounce_ms: 500
  dropdown:
    enabled: true               # compact navbar live-search dropdown
    max_items: 5
    min_chars: 2
    debounce_ms: 150
    redirect_url: /search/
  related:
    enabled: false
    output: search-relations.json
    minimum_similarity: 0.55
    max_items: 5                # default: 5; null = no limit
  embedding:
    enabled: false
    model: embeddinggemma:300m
    base_url: http://localhost:11434
    query_embedder:
      type: transformers         # transformers | ollama_api | none
    connect_timeout: 5
    read_timeout: 120
    fail_on_error: true
```

The `engine` option selects `minisearch`, `elasticlunr`, or `semantic`.
Configured collections are indexed as documents with `id`, `title`, `url`,
`excerpt`, `content`, `categories`, `tags`, normalized publication date
fields, and `source` (the collection label, e.g. `"posts"`, `"pages"`).
The `passthrough_fields` config option lets external plugins (e.g.
jekyll-documents) declare which document `data` fields to forward into the
search index — entries can be strings (same name) or hashes (`{source =>
target}`) for field renaming. The `icon_field` config option (default:
`"icon_url"`) tells the browser runtime which field to render as an `<img>`
icon. When `embedding.enabled` is true, vectors are generated at build time;
they remain in the index for semantic search and can be omitted from lexical
indexes after related analysis. When `related.enabled` is true, the generator
writes a separate cutoff-based `search-relations.json` file.

The browser runtime renders each result as an `<article>` with `data-source`,
`data-categories`, `data-tags`, and `data-*` attributes for all passthrough
fields (converted from `snake_case` to `data-kebab-case`), enabling CSS-based
customization of search results (icons, badges, styling by source or file
type). When the configured `icon_field` is present in a result, an
`<img class="client-search-result-icon">` is rendered inside the heading,
before the title link, sized to `1em` (line-height) with inline styles so it
works with any CSS framework.

## Embeddings and incremental indexing

When `embedding.enabled: true`:
- The `OllamaEmbeddingAdapter` sends each prefixed document's text to a local
  Ollama server and receives a float vector.
- The default query embedder runs the compatible ONNX model in the browser
  through transformers.js. `ollama_api` calls a reachable `/api/embed`
  endpoint instead. Model-specific document/query prefixes must remain
  aligned.
- The `IndexCache` (`.jekyll-client-search-cache.json` in the site source)
  stores content hashes, embedding identity, and cached vectors per document ID.
- On rebuild, unchanged documents reuse cached embeddings only when the model,
  endpoint, provider, and cache schema also match.
- Cache writes are atomic; the cache is git-ignored and safe to delete.
- Embedding failures fail the build by default. Warning-only behavior requires
  the explicit `embedding.fail_on_error: false` setting.
- `ollama-ruby` is an optional dependency — lazy-loaded only when
  embeddings are enabled. Users who don't use embeddings never need it.

## Search strategy

The base runtime owns form submission and optional engine-aware live search.
Live search uses a 150 ms lexical debounce or 500 ms semantic debounce by
default, invalidates stale work immediately, and preserves explicit form
submission.

The base runtime owns the two-stage strategy, applied uniformly:

1. **Exact AND search** with prefix matching and field boosting — returns
   only documents matching all query terms.
2. **Fuzzy OR fallback** — if the AND search returns no results, retries
   with relaxed matching for typo tolerance.

The base runtime passes a uniform query `{ combineWith, fuzzy, prefix }`
to the adapter for each stage. The adapter translates this into the engine's
native options and returns `[{ ref, score }]` or a Promise of that array. The
semantic adapter requires `window.ClientSearchQueryEmbedder`, caches query
vectors, and accepts arrays or typed arrays. The packaged transformers.js and
Ollama API scripts provide that function; sites may still provide a custom one.
The base shell ignores stale async results and looks up documents by `ref` (id)
regardless of engine.

## Coding conventions

- All Ruby files use frozen string literals.
- Use double-quoted Ruby strings.
- Keep public APIs small and documented.
- Prefer explicit errors and safe defaults over silently inventing metadata.
- Do not include secrets or personal credentials in tests, fixtures, or docs.
- Keep browser output HTML-escaped before inserting it into the DOM.
- Never name local variables `document` in browser code — it shadows the
  global `document` object.

## JavaScript dependency policy

The gem does not pin or bundle the search engine library (MiniSearch or
ElasticLunr). The consuming Jekyll site owns that dependency.
Keep CDN versions exact and add Subresource Integrity hashes, or self-host
reviewed assets for offline builds and strict Content Security Policy
deployments. Upgrade the engine separately from the Ruby gem and verify
the consuming site's search behavior afterward.
