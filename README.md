# jekyll-client-search

[![Ruby](https://img.shields.io/badge/ruby-3.4.10-red.svg)](https://www.ruby-lang.org/)
[![Jekyll](https://img.shields.io/badge/jekyll-4.x-blue.svg)](https://jekyllrb.com/)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](LICENSE)

A Jekyll plugin that generates a configurable JSON document index for
client-side search. It uses a base runtime + adapter architecture so the
same Jekyll-generated index works with any supported JavaScript search
engine. Supports lexical search ([MiniSearch](https://lucaong.github.io/minisearch/),
[ElasticLunr](https://github.com/weixsong/elasticlunr.js)) and semantic
search via pre-computed embeddings from a local [Ollama](https://ollama.ai)
server.

- [MiniSearch homepage](https://lucaong.github.io/minisearch/)
- [ElasticLunr source](https://github.com/weixsong/elasticlunr.js)
- [Ollama homepage](https://ollama.ai/)

The plugin handles the Jekyll build-time part of search: it generates a JSON
document index and copies a base runtime plus the selected engine adapter
into the site. The search engine library itself remains a dependency of the
consuming site. When embeddings are enabled, the plugin also generates
embedding vectors at build time and caches them to avoid re-embedding
unchanged documents.

> **Looking for Pagefind?** Pagefind is a different approach — it crawls
> rendered HTML at build time and ships its own UI bundle, so it doesn't
> fit this plugin's JSON-index + browser-adapter model. For Pagefind with
> Jekyll, use the [`jekyll-pagefind`](https://github.com/phothinmg/jekykll-pagefind)
> gem directly.

## Installation

Add the gem to the consuming Jekyll site's `Gemfile`:

```ruby
group :jekyll_plugins do
  gem "jekyll-client-search", "~> 0.1"
end
```

During local development of this gem, use a path dependency:

```ruby
gem "jekyll-client-search", path: "../jekyll-client-search"
```

Enable the plugin in `_config.yml`:

```yaml
plugins:
  - jekyll-client-search
```

Then run:

```bash
bundle install
bundle exec jekyll build
```

The default build output is `/search-index.json`. For JavaScript engines the
plugin also copies a base runtime (`/assets/client-search-base.js`) and the
selected engine adapter (e.g. `/assets/adapters/minisearch.js`) into the site.

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

Options:

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `true` | Enable or disable index generation. |
| `engine` | `minisearch` | Search engine: `minisearch`, `elasticlunr`, or `semantic`. |
| `output` | `search-index.json` | Output path for the generated JSON index. |
| `collections` | `[posts]` | Jekyll collections to index. |
| `include_pages` | `false` | Include titled Jekyll pages in the index. |
| `copy_runtime` | `true` | Copy the base runtime and engine adapter into the site. |
| `embedding.enabled` | `false` | Generate embedding vectors at build time via Ollama. |
| `embedding.model` | `embeddinggemma:300m` | Ollama model name for embedding generation. |
| `embedding.base_url` | `http://localhost:11434` | Ollama server URL. |

Each document contains:

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

The plugin uses the Jekyll collection API, so custom collections can be
included by adding their labels to `collections`.

## Architecture

The plugin uses a base runtime + adapter architecture where the base owns
the search strategy and each adapter is a pure translator:

- **`assets/client-search-base.js`** — engine-agnostic shell that handles form
  wiring, index fetching, document normalization, DOM rendering, same-origin
  URL safety, and the two-stage search strategy (AND first, fuzzy OR fallback).
  It calls into the adapter with a uniform query model for each stage.
- **`assets/adapters/minisearch.js`** — translates the uniform query into
  MiniSearch's native API.
- **`assets/adapters/elasticlunr.js`** — translates the uniform query into
  ElasticLunr's native API.

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
   gem "ollama-ruby"
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
  vector.
- The vector is stored in the `embedding` field of the JSON document.
- A content-hash cache (`.jekyll-client-search-cache.json` in the site
  source) tracks which documents have already been embedded. Unchanged
  documents reuse the cached embedding — only new or modified documents
  are sent to the model.
- The cache file is git-ignored and safe to delete (it will be rebuilt on
  the next `jekyll build`).

### Choosing a model

Any Ollama-compatible embedding model works. Common choices:

| Model | Dimensions | Good for |
| --- | --- | --- |
| `embeddinggemma:300m` | 768 | Default, multilingual, good quality |
| `nomic-embed-text` | 768 | Multilingual, good quality |
| `bge-m3` | 1024 | Multilingual, high quality |
| `all-minilm` | 384 | English, fast, lightweight |

The model used at build time must match the model used to embed queries in
the browser. For the `semantic` adapter, set
`window.clientSearchEmbeddingModel` to the same model name.

## Browser usage

The generated JSON is engine-neutral. A consuming site can either use the
packaged runtime or build its own index directly from the JSON.

### Using the packaged runtime (MiniSearch)

```html
<form id="search-form">
  <input id="search-query" type="search" name="q">
  <button type="submit">Search</button>
</form>
<div id="search-status" aria-live="polite"></div>
<div id="search-results"></div>
<script src="https://cdn.jsdelivr.net/npm/minisearch@7.2.0/dist/umd/index.min.js"
        crossorigin="anonymous"></script>
<script>
  window.clientSearchConfig = {
    indexUrl: "/search-index.json"
  };
</script>
<script src="/assets/client-search-base.js"></script>
<script src="/assets/adapters/minisearch.js"></script>
```

### Using the packaged runtime (ElasticLunr)

```html
<form id="search-form">
  <input id="search-query" type="search" name="q">
  <button type="submit">Search</button>
</form>
<div id="search-status" aria-live="polite"></div>
<div id="search-results"></div>
<script src="https://cdn.jsdelivr.net/npm/elasticlunr@0.9.5/elasticlunr.min.js"
        crossorigin="anonymous"></script>
<script>
  window.clientSearchConfig = {
    indexUrl: "/search-index.json"
  };
</script>
<script src="/assets/client-search-base.js"></script>
<script src="/assets/adapters/elasticlunr.js"></script>
```

### Two-stage search strategy

The base runtime owns the two-stage strategy, applied uniformly across all
adapters:

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

This project targets Ruby 3.4.10 through rbenv. The required version is stored
in `.ruby-version`, and the lockfile uses Bundler 4.0.9.

```bash
rbenv install 3.4.10       # if not already installed
rbenv local 3.4.10
bundle install
npm ci
bundle exec rake ci
```

### Testing strategy

The test suite uses **80 real-world articles** as fixture content to ensure
realistic search behavior testing:

- **40 Wikipedia articles** (CC BY-SA 3.0) covering arctic/geography,
  climbing/sports, photography/optics, food/cooking, and technology topics.
  Downloaded via the Wikipedia API with source attribution, download date,
  and license recorded in each post's frontmatter.
- **40 arXiv papers** (arXiv non-exclusive license) covering information
  retrieval, NLP, computer vision, recommendation systems, and knowledge
  graphs. Downloaded via the arXiv API with full-text PDF extraction.

The articles have deliberate cross-topic vocabulary overlap (e.g., "ice"
appears in both glacier articles and climbing articles; "embeddings" appears
in both IR and NLP papers) to test search discrimination between related but
distinct topics.

**Test layers:**

| Layer | What it tests | Command |
| --- | --- | --- |
| Ruby unit specs | Configuration, cache, adapter, document builder | `bundle exec rspec` |
| Ruby system specs | Jekyll build generates correct JSON from 80 posts | `bundle exec rspec spec/system_spec.rb` |
| JS unit tests | Adapter behavior in jsdom (load, AND/OR, URL safety) | `npm test` |
| JS system tests | Search results against built 80-post index in jsdom | `npm test` |
| Ollama integration | Real embedding generation + cache reuse against local Ollama | `OLLAMA_INTEGRATION=1 bundle exec rspec spec/ollama_integration_spec.rb` |

**Regenerating fixture posts:**

```bash
ruby spec/fixtures/download_wikipedia.rb   # ~40 Wikipedia articles
ruby spec/fixtures/download_arxiv.rb        # ~40 arXiv papers
```

Each post includes `source`, `source_url`, `download_date`, and `license`
fields in its frontmatter for attribution.

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
