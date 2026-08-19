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
npm test
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
- `assets/client-search.js` — optional browser runtime copied by the plugin
- `spec/` — unit tests

The generator creates `search-index.json` by default. It does not require a
Ruby search runtime; MiniSearch is a JavaScript browser library and is
loaded by the consuming Jekyll site.

## Configuration

```yaml
client_search:
  enabled: true
  output: search-index.json
  collections:
    - posts
  include_pages: false
```

Configured collections are indexed as documents with `id`, `title`, `url`,
`excerpt`, `content`, `categories`, and `tags` fields. The browser runtime
configures MiniSearch fields and query-time boosts.

## Search strategy

The packaged runtime (`assets/client-search.js`) uses a two-stage strategy:

1. **Exact AND search** with `combineWith: "AND"`, `prefix: true`, and field
   boosting — returns only documents matching all query terms.
2. **Fuzzy OR fallback** — if the AND search returns no results, retries with
   `combineWith: "OR"`, `fuzzy: 0.2`, and `prefix: true` for typo tolerance.

MiniSearch indexes `title`, `excerpt`, `content`, `categoriesText`, and
`tagsText` (categories and tags joined into strings). The `storeFields`
configuration keeps `title`, `url`, `excerpt`, `categories`, and `tags`
available in results without a separate lookup.

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

The gem does not pin or bundle MiniSearch. The consuming Jekyll site owns
that browser dependency. Keep its CDN version exact and add a Subresource
Integrity hash, or self-host the reviewed asset for offline builds and strict
Content Security Policy deployments. Upgrade MiniSearch separately from the
Ruby gem and verify the consuming site's search behavior afterward.

## Release checklist

Before publishing:

1. Run `bundle exec rspec`.
2. Build the gem and inspect its contents with `gem contents` or `tar`.
3. Verify the integration site using the local path dependency.
4. Update the README and changelog.
5. Review the gemspec metadata and version.
6. Build and publish only after the local integration build succeeds.
