# Ouroboros v7.1 — Autonomous Orchestrator

Production-ready orchestrator infrastructure for the Ouroboros v7.1 code refactoring engine. Coordinates three specialized AI agents across three repositories, validates every code change against architectural constraints, and learns from GPU crashes.

## Architecture

```
launch.sh
  └─ Docker (nvidia/cuda:12.6)
       └─ SupervisorD
            ├─ ECC Orchestrator (ox-alpha via OpenAI-compatible API)
            │    ├─ tdd-guide         → ouroboros-core    (Python/PyTorch)
            │    ├─ systems-engineer   → ouroboros-triton  (C++/Triton)
            │    └─ rust-specialist    → ouroboros-dfg     (Rust/egg)
            │
            └─ Triton Worker (auto-restarts on crash)

MCP Servers:
  ├─ codegraph_server  → Constraint validation (ox-alpha)
  └─ context7           → Documentation lookup

Hooks:
  └─ post_tool_use.py  → CUDA crash detection → crash_instincts.json
```

## Prerequisites

- **NVIDIA GPU** with CUDA 12.6 support
- **Docker** with [`nvidia-container-toolkit`](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- **API Configuration** (OpenAI-compatible ox-alpha API):
  - `OX_ALPHA_BASE_URL` — e.g. `https://api.example.com/v1`
  - `OX_ALPHA_API_KEY` — bearer token
  - `OX_ALPHA_MODEL` — model id (default: `ox-alpha`)
- **Source repositories** (sibling directories):
  - `ouroboros-core/` — Python/PyTorch diffusion engine
  - `ouroboros-triton/` — C++/Triton bare-metal engine
  - `ouroboros-dfg/` — Rust semantic verifier

## Quick Start

```bash
# 1. Point at the ox-alpha OpenAI-compatible API
export OX_ALPHA_BASE_URL="https://api.example.com/v1"
export OX_ALPHA_API_KEY="your-ox-alpha-key"
# optional: export OX_ALPHA_MODEL="ox-alpha"

# 2. Make launch script executable
chmod +x launch.sh

# 3. Launch
./launch.sh
```

The script will:
1. Validate that API keys are set
2. Build the Docker image with all pinned dependencies
3. Start the container with GPU passthrough
4. SupervisorD launches the ECC orchestrator and Triton worker

Monitor progress:
```bash
docker logs -f ouroboros-runtime
```

## Project Structure

```
ouroboros-v7/
├── bin/
│   ├── ecc                     # Minimal orchestrator runner (ox-alpha)
│   └── ouroboros-worker        # Minimal supervised GPU worker
├── memory_seeds/
│   ├── laws.json              # Architectural constraints (Super Memory Seed)
│   └── crash_instincts.json   # Persistent crash learning (auto-generated)
├── .mcp/
│   └── servers/
│       └── codegraph_server.py # MCP server for constraint validation
├── .ecc/
│   ├── config.yaml            # ECC orchestrator configuration
│   └── hooks/
│       └── post_tool_use.py   # CUDA crash detection hook
├── docker/
│   ├── unified-ci.Dockerfile  # Full build environment
│   └── supervisord.conf       # Process management
├── launch.sh                  # One-click startup
└── README.md                  # This file
```

## Running Modes

### DSH-native (default on this machine)

No Docker required — the DeepSeek Harness session itself is the orchestrator
(ox-alpha model, subagents, background jobs, budget-free):

1. Constraint-validate an intent against `memory_seeds/laws.json` via
   `bin/ecc`'s validator path or a direct OpenRouter call (`stealth/ox-alpha`).
2. Dispatch each specialist as a harness subagent with the system prompts from
   `.ecc/config.yaml`.
3. Reports land in `.ecc/reports/<agent>.phase<N>.md`.

### Docker (production / Module 6 HA)

```bash
export OX_ALPHA_BASE_URL="https://openrouter.ai/api/v1"
export OX_ALPHA_API_KEY="your-ox-alpha-key"
./launch.sh
```

## Agent Virtual Office (live visualization)

Watch the team work in a pixel office:

```bash
npx github:KbWen/agent-virtual-office --no-host   # localhost-only
# open http://localhost:5174/?agents=tdd-guide:dev,systems-engineer:ops,rust-specialist:qa,orchestrator:pm,codegraph:gate
```

Role mapping lives in `bin/office_bridge.py`. `bin/ecc` and the
`.ecc/hooks/post_tool_use.py` crash detector push statuses automatically
(working / blocked / done, incidents); anything can push manually:

```bash
python3 bin/office_bridge.py status tdd-guide working "Implementing tokenizer"
python3 bin/office_bridge.py event test-passed
```

All bridge calls fail-open — the office is optional sugar, never a dependency.

## Configuration

### Architectural Laws (`memory_seeds/laws.json`)

Four inviolable constraints validated before every code change:

| Law | Constraint | Confidence |
|-----|-----------|------------|
| `math-rope` | 1D RoPE + Additive AST Graph Bias (no 2D RoPE) | 0.99 |
| `sys-blocks` | 64-token block linked lists (no tensor reshapes) | 0.99 |
| `hw-gb10` | Grace Blackwell CUDA graph try-catch warmup | 0.95 |
| `egraph-limits` | Hardcoded egg::Runner resource limits | 0.99 |

### Orchestrator (`config.yaml`)

- **Model**: ox-alpha via OpenAI-compatible API (`OX_ALPHA_BASE_URL` / `OX_ALPHA_API_KEY`)
- **Budget**: disabled by default (ox-alpha via OpenRouter is free) — set `ECC_BUDGET` (e.g. `10.00`) to enforce a USD cap on estimated spend
- **Agents**: 3 specialists, each bound to one worktree
- **Runner**: `bin/ecc` — minimal orchestrator CLI installed as `/usr/local/bin/ecc`
- **MCP Servers**: codegraph (ox-alpha) + Context7 (docs)

### Crash Learning (`post_tool_use.py`)

Automatically detects CUDA segfaults (`cudaErrorIllegalAddress`, `Segmentation fault`) in tool output, writes instinct records to `crash_instincts.json`, and triggers SupervisorD worker restarts.

## Cost Monitoring

The orchestrator enforces a budget limit (default: $10.00 USD). To adjust:

```bash
export ECC_BUDGET="20.00"
./launch.sh
```

The orchestrator pauses and requests confirmation if the budget is exceeded.

## Dependency Versions

| Package | Version |
|---------|--------|
| Python | 3.12.x (Ubuntu noble) |
| Rust | 1.82.0 |
| PyTorch | 2.6.0+cu126 |
| Triton | 3.2.0 |
| tree-sitter | 0.25.0 |
| mypy | 1.13.0 |
| maturin | 1.7.0 |
| egg | 0.9.5 |
| clang/llvm | 18 |

## Reference

See the [Ouroboros v7.1 Specification](https://ouroboros.dev/spec/v7.1) for the complete system design.
