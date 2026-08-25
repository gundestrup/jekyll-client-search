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
bundle exec rspec          # Ruby tests (175 examples; 7 opt-in Ollama examples pending)
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
