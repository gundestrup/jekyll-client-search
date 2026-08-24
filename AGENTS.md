# AI Assistant Guide — jekyll-client-search

## Project overview

This repository contains the `jekyll-client-search` Ruby gem. It provides a
Jekyll generator that creates a JSON document index for client-side
[MiniSearch](https://lucaong.github.io/minisearch/) search.

The integration test platform is `/Users/svend/workspace/gundestrup.dk`, which
uses this gem through a local Bundler path dependency.

## Runtime and development environment

- Ruby: 3.4.10, managed with rbenv via `.ruby-version`
- Bundler: 4.0.9, pinned in `Gemfile.lock`
- License: AGPL-3.0-or-later
- Jekyll: 4.x
- Test framework: RSpec
- Browser search engine: MiniSearch 7.2.0, loaded by the consuming site

Set up the environment with:

```bash
rbenv install 3.4.10       # if it is not already installed
rbenv local 3.4.10
bundle install
npm ci
```

## Commands

```bash
bundle exec rspec
bundle exec rubocop
npm test
npm run lint
bundle exec ruby -c lib/jekyll/client_search/generator.rb
bundle exec rake ci
bundle exec rake version:show
bundle exec rake "version:bump[patch]"
gem build jekyll-client-search.gemspec
```

The integration site can be verified with:

```bash
cd ../gundestrup.dk
bundle install
bundle exec jekyll build --incremental
```

The integration build processes images through jekyll-imgflow and can take a
long time after the migration script recreates the source images. This is
expected and is separate from the search plugin.

## Architecture

- `lib/jekyll/client_search/generator.rb` — Jekyll generator entry point
- `lib/jekyll/client_search/configuration.rb` — site configuration and defaults
- `lib/jekyll/client_search/document_builder.rb` — normalized search documents
- `lib/jekyll/client_search/search_index_page.rb` — generated JSON page
- `lib/jekyll/client_search/index_cache.rb` — content-hash cache for
  incremental indexing (avoids re-embedding unchanged documents)
- `lib/jekyll/client_search/ollama_embedding_adapter.rb` — generates
  embeddings via a local Ollama server (lazy-loads `ollama-ruby`)
- `assets/client-search-base.js` — engine-agnostic browser runtime shell
  (owns the two-stage search strategy)
- `assets/adapters/minisearch.js` — MiniSearch translator adapter
- `assets/adapters/elasticlunr.js` — ElasticLunr translator adapter
- `assets/adapters/semantic.js` — cosine similarity adapter for
  pre-computed embeddings
- `spec/` — Ruby unit and system tests
- `spec/fixtures/site/` — Jekyll fixture site with 80 real-world posts
  (40 Wikipedia articles CC BY-SA 3.0 + 40 arXiv papers)
- `spec/fixtures/download_wikipedia.rb` — script to download Wikipedia articles
- `spec/fixtures/download_arxiv.rb` — script to download arXiv papers
- `test/runtime.test.js` — uniform JS unit tests parameterized over adapters
- `test/system.test.js` — JS system tests using the built 80-post fixture site

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

## Configuration

```yaml
client_search:
  enabled: true
  engine: minisearch
  output: search-index.json
  collections:
    - posts
  include_pages: false
  copy_runtime: true
  embedding:
    enabled: false
    model: embeddinggemma:300m
    base_url: http://localhost:11434
```

The `engine` option selects `minisearch`, `elasticlunr`, or `semantic`.
Configured collections are indexed as documents with `id`, `title`, `url`,
`excerpt`, `content`, `categories`, and `tags` fields. When
`embedding.enabled` is true, an `embedding` field (float vector) is added
to each document. The browser runtime configures engine fields and
query-time boosts via the selected adapter.

## Embeddings and incremental indexing

When `embedding.enabled: true`:
- The `OllamaEmbeddingAdapter` sends each document's text to a local
  Ollama server and receives a float vector.
- The `IndexCache` (`.jekyll-client-search-cache.json` in the site source)
  stores content hashes + cached embeddings per document ID.
- On rebuild, unchanged documents (matching content hash) reuse the cached
  embedding — only new or modified documents are sent to the model.
- The cache is git-ignored and safe to delete.
- `ollama-ruby` is an optional dependency — lazy-loaded only when
  embeddings are enabled. Users who don't use embeddings never need it.

## Search strategy

The base runtime owns the two-stage strategy, applied uniformly:

1. **Exact AND search** with prefix matching and field boosting — returns
   only documents matching all query terms.
2. **Fuzzy OR fallback** — if the AND search returns no results, retries
   with relaxed matching for typo tolerance.

The base runtime passes a uniform query `{ combineWith, fuzzy, prefix }`
to the adapter for each stage. The adapter translates this into the engine's
native options and returns `[{ ref, score }]`. The base shell looks up
documents by `ref` (id) regardless of engine.

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

## Release checklist

Before publishing:

1. Run `bundle exec rspec`.
2. Build the gem and inspect its contents with `gem contents` or `tar`.
3. Verify the integration site using the local path dependency.
4. Update the README and changelog.
5. Review the gemspec metadata and version.
6. Build and publish only after the local integration build succeeds.
