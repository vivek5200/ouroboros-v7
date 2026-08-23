#!/usr/bin/env python3
"""office-bridge — pushes Ouroboros orchestration state to Agent Virtual Office.

Agent Virtual Office (https://github.com/KbWen/agent-virtual-office) renders a
pixel office where each character mirrors a real agent. This bridge maps the
Ouroboros v7.1 team onto AVO roles:

    tdd-guide        -> dev     (ouroboros-core, Python/PyTorch)
    systems-engineer -> ops     (ouroboros-triton, kernels/build/serving)
    rust-specialist  -> qa      (ouroboros-dfg, semantic verification)
    orchestrator/ecc -> pm      (pipeline coordination)
    codegraph        -> gate    (constraint validation gate)

Design notes:
  - Statuses are EPHEMERAL in AVO by design ('done' celebrates ~10s, then the
    character returns to idle; working/blocked expire after ~5 min). This
    bridge therefore keeps a SHARED STATE FILE and a `watch` keepalive mode
    that re-posts the current truth every tick, so long-running sessions stay
    lit without faking anything: the state file only ever contains statuses
    some Ouroboros process actually set.
  - Every POST carries the FULL agent map (merge, not replace).
  - All functions fail OPEN: if the office isn't running they silently no-op.

State file: /tmp/ouroboros-office-state.json  ({role: {status, label}})

CLI:
    python3 office_bridge.py status <agent> <status> [label]
    python3 office_bridge.py event <name>
    python3 office_bridge.py watch [interval_s]     # keepalive daemon

Environment:
    OFFICE_URL    base URL of the office (default http://localhost:5174)
    OFFICE_STATE  state file path override
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.request

OFFICE_URL = os.environ.get("OFFICE_URL", "http://localhost:5174").rstrip("/")
STATE_PATH = os.environ.get("OFFICE_STATE", "/tmp/ouroboros-office-state.json")

# Ouroboros agent name -> AVO character role
ROLE_MAP = {
    "tdd-guide": "dev",
    "systems-engineer": "ops",
    "rust-specialist": "qa",
    "orchestrator": "pm",
    "ecc": "pm",
    "codegraph": "gate",
}


# ---------------------------------------------------------------------------
# Shared state (merged across all Ouroboros processes via the state file)
# ---------------------------------------------------------------------------


def _load_state() -> dict:
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


def _save_state(state: dict) -> None:
    try:
        with open(STATE_PATH, "w", encoding="utf-8") as f:
            json.dump(state, f)
    except Exception:  # noqa: BLE001
        pass


def _post(path: str, payload: dict) -> bool:
    """Fire-and-forget POST; returns True on 2xx, never raises."""
    try:
        req = urllib.request.Request(
            f"{OFFICE_URL}{path}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=2) as resp:
            return 200 <= resp.status < 300
    except Exception:  # noqa: BLE001 — visualization must never break the pipeline
        return False


def _map_role(name: str) -> str:
    return ROLE_MAP.get(name.lower(), name.lower())


def push_full_state(state: dict | None = None) -> bool:
    """POST the complete current agent map (single authoritative update)."""
    state = state if state is not None else _load_state()
    agents = [
        {"role": role, "status": info["status"],
         **({"label": info["label"]} if info.get("label") else {})}
        for role, info in sorted(state.items())
        if isinstance(info, dict) and info.get("status")
    ]
    if not agents:
        return False
    workflow = "Ouroboros v7.1"
    return _post("/api/status", {"type": "office-status",
                                 "agents": agents,
                                 "workflow": workflow})


def set_status(agent_statuses: dict[str, str], label: str = "",
               workflow: str = "") -> bool:
    """Merge one or more agent statuses into shared state and push everything."""
    state = _load_state()
    for name, status in agent_statuses.items():
        role = _map_role(name)
        entry = {"status": status}
        if label:
            entry["label"] = label
        state[role] = entry
    _save_state(state)
    ok = push_full_state(state)
    if workflow:
        ok = _post("/api/status", {"workflow": workflow}) or ok
    return ok


def office_status(agent_statuses: dict[str, str], label: str = "",
                  workflow: str = "") -> bool:
    """Alias kept for bin/ecc compatibility."""
    return set_status(agent_statuses, label=label, workflow=workflow)


def office_agent_status(agent: str, status: str, label: str = "") -> bool:
    """Status for a single Ouroboros agent by its own name."""
    return set_status({agent: status}, label=label)


def office_event(name: str) -> bool:
    """Fire a predefined moment: test-passed, build-failed, deploy-success, ..."""
    return _post("/api/event", {"event": name})


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    if args[0] == "status" and len(args) >= 3:
        agent, status = args[1], args[2]
        label = args[3] if len(args) > 3 else ""
        return 0 if office_agent_status(agent, status, label) else 1
    if args[0] == "event" and len(args) >= 2:
        return 0 if office_event(args[1]) else 1
    if args[0] == "watch":
        interval = float(args[1]) if len(args) > 1 else 25.0
        print(f"[office-bridge] keepalive: posting {_load_state().keys().__len__()}"
              f" agent(s) every {interval}s from {STATE_PATH}", flush=True)
        while True:
            if push_full_state():
                time.sleep(interval)
            else:
                time.sleep(min(interval, 10))
    return 2


if __name__ == "__main__":
    sys.exit(main())
