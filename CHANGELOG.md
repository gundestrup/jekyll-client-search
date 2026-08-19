# Changelog

## 0.1.0 — Unreleased

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
