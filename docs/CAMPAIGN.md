# Ouroboros v7.1 — Phase 1 Campaign (Waves 0–8)

One-paragraph summary of each orchestration wave executed through the DSH
harness (ox-alpha via OpenRouter). Source of record:
[`.ecc/reports/WAVELOG.md`](../.ecc/reports/WAVELOG.md) — test counts there are
independently verified by the orchestrator, not just agent claims. Hardware- and
environment-bound deferrals live in
[`.ecc/reports/DEFERRED.md`](../.ecc/reports/DEFERRED.md).

## Wave 0 — Bootstrap

The stack was rewired from DeepSeek/Groq to ox-alpha via OpenRouter
(`stealth/ox-alpha`, $0/M), the constraint validator was ported into
`codegraph_server.py` with reasoning-model awareness, and Phase 0.5 surveys were
completed for all three repos — `laws.json` validated each specialist's intent,
returning **ALLOW ×3**. The Docker path was hardened (mirror swap, retry loops)
but parked in favor of DSH-native mode, in which the harness session itself is
the orchestrator.

## Wave 1 — First concrete steps

The first orchestrator-executed landings touched all three repos at once: core
gained `front_pack()` (Algorithm 1 lines 1–2) plus a PEP-517 build system
(12/12 tests); triton killed a BlockTable desync bug with a slot-identity
rewrite and added double-free rejection (9/9); dfg got law-pinned `RunnerLimits`
in `limits.rs` together with a drift guard (5/5, plus 5 pre-existing).

## Wave 2 — Parallel specialists

The first successful parallel subagent run landed three lanes simultaneously.
Core added `MASK_ID`/`IGNORE_ID` sentinels, `insert_masks` ([EXPAND]),
`logical_delete` ([DELETE]) and `derive_mask` (**29/29**). Triton delivered the
chain manager — `allocate_chain`/`walk`/`chain_len`/`expand_chain` with
orphan-proof [EXPAND] and all-or-nothing failure semantics (**24/24**). DFG
built `engine.rs`: an `EggEngine` with a law-pinned Runner +
BackoffScheduler and `verify() → Equivalent/Unproven`, egg APIs cited from
local crate source (**14/14**).

## Wave 3 — In flight → landed

Three specialist lanes ran in parallel: core authored Module 4 `src/scoping.py`
(block-sparse mask per Table 1, pure Python; **59/59**, orchestrator
spot-check PASS); triton began the fused Triton `make_block_ptr` kernel (RoPE +
AST bias + scoping mask in-SRAM) with an importorskip harness, plus a C++
BlockTable scaffold behind a pybind11 parity harness; dfg shipped async tokio
isolation (`spawn_blocking`, <50 ms poll latency under saturation) and the SRE
green/yellow telemetry sink (JSONL) for **25/25** cargo. Hardware-bound items
were documented honestly rather than faked — GB10 sm_121a warmup, real GPU
kernel execution — creating `DEFERRED.md`. While CPU torch trickled down over a
resumable curl (~100 KB/s), the orchestrator itself authored Module 3
`src/attention.py` (1D RoPE + additive AST bias + a `math-rope` structural
guard rejecting 2D position grids), and the PyO3 wheel (`ouroboros_dfg`)
was verified end-to-end from Python: equivalent / unproven / law_limits all PASS.

## Wave 4 — torch live, all green

With torch-cpu 2.13.0 installed, Module 3 attention tests went LIVE (core
69/69). Core then landed Coupled-GRPO `src/grpo.py` — antithetic pairs by
construction, 3-stage curriculum, coupled reward reuse — for **95/95**
(26 new). Triton delivered Module 6 HA serving: Supervisor owns BlockTable +
kv_cache through a single `table_op` door, purity-enforced stateless workers,
and WorkerCrash → Safe Queue sentinel + FIFO drain (**64 passed / 10
skipped-by-design / 0 failed**). DFG added `rules.rs` (bidirectional De Morgan
×2, double-negation, add-zero/mul-one) plus `verify_telemetry`; **35/35** cargo
with PyO3 re-verified from Python after a wheel rebuild.

## Wave 5 — Module 1 complete

Core completed Module 1: AST-aware `tokenize`/`tokenize_with_nodes`/Vocab and
`ast_spd_matrix` (BFS φ for b_phi), **113/113** (18 new). Triton integrated HA
with BlockTable — chain allocation per request, zero-leak crash handling,
[EXPAND] `expand_request`, re-dispatching drain — at **70/10skip/0fail**. DFG's
`ssa.rs` introduced the SSA DFG IR (Value/Op/Ssa with `uses()`, straight-line
dominance, use-before-def rejection, constant-fold `evaluate`), taking cargo to
**43/43**; `bin/ecc` gained a verify-pair wired to the PyO3 verifier.

## Wave 6 — Training scaffold, oracle, SSA→egg bridge

Core added the GRPO training scaffold `src/training.py` (PhantomPolicy +
antithetic `grpo_step`; loss finite, weights move, zero-advantage ⇒ zero-delta;
**124/124**). Triton built the golden-reference attention oracle
(`reference_attention.py`, 23 tests; **93 passed/10 skipped**) — its scoping
semantics mirror kernel-local masking, so alignment with core's `scoping.py`
was flagged for review. DFG bridged SSA into egg (`ssa_bridge.rs::to_rec_expr`,
`verify_ssa_roots`/`verify_ssa`/`verify_ssa_telemetry`; **62/62**), and the
verify-manifest gate went live in `bin/ecc`. Early Wave-7 work also landed:
triton's `scoping_mask.py` Table-1 port, bit-for-bit aligned to core across 6
layouts, plus two e2e masked golden-attention tests (**116 passed/10 skipped**).

## Wave 7 — Algorithm 1 loop + Python frontend

Core implemented the Algorithm 1 Phantom Loop in `src/diffusion.py` —
policy-driven [EXPAND]/[DELETE]/KEEP with the shape law enforced in every step
and delete-driven convergence (**143/143**, 19 new). Triton consolidated the
masked golden-attention e2e path on the Table-1-aligned scoping mask
(**116 passed/10 skipped**). DFG shipped `frontend_python.rs`, lowering a
Python subset (assign/arith/unary) into SSA via tree-sitter 0.25.10 + grammar
0.23.6 (**75/75**, 13 new).

## GPU verification milestone (Lightning-free path)

Using a Colab T4 reached through a bore tunnel and a git push/pull loop — no
paid Lightning — the **full triton suite ran on real hardware: 120 passed /
6 skipped (C++ parity only) / 0 failed**. Kernel-vs-golden-reference agreement
was confirmed after three remote-debugged fixes (`_as_int32` name argument,
RoPE broadcast axis in `dense_reference`, finite `-1e30` masking replacing NaN
poison). DEFERRED.md item #2 (Triton kernel execution) flipped to RESOLVED.

## Wave 8 — First real learning run ✅

Core landed `curriculum_data.py` (AST-derived gap ground truth) and
`train_loop.py` (masked gap-only REINFORCE via coupled rewards, with
checkpointing), and **learning was proven**: held-out EXPAND@gap accuracy rose
0.107 → 0.209 (**2.0×** on an independent orchestrator run with a fresh seed;
agent-reported ×2.8 across 5 policy seeds). Triton added
`scripts/demo_serving.py` exercising 12 requests with a mid-stream crash
against 6 Module-6 HA invariants — served-exactly-once, blast-radius-1, zero
leaks, FIFO drain (**121 passed/10 skipped**). Final suites: core **163** ·
triton **121+10skip** · dfg **75**, all green. The wave closed honestly: the
curriculum corruption was redesigned around single-token holes after
whole-statement gaps proved information-theoretically ambiguous for trigram
features; the learning proof was recast as robust paired-lift (>0.01 absolute
on the same held-out set); and the scaffold ceiling was documented — the
trigram-mean readout saturates at ~0.15–0.16 gap-localization accuracy, making
an attention-based placement head over candidate sites the next architecture
step (tracked in DEFERRED.md).
