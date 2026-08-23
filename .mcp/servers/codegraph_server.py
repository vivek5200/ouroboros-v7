#!/usr/bin/env python3
"""Codegraph MCP Server — Constraint validation via the ox-alpha model.

Exposes a single MCP tool `validate_constraint` that checks proposed code
changes against the Ouroboros v7.1 architectural laws before any agent
writes memory allocation, attention, or verification code.

Protocol: MCP over stdio
External API: ox-alpha (OpenAI-compatible POST {OX_ALPHA_BASE_URL}/chat/completions)
Model: ${OX_ALPHA_MODEL} (default: ox-alpha) | Temperature: 0.0 | Max tokens: 128
Fallback: fail-open (ALLOW with error annotation) on ox-alpha errors
"""

import json
import os
import sys
from pathlib import Path

import requests
from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

OX_ALPHA_BASE_URL = os.environ.get("OX_ALPHA_BASE_URL", "").rstrip("/")
OX_ALPHA_MODEL = os.environ.get("OX_ALPHA_MODEL", "ox-alpha")
OX_ALPHA_TIMEOUT_S = float(os.environ.get("OX_ALPHA_TIMEOUT_S", "60"))
# NOTE: stealth/ox-alpha is a reasoning model (reasoning cannot be disabled).
# max_tokens must leave room for internal reasoning (~300+ tokens) or
# `content` comes back empty. Do not lower this below ~512.
OX_ALPHA_MAX_TOKENS = int(os.environ.get("OX_ALPHA_MAX_TOKENS", "1000"))

LAWS_PATH = Path(__file__).resolve().parent.parent.parent / "memory_seeds" / "laws.json"

VALID_REPOS = frozenset({"ouroboros-core", "ouroboros-triton", "ouroboros-dfg"})

# ---------------------------------------------------------------------------
# Load laws once at module import
# ---------------------------------------------------------------------------


def _load_laws() -> list[dict]:
    """Read architectural laws from the Super Memory Seed."""
    try:
        with open(LAWS_PATH, "r", encoding="utf-8") as f:
            laws = json.load(f)
        if not isinstance(laws, list) or not laws:
            print(f"[codegraph] WARNING: {LAWS_PATH} is empty or not a list", file=sys.stderr)
            return []
        return laws
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        print(f"[codegraph] ERROR loading laws: {exc}", file=sys.stderr)
        return []


LAWS: list[dict] = _load_laws()

# ---------------------------------------------------------------------------
# ox-alpha validation
# ---------------------------------------------------------------------------


def _build_system_prompt(laws: list[dict]) -> str:
    """Build the system prompt containing all architectural laws."""
    header = (
        "You are a code-change constraint validator for the Ouroboros v7.1 project.\n"
        "Below are the project's inviolable architectural laws. A developer proposes\n"
        "a code change. You must decide whether the change VIOLATES any law.\n\n"
        "Respond with EXACTLY one of:\n"
        "  ALLOW — if the change does not violate any law\n"
        "  BLOCK: <one-line reason> — if the change violates a law\n\n"
        "Do NOT add any other text.\n\n"
        "=== ARCHITECTURAL LAWS ===\n"
    )
    law_texts = []
    for law in laws:
        law_texts.append(
            f"[{law['id']}] (confidence: {law['confidence']})\n{law['content']}"
        )
    return header + "\n\n".join(law_texts)


def _query_ox_alpha(change_description: str, target_repo: str) -> str:
    """Send the validation request to ox-alpha and return the raw decision string."""
    api_key = os.environ.get("OX_ALPHA_API_KEY", "")
    if not api_key:
        print("[codegraph] WARNING: OX_ALPHA_API_KEY not set — failing open", file=sys.stderr)
        return "ALLOW (ox-alpha error: OX_ALPHA_API_KEY not set)"
    if not OX_ALPHA_BASE_URL:
        print("[codegraph] WARNING: OX_ALPHA_BASE_URL not set — failing open", file=sys.stderr)
        return "ALLOW (ox-alpha error: OX_ALPHA_BASE_URL not set)"

    system_prompt = _build_system_prompt(LAWS)
    user_prompt = (
        f"Target repository: {target_repo}\n\n"
        f"Proposed change:\n{change_description}"
    )

    payload = {
        "model": OX_ALPHA_MODEL,
        "temperature": 0.0,
        "max_tokens": OX_ALPHA_MAX_TOKENS,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    try:
        resp = requests.post(
            f"{OX_ALPHA_BASE_URL}/chat/completions",
            json=payload,
            headers=headers,
            timeout=OX_ALPHA_TIMEOUT_S,
        )
        resp.raise_for_status()
        data = resp.json()
        message = data["choices"][0]["message"]
        decision = (message.get("content") or "").strip()
        if not decision:
            # Reasoning models may exhaust max_tokens before emitting content;
            # recover the verdict from the reasoning trace if possible.
            reasoning = message.get("reasoning") or ""
            match = re.search(r"\b(ALLOW|BLOCK)\b", reasoning)
            if match:
                return match.group(1)
            print("[codegraph] WARNING: empty model content — failing open", file=sys.stderr)
            return "ALLOW (ox-alpha error: empty content — increase OX_ALPHA_MAX_TOKENS)"
        return decision
    except requests.RequestException as exc:
        return f"ALLOW (ox-alpha error: {exc})"
    except (KeyError, IndexError) as exc:
        return f"ALLOW (ox-alpha error: malformed response — {exc})"


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------

mcp = FastMCP("codegraph", version="0.2.0")


@mcp.tool()
def validate_constraint(change_description: str, target_repo: str) -> str:
    """Validate a proposed code change against Ouroboros v7.1 architectural laws.

    Must be called BEFORE writing any memory allocation, attention mechanism,
    or verification code. Returns ALLOW or BLOCK with a reason.

    Args:
        change_description: Natural-language description of the planned change.
        target_repo: One of 'ouroboros-core', 'ouroboros-triton', 'ouroboros-dfg'.

    Returns:
        A string starting with 'ALLOW' or 'BLOCK: <reason>'.
    """
    if target_repo not in VALID_REPOS:
        return (
            f"BLOCK: Invalid target_repo '{target_repo}'. "
            f"Must be one of: {', '.join(sorted(VALID_REPOS))}"
        )

    if not LAWS:
        return "ALLOW (no laws loaded — constraint validation skipped)"

    return _query_ox_alpha(change_description, target_repo)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run(transport="stdio")
