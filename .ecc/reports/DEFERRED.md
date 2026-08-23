# Ouroboros v7.1 — Deferred & Hardware-Bound Items

Honest ledger of what Phase 1 on this machine (RTX 3050 Laptop, Ada sm_89,
4 GB VRAM, no torch/triton at authoring time) **cannot** implement or verify
locally, and what exists instead. Nothing here is silently faked.

## 1. Grace Blackwell sm_121a ATS/TLB warmup path (`hw-gb10`, confidence 0.95)

- **Cannot reproduce**: requires GB10 unified memory (LPDDR5x + ATS demand paging).
  The failure mode (`cudaErrorIllegalAddress` during first capture before TLB init)
  does not exist on Ada discrete GPUs.
- **Exists instead**: warmup-guard mandate encoded in
  - `bin/ouroboros-worker` (dummy-tensor matmul before any real work),
  - `systems-engineer` Phase 0.5 report §Constraint Risk (try-catch capture spec),
  - Wave 3 C++ scaffold comment block (graph registry isolation point).
- **Verification deferred to**: GB10 hardware or CI runner with unified memory.

## 2. Triton kernel GPU execution

- Kernel source authored law-compliantly (`make_block_ptr`, additive AST bias,
  scoping mask fused in-SRAM) with correctness harness.
- **Cannot execute locally**: no triton/torch installed at authoring time; RTX 3050
  4 GB constrains sizes even when installed.
- **Exists instead**: `pytest.importorskip("triton")` harness + dense-reference
  comparison test that activates automatically wherever triton+GPU exist.

## 3. AOT CUDA Graph static dispatch loop (paper §4.4)

- Capture/replay requires CUDA context; host verification impossible until
  torch+CUDA validated on-device.
- **Exists instead**: Algorithm 2 dispatch design documented in chain-manager API
  notes (`allocate_chain` all-or-nothing semantics chosen specifically so the
  CPU-side replay loop can catch-and-retry safely).

## 4. Real-scale diffusion training (Module 1 RL loop, Coupled-GRPO)

- 4 GB VRAM cannot hold meaningful batch × L_max=1024 training runs.
- **Exists instead**: buffer primitives fully implemented + property-tested;
  curriculum dataset builders remain future work when compute allows.

## Verification matrix

| Item | Source authored | Locally tested | Needs |
|---|---|---|---|
| Block-sparse mask (M4) | ✅ | ✅ 59/59 core | — |
| egg engine + limits (M5) | ✅ | ✅ cargo | — |
| Async isolation + telemetry | ✅ | ✅ cargo | — |
| Triton kernel (M2/M3 fusion) | ✅ | ⏸ skips | triton + any CUDA GPU |
| C++ block table parity | ✅ scaffold | ⏸ skips | pybind11 build |
| GB10 warmup path | 📋 spec only | ❌ impossible here | sm_121a hardware |
| Coupled-GRPO training | ❌ future | ❌ | >4 GB VRAM GPU |

## 5. C++ BlockTable parity EXECUTION (added round 13)

- Source fully authored (`src/cpp/block_table.{h,cpp}`, `bindings.cpp`, `build.sh`);
  tests skip-guarded and green.
- **Execution blocked**: host lacks `python3.12-dev` (no `Python.h`) and has no
  passwordless sudo to install it. g++ 13 present; pybind11 installed.
- **Unblocks with**: `sudo apt install python3.12-dev` → `bash src/cpp/build.sh`
  → parity suite activates automatically.
