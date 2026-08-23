# tdd-guide — Phase 0.5 Report (ouroboros-core)

- agent: tdd-guide | worktree: /home/vivek/ouroboros/ouroboros-core
- constraint pre-check: **ALLOW** — validated against memory_seeds/laws.json via ox-alpha (OpenRouter), 2026-08-17
- mode: DSH-native Phase 0.5 survey (read-only; no source files modified)

## Current State

Inventory of every file in the worktree:

| File | Status | Notes |
|---|---|---|
| `src/tokenizer.py` | partial | `L_MAX = 1024` correct per spec (Algorithm 1). `phantom_pad()` fully implemented: truncates over-length, right-pads with `pad_id=0` to exactly `L_MAX`. `tokenize()` raises `NotImplementedError` — no AST-aware tokenization at all. |
| `src/attention.py` | stub | `ASTGraphBiasAttention.__init__` stores `d_model`, `n_heads`, `head_dim`; **no weights, no projections, no RoPE tables, no bias injection**. `forward()` raises `NotImplementedError`. Docstring correctly encodes the math-rope law. |
| `src/reward.py` | complete | Exact Fuzzy Proxy Eq. 7: constants `ALPHA_PARSES=0.1`, `BETA_TYPECHECKS=0.3`, `GAMMA_TESTS=0.6`; `compute_reward()` returns weighted sum in [0.0, 1.0]. Matches spec verbatim. |
| `tests/test_tokenizer.py` | passing | 3 tests: short-sequence padding, exact-length identity, truncation of L_MAX+100. All exercise only `phantom_pad`. |
| `tests/test_reward.py` | passing | 4 tests pin the exact weights (1.0 / 0.0 / 0.1 / 0.4 combinations) with 1e-9 tolerance. |
| `pyproject.toml` | minimal | name/version/description + pytest config only. No `[build-system]`, no package discovery → `pip install -e .` fails (observed during Docker build attempts). |
| `requirements.txt` | present | unpinned helper list; not used by Dockerfile pins. |

Summary: **2 of 3 owned modules are non-functional** (tokenizer half-done, attention empty). Reward is production-ready and law-pinned by tests.

## Constraint Risk Assessment

1. **math-rope (confidence 0.99)** — highest risk lives in Module 3 implementation temptations:
   - Splitting `head_dim` channels into two rotated groups keyed on `(AST depth, sibling index)` is the forbidden 2D construction. Tests must structurally forbid it: assert attention scores depend on lexical offset via 1D RoPE only, and that AST influence enters *additively* in pre-softmax logits (`A_ij = Softmax(QK/√dk + b_φ(i,j))`).
   - The SPD matrix `φ(i,j)` must come from tree-sitter shortest-path distance with log/normalized compression; risk of accidentally re-introducing per-channel rotation when fusing bias into kernels later (Phase 2 hand-off).
   - Pin with a property test: for two token pairs with equal `(d,l)` coordinates but different subtree roots, scores differ only through `b_φ`.
2. **Phantom Padding discipline** — `tokenize()` is where sequence lengths first vary. Risk: eager trimming/padding that violates front-packing semantics of Algorithm 1 (`FrontPack(x, L_max)` then logical `[IGNORE]` tail). Tests must assert buffer shape is *always* `(L_max,)` and `[EXPAND]` mutation happens in-place (index write), never a resize.
3. **Reward drift** — low risk (implemented + tested), but Coupled-GRPO antithetic pairing (`m⁽¹⁾ ∪ m⁽²⁾ = 1`, disjoint) has zero code or tests yet; a naive reward-hacker could rescale weights. Add a frozen-constants conformance test mirroring `test_reward.py` style.
4. **Packaging** — missing `[build-system]` blocks CI/install paths (already bit us in the Docker build). Trivial fix, do it first so `pip install -e .` works before any feature commits.

## Phase Plan

TDD order (each step: test first, then implementation):

1. **P0 packaging**: add `[build-system]` (setuptools, src-layout discovery) → test: editable install succeeds in CI.
2. **Module 1 completion**:
   a. `tests/test_tokenizer.py::test_tokenize_basic` — vocabulary contract for identifiers/keywords/literals on a golden Python snippet.
   b. Implement AST-aware `tokenize()` using tree-sitter (Python grammar): token stream carries `(lexical_pos, ast_node_id)`.
   c. `test_front_pack` — new `front_pack()` helper returning fixed `(1024,)` buffer + logical mask; Algorithm 1 lines 1–2.
3. **Module 3**:
   a. `test_rope_is_1d` — rotation depends only on lexical position difference (Eq. 3 property).
   b. `test_bias_additive_pre_softmax` — with `W_Q=W_K=I`, logits == raw dot products + `b_φ(i,j)` exactly.
   c. Implement `ASTGraphBiasAttention.forward`: q/k projections → 1D RoPE → `+ b_φ` → masked softmax → out projection. Bias built by a pure-Python `ast_spd_bias(tokens, tree)` helper (log-compressed), unit-tested separately against NetworkX-computed tree distances.
4. **Module 4 extension**:
   a. `test_coupled_grpo_pairs` — antithetic masks are complements, union covers sequence.
   b. Implement mask sampler; keep `compute_reward` untouched (frozen by existing tests).
5. **Curriculum hooks**: three dataset builders (syntactic boundaries / trivial subtrees / macro-migrations) as pure functions with round-trip tests.

## First Concrete Steps

1. `chore(build): add PEP-517 build-system to pyproject` + smoke test that `pip -e .` imports `src.tokenizer`.
2. `feat(m1): tokenize() via tree-sitter with (pos, node_id) pairs` — preceded by `test_tokenize_golden_python_snippet`.
3. `feat(m1): front_pack() fixed-buffer entry for Phantom Padding loop` — preceded by `test_front_pack_shape_and_mask`.
4. `feat(m3): 1D RoPE helper with relative-offset property test` (no attention surgery yet).
5. `feat(m3): additive AST graph bias from tree-sitter SPD matrix` — preceded by `test_spd_matches_reference_distances`.

Each commit keeps `pytest tests/` green; no step touches tensor-resize patterns (sys-blocks hygiene even in Phase 1).
