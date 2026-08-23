# =============================================================================
# Ouroboros v7.1 — Unified CI Dockerfile
# =============================================================================
#
# Builds the complete execution environment with exact dependency pins.
# Base: nvidia/cuda:12.6.0-devel-ubuntu24.04
#
# Build order (dependency chain):
#   1. System packages (apt)  →  2. Python packages (pip)
#   3. Rust toolchain (rustup)  →  4. Copy source repos
#   5. Build ouroboros-dfg (Rust/maturin)
#   6. Build ouroboros-triton (C++/setup.py)
#   7. Install ouroboros-core (pip -e)
#   8. Configure SupervisorD
#
# Usage:
#   docker build -t ouroboros-unified -f docker/unified-ci.Dockerfile .
#   docker run --gpus all -e OX_ALPHA_API_KEY -e OX_ALPHA_BASE_URL ouroboros-unified
# =============================================================================

FROM nvidia/cuda:12.6.0-devel-ubuntu24.04

LABEL maintainer="ouroboros-team" \
      version="7.1.0" \
      description="Ouroboros v7.1 Unified CI Environment"

# Prevent interactive prompts during apt-get
ENV DEBIAN_FRONTEND=noninteractive

# ---- Step 1: System packages ------------------------------------------------
# Mirror swap: archive/security.ubuntu.com stall on some ISPs (observed on
# Jio IPv6/IPv4); mirrors.edge.kernel.org is CDN-fronted and fast.
# Acquire::Retries/Timeout: tolerate transient resets.
# ForceIPv4: belt-and-braces against broken v6 routes to the mirror.
RUN sed -i -E 's|http://(archive\|security\|in\.archive)\.ubuntu\.com/ubuntu/?|http://mirrors.edge.kernel.org/ubuntu|g' \
        /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null || true
RUN apt-get update \
        -o Acquire::ForceIPv4=true \
        -o Acquire::Retries=8 \
        -o Acquire::http::Timeout=30 \
        -o Acquire::https::Timeout=30 \
    && apt-get install -y --no-install-recommends \
        -o Acquire::ForceIPv4=true \
        -o Acquire::Retries=8 \
        -o Acquire::http::Timeout=30 \
        -o Acquire::https::Timeout=30 \
        python3.12 \
        python3.12-dev \
        python3.12-venv \
        python3-pip \
        build-essential \
        cmake \
        git \
        curl \
        wget \
        pkg-config \
        libssl-dev \
        clang-18 \
        llvm-18 \
        llvm-18-dev \
        lld-18 \
        supervisor \
        nodejs \
        npm \
    && ln -sf /usr/bin/clang-18 /usr/bin/clang \
    && ln -sf /usr/bin/clang++-18 /usr/bin/clang++ \
    && ln -sf /usr/bin/llvm-config-18 /usr/bin/llvm-config \
    && ln -sf /usr/bin/lld-18 /usr/bin/lld \
    && rm -rf /var/lib/apt/lists/*

# Ensure python3 points to 3.12
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# ---- Step 2a: Pre-fetch CUDA component wheels from pypi.org -------------------
# torch's +cu126 build pulls its nvidia-* dependency wheels via
# download.pytorch.org / pypi.nvidia.com, which stall on some ISPs. Resolve
# the EXACT pinned set via a metadata-only dry run, then install those
# identical versions from pypi.org (Fastly CDN), so the torch step finds
# every dependency satisfied and never touches the slow endpoints.
RUN set -e; \
    for i in 1 2 3 4 5; do \
        if pip3 install --no-cache-dir --dry-run --ignore-installed --quiet \
                --report /tmp/torch-report.json \
                torch==2.6.0+cu126 \
                --index-url https://download.pytorch.org/whl/cu126; then break; fi; \
        echo "WARN: dependency resolution attempt $i failed — retrying"; sleep 10; \
    done; \
    python3 -c "import json;r=json.load(open('/tmp/torch-report.json'));f=open('/tmp/cuda-deps.txt','w');items=[i for i in r.get('install',[]) if i['metadata']['name']!='torch'];[f.write(i['metadata']['name']+'=='+i['metadata']['version']+'\n') for i in items];f.close();print('resolved %d cuda deps' % len(items))"; \
    ok=0; \
    for i in 1 2 3 4 5 6 7 8; do \
        if pip3 install --no-cache-dir --break-system-packages --timeout 120 --retries 10 \
                -r /tmp/cuda-deps.txt; then ok=1; break; fi; \
        echo "WARN: cuda-deps install attempt $i/8 failed — retrying in 20s"; sleep 20; \
    done; \
    [ "$ok" = "1" ] || { echo "FATAL: cuda deps install failed after 8 attempts"; exit 1; }

# ---- Step 2b: PyTorch (large download — retry loop for flaky networks) ------
# Each attempt re-downloads from scratch (pip cannot resume); 8 rounds with a
# wide per-read timeout has proven sufficient on lossy ISP routes.
RUN ok=0; \
    for i in 1 2 3 4 5 6 7 8; do \
        if pip3 install --no-cache-dir --break-system-packages --timeout 180 --retries 20 \
                torch==2.6.0+cu126 \
                --index-url https://download.pytorch.org/whl/cu126; then \
            ok=1; break; \
        fi; \
        echo "WARN: torch install attempt $i/8 failed — retrying in 20s"; \
        sleep 20; \
    done; \
    [ "$ok" = "1" ] || { echo "FATAL: torch install failed after 8 attempts"; exit 1; }

# ---- Step 2c: Remaining Python packages (pinned versions) --------------------
RUN pip3 install --no-cache-dir --break-system-packages --timeout 60 --retries 10 \
        triton==3.2.0 \
        tree-sitter==0.25.0 \
        tree-sitter-languages==1.10.0 \
        mypy==1.13.0 \
        maturin==1.7.0 \
        mcp==1.9.0 \
        requests \
        pyyaml \
        pytest

# ---- Step 3: Rust toolchain (pinned) ----------------------------------------
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain 1.82.0 --profile minimal

# ---- Step 4: Copy source repos ----------------------------------------------
WORKDIR /workspace

# Copy the three source repositories (expected at build context siblings)
COPY ouroboros-dfg/ /workspace/ouroboros-dfg/
COPY ouroboros-triton/ /workspace/ouroboros-triton/
COPY ouroboros-core/ /workspace/ouroboros-core/
COPY ouroboros-v7/ /workspace/ouroboros-v7/

# ---- Step 5: Build ouroboros-dfg (Rust → Python via maturin) -----------------
# Best-effort: skipped with a warning until the dfg repo contains real Rust
# sources (it is currently a Cargo-only skeleton).
WORKDIR /workspace/ouroboros-dfg
RUN if [ -d src ] || [ -f pyproject.toml ]; then \
        cargo add egg@0.9.5 pyo3@0.22.0 \
        && maturin develop --release; \
    else \
        echo "WARN: ouroboros-dfg has no Rust sources yet — skipping maturin build"; \
    fi

# ---- Step 6: Build ouroboros-triton (C++ extensions) -------------------------
# Best-effort: setup.py / PEP-517 build config may not exist in the skeleton.
WORKDIR /workspace/ouroboros-triton
RUN if [ -f setup.py ]; then \
        python3 setup.py build_ext --inplace; \
    elif grep -q "build-system" pyproject.toml 2>/dev/null; then \
        pip3 install --no-cache-dir --break-system-packages -e .; \
    else \
        echo "WARN: ouroboros-triton has no build config yet — skipping native build"; \
    fi

# ---- Step 7: Install ouroboros-core (editable) -------------------------------
WORKDIR /workspace/ouroboros-core
RUN if grep -q "build-system" pyproject.toml 2>/dev/null; then \
        pip3 install --no-cache-dir --break-system-packages -e .; \
    else \
        echo "WARN: ouroboros-core pyproject has no build-system — skipping editable install"; \
    fi

# ---- Step 8: Configure SupervisorD ------------------------------------------
RUN mkdir -p /var/log/ouroboros /etc/supervisor/conf.d
COPY ouroboros-v7/docker/supervisord.conf /etc/supervisor/conf.d/ouroboros.conf

# ---- Step 9: Install orchestrator + worker executables ------------------------
# Minimal implementations shipped in ouroboros-v7/bin (the upstream ECC repo
# provides only an LLM provider library, not an `ecc` CLI).
RUN install -m 0755 /workspace/ouroboros-v7/bin/ecc /usr/local/bin/ecc \
    && install -m 0755 /workspace/ouroboros-v7/bin/ouroboros-worker /usr/local/bin/ouroboros-worker

# ---- Runtime -----------------------------------------------------------------
WORKDIR /workspace/ouroboros-v7

# ox-alpha API configuration must be provided at runtime (-e flags in launch.sh)
ENV OX_ALPHA_API_KEY="" \
    OX_ALPHA_BASE_URL="" \
    OX_ALPHA_MODEL="ox-alpha" \
    ECC_BUDGET="0.00"

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/ouroboros.conf"]
