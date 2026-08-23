#!/usr/bin/env bash
# colab_gpu_verify.sh — run inside a Google Colab GPU (T4) notebook cell:
#
#   !git clone https://${GH_TOKEN}@github.com/vivek5200/ouroboros-v7.git
#   !cd ouroboros-v7/scripts && bash colab_gpu_verify.sh
#
# Requires GH_TOKEN env var (classic PAT with `repo` scope) for the four
# PRIVATE repos. Clones all repos, installs anything missing, runs
# gpu_verify_kit.sh, saves results log.
set -u
[ -n "${GH_TOKEN:-}" ] || { echo "FATAL: set GH_TOKEN first (github.com/settings/tokens, scope: repo)"; exit 1; }

H="https://x-access-token:${GH_TOKEN}@github.com/"
for r in ouroboros-core ouroboros-triton ouroboros-dfg ouroboros-v7; do
  [ -d "$r" ] || git clone -q "${H}vivek5200/$r.git"
done

python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null && \
  echo "torch+CUDA present" || pip install -q torch --index-url https://download.pytorch.org/whl/cu124
python3 -c "import triton" 2>/dev/null || pip install -q triton
python3 -c "import pytest" 2>/dev/null || pip install -q pytest

bash ouroboros-v7/scripts/gpu_verify_kit.sh "$(pwd)" 2>&1 | tee gpu_verify_results.log
echo "=== results saved to $(pwd)/gpu_verify_results.log ==="
