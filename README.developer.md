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
bundle exec rspec                          # Ruby tests (248 examples; 7 Ollama pending)
OLLAMA_INTEGRATION=1 bundle exec rspec     # all tests including Ollama integration
npm test                                   # JavaScript tests (134 tests)
```

Both test suites pass with only the committed Wikipedia fixtures and the
committed baseline JSON artifacts. No network access or external services
are required for the default test run.

## Quality checks and git hooks

The project uses a focused quality stack: RuboCop (style), bundler-audit
(security), RSpec (Ruby tests), and `npm test` (JavaScript tests). This
covers the actionable ground without the maintenance burden of additional
code-smell tools on a small focused gem.

### Rake tasks

| Task | What it runs |
| --- | --- |
| `rake` (default) | `rake quality` — all checks below |
| `rake quality` | rubocop + bundler-audit + rspec + npm test |
| `rake quick` | rubocop + rspec (fast pre-push subset) |
| `rake rubocop` | RuboCop style check |
| `rake rubocop_fix` | RuboCop auto-fix |
| `rake bundler_audit` | `bundle-audit check --update` security scan |
| `rake spec` | RSpec test suite |
| `rake npm_test` | JavaScript test suite (`npm test`) |
| `rake ci` | rspec + rubocop + syntax checks + npm test + gem build |

### Git hooks

Git hooks are not committed to the repository. Install them locally after
cloning:

```bash
bin/install-hooks.sh
```

This installs two hooks:

| Hook | What it runs | When |
| --- | --- | --- |
| `pre-commit` | `rubocop` only (~2s) | Before each commit |
| `pre-push` | `rubocop + rspec` (~15s) | Before each push |

The pre-commit hook is intentionally fast (style only) to avoid bypassing
with `--no-verify`. The full test suite runs on pre-push and in CI. Skip
either with `git commit --no-verify` or `git push --no-verify`.

### CI checks

The [CI workflow](.github/workflows/ci.yml) runs on every push and pull
request across Ruby 3.2/3.3/3.4 and Node 22/24:

- `bundle exec rake ci` (rspec, rubocop, syntax checks, npm test, gem build)
- `bundle exec bundle-audit check --update` (Ruby dependency security)
- `npm audit --audit-level=high` (JavaScript dependency security)
- `npm outdated` (non-blocking — warns about outdated npm packages)

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

See the [Spec files](#spec-files) table for the full list. The key related
test files are `spec/related_analyzer_spec.rb`, `spec/related_tag_spec.rb`,
`spec/system_spec.rb`, and `test/related.test.js`.

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

## Coverage

The project uses SimpleCov 1.1+ with branch coverage. The target is 100%
branch coverage and ~99.6% line coverage. Three lines are intentionally
excluded via `# simplecov:disable branch` for an unreachable defensive
guard in `search_tag.rb` (the `if embedder_asset` check that can never be
false with current embedder types — `semantic_with_embedder?` already
filters out the `none` type, and both `transformers` and `ollama_api`
always return an asset).

The coverage report is generated at `coverage/index.html` after each RSpec
run. Raw data is in `coverage/.resultset.json` (SimpleCov 1.0+ format with
`lines` and `branches` keys per file).

To check remaining uncovered lines and branches after a run:

```bash
python3 -c "
import json
with open('coverage/.resultset.json') as f:
    data = json.load(f)
for suite, info in data.items():
    cov = info.get('coverage', {})
    for file, lines in sorted(cov.items()):
        if 'lib/jekyll' not in file: continue
        short = file.split('/lib/')[-1]
        line_data = lines.get('lines', []) if isinstance(lines, dict) else lines
        uncovered = [i+1 for i, v in enumerate(line_data) if v == 0]
        if uncovered:
            print(f'{short}: lines {uncovered}')
        branches = lines.get('branches', {}) if isinstance(lines, dict) else {}
        for bk, bd in branches.items():
            for sk, count in bd.items():
                if count == 0:
                    print(f'{short}: {sk} (count=0)')
"
```

## Spec files

| File | Description |
| --- | --- |
| `spec/configuration_spec.rb` | Site configuration, defaults, validation |
| `spec/dropdown_configuration_spec.rb` | Dropdown config validation |
| `spec/dropdown_tag_spec.rb` | `{% search_dropdown %}` Liquid tag |
| `spec/search_tag_spec.rb` | `{% search_form %}` Liquid tag |
| `spec/related_tag_spec.rb` | `{% related_articles %}` Liquid tag |
| `spec/related_analyzer_spec.rb` | Build-time relation analysis |
| `spec/related_configuration_spec.rb` | Related config validation |
| `spec/generator_spec.rb` | Jekyll generator integration |
| `spec/document_builder_spec.rb` | Normalized search documents |
| `spec/search_index_page_spec.rb` | Generated JSON page |
| `spec/index_cache_spec.rb` | Index cache |
| `spec/embedding_cache_spec.rb` | Embedding cache |
| `spec/runtime_assets_spec.rb` | Runtime asset copying |
| `spec/runtime_config_page_spec.rb` | Runtime config page generation |
| `spec/ollama_embedding_adapter_spec.rb` | Ollama adapter unit tests |
| `spec/ollama_integration_spec.rb` | Ollama integration tests (pending) |
| `spec/llm_injection_spec.rb` | LLM injection baseline tests (pending) |
| `spec/tasks_spec.rb` | Rake tasks (reference_files, install) |
| `spec/gemspec_spec.rb` | Gemspec metadata |
| `spec/system_spec.rb` | End-to-end system tests |
| `test/runtime.test.js` | JS unit tests parameterized over adapters |
| `test/related.test.js` | JS tests for related renderer |
| `test/system.test.js` | JS system tests using committed baseline index |

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
   - **Environment**: `release`

If the gem has never been published before, rubygems.org may require a
one-time manual `gem push` with an API key to create the gem name before
a trusted publisher can be attached. After that, all subsequent releases
use trusted publishing automatically.

### Version bumping

The version lives in [`lib/jekyll/client_search/version.rb`](lib/jekyll/client_search/version.rb)
and follows [Semantic Versioning](https://semver.org/). The gemspec reads
from this file — it is the **single source of truth**. No other file
stores the version (`package.json` is `private: true` and has no version
field). Use the rake task to bump it:

```bash
bundle exec rake "version:bump[patch]"   # 0.1.0 -> 0.1.1  (bug fixes)
bundle exec rake "version:bump[minor]"   # 0.1.0 -> 0.2.0  (new features, backwards compatible)
bundle exec rake "version:bump[major]"   # 0.1.0 -> 1.0.0  (incompatible API changes)
```

The rake task only edits `version.rb`. It does not commit, tag, or update
the changelog — those are manual steps in the release checklist below.

You can verify that the CHANGELOG has an entry for the current version:

```bash
bundle exec rake version:check_changelog
```

This check also runs in the release workflow — the publish will fail if
`CHANGELOG.md` has no `## X.Y.Z` entry matching the version being released.

### Release checklist

1. **Ensure the working tree is clean** and on `main`:

   ```bash
   git status
   ```

2. **Ensure all 80 fixture posts are present** (needed for Ollama
   integration tests and baseline regeneration):

   ```bash
   ruby spec/fixtures/download_arxiv.rb
   ```

   Requires `pdftotext` (`brew install poppler` on macOS). Skip if the
   arXiv posts are already present and unchanged.

3. **Run the full test suite locally**, including Ollama integration tests:

   ```bash
   bundle exec rspec
   OLLAMA_INTEGRATION=1 bundle exec rspec spec/ollama_integration_spec.rb
   OLLAMA_INTEGRATION=1 bundle exec rspec spec/llm_injection_spec.rb
   bundle exec rubocop
   npm test
   npm run lint
   gem build jekyll-client-search.gemspec
   ```

   The Ollama integration tests require a running [Ollama](https://ollama.ai/)
   server with the `embeddinggemma:300m` model pulled (`ollama pull
   embeddinggemma:300m`). Do not publish a release until the Ollama
   integration tests pass locally — they are skipped by default and will
   not block CI, so they must be run manually before each release.

4. **Bump the version** (see above) and update the `## Unreleased` or new
   `## X.Y.Z — YYYY-MM-DD` section at the top of
   [`CHANGELOG.md`](CHANGELOG.md) with a user-facing summary of changes.

5. **Commit the version bump and changelog**:

   ```bash
   git add lib/jekyll/client_search/version.rb CHANGELOG.md
   git commit -m "Release X.Y.Z: <short summary>"
   ```

6. **Tag the release** with an annotated tag:

   ```bash
   git tag -a vX.Y.Z -m "Release X.Y.Z

   <one-line summary of notable changes>"
   ```

7. **Push `main` and the tag** to GitHub — pushing the tag triggers the
   release workflow automatically:

   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

   No manual `gh release create` is needed. The workflow builds the gem,
   attaches it to a GitHub release, and publishes to RubyGems.

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
pushing a `v*` tag:

1. Checks out the repository at the release tag (`persist-credentials: false`).
2. Sets up Ruby 3.4.10.
3. Verifies the tag name matches `v<gem version>` (fails on mismatch).
4. Verifies `CHANGELOG.md` has a `## X.Y.Z` entry for the version
   (`rake version:check_changelog` — fails if missing).
5. Builds the gem (`gem build`).
6. Creates a GitHub Release and attaches the `.gem` file as a downloadable
   asset (`softprops/action-gh-release@v2`).
7. Publishes the gem to RubyGems.org using trusted publishing
   (`rubygems/release-gem@v1` with OIDC).

CI already validates tests on every push — the release workflow does not
re-run the test suite. It only builds and publishes. The workflow runs in
the `release` environment, which must match the environment name
configured on the trusted publisher.
