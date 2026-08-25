# Performance Benchmarks

This file is **auto-generated** by `benchmarks/generate_perf_readme.rb`.
Do not edit manually — run the benchmark script to update.

## Methodology

- **Fixture site**: 80 source posts (40 Wikipedia + 40 unique arXiv papers)
- **Ruby**: 3.4.10
- **LLM model**: embeddinggemma:300m
- **Measurements**: cold, warm, and incremental Jekyll build time;
  index/cache size; embedding dimensions; and average engine-core query
  latency using the same search options as the runtime adapters

Build and query timings are environment-sensitive, especially cold Ollama
runs. Compare measurements from equivalent hardware, model state, and system
load; index and cache sizes are deterministic for the same fixture/model.

Run the benchmarks:

```bash
bundle exec ruby benchmarks/run_benchmarks.rb
bundle exec ruby benchmarks/generate_perf_readme.rb
```

## Baseline vs Current

The baseline is the first measurement for the current benchmark schema. The
current is the latest measurement. Compare only rows with the same schema;
fixture or methodology changes increment the schema, and older rows may show
`N/A` for metrics that did not exist yet.

| Metric | Baseline | Current | Change |
| --- | --- | --- | --- |
| Build time (no LLM) | 1.53 s | 1.53 s | → 0.0% (0 ms) |
| Cold build time (with LLM) | 1.86 min | 1.86 min | → 0.0% (0 ms) |
| Warm build time (with LLM) | 2.04 s | 2.04 s | → 0.0% (0 ms) |
| Incremental build time (with LLM) | 4.11 s | 4.11 s | → 0.0% (0 ms) |
| Index size (no LLM) | 1.98 MB | 1.98 MB | → 0.0% (0 bytes) |
| Index size (with LLM) | 2.75 MB | 2.75 MB | → 0.0% (0 bytes) |
| Document count | 80 | 80 | — |
| Embedding dimensions | 768 | 768 | — |
| Cache size | 1.22 MB | 1.22 MB | → 0.0% (0 bytes) |
| MiniSearch avg query | 0.045 ms | 0.045 ms | → 0.0% (0.0 ms) |
| ElasticLunr avg query | 0.071 ms | 0.071 ms | → 0.0% (0.0 ms) |
| Semantic cosine search | 0.138 ms | 0.138 ms | → 0.0% (0.0 ms) |
| Semantic query embedding | 87.259 ms | 87.259 ms | → 0.0% (0.0 ms) |

## History

### Run #1 — 2026-08-24T20:55:28Z

| Metric | Value |
| --- | --- |
| Benchmark schema | legacy |
| Ruby | 3.4.10 |
| Ollama model | embeddinggemma:300m |
| Build time (no LLM) | 2.0 s |
| Cold build time (with LLM) | 33.08 s |
| Warm build time (with LLM) | N/A |
| Incremental build time (with LLM) | N/A |
| Index size (no LLM) | 1.95 MB |
| Index size (with LLM) | 2.71 MB |
| Documents | 80 |
| Embedding dims | 768 |
| Cache size | 1.21 MB |
| MiniSearch avg query | N/A |
| ElasticLunr avg query | N/A |
| Semantic cosine search | N/A |
| Semantic query embedding | N/A |

### Run #2 — 2026-08-24T21:33:28Z

| Metric | Value |
| --- | --- |
| Benchmark schema | legacy |
| Ruby | 3.4.10 |
| Ollama model | embeddinggemma:300m |
| Build time (no LLM) | 2.06 s |
| Cold build time (with LLM) | 32.64 s |
| Warm build time (with LLM) | 1.97 s |
| Incremental build time (with LLM) | 2.34 s |
| Index size (no LLM) | 1.95 MB |
| Index size (with LLM) | 2.71 MB |
| Documents | 80 |
| Embedding dims | 768 |
| Cache size | 1.22 MB |
| MiniSearch avg query | 0.021 ms |
| ElasticLunr avg query | 0.039 ms |
| Semantic cosine search | N/A |
| Semantic query embedding | N/A |

### Run #3 — 2026-08-24T21:38:40Z

| Metric | Value |
| --- | --- |
| Benchmark schema | legacy |
| Ruby | 3.4.10 |
| Ollama model | embeddinggemma:300m |
| Build time (no LLM) | 2.04 s |
| Cold build time (with LLM) | 30.93 s |
| Warm build time (with LLM) | 1.91 s |
| Incremental build time (with LLM) | 2.3 s |
| Index size (no LLM) | 1.95 MB |
| Index size (with LLM) | 2.71 MB |
| Documents | 80 |
| Embedding dims | 768 |
| Cache size | 1.22 MB |
| MiniSearch avg query | 0.023 ms |
| ElasticLunr avg query | 0.053 ms |
| Semantic cosine search | 0.066 ms |
| Semantic query embedding | 58.942 ms |

### Run #4 — 2026-08-25T06:23:51Z

| Metric | Value |
| --- | --- |
| Benchmark schema | 2 |
| Ruby | 3.4.10 |
| Ollama model | embeddinggemma:300m |
| Build time (no LLM) | 3.33 s |
| Cold build time (with LLM) | 13.11 min |
| Warm build time (with LLM) | 4.38 s |
| Incremental build time (with LLM) | 5.86 s |
| Index size (no LLM) | 1.95 MB |
| Index size (with LLM) | 2.71 MB |
| Documents | 80 |
| Embedding dims | 768 |
| Cache size | 1.22 MB |
| MiniSearch avg query | 0.038 ms |
| ElasticLunr avg query | 0.06 ms |
| Semantic cosine search | 0.111 ms |
| Semantic query embedding | 78.07 ms |

### Baseline — 2026-08-25T06:56:00Z

| Metric | Value |
| --- | --- |
| Benchmark schema | 3 |
| Ruby | 3.4.10 |
| Ollama model | embeddinggemma:300m |
| Build time (no LLM) | 1.53 s |
| Cold build time (with LLM) | 1.86 min |
| Warm build time (with LLM) | 2.04 s |
| Incremental build time (with LLM) | 4.11 s |
| Index size (no LLM) | 1.98 MB |
| Index size (with LLM) | 2.75 MB |
| Documents | 80 |
| Embedding dims | 768 |
| Cache size | 1.22 MB |
| MiniSearch avg query | 0.045 ms |
| ElasticLunr avg query | 0.071 ms |
| Semantic cosine search | 0.138 ms |
| Semantic query embedding | 87.259 ms |

