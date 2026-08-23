# systems-engineer — Phase 0.5 Report (ouroboros-triton)

- agent: systems-engineer | worktree: /home/vivek/ouroboros/ouroboros-triton
- constraint pre-check: **ALLOW** — validated against memory_seeds/laws.json via ox-alpha (OpenRouter), 2026-08-17
- mode: DSH-native Phase 0.5 survey (read-only; no source files modified)

## Current State

| File | Status | Notes |
|---|---|---|
| `src/block_table.py` | partial + **buggy** | `BLOCK_SIZE=64` ✓ per sys-blocks law. Basic allocate/free exists but index bookkeeping is broken — see finding below. |
| `src/serving.py` | stub | `Supervisor` and `Worker` are flag-only shells (`is_running` / `is_alive` booleans). No KV-cache or block-table ownership, no health monitoring, no restart path, no Safe Queue routing. |
| `src/kernels/block_attention.py` | empty | 10 lines, entirely commented out. No Triton imports, no kernel. |
| `tests/test_block_table.py` | passing | 4 tests (block size constant, allocate, free, exhaustion). None exercise free→realloc cycles, so the desync bug below is invisible to CI. |
| `pyproject.toml` / `requirements.txt` | minimal | No `[build-system]`, no `setup.py` → the spec'd native build (`setup.py build_ext`) has no entrypoint (confirmed during Docker build attempts). |

**No C++ exists anywhere in the repo**, despite the paper's Module 2 mandate ("C++ array-backed linked list", "CUDA Graph registry in C++") — everything is Python-side so far.

### Finding: BlockTable index desync (confirmed by code reading)

In `allocate_block()`:
```python
block_idx = self.free_list.pop(0)   # e.g. returns 0 after a free
self.blocks.append([0] * self.block_size)   # appends at END of list
self.next_ptr.append(-1)
return block_idx
```
The returned id comes from the free-list, but storage is appended at `len(blocks)-1`. On the first allocation (`blocks == []`) they coincide; **after any free→realloc cycle they diverge**: caller receives block id 0 while its data physically lives at `blocks[1]`. Compounding it:
- `free_block(idx)` only does `free_list.append(idx)` — never clears `blocks[idx]`/`next_ptr[idx]`, so stale payloads survive "deallocation".
- Double-free is accepted silently (id re-enters free-list twice) → two live owners of one block.
- `next_ptr` alignment breaks identically, so future pointer-chasing kernels would traverse wrong chains.

Suggested invariant for the rewrite: block id ⇔ slot index must be identity-mapped (pre-allocated slots array with occupancy flags), and `free_block` must be idempotent-safe (assert not already free).

## Constraint Risk Assessment

1. **sys-blocks (0.99)** — risks during implementation:
   - Reaching for `torch.cat` / `tensor.resize_` when sequences grow — the exact forbidden move. The block table rewrite must expose `expand_sequence()` that allocates a fresh 64-slot block and links it; tests assert tensor shapes never change mid-generation.
   - The current Python `list[list[int]]` blocks are fine for Phase 1 logic tests but the law mandates the production table be C++ (array-backed, cache-coherent). Plan must keep a Python reference implementation for TDD, then bind the C++ one via pybind11 and differential-test both.
2. **hw-gb10 (0.95)** — cannot reproduce locally (dev GPU: RTX 3050 Laptop, Ada sm_89, 4 GB — no ATS unified memory), but the guard is mandatory shipping behavior:
   - CUDA graph capture wrapped in try-catch executing a dummy-tensor warmup pass first (forces TLB page mapping). Add an emulation test: mock a capture failure on first attempt, assert warmup+retry path engages.
   - Keep the graph registry isolated (C++ side) so the workaround lives in exactly one place.
3. **Module 6 HA** — Supervisor/Worker split has no code reality yet. Risk: KV-cache accidentally living inside Worker state → restart loses session. Tests must assert worker restart with preserved supervisor-owned table resumes generation.
4. **4 GB VRAM reality** — Phase 2 experiments must size batches/blocks accordingly (e.g., single-sequence smoke configs); document as a test fixture constraint rather than discovering it at runtime.

## Phase Plan

1. **P0 hygiene**: add `[build-system]`; fix BlockTable bookkeeping (slot-array redesign) with regression tests: alloc→free→alloc returns consistent ids, data isolation between cycles, double-free raises.
2. **Python reference engine**: `BlockTable` gains `expand_sequence(seq, k)` (link new block at logical position), `logical_to_physical(pos)`, iteration over chains — all shape-stable by construction.
3. **C++ core via pybind11**: `block_table.cpp` (array-backed linked list, occupancy bitmap) mirroring the Python API; differential fuzz test Python vs C++ implementations; this becomes the law-compliant production table.
4. **Triton kernel**: fused pointer-chasing attention using `make_block_ptr`: load Q/K blocks via page-table indirection, apply 1D RoPE + additive AST bias + block-sparse scope mask inside SRAM (Module 3/4 fusion point). Start with a correctness harness vs dense PyTorch reference on random small tables.
5. **Static AOT graph dispatch**: one captured graph per 64-token block; CPU loop replays per block-table entry (`Algorithm 2`); try-catch dummy-warmup guard per hw-gb10.
6. **Serving (Module 6)**: Supervisor owns KV-cache + table; stateless workers; crash → SupervisorD-style respawn → affected request routed to Phase 1 Safe Queue.

## First Concrete Steps

1. `fix(m2): make block ids slot-identity mapped; clear state on free` + `test_alloc_free_realloc_cycle_consistency`.
2. `test(m2): double-free detection` then implement the raise.
3. `feat(m2): expand_sequence links new 64-token blocks without any tensor resize` (property test: physical buffer count grows, logical length grows, no `.shape` mutation of payload tensors).
4. `chore(build): PEP-517 build-system so pytest/editable install work`.
5. `feat(m2): pybind11 skeleton for C++ BlockTable with differential test harness`.

Each step keeps `pytest tests/` green and never introduces reshape-based expansion.
