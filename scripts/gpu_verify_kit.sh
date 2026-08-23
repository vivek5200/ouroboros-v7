#!/usr/bin/env bash
# gpu_verify_kit.sh — run every GPU-gated Ouroboros test on a CUDA machine.
#
# Designed for Lightning AI / Colab / any box with:
#   NVIDIA GPU + torch (CUDA build) + triton + pytest
#
# Usage:
#   bash gpu_verify_kit.sh [repo_root]     # default: script's parent dir
#
# What it does:
#   1. Prints GPU/environment facts.
#   2. Activates the tests that skip on CPU-only machines:
#      - ouroboros-triton: Triton kernel correctness vs golden reference
#      - C++ parity if pybind11+Python.h happen to be present
#   3. Exits non-zero if any activated test fails.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
echo "=== Ouroboros GPU verification kit ==="
echo "repo root : $ROOT"

echo "--- environment ---"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null \
  || { echo "FATAL: nvidia-smi unavailable — is this a GPU machine?"; exit 1; }
python3 - <<'EOF'
import torch, triton
print("torch :", torch.__version__, "| cuda:", torch.cuda.is_available(),
      "| device:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "-")
print("triton:", triton.__version__)
assert torch.cuda.is_available(), "CUDA not available to torch"
EOF
[ $? -ne 0 ] && exit 1

echo "--- triton kernel vs golden reference ---"
cd "$ROOT/ouroboros-triton"
python3 -m pytest tests/test_block_attention.py tests/test_reference_attention.py -q

echo "--- full triton suite (skips should now be zero) ---"
python3 -m pytest tests/ -q

echo "--- C++ parity (optional; needs Python.h) ---"
if python3 -c "import sysconfig,os; assert os.path.exists(os.path.join(sysconfig.get_path('include'),'Python.h'))" 2>/dev/null; then
  bash src/cpp/build.sh && python3 -m pytest tests/test_cpp_parity.py -q
else
  echo "SKIP: Python.h missing (apt install python3.12-dev to activate)"
fi

echo "=== kit complete ==="
