# rust-specialist — Phase 0.5 Report (ouroboros-dfg)

- agent: rust-specialist | worktree: /home/vivek/ouroboros/ouroboros-dfg
- constraint pre-check: **ALLOW** — validated against memory_seeds/laws.json via ox-alpha (OpenRouter), 2026-08-17
- mode: DSH-native Phase 0.5 survey (read-only; no source files modified)

## Current State

The crate is a **declaration without a body**:

| File | Status | Notes |
|---|---|---|
| `Cargo.toml` | present | `ouroboros-dfg 0.1.0`, edition 2021. Deps: `egg 0.9.5`, `tokio` (features full), `serde`, `serde_json`. No `[dev-dependencies]`, no `[lib]` crate-type, no pyo3 yet (Docker build attempted `cargo add pyo3@0.22.0`). |
| `README.md` | present | Correctly encodes Module 5 constraints (Runner limits, async isolation, mypy/libclang frontends). |
| `src/` | **missing** | No `lib.rs`/`main.rs` → `cargo build` fails ("no targets"); `maturin develop` impossible; PyO3 surface nonexistent. |

Downstream confirmation of impact: the unified Dockerfile's Step 5 (`cargo add … && maturin develop --release`) cannot succeed against this tree — the guarded-skip added during build debugging exists precisely because of this gap.

Sibling expectations (what Module 5 must eventually ingest):
- `ouroboros-core/src/*.py` — Python sources for the mypy/tree-sitter frontend path.
- `ouroboros-triton/src/*.py` (+ future C++) — Python today, C++ tomorrow → libclang frontend path.

## Constraint Risk Assessment

1. **egraph-limits (0.99)** — structural enforcement required, not convention:
   - Risk: future call sites constructing `egg::Runner` directly with defaults "just to test". Mitigate by making limits unavoidable: a single `verified_runner()` constructor in a `limits` module marked `#![deny(missing_docs)]`; clippy lint denying re-export; integration test asserting a pathological rewrite loop terminates ≤10 s wall and ≤NodeLimit nodes.
   - `BackoffScheduler { match_limit: 5000, ban_length: 3 }` must be the *only* scheduler reachable from public API.
2. **Async isolation** — equality saturation must never block GPU loops:
   - Design: `tokio::spawn` a bounded worker task owning the e-graph; callers submit `(before_ssa, after_ssa, reply_tx)` pairs; results stream back over a `tokio::sync::mpsc` telemetry channel. Test: saturate verifier with 100 jobs while a heartbeat task ticks at 60 fps-equivalent; assert no tick starvation beyond threshold.
3. **Rice's theorem honesty (telemetry)** — the UI contract depends on a truthful green/yellow split:
   - Green only when roots share an e-class; yellow on timeout/backoff-trigger/no-proof. Never emit green-by-default. Golden tests pin verdict mapping incl. the timeout path.
4. **FFI boundary** — PyO3 methods must be non-blocking wrappers over the async core (return futures/poll handles or use channels); risk of accidentally exposing synchronous `block_on` into Python training loops. Lint/test: no `block_on` outside the runtime bootstrap module.

## Phase Plan

Dependency-ordered crate skeleton:

1. **P0 skeleton**: `src/lib.rs` with PyO3 module registration (`#[pymodule] ouroboros_dfg`), `limits.rs` (the four hardcoded bounds + `verified_runner()`), unit-tested via a trivial egg program.
2. **SSA DFG model**: `dfg.rs` — minimal SSA IR (ops, values, uses) + `Display`; property tests (every use refers to a dominating def).
3. **Python frontend**: `frontends/python.rs` — tree-sitter-python → scope/flow extraction → SSA lowering on a constrained golden subset (assignments, arithmetic, if/else, loops). Golden-file tests.
4. **C++ frontend stub**: `frontends/cpp.rs` behind a feature flag until libclang wiring lands (keeps CI light).
5. **Egg engine**: `verify.rs` — bidirectional rewrite rules (De Morgan, algebraic simplification, loop-friendly identities), BackoffScheduler per law, e-class equivalence verdict enum `{Verified, Unproven{Timeout|Backoff|NoProof}}`.
6. **Telemetry**: `telemetry.rs` — JSON lines over mpsc: `{job_id, verdict, iterations, nodes, elapsed_ms}` → consumed by ecc reports / future SRE dashboards (green/yellow ratio).
7. **PyO3 surface**: `spawn_verify(before, after) -> JobHandle`, `poll(job_id) -> Option<Verdict>`; integration test from Python side via maturin once P0 lands.

## First Concrete Steps

1. `feat(m5): crate skeleton with PyO3 module + hardcoded egg Runner limits` — includes `test_runner_limits_enforced`.
2. `feat(m5): minimal SSA DFG IR with domination property tests`.
3. `feat(m5): tree-sitter-python frontend lowering golden subset to SSA` — golden files first.
4. `feat(m5): egg verify engine with BackoffScheduler + verdict telemetry` — preceded by timeout-path test.
5. `build: add pyproject.toml + maturin backend so pip/maturin builds work` — unblocks the Docker path permanently.

Each step keeps `cargo test` green; no step constructs an unbounded Runner.
