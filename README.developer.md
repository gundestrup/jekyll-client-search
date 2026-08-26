# Developer Guide — jekyll-client-search

This guide explains how to set up the full test fixture set for local
development. Most tests run without any special setup, but a few require
fixture data that is not committed to the repository for licensing reasons.
See [README.md](README.md) for user-facing configuration and usage docs.

## Quick start

```bash
rbenv install 3.4.10       # if not already installed
rbenv local 3.4.10
bundle install
npm ci
bundle exec rspec          # Ruby tests (176 examples; 7 opt-in Ollama examples pending)
npm test                   # JavaScript tests (130 tests)
```

Both test suites pass with only the committed Wikipedia fixtures and the
committed baseline JSON artifacts. No network access or external services
are required for the default test run.

## Build-time related articles

The optional related-analysis pass writes `search-relations.json` separately
from the normal search index. It combines exact shared tags/categories and
hierarchical category parents with vector similarity when embeddings are
available. Semantic relations use a configurable similarity cutoff; there is
no default five-item limit. `client-search-related.js` renders the relations
on an article page without loading an embedding model.

For a MiniSearch site, set `embedding.include_in_index: false` (the default
when the selected engine is not semantic) to use Ollama vectors during the
build and omit them from the public search index.

### Adoption paths

Three adoption paths are documented in [README.md](README.md#related-articles):

1. **`{% related_articles %}` Liquid tag** — one-line in any post layout
2. **`{% include related-articles.html %}`** — reference include file shipped
   at `assets/includes/related-articles.html`
3. **Drop-in layout** — reference post layout shipped at
   `assets/layouts/post-with-related.html`

The JS helper (`assets/client-search-related.js`) also supports `renderItem`
and `filter` callbacks for custom rendering and filtering.

### Fixture site demo

The fixture site (`spec/fixtures/site/`) has related articles enabled in its
`_config.yml`. It includes:

- `_layouts/post.html` — minimal post layout using `{% related_articles %}`
- `related-test.html` — demo page at `/related-test/` exercising all five
  variants: default Liquid tag, `sort:date` + `no_scripts`, custom
  `renderItem`, `filter`, and raw JSON link

System tests in `spec/system_spec.rb` verify the relations file structure,
runtime asset copying, Liquid tag rendering in post pages, demo page
content, self-exclusion, and score sorting.

### Related test files

| File | Description |
| --- | --- |
| `spec/related_analyzer_spec.rb` | Unit tests for the relation analyzer |
| `spec/related_tag_spec.rb` | Unit tests for the `{% related_articles %}` Liquid tag |
| `spec/search_tag_spec.rb` | Unit tests for the `{% search_form %}` Liquid tag |
| `spec/tasks_spec.rb` | Unit tests for the rake tasks (reference_files, install) |
| `spec/system_spec.rb` | System tests building the fixture site with related and search_form |
| `test/related.test.js` | JS tests for the related renderer (default, renderItem, filter, sort) |

## What is committed

| Artifact | Committed? | Why |
|---|---|---|
| Wikipedia fixture posts (40) | Yes | CC BY-SA 3.0 allows redistribution with attribution |
| arXiv fixture posts (40) | **No** | Mixed/restrictive licenses — see below |
| Baseline search-index JSON | Yes | Generated test artifact (indexed data, not raw text) |
| Semantic embeddings JSON | Yes | Generated test artifact (embedding vectors) |
| Download scripts | Yes | Kept for reference and regeneration |

## When you need the arXiv fixtures

The arXiv fixture posts are needed only for:

1. **Ruby system tests that build the fixture site** — without arXiv posts,
   these tests run with 40 Wikipedia posts instead of 80 and skip the
   baseline comparison (the baseline was generated from the full 80-post
   set).

2. **Ollama integration tests** (`OLLAMA_INTEGRATION=1`) — these build the
   full 80-post index with real embeddings and require both Wikipedia and
   arXiv posts.

3. **Regenerating the baseline JSON** — `ruby spec/fixtures/generate_baseline.rb`
   requires all 80 posts.

### Downloading arXiv fixtures

```bash
ruby spec/fixtures/download_arxiv.rb
```

This script:
- Fetches 40 recent arXiv papers from 5 CS/AI subfields
- Downloads each PDF and extracts text with `pdftotext`
- Records the actual per-paper license in each post's frontmatter
- Writes posts to `spec/fixtures/site/_posts/`
- Requires `pdftotext` (available via `brew install poppler` on macOS)

The arXiv API returns versioned papers (e.g. `2608.23419v1`). Running the
script at different times will return different papers, but a specific
version is permanent — arXiv never changes a published version.

### Downloading Wikipedia fixtures (optional)

The Wikipedia fixtures are already committed. You only need this script if
you want to regenerate them (e.g. to get newer article versions):

```bash
ruby spec/fixtures/download_wikipedia.rb
```

Each Wikipedia post includes a `wikipedia_oldid` field with a permanent
link to the exact revision that was downloaded.

## LLM / vector search testing

### Without Ollama (default)

Semantic search tests run without a local Ollama server. They use committed
real-model embedding vectors (`spec/fixtures/baseline/semantic-embeddings.json`)
injected into the committed baseline index. This covers the browser-side
cosine similarity adapter and cross-engine comparison tests.

### With Ollama (opt-in integration tests)

To run the full integration tests that call a real Ollama server:

1. Install [Ollama](https://ollama.ai/)

2. Pull the required model:

   ```bash
   ollama pull embeddinggemma:300m
   ```

3. Run the integration tests:

   ```bash
   OLLAMA_INTEGRATION=1 bundle exec rspec spec/ollama_integration_spec.rb
   OLLAMA_INTEGRATION=1 bundle exec rspec spec/llm_injection_spec.rb
   ```

These tests:
- Build the full 80-post index with real Ollama embeddings
- Verify embedding dimensions and validity
- Test semantic search quality with concept queries
- Generate the semantic index used by JS comparison tests
- Require arXiv fixture posts to be downloaded first

### Regenerating committed test artifacts

If you need to regenerate the baseline or semantic gold fixtures (e.g.
after changing the document builder or fixture content):

```bash
# 1. Ensure all 80 fixture posts are present
ruby spec/fixtures/download_arxiv.rb

# 2. Regenerate the baseline index (without embeddings)
ruby spec/fixtures/generate_baseline.rb

# 3. Run the Ollama integration test to generate the semantic index
OLLAMA_INTEGRATION=1 bundle exec rspec spec/ollama_integration_spec.rb

# 4. Regenerate the semantic gold fixture from the built index
ruby spec/fixtures/generate_semantic_gold.rb
```

## Test categories

| Tag | Description | Requires arXiv? | Requires Ollama? |
|---|---|---|---|
| `:unit` | Ruby unit tests | No | No |
| `:system` | Ruby system tests (build fixture site) | Partially | No |
| `:integration` | Ruby integration tests | No | No |
| `:ollama_integration` | Real Ollama server tests | Yes | Yes |

Run a specific category:

```bash
bundle exec rspec --tag unit
bundle exec rspec --tag system
bundle exec rspec --tag ollama_integration
```

## CI

The CI pipeline runs `bundle exec rspec` and `npm test` without arXiv
fixtures or Ollama. The committed baseline JSON and semantic embeddings
ensure all tests pass in CI without external dependencies.

## Releasing

Releases are published to RubyGems.org via the
[`release.yml`](.github/workflows/release.yml) GitHub Actions workflow,
which triggers automatically when a GitHub Release is published. The
workflow uses RubyGems trusted publishing (OIDC) — no API key is stored
in the repository.

### Prerequisites (one-time setup)

Trusted publishing must be configured on rubygems.org for the gem before
the first release:

1. Log into <https://rubygems.org> and open the gem's page.
2. Go to **Settings → Trusted Publishers → Add trusted publisher**.
3. Enter:
   - **Repository**: `gundestrup/jekyll-client-search`
   - **Workflow filename**: `release.yml`
   - **Environment**: `rubygems`

If the gem has never been published before, rubygems.org may require a
one-time manual `gem push` with an API key to create the gem name before
a trusted publisher can be attached. After that, all subsequent releases
use trusted publishing automatically.

### Version bumping

The version lives in [`lib/jekyll/client_search/version.rb`](lib/jekyll/client_search/version.rb)
and follows [Semantic Versioning](https://semver.org/). Use the rake task
to bump it:

```bash
bundle exec rake "version:bump[patch]"   # 0.1.0 -> 0.1.1  (bug fixes)
bundle exec rake "version:bump[minor]"   # 0.1.0 -> 0.2.0  (new features, backwards compatible)
bundle exec rake "version:bump[major]"   # 0.1.0 -> 1.0.0  (incompatible API changes)
```

The rake task only edits `version.rb`; it does not commit, tag, or update
the changelog.

### Release checklist

1. **Ensure the working tree is clean** and on `main`:

   ```bash
   git status
   ```

2. **Run the full test suite locally**:

   ```bash
   bundle exec rspec
   bundle exec rubocop
   npm test
   npm run lint
   gem build jekyll-client-search.gemspec
   ```

3. **Bump the version** (see above) and update the `## Unreleased` or new
   `## X.Y.Z — YYYY-MM-DD` section at the top of
   [`CHANGELOG.md`](CHANGELOG.md) with a user-facing summary of changes.

4. **Commit the version bump and changelog**:

   ```bash
   git add lib/jekyll/client_search/version.rb CHANGELOG.md
   git commit -m "Release X.Y.Z: <short summary>"
   ```

5. **Tag the release** with an annotated tag:

   ```bash
   git tag -a vX.Y.Z -m "Release X.Y.Z

   <one-line summary of notable changes>"
   ```

6. **Push `main` and the tag** to GitHub:

   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

7. **Create the GitHub Release** — this triggers the publish workflow:

   ```bash
   gh release create vX.Y.Z --title "Release X.Y.Z" --notes "<changelog notes>"
   ```

   Or paste the relevant `CHANGELOG.md` section into the release notes via
   the GitHub UI.

8. **Watch the workflow** and verify the gem appears on RubyGems:

   ```bash
   gh run watch --workflow=release.yml
   gem list jekyll-client-search --remote --exact
   ```

9. **Verify the integration site** builds cleanly against the published
   gem (update the path dependency to the released version in
   `../gundestrup.dk` and run `bundle exec jekyll build`).

### What the release workflow does

The [`release.yml`](.github/workflows/release.yml) workflow, triggered by
a published GitHub Release:

1. Checks out the repository at the release tag.
2. Sets up Ruby 3.4.10 and Node.js 22.
3. Verifies the tag name matches `v<gem version>` (fails the build on
   mismatch).
4. Runs `bundle exec rake ci` (RSpec, RuboCop, syntax checks, `npm test`,
   and `gem build`).
5. Publishes the built gem to RubyGems.org using trusted publishing
   (`rubygems/release-gem@v1` with OIDC).

The workflow runs in the `rubygems` environment, which must match the
environment name configured on the trusted publisher in step 1 of the
prerequisites.
