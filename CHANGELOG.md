# Changelog

## Unreleased

### Fixed
- Allow whitespace in script/style end tags in `DocumentBuilder#clean` (`</script\s*>` instead of `</script>`) — CodeQL: bad HTML filtering regexp
- Fix polynomial ReDoS in `SearchTag` and `RelatedTag` syntax regexes — strip markup before matching, remove leading/trailing `\s*` patterns that caused O(n²) backtracking (CodeQL: polynomial regex on uncontrolled data)

### Changed
- Simplified release workflow to tag-push trigger (`push: tags: v*`) — no manual `gh release create` needed
- Switched to RubyGems trusted publishing (`rubygems/release-gem@v1` with OIDC)
- Centralized version in `version.rb` as single source of truth — removed `version` field from `package.json`
- Added `rake version:bump` and `rake version:check_changelog` tasks
- Added CHANGELOG gate to release workflow (fails if entry missing for the version)
- Added `npm audit` and `npm outdated` (non-blocking) to CI
- Replaced pre-commit hook with rubocop-only (fast); added pre-push hook (rubocop + rspec)
- Dropped reek from quality stack (KISS — marginal value on a small gem)
- Aligned AGENTS.md to the open convention; added CLAUDE.md and .windsurfrules pointer files

## 0.1.0 — 2026-08-25

- Add a pluggable search engine architecture with a base runtime and adapters.
- Support `minisearch`, `elasticlunr`, and `semantic` engines via `engine` config.
- Split the browser runtime into `client-search-base.js` (engine-agnostic shell
  that owns the two-stage search strategy) and per-engine adapters under
  `assets/adapters/` that act as pure translators.
- Add ElasticLunr adapter that translates the uniform query model into
  ElasticLunr's native API.
- Add semantic adapter that ranks documents by cosine similarity against
  pre-computed embeddings, supports async/typed-array query vectors, caches
  query embeddings, and ignores stale asynchronous results.
- Add packaged query embedders for semantic search: transformers.js running
  entirely in the browser (default) and an Ollama-compatible remote HTTP API.
  Generate browser embedder configuration from `_config.yml`, support fully
  self-hosted library/model/WASM assets, and apply model-specific asymmetric
  document/query prefixes for EmbeddingGemma and Nomic.
- Pin transformers.js, run browser model inference in a Web Worker, add
  loading progress, retry/timeout controls, query truncation, strict finite
  vector/dimension validation, and main-thread fallback.
- Add optional engine-aware live search with configurable minimum length,
  lexical/semantic debounce, URL synchronization, stale-result protection,
  and cancellation of obsolete remote API requests.
- Add optional build-time related-article analysis combining shared tags,
  exact/parent categories, and vector similarity above a configurable cutoff.
  Write relations to a separate JSON artifact and provide a lightweight
  browser renderer with relevance/newest sorting; search results can also be
  sorted by relevance or publication date, and lexical indexes can omit
  temporary analysis embeddings.
- Add `{% related_articles %}` Liquid tag for one-line adoption in any post
  layout. Supports `sort:date` and `no_scripts` parameters; renders nothing
  when related is disabled.
- Add `{% search_form %}` Liquid tag for config-driven search form + scripts.
  Outputs the form HTML, status/results containers, and all runtime scripts
  (engine library, runtime config, embedder config, query embedder, base
  runtime, adapter) in the correct order based on `_config.yml`. Supports
  `scripts_only` and `no_scripts` modes. Changing engines requires zero
  template changes.
- Enable live search by default for lexical engines (MiniSearch, ElasticLunr)
  and disable by default for semantic (to avoid embedding every keystroke).
  Form submission always remains available. Set `live_search.enabled: false`
  to restore submit-only behavior.
- Add `engine_url`, `engine_sri`, and `engine_crossorigin` config options
  with per-engine CDN defaults (MiniSearch 7.2.0, ElasticLunr 0.9.5).
  Override to self-host or pin a version; set `engine_sri` for Subresource
  Integrity.
- Add rake tasks `jekyll_client_search:reference_files` (list, diff, and
  status of reference files) and `jekyll_client_search:install` (copy
  reference layouts/includes into the consuming site, with overwrite
  protection for modified copies).
- Ship reference `_includes/related-articles.html` and
  `_layouts/post-with-related.html` for copy-paste adoption.
- Extend `client-search-related.js` with `renderItem` callback for custom
  list item rendering, `filter` callback for narrowing visible relations,
  richer default rendering (date, shared tags, shared categories, excerpt),
  and `data-related-sort` attribute support for the Liquid tag.
- Add fixture site demo page (`spec/fixtures/site/related-test.html`) and
  post layout (`spec/fixtures/site/_layouts/post.html`) exercising all
  related-articles adoption paths. Add system tests verifying relations file
  structure, runtime asset copying, Liquid tag rendering, demo page content,
  self-exclusion, and score sorting.
- Add embedding generation at build time via a local Ollama server using
  the `ollama-ruby` gem (optional dependency, lazy-loaded).
- Add incremental indexing via an atomically written content-hash cache
  (`.jekyll-client-search-cache.json`) — unchanged documents reuse cached
  embeddings only when the provider, model, endpoint, and schema match.
- Add configurable Ollama connection/read timeouts and fail semantic builds by
  default when an embedding cannot be generated.
- Report browser query-embedding failures as unavailable instead of presenting
  them as valid zero-result searches.
- Load only `cgi/escape` for Ruby 3.5 compatibility.
- Add uniform JS test suite parameterized over all adapters — the same
  assertions run against each engine.
- Add Ruby system tests that build an 80-post fixture of 40 Wikipedia articles
  and 40 unique arXiv papers per engine, plus JS system tests for baseline
  results (AND, OR fallback, cross-domain) in jsdom.
- Add Ollama integration tests that generate real embeddings via a local
  Ollama server with `embeddinggemma:300m` and verify cache reuse.
- Add RuboCop, ESLint, SimpleCov thresholds, and Ruby/JavaScript dependency
  audits to CI.
- Add reproducible performance history for cold, warm, incremental, index-size,
  query-embedding, and engine-core search latency measurements.
- Correct fixture documentation and make the Wikipedia/arXiv regeneration
  scripts remove dated outputs correctly; arXiv regeneration now deduplicates
  paper IDs across category queries and records the actual per-paper license.
- Add `wikipedia_oldid` and permanent revision links to all Wikipedia fixture
  posts so the exact downloaded version can be referenced as articles change.
- Remove arXiv fixture posts from the repository due to mixed/restrictive
  licenses (some papers use CC BY-NC, CC BY-NC-ND, or arXiv non-exclusive
  licenses that do not clearly permit redistribution). Developers run
  `download_arxiv.rb` locally to fetch them. The committed baseline JSON
  and semantic embeddings remain as stable test artifacts. See
  README.developer.md and NOTICE for details.
- Add README.developer.md with fixture setup and LLM/vector testing
  instructions, and a NOTICE file with source attribution.
- Make JS system, gold, comparison, and meta tests consume required committed
  baseline fixtures directly, eliminating order-dependent test setup and skips.
- Preserve `#` as the safe link fallback for incomplete index records.
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
- Standardize development on Ruby 3.4.10 and test supported Ruby 3.2, 3.3,
  and 3.4 versions in CI with Bundler 4.0.9.
- License the gem under AGPL-3.0-or-later.
- Rename gem from `jekyll-elasticlunr-search` to `jekyll-client-search`.
- Replace Elasticlunr.js browser runtime with MiniSearch 7.2.0.
- Implement two-stage search: exact AND with prefix, then fuzzy OR fallback.
- Change configuration key from `elasticlunr_search` to `client_search`.
