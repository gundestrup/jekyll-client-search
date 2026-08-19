# jekyll-elasticlunr-search

[![Ruby](https://img.shields.io/badge/ruby-3.4.10-red.svg)](https://www.ruby-lang.org/)
[![Jekyll](https://img.shields.io/badge/jekyll-4.x-blue.svg)](https://jekyllrb.com/)

A Jekyll plugin that generates a configurable JSON document index for
[Elasticlunr.js](http://elasticlunr.com/), a lightweight full-text search engine
for browser and offline search.

- [Elasticlunr.js homepage](http://elasticlunr.com/)
- [Elasticlunr.js documentation](http://elasticlunr.com/docs/index.html)
- [Elasticlunr.js source](https://github.com/weixsong/elasticlunr.js)

The plugin handles the Jekyll build-time part of search. It generates the
search documents and copies an optional browser runtime asset. Elasticlunr.js
itself remains a JavaScript dependency of the consuming site.

## Installation

Add the gem to the consuming Jekyll site's `Gemfile`:

```ruby
group :jekyll_plugins do
  gem "jekyll-elasticlunr-search", "~> 0.1"
end
```

During local development of this gem, use a path dependency:

```ruby
gem "jekyll-elasticlunr-search", path: "../jekyll-elasticlunr-search"
```

Enable the plugin in `_config.yml`:

```yaml
plugins:
  - jekyll-elasticlunr-search
```

Then run:

```bash
bundle install
bundle exec jekyll build
```

The default build output is `/search-index.json`. The plugin also makes its
browser runtime available at `/assets/elasticlunr-search.js`.

## Configuration

```yaml
elasticlunr_search:
  enabled: true
  output: search-index.json
  collections:
    - posts
  include_pages: false
```

Options:

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `true` | Enable or disable index generation. |
| `output` | `search-index.json` | Output path for the generated JSON index. |
| `collections` | `[posts]` | Jekyll collections to index. |
| `include_pages` | `false` | Include titled Jekyll pages in the index. |

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
an Elasticlunr index using the fields it wants to search, following the
[Elasticlunr build-index documentation](http://elasticlunr.com/docs/index.html):

```html
<script src="https://cdn.jsdelivr.net/npm/elasticlunr@0.9.5/elasticlunr.min.js"></script>
<script>
  fetch("/search-index.json")
    .then(response => response.json())
    .then(documents => {
      const index = elasticlunr(function () {
        this.addField("title");
        this.addField("excerpt");
        this.addField("content");
        this.addField("categories");
        this.addField("tags");
        this.setRef("id");
        this.saveDocument(false);
      });

      documents.forEach(document => index.addDoc({
        ...document,
        categories: document.categories.join(" "),
        tags: document.tags.join(" ")
      }));

      const results = index.search("greenland", {
        expand: true,
        fields: {
          title: { boost: 10 },
          categories: { boost: 5 },
          tags: { boost: 4 },
          excerpt: { boost: 2 },
          content: { boost: 1 }
        }
      });
    });
</script>
```

Elasticlunr supports query-time field boosting, field search, Boolean modes,
and token expansion. The plugin leaves those choices to the consuming site so
that the same generated index can support different interfaces.

## Keeping Elasticlunr.js current

The gem deliberately does not bundle or build Elasticlunr.js. The consuming
site owns the browser dependency and currently loads a pinned CDN version with
Subresource Integrity. This keeps the Ruby gem independent from the JavaScript
release cycle.

Recommended policy:

1. Pin an exact Elasticlunr.js version in the consuming site.
2. Keep the Subresource Integrity hash with the URL.
3. Review the Elasticlunr release notes and documentation before upgrading.
4. Run the consuming site's search and integration checks after an upgrade.
5. Prefer a local copy when a site needs offline builds or a strict CSP.

Elasticlunr's documented query-time boosting and field configuration are
available to the consuming site's runtime; the gem only standardizes the
build-time document format.

## Development

This project uses Ruby 3.4.10 through rbenv. The required version is stored in
`.ruby-version`.

```bash
rbenv install 3.4.10       # if not already installed
rbenv local 3.4.10
bundle install
bundle exec rspec
```

The Gundestrup.dk repository is the integration test platform. Its `Gemfile`
uses this gem through a local path dependency:

```ruby
gem "jekyll-elasticlunr-search", path: "../jekyll-elasticlunr-search"
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

