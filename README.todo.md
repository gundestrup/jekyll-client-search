# README TODO

## Shared contract fixtures — OPEN

This gem consumes generated Jekyll documents (typically from
`jekyll-documents`) and indexes them for client-side lexical and optional
semantic search. It does not re-derive document identity — it relies on the
producer gem's `doc.content`, `title`, `category`, `date`, and passthrough
fields.

Because of that, this gem should own a separate search-index contract
fixture set, distinct from the document-identity fixtures owned by
`jekyll-documents`. The document-identity contract is between
`jekyll-documents` and the VS Code companion extension; the search-index
contract is between `jekyll-documents` (as producer) and this gem (as
consumer).

### Ownership model

```text
jekyll-client-search (this repo)
  spec/fixtures/contracts/search-index/v1/
    extracted-content.yml
    passthrough-fields.yml
    icon-fields.yml
    related-content.yml

jekyll-documents (separate repo)
  spec/fixtures/contracts/document-autocomplete/v1/   # separate contract, not consumed here
```

This gem owns the canonical search-index fixtures because it defines the
indexing and search-runtime behavior. `jekyll-documents` owns the
document-identity contract separately, because that contract is shared with
the VS Code extension, not with this gem.

### Fixture scope

Search-index fixtures should cover the contract between the document
producer and this search consumer:

- `doc.content` includes extracted text when `extract_text: true`.
- `doc.content` retains a metadata fallback when extraction is disabled.
- `title`, `category`, `date`, `url` are preserved in search entries.
- `passthrough_fields` (strings or `{source: target}` hashes) are forwarded.
- `icon_field` (default `icon_url`) is available for result rendering.
- `categories` is an array.
- Related-content analysis input matches the expected document fields.

They should NOT duplicate document filename parsing, `source_path`
derivation, `category_map` logic, permalink implementation, or VS Code
autocomplete behavior. Those belong in `jekyll-documents`'s own
document-identity contract.

They should also NOT duplicate search engine internals (MiniSearch,
ElasticLunr, semantic cosine similarity, Ollama embedding adapters). Those
belong in this gem's own internal test suite, not in the cross-repository
contract.

### Versioning and consumption

- Each fixture set carries a version directory (`v1/`).
- If a future consumer (another search UI, an editor, or a static-site
  generator adapter) needs to validate against the same index contract, it
  pins/copies these fixtures.
- Fixtures are copied into the consumer's test tree so tests run offline
  and reproducibly — no network fetch during every CI run.
- Fixture/schema changes are treated as compatibility changes and updated
  through explicit pull requests in each consumer.

### Why not a single shared fixture repository now

A neutral `jekyll-contract-fixtures` repository would add another release
process, another versioning system, cross-repository coordination, and more
CI complexity. It becomes worthwhile only when multiple external consumers
actually need the same fixtures. Until then, this gem owns its search-index
contract and any future consumer pins copies.

### Why not live-link fixtures

A live branch dependency or per-run network download would make tests
non-reproducible, dependent on GitHub/network availability, vulnerable to
unexpected fixture changes, and hard to correlate with a released gem version.
