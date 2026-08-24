# Performance Benchmarks

This file is **auto-generated** by `benchmarks/generate_perf_readme.rb`.
Do not edit manually — run the benchmark script to update.

## Methodology

- **Fixture site**: 80 real-world articles (40 Wikipedia + 40 arXiv papers)
- **Ruby**: 3.4.10
- **LLM model**: embeddinggemma:300m
- **Measurements**: build time (Jekyll build), index size (JSON bytes),
  cache size, embedding dimensions

Run the benchmarks:

```bash
bundle exec ruby benchmarks/run_benchmarks.rb
bundle exec ruby benchmarks/generate_perf_readme.rb
```

## Baseline vs Current

The baseline is the first recorded measurement. The current is the latest.

| Metric | Baseline | Current | Change |
| --- | --- | --- | --- |
| Build time (no LLM) | 2.0 s | 2.0 s | → 0.0% (0 ms) |
| Build time (with LLM) | 33.08 s | 33.08 s | → 0.0% (0 ms) |
| Index size (no LLM) | 1.95 MB | 1.95 MB | → 0.0% (0 bytes) |
| Index size (with LLM) | 2.71 MB | 2.71 MB | → 0.0% (0 bytes) |
| Document count | 80 | 80 | — |
| Embedding dimensions | 768 | 768 | — |
| Cache size | 1.21 MB | 1.21 MB | → 0.0% (0 bytes) |

## History

### Baseline — 2026-08-24T20:55:28Z

| Metric | Value |
| --- | --- |
| Ruby | 3.4.10 |
| Ollama model | embeddinggemma:300m |
| Build time (no LLM) | 2.0 s |
| Build time (with LLM) | 33.08 s |
| Index size (no LLM) | 1.95 MB |
| Index size (with LLM) | 2.71 MB |
| Documents | 80 |
| Embedding dims | 768 |
| Cache size | 1.21 MB |

