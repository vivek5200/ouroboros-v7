#!/usr/bin/env bash
# lightning_bootstrap.sh — run INSIDE a Lightning AI Studio (or any CUDA box)
# after `git clone`ing the four Ouroboros repos into the same directory.
#
# Usage:
#   bash lightning_bootstrap.sh [parent_dir_of_repos]
#
# What it does:
#   1. Installs CUDA torch + triton + pytest (skips pieces already present).
#   2. Runs scripts/gpu_verify_kit.sh across ouroboros-triton.
set -u
PARENT="${1:-$(pwd)}"
V7="$PARENT/ouroboros-v7"
[ -d "$V7" ] || { echo "FATAL: $V7 not found — clone the four repos into $PARENT first"; exit 1; }

echo "=== Ouroboros Lightning bootstrap ==="
echo "parent: $PARENT"

echo "--- 1. python deps (CUDA torch ~2.5GB; resumable pip retries below) ---"
python3 -c "import torch" 2>/dev/null || {
  ok=0
  for i in 1 2 3 4 5 6; do
    pip install torch triton pytest --index-url https://download.pytorch.org/whl/cu124 && { ok=1; break; }
    echo "attempt $i failed — retrying in 20s"; sleep 20
  done
  [ $ok = 1 ] || { echo "FATAL: torch install failed after 6 attempts"; exit 1; }
}
python3 - <<'EOF'
import torch, triton
print("torch:", torch.__version__, "| cuda:", torch.cuda.is_available(),
      "|", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "-")
print("triton:", triton.__version__)
assert torch.cuda.is_available()
EOF

echo "--- 2. GPU verification kit ---"
bash "$V7/scripts/gpu_verify_kit.sh" "$PARENT"
