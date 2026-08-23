#!/usr/bin/env python3
"""Post-tool-use hook — CUDA crash detection and persistent learning.

Runs after every tool invocation by an ECC agent. Reads a JSON payload from
stdin containing stdout, stderr, and timestamp fields. Scans for CUDA crash
signatures, and on detection:
  1. Appends a crash instinct record to memory_seeds/crash_instincts.json
  2. Prints a SYSTEM ALERT to stdout for the ECC orchestrator

Always exits 0 — this hook is observational and must never fail the pipeline.

Input (stdin JSON):
  {
    "stdout": "...",
    "stderr": "...",
    "timestamp": "2026-08-15T12:00:00Z"
  }
"""

import json
import re
import sys
from pathlib import Path

# Optional visualizer bridge (fail-open; office may not be running)
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "bin"))
try:
    from office_bridge import office_agent_status, office_event
except Exception:  # noqa: BLE001
    def office_agent_status(*a, **k): return False
    def office_event(*a, **k): return False

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CRASH_INSTINCTS_PATH = (
    Path(__file__).resolve().parent.parent.parent
    / "memory_seeds"
    / "crash_instincts.json"
)

# Patterns that indicate a CUDA crash
CRASH_PATTERNS = [
    re.compile(r"cudaErrorIllegalAddress"),
    re.compile(r"Segmentation fault"),
]

# Context window size (characters) around the crash signature
CONTEXT_WINDOW = 200


# ---------------------------------------------------------------------------
# Crash detection
# ---------------------------------------------------------------------------


def _find_crash(text: str) -> str | None:
    """Search for crash signatures and return a context snippet, or None."""
    for pattern in CRASH_PATTERNS:
        match = pattern.search(text)
        if match:
            start = max(0, match.start() - CONTEXT_WINDOW // 2)
            end = min(len(text), match.end() + CONTEXT_WINDOW // 2)
            return text[start:end].strip()
    return None


# ---------------------------------------------------------------------------
# Crash instincts persistence
# ---------------------------------------------------------------------------


def _load_instincts() -> list[dict]:
    """Load existing crash instincts from disk, or return empty list."""
    try:
        with open(CRASH_INSTINCTS_PATH, "r", encoding="utf-8") as f:
            instincts = json.load(f)
        if isinstance(instincts, list):
            return instincts
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return []


def _save_instincts(instincts: list[dict]) -> None:
    """Write crash instincts to disk, creating parent directories if needed."""
    CRASH_INSTINCTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CRASH_INSTINCTS_PATH, "w", encoding="utf-8") as f:
        json.dump(instincts, f, indent=2)


# ---------------------------------------------------------------------------
# Main hook logic
# ---------------------------------------------------------------------------


def main() -> None:
    """Read tool output from stdin, detect crashes, persist instincts."""
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return
        payload = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        # Malformed input — silently exit
        return

    stdout_text = payload.get("stdout", "")
    stderr_text = payload.get("stderr", "")
    timestamp = payload.get("timestamp", "unknown")

    combined = f"{stdout_text}\n{stderr_text}"

    crash_context = _find_crash(combined)
    if crash_context is None:
        # No crash detected — nothing to do
        return

    # --- Crash detected: persist instinct ---

    instincts = _load_instincts()
    crash_id = f"crash-{len(instincts) + 1}"

    new_instinct = {
        "id": crash_id,
        "content": f"CUDA SEGFAULT detected: {crash_context}",
        "timestamp": timestamp,
        "resolution": (
            "SupervisorD restarted worker; "
            "request routed to Phase 1 Safe Queue."
        ),
    }

    instincts.append(new_instinct)
    _save_instincts(instincts)

    # --- Visualizer: stamp the GPU worker blocked + fire incident moment ---
    office_agent_status("systems-engineer", "blocked", "CUDA crash → Phase 1 Safe Queue")
    office_event("incident-start")

    # --- Alert the orchestrator via stdout ---

    alert = (
        f"\n{'=' * 72}\n"
        f"SYSTEM ALERT: CUDA CRASH DETECTED\n"
        f"{'=' * 72}\n"
        f"Instinct ID : {crash_id}\n"
        f"Timestamp   : {timestamp}\n"
        f"Context     : {crash_context[:120]}...\n"
        f"Action      : Crash instinct written to {CRASH_INSTINCTS_PATH}\n"
        f"Recovery    : SupervisorD will auto-restart the Triton worker.\n"
        f"{'=' * 72}\n"
    )
    print(alert)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Hook must NEVER crash the pipeline
        pass
    sys.exit(0)
