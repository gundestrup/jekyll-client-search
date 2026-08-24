# Changelog

## 0.1.0 — Unreleased

- Add a pluggable search engine architecture with a base runtime and adapters.
- Support `minisearch`, `elasticlunr`, and `semantic` engines via `engine` config.
- Split the browser runtime into `client-search-base.js` (engine-agnostic shell
  that owns the two-stage search strategy) and per-engine adapters under
  `assets/adapters/` that act as pure translators.
- Add ElasticLunr adapter that translates the uniform query model into
  ElasticLunr's native API.
- Add semantic adapter that ranks documents by cosine similarity against
  pre-computed embeddings.
- Add embedding generation at build time via a local Ollama server using
  the `ollama-ruby` gem (optional dependency, lazy-loaded).
- Add incremental indexing via a content-hash cache
  (`.jekyll-client-search-cache.json`) — unchanged documents reuse cached
  embeddings and are not re-processed.
- Add uniform JS test suite parameterized over all adapters — the same
  assertions run against each engine.
- Add system tests that build a real Jekyll fixture site with 80 real-world
  articles (40 Wikipedia + 40 arXiv papers) per engine and verify search
  results (AND, OR fallback, cross-domain) in jsdom.
- Add Ollama integration tests that generate real embeddings via a local
  Ollama server with `embeddinggemma:300m` and verify cache reuse.
- Add RuboCop (Ruby linting) and ESLint (JavaScript linting) to CI.
- Document `jekyll-pagefind` as a recommended alternative for users who
  want Pagefind's HTML-crawling indexing approach.
- Add a safe Jekyll generator for MiniSearch JSON indexes.
- Support posts and configurable custom collections.
- Optionally include titled Jekyll pages.
- Include searchable title, excerpt, content, categories, and tags fields.
- Copy the browser runtime asset into the consuming site's assets directory.
- Add RSpec coverage for configuration and document normalization.
- Add Gundestrup.dk as the local integration test platform.
- Validate configuration and reject unsafe output paths.
- Deduplicate indexed documents and normalize searchable metadata.
- Harden browser result rendering with DOM APIs and same-origin URLs.
- Add runtime asset, generated page, page indexing, disabled mode, and edge-case tests.
- Add browser runtime behavior and URL-safety tests with Node.js and jsdom.
- Standardize development and CI on Ruby 3.4.10 with Bundler 4.0.9.
- License the gem under AGPL-3.0-or-later.
- Rename gem from `jekyll-elasticlunr-search` to `jekyll-client-search`.
- Replace Elasticlunr.js browser runtime with MiniSearch 7.2.0.
- Implement two-stage search: exact AND with prefix, then fuzzy OR fallback.
- Change configuration key from `elasticlunr_search` to `client_search`.
