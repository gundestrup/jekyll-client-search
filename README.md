# jekyll-client-search

[![Ruby](https://img.shields.io/badge/ruby-3.4.10-red.svg)](https://www.ruby-lang.org/)
[![Jekyll](https://img.shields.io/badge/jekyll-4.x-blue.svg)](https://jekyllrb.com/)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](LICENSE)

A Jekyll plugin that generates a configurable JSON document index for
[MiniSearch](https://lucaong.github.io/minisearch/), a lightweight full-text
search engine for browser and offline search.

- [MiniSearch homepage](https://lucaong.github.io/minisearch/)
- [MiniSearch documentation](https://lucaong.github.io/minisearch/classes/MiniSearch.html)
- [MiniSearch source](https://github.com/lucaong/minisearch)

The plugin handles the Jekyll build-time part of search. It generates the
search documents and copies an optional browser runtime asset. MiniSearch
itself remains a JavaScript dependency of the consuming site.

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

The default build output is `/search-index.json`. The plugin also makes its
browser runtime available at `/assets/client-search.js`.

## Configuration

```yaml
client_search:
  enabled: true
  output: search-index.json
  collections:
    - posts
  include_pages: false
  copy_runtime: true
```

Options:

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `true` | Enable or disable index generation. |
| `output` | `search-index.json` | Output path for the generated JSON index. |
| `collections` | `[posts]` | Jekyll collections to index. |
| `include_pages` | `false` | Include titled Jekyll pages in the index. |
| `copy_runtime` | `true` | Copy the packaged runtime to `/assets/client-search.js`. |

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

## Browser usage

The generated JSON is intentionally engine-neutral. A consuming site creates
a MiniSearch index using the fields it wants to search, following the
[MiniSearch documentation](https://lucaong.github.io/minisearch/classes/MiniSearch.html):

```html
<script src="https://cdn.jsdelivr.net/npm/minisearch@7.2.0/dist/umd/index.min.js"></script>
<script>
  fetch("/search-index.json")
    .then(response => response.json())
    .then(documents => {
      const miniSearch = new MiniSearch({
        fields: ["title", "excerpt", "content", "categories", "tags"],
        storeFields: ["title", "url", "excerpt", "categories", "tags"],
        searchOptions: {
          combineWith: "AND",
          prefix: true,
          boost: { title: 10, categories: 5, tags: 4, excerpt: 2, content: 1 }
        }
      });
      miniSearch.addAll(documents.map(doc => ({
        ...doc,
        categories: doc.categories.join(" "),
        tags: doc.tags.join(" ")
      })));
      const results = miniSearch.search("greenland");
    });
</script>
```

MiniSearch supports query-time field boosting, prefix search, fuzzy matching,
and Boolean term combination (`AND`, `OR`, `AND_NOT`). The plugin leaves those
choices to the consuming site so that the same generated index can support
different interfaces.

The packaged runtime expects a search form, status region, and result container.
Selectors and the index URL can be overridden before loading the runtime:

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
<script src="/assets/client-search.js"></script>
```

The packaged runtime uses a two-stage search strategy:

1. **Exact AND search** with prefix matching and field boosting — returns only
   documents matching all query terms.
2. **Fuzzy OR fallback** — if the AND search returns no results, retries with
   `combineWith: "OR"`, `fuzzy: 0.2`, and prefix matching for typo tolerance.

## Keeping MiniSearch current

The gem deliberately does not bundle or build MiniSearch. The consuming
site owns the browser dependency and currently loads a pinned CDN version.
This keeps the Ruby gem independent from the JavaScript release cycle.

Recommended policy:

1. Pin an exact MiniSearch version in the consuming site.
2. Add a Subresource Integrity hash when loading from a CDN.
3. Review the MiniSearch release notes and documentation before upgrading.
4. Run the consuming site's search and integration checks after an upgrade.
5. Prefer a local copy when a site needs offline builds or a strict CSP.

MiniSearch's documented query-time boosting, fuzzy matching, and Boolean
combination are available to the consuming site's runtime; the gem only
standardizes the build-time document format.

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
