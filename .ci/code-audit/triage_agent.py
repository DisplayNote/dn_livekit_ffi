#!/usr/bin/env python3
"""
Agent-based triage step for roadmap 2.22.

Pipeline:
  1. Read the code-audit security report (executive-overview.md + security/*.md).
  2. Enumerate: scan each document with a forced tool call and collect every
     Critical/High candidate (per-file keeps each call focused; a single
     whole-audit call overflowed and returned nothing). Dedup by candidate_key
     (concrete file:line, else lowercased title).
  3. Prioritize: "Ian" (CISO persona) takes the full candidate set and, via a
     forced tool, merges chains/duplicates, re-rates severity in context, and
     ranks them — this is the review brain that decides ticket grouping and
     priority. Coverage is guaranteed: any candidate Ian doesn't place still
     becomes its own ticket. A best-effort prose interpretation is also saved
     as ian-interpretation.md for humans.
  4. Create one ADO Bug per ticket — deduped *semantically* against the open
     `code-audit` Bugs (a model pass matches same-vulnerability tickets); the
     `[audit-id:<hash>]` in the title is only a human reference. Or print them
     with --dry-run.

The model does the judgement; this script does the deterministic ADO writes.

Env:
  ANTHROPIC_API_KEY    required
  SYSTEM_ACCESSTOKEN   ADO OAuth token (System.AccessToken) used to create Bugs.
                       If absent (and no PAT), the run fails open: it prints the
                       tickets and exits 0, exactly as --dry-run does.

Individual LLM calls are best-effort: a single document's interpretation,
extraction, or the prioritization pass can fail and the run still continues, so
a noisy or partially-failing audit never red-fails the pipeline. The run exits
non-zero only on a hard failure — no audit content, an ADO write error, or
*every* document extraction failing (which means the API is down/misconfigured
rather than a genuinely empty audit).
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import html
import json
import os
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests
from anthropic import Anthropic

MODEL = os.environ.get("TRIAGE_MODEL", "claude-sonnet-4-6")
EXTRACT_CONCURRENCY = int(os.environ.get("TRIAGE_CONCURRENCY", "6"))

# Placeholder for required fields an automated finding has no real value for.
REQUIRED_PLACEHOLDER = "N/A — filed automatically by code-audit (roadmap 2.22); see Repro Steps."

# Required fields the DisplayNote Bug process mandates beyond the standard set.
# These are the same across DisplayNote ADO projects, so they are the DEFAULT.
# Override or extend per project by setting TRIAGE_EXTRA_FIELDS to a JSON object
# keyed by field path, e.g.
#   '{"/fields/Custom.Team":"Platform","/fields/Microsoft.VSTS.Build.FoundIn":"main"}'
# (env values are merged over these defaults). Free-text required fields are also
# auto-filled by the self-heal retry, so you mainly need this for required PICKLISTS.
DEFAULT_EXTRA_FIELDS = {
    "/fields/Microsoft.VSTS.Build.FoundIn": "N/A — static code audit",
    "/fields/Custom.Reproducibility": REQUIRED_PLACEHOLDER,
    "/fields/Custom.ReproducibleincurrentversioninProduction": REQUIRED_PLACEHOLDER,
}
try:
    _env_extra = json.loads(os.environ.get("TRIAGE_EXTRA_FIELDS", "{}"))
    if not isinstance(_env_extra, dict):
        raise ValueError("expected a JSON object of field path -> value")
except Exception as _e:  # noqa: BLE001 - fail open so a bad env var can't break import
    print(f"  (TRIAGE_EXTRA_FIELDS ignored — {_e})", file=sys.stderr)
    _env_extra = {}
EXTRA_FIELDS = {**DEFAULT_EXTRA_FIELDS, **_env_extra}

# Repo files documenting deliberate, security-reviewed decisions are listed in a
# per-repo sidecar (triage-context.json next to this script) — NOT hardcoded here,
# so this engine stays portable across projects. The auditor (`code-audit run`) is
# BLIND to some such files: its walker skips dotfiles (e.g. .yarnrc.yml) and
# `docs/` is in scan.exclude-paths, so it can raise a finding for a risk these
# files already mitigate or intentionally accept (e.g. CSP style-src unsafe-inline
# documented in docs/about-csp.md; enableScripts:false in .yarnrc.yml neutralises
# install-script supply-chain risk). Feeding their contents into triage lets the
# model suppress/down-rate such false positives before a Bug is ever filed.
DEFAULT_CONTEXT_CONFIG = Path(__file__).resolve().parent / "triage-context.json"
REPO_CONTEXT_MAX_LINES_DEFAULT = 400


def load_context_config(path: Path) -> tuple[list[str], int]:
    """Read the sidecar JSON listing repo files that document reviewed decisions.

    Returns (context_files, max_lines). Shape:
        {"context_files": [".yarnrc.yml", "docs/about-csp.md"], "max_lines": 400}
    A missing/invalid file is non-fatal — triage just runs without suppression.
    Env vars override the file for quick per-pipeline tweaks: TRIAGE_REPO_CONTEXT
    (comma-separated, repo-root-relative paths) and TRIAGE_REPO_CONTEXT_MAX_LINES."""
    files: list[str] = []
    max_lines = REPO_CONTEXT_MAX_LINES_DEFAULT
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            files = [str(x) for x in (data.get("context_files") or [])]
            max_lines = int(data.get("max_lines", max_lines))
        except (OSError, ValueError) as e:
            print(f"  (triage-context: could not parse {path}: {e})", file=sys.stderr)
    else:
        print(f"  (triage-context: no config at {path}; triage runs without suppression)")
    env_files = os.environ.get("TRIAGE_REPO_CONTEXT", "").strip()
    if env_files:
        files = [p.strip() for p in env_files.split(",") if p.strip()]
    env_max = os.environ.get("TRIAGE_REPO_CONTEXT_MAX_LINES", "").strip()
    if env_max:
        max_lines = int(env_max)
    return files, max_lines

# Per-MTok pricing (input, output) for triage cost reporting. The triage step is
# NOT budget-capped (only `code-audit run` is); this just makes its cost visible.
PRICE_USD_PER_MTOK = {
    "claude-sonnet-4-6": (3.0, 15.0),
    "claude-opus-4-8": (15.0, 75.0),
    "claude-haiku-4-5": (1.0, 5.0),
}
_usage_lock = threading.Lock()
_usage = {"in": 0, "out": 0}


def _track(resp) -> None:
    u = getattr(resp, "usage", None)
    if not u:
        return
    with _usage_lock:
        _usage["in"] += getattr(u, "input_tokens", 0) or 0
        _usage["out"] += getattr(u, "output_tokens", 0) or 0


def estimated_cost() -> float:
    pin, pout = PRICE_USD_PER_MTOK.get(MODEL, (0.0, 0.0))
    return (_usage["in"] * pin + _usage["out"] * pout) / 1_000_000
SEVERITY_RANK = {"Critical": 3, "High": 2, "Medium": 1, "Low": 0}
ADO_API = "7.1"

# Structured-output contract. Forcing this tool guarantees a valid schema and
# sidesteps the Ian persona's tendency to answer in prose.
FINDINGS_TOOL = {
    "name": "report_findings",
    "description": (
        "Report the security findings that warrant an ADO Bug. Include a finding "
        "ONLY if its in-context severity is Critical or High."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "findings": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "concise symptom, no period, <70 chars"},
                        "severity": {"type": "string", "enum": ["Critical", "High"]},
                        "summary": {"type": "string", "description": "1-2 sentences, attacker/user-visible impact"},
                        "file_line": {"type": "string", "description": "path/to/file.ext:line or 'Unknown'"},
                        "suspected_root_cause": {"type": "string", "description": "short hypothesis, mark 'Unconfirmed'"},
                        "acceptance_criteria": {"type": "array", "items": {"type": "string"}},
                    },
                    "required": ["title", "severity", "summary", "file_line",
                                 "suspected_root_cause", "acceptance_criteria"],
                },
            }
        },
        "required": ["findings"],
    },
}

EXTRACT_SYSTEM = (
    "You are a security triage assistant. Read this one code-audit document and "
    "call report_findings with the Critical/High issues it describes. Re-rate "
    "severity in the system's context, not the auditor's raw label. If none "
    "qualify, return an empty list."
)

# Stage 2: Ian's structured prioritization over the enumerated candidate set.
# Forcing the tool keeps Ian's JUDGEMENT (chains, in-context severity, priority)
# but routes it through a schema we can act on, instead of prose.
PRIORITIZE_TOOL = {
    "name": "prioritize_findings",
    "description": (
        "Group the candidate findings into Bug tickets. Merge findings that are "
        "the same vulnerability or links of one attack chain into a single ticket "
        "(list their indices in member_ids). Re-rate severity in this system's "
        "context and assign a priority rank (1 = fix first) by chain / blast-radius "
        "logic. Every candidate index must appear in exactly one ticket."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "tickets": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "member_ids": {"type": "array", "items": {"type": "integer"},
                                       "description": "indices of candidate findings merged into this ticket"},
                        "title": {"type": "string", "description": "concise, no period, <70 chars"},
                        "severity": {"type": "string", "enum": ["Critical", "High"]},
                        "priority": {"type": "integer", "description": "1 = fix first; ascending"},
                        "rationale": {"type": "string", "description": "one line: why this priority (chain logic)"},
                    },
                    "required": ["member_ids", "title", "severity", "priority"],
                },
            }
        },
        "required": ["tickets"],
    },
}

# Cross-run dedup: decide which new tickets are the SAME vulnerability as an
# already-open code-audit Bug. Title-independent (Ian re-words between runs) and
# location-aware without being location-only (a *different* bug on the same line
# must NOT be suppressed).
DEDUP_TOOL = {
    "name": "match_existing",
    "input_schema": {
        "type": "object",
        "properties": {
            "matches": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "ticket_index": {"type": "integer"},
                        "existing_id": {"type": ["integer", "null"],
                                        "description": "id of the existing bug this duplicates, or null if new"},
                    },
                    "required": ["ticket_index", "existing_id"],
                },
            }
        },
        "required": ["matches"],
    },
}

DEDUP_SYSTEM = (
    "You deduplicate new security findings against already-filed bugs. Mark a new "
    "ticket as a duplicate (give the existing bug id) ONLY if it is the SAME "
    "underlying vulnerability — same root cause at the same location — even when "
    "the title is worded differently. A DIFFERENT vulnerability that merely touches "
    "the same file or line is NOT a duplicate. When in doubt, return null (treat as "
    "new) — never suppress a possibly-new finding. Call match_existing for every "
    "ticket."
)


# Pure-summary templates re-list findings the category files already cover, and
# usually without file:line. Enumerating them just inflates duplicates, so they
# are skipped for extraction (still handed to Ian as overview context).
SUMMARY_TEMPLATES = {"executive-summary.md", "remediation-plan.md", "audit-checklist.md"}


def enumeration_docs(audit_dir: Path) -> list[tuple[str, str]]:
    """Detail docs to enumerate — the category templates + vulnerability-report,
    which carry real file:line evidence. Summaries and the overview are skipped."""
    docs: list[tuple[str, str]] = []
    sec = audit_dir / "security"
    if sec.is_dir():
        for md in sorted(sec.glob("*.md")):
            if md.name not in SUMMARY_TEMPLATES:
                docs.append((f"security/{md.name}", md.read_text(encoding="utf-8")))
    if not docs:
        sys.exit(f"No audit content found under {audit_dir}")
    return docs


def overview_text(audit_dir: Path) -> str:
    f = audit_dir / "executive-overview.md"
    return f.read_text(encoding="utf-8") if f.exists() else ""


def read_audit(audit_dir: Path) -> str:
    """Full concatenated text — used for Ian's holistic prose interpretation."""
    parts = []
    ov = overview_text(audit_dir)
    if ov:
        parts.append("# EXECUTIVE OVERVIEW\n" + ov)
    sec = audit_dir / "security"
    if sec.is_dir():
        for md in sorted(sec.glob("*.md")):
            parts.append(f"# security/{md.name}\n" + md.read_text(encoding="utf-8"))
    return "\n\n---\n\n".join(parts)


def load_repo_context(repo_root: Path, context_files: list[str], max_lines: int) -> str:
    """Concatenate the reviewed-decision files (from the sidecar config) into a
    context block appended to the triage prompts. These files justify or already
    mitigate risks the auditor can't see (dotfiles + docs/ are not scanned), so
    this lets the model drop/down-rate the resulting false positives before a Bug
    is filed. Missing files are skipped silently — not every repo has all of them.
    Each file is truncated to max_lines to bound prompt cost."""
    blocks = []
    for rel in context_files:
        p = repo_root / rel
        if not p.is_file():
            continue
        try:
            lines = p.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError as e:
            print(f"  (repo-context: could not read {rel}: {e})", file=sys.stderr)
            continue
        body = "\n".join(lines[:max_lines])
        if len(lines) > max_lines:
            body += f"\n… (truncated; {len(lines) - max_lines} more line(s))"
        blocks.append(f"## {rel}\n{body}")
    if not blocks:
        return ""
    print(f"  repo-context: loaded {len(blocks)} file(s) for triage suppression")
    return (
        "\n\n# REPO CONTEXT — reviewed decisions & scope boundary\n"
        "The files below document deliberate, security-reviewed choices AND the "
        "trust boundary of this repository. The auditor cannot see some of them "
        "(dotfiles and docs/ are not scanned), so it may have raised findings for "
        "risks these files explicitly justify, already mitigate, or place outside "
        "this repo's responsibility. Do NOT report or keep such a finding — drop "
        "it, or down-rate it below the Critical/High bar. This applies in two "
        "cases: (1) the finding describes an intentional, documented decision "
        "(e.g. a CSP relaxation, a package-install setting that neutralises the "
        "risk, or a public REACT_APP_* value in the bundle); or (2) the finding is "
        "OUT OF SCOPE — its only real fix lives in the backend, in Auth0, in a "
        "third-party service, or in infra/hosting, not in this web-only client. "
        "See about-security-scope.md for the full boundary. Keep filing genuine "
        "client-side findings this repo can actually remediate.\n\n"
        + "\n\n".join(blocks)
    )


def interpret_with_ian(client: Anthropic, ian_prompt: str, audit_text: str) -> str:
    """Best-effort CISO interpretation (prose). Never fatal — if it fails the
    extraction still runs on the raw audit."""
    try:
        msg = client.messages.create(
            model=MODEL,
            max_tokens=2000,
            system=ian_prompt,
            messages=[{"role": "user", "content": (
                "Session: list\n\nHere is the code-audit security report for our "
                "repository. Interpret it.\n\n" + audit_text
            )}],
        )
        _track(msg)
        return "".join(b.text for b in msg.content if getattr(b, "type", None) == "text").strip()
    except Exception as e:  # noqa: BLE001 - interpretation is optional
        print(f"  (Ian interpretation skipped: {e})", file=sys.stderr)
        return ""


def _extract_one(client: Anthropic, label: str, text: str, context: str) -> tuple[str, list[dict], bool]:
    """Extract Critical/High findings from a single document. Best-effort per
    file: a failure returns ([], ok=False) rather than aborting the whole run —
    the caller distinguishes a real failure from a legitimately empty result and
    only fails the job when *every* document fails (see extract_findings)."""
    try:
        resp = client.messages.create(
            model=MODEL,
            max_tokens=8192,
            system=EXTRACT_SYSTEM,
            tools=[FINDINGS_TOOL],
            tool_choice={"type": "tool", "name": "report_findings"},
            messages=[{"role": "user", "content": f"# {label}\n\n{text}{context}"}],
        )
    except Exception as e:  # noqa: BLE001
        print(f"  {label}: extraction failed ({e})", file=sys.stderr)
        return label, [], False
    _track(resp)
    found = []
    for b in resp.content:
        if getattr(b, "type", None) == "tool_use" and b.name == "report_findings":
            for f in (b.input or {}).get("findings", []):
                if SEVERITY_RANK.get(f.get("severity"), 0) >= SEVERITY_RANK["High"]:
                    found.append(f)
    return label, found, True


def extract_findings(client: Anthropic, docs: list[tuple[str, str]], ian_notes: str,
                     repo_ctx: str = "") -> list[dict]:
    """Per-document forced extraction (run concurrently), then dedup. One call
    over the whole audit (~130k tokens) overflows and returns nothing; scanning
    each file keeps the model focused. The calls are independent, so they run in
    a thread pool (TRIAGE_CONCURRENCY, default 6) to cut wall time to roughly the
    slowest single call. Findings are deduped by candidate_key (concrete
    file:line, else title) so the same vuln cited in several templates lands once."""
    context = ""
    if ian_notes:
        context = "\n\n# SENIOR REVIEWER INTERPRETATION (for severity context)\n" + ian_notes
    context += repo_ctx
    by_key: dict[str, dict] = {}
    failures = 0
    with ThreadPoolExecutor(max_workers=max(1, EXTRACT_CONCURRENCY)) as ex:
        futures = [ex.submit(_extract_one, client, label, text, context) for label, text in docs]
        for fut in futures:  # in submission order -> stable, readable output
            label, found, ok = fut.result()
            if not ok:
                failures += 1
            for f in found:
                k = candidate_key(f)
                if k not in by_key or _richer(f, by_key[k]):
                    by_key[k] = f
            print(f"  {label}: {len(found)} Critical/High" + ("" if ok else " (extraction FAILED)"))
    # A single failed file is tolerated, but if EVERY document failed the API is
    # down/throttled/misconfigured — fail hard (non-zero exit) rather than report
    # an empty audit that looks like a clean "no findings" result.
    if docs and failures == len(docs):
        raise RuntimeError(
            f"all {failures} document extraction(s) failed — Anthropic API likely "
            "down/throttled/misconfigured; refusing to report an empty audit")
    if failures:
        print(f"  WARNING: {failures}/{len(docs)} document extraction(s) failed; "
              "the candidate set may be incomplete.", file=sys.stderr)
    return list(by_key.values())


def prioritize_with_ian(client: Anthropic, ian_prompt: str, candidates: list[dict],
                        overview: str, repo_ctx: str = "") -> list[dict]:
    """Stage 2 — Ian groups the candidate findings into chains, re-rates severity
    in context, and ranks them. Returns a list of 'tickets', each with its member
    findings attached. Coverage is guaranteed: any candidate Ian fails to place
    still becomes its own ticket, and if the whole call fails we fall back to one
    ticket per candidate."""
    if not candidates:
        return []
    listing = "\n".join(
        f"[{i}] ({f['severity']}) {f.get('title','')} — {f.get('file_line','?')}\n"
        f"    {f.get('summary','')}"
        for i, f in enumerate(candidates)
    )
    user = (
        "You are triaging the candidate security findings below into ADO Bug "
        "tickets for this codebase. Merge same-vuln / one-chain findings into a "
        "single ticket, re-rate severity in context, and rank by what to fix "
        "first. Call prioritize_findings.\n\n"
        f"# AUDIT OVERVIEW\n{overview}\n\n# CANDIDATE FINDINGS\n{listing}" + repo_ctx
    )
    try:
        resp = client.messages.create(
            model=MODEL, max_tokens=8192, system=ian_prompt,
            tools=[PRIORITIZE_TOOL], tool_choice={"type": "tool", "name": "prioritize_findings"},
            messages=[{"role": "user", "content": user}],
        )
    except Exception as e:  # noqa: BLE001
        print(f"  (Ian prioritization failed; 1 ticket per finding: {e})", file=sys.stderr)
        return _fallback_tickets(candidates)
    _track(resp)

    tickets: list[dict] = []
    used: set[int] = set()
    for b in resp.content:
        if getattr(b, "type", None) == "tool_use" and b.name == "prioritize_findings":
            for t in (b.input or {}).get("tickets", []):
                members = [candidates[i] for i in t.get("member_ids", []) if 0 <= i < len(candidates)]
                if not members:
                    continue
                used.update(i for i in t.get("member_ids", []) if 0 <= i < len(candidates))
                sev = t.get("severity") if t.get("severity") in ("Critical", "High") else members[0]["severity"]
                tickets.append({"title": t.get("title") or members[0]["title"],
                                "severity": sev, "priority": int(t.get("priority", 99)),
                                "rationale": t.get("rationale", ""), "members": members})
    # Coverage safety net: never silently drop a candidate — but don't recreate
    # one Ian already folded into a ticket under a differently-worded title.
    covered = {candidate_key(m) for t in tickets for m in t["members"]}
    for i, f in enumerate(candidates):
        if i in used or candidate_key(f) in covered:
            continue
        tickets.append({"title": f["title"], "severity": f["severity"], "priority": 99,
                        "rationale": "(not grouped by triage)", "members": [f]})
        covered.add(candidate_key(f))
    tickets.sort(key=lambda x: x["priority"])
    return tickets


def _fallback_tickets(candidates: list[dict]) -> list[dict]:
    return [{"title": f["title"], "severity": f["severity"], "priority": i + 1,
             "rationale": "", "members": [f]} for i, f in enumerate(candidates)]


def candidate_key(f: dict) -> str:
    """Dedup key for a candidate. Same concrete file:line == same finding (the
    different audit templates word the title differently, so we key on the line
    when we have one, and fall back to the lowercased title otherwise)."""
    fl = (f.get("file_line") or "").strip()
    if fl and fl.lower() != "unknown":
        return f"fl:{fl.lower()}"
    return f"ti:{(f.get('title') or '').strip().lower()}"


def _richer(a: dict, b: dict) -> bool:
    """Prefer the higher-severity / more-detailed of two duplicate candidates."""
    if SEVERITY_RANK.get(a.get("severity"), 0) != SEVERITY_RANK.get(b.get("severity"), 0):
        return SEVERITY_RANK.get(a.get("severity"), 0) > SEVERITY_RANK.get(b.get("severity"), 0)
    return len(a.get("summary", "")) > len(b.get("summary", ""))


def ticket_filelines(ticket: dict) -> set[str]:
    """Concrete (non-Unknown) file:line locations a ticket covers, normalized."""
    out = set()
    for m in ticket["members"]:
        fl = (m.get("file_line") or "").strip().lower()
        if fl and fl != "unknown":
            out.add(fl)
    return out


def ticket_id(ticket: dict) -> str:
    """Stable id for a ticket — derived from its members' stable identifiers
    (sorted candidate_key values: concrete file:line, else the per-finding
    title), NOT the Ian-generated ticket title, which is re-worded between runs
    and would defeat dedup. Used as a human-readable marker in the Bug title."""
    keys = sorted(candidate_key(m) for m in ticket.get("members", []))
    basis = "|".join(keys) if keys else (ticket.get("title") or "").strip().lower()
    return hashlib.sha1(basis.encode()).hexdigest()[:12]


def _esc(value) -> str:
    """HTML-escape LLM-provided text before embedding it in the Bug body, so it
    can't break the ADO rich-text markup or inject HTML. Uses the stdlib
    html.escape (similar in intent to tools/testplan_sync/testplan-sync.py's
    escape_html_text, which is a hand-rolled variant)."""
    return html.escape("" if value is None else str(value))


def bug_body(ticket: dict, marker: str) -> str:
    pri, rat = ticket.get("priority"), ticket.get("rationale", "")
    head = ""
    if pri and pri != 99:
        head = f"<p><b>Triage priority:</b> #{pri}" + (f" — {_esc(rat)}" if rat else "") + "</p>"
    blocks = []
    for m in ticket["members"]:
        ac = "".join(f"<li>{_esc(c)}</li>" for c in m.get("acceptance_criteria", []))
        blocks.append(
            f"<p><b>{_esc(m.get('title',''))}</b> ({_esc(m.get('severity',''))})<br>"
            f"{_esc(m.get('summary',''))}<br>"
            f"Suspected root cause: {_esc(m.get('suspected_root_cause','Unknown'))}<br>"
            f"<code>{_esc(m.get('file_line','Unknown'))}</code></p>"
            + (f"<ul>{ac}</ul>" if ac else "")
        )
    return head + "".join(blocks) + f"<p><i>Source: automated code-audit (roadmap 2.22). {marker}</i></p>"


def ado_token() -> str | None:
    """SYSTEM_ACCESSTOKEN (pipeline, Bearer) or a PAT (local testing, Basic)."""
    return (os.environ.get("SYSTEM_ACCESSTOKEN")
            or os.environ.get("AZURE_DEVOPS_PAT")
            or os.environ.get("AZURE_DEVOPS_TOKEN"))


def ado_headers() -> dict:
    tok = os.environ.get("SYSTEM_ACCESSTOKEN")
    if tok:  # pipeline OAuth token
        return {"Authorization": f"Bearer {tok}"}
    pat = os.environ.get("AZURE_DEVOPS_PAT") or os.environ.get("AZURE_DEVOPS_TOKEN")
    if pat:  # personal access token -> Basic ":PAT"
        return {"Authorization": "Basic " + base64.b64encode(f":{pat}".encode()).decode()}
    return {}


def existing_open_bugs(org: str, project: str) -> list[dict]:
    """Open `code-audit` Bugs with their title + file:line locations (parsed from
    Repro Steps). Input to the semantic dedup. Fail-open (returns [] on error)."""
    wiql = {"query": (
        "SELECT [System.Id] FROM WorkItems "
        "WHERE [System.TeamProject] = @project "
        "AND [System.WorkItemType] = 'Bug' "  # only Bugs: the batch fetch reads Bug-only fields
        "AND [System.Tags] CONTAINS 'code-audit' "
        "AND [System.State] NOT IN ('Closed','Removed','Resolved','Done')"
    )}
    try:
        r = requests.post(f"{org}/{project}/_apis/wit/wiql?api-version={ADO_API}",
                          json=wiql, headers=ado_headers(), timeout=60)
        if not r.ok:
            print(f"    (dedup scan WIQL failed HTTP {r.status_code}; proceeding without)", file=sys.stderr)
            return []
        ids = [w["id"] for w in r.json().get("workItems", [])]
    except Exception as e:  # noqa: BLE001 - fail open: dedup is best-effort, never block creation
        print(f"    (dedup scan WIQL errored: {e}; proceeding without)", file=sys.stderr)
        return []
    bugs: list[dict] = []
    for i in range(0, len(ids), 200):
        try:
            rb = requests.post(f"{org}/{project}/_apis/wit/workitemsbatch?api-version={ADO_API}",
                               json={"ids": ids[i:i + 200], "fields": ["System.Title", "Microsoft.VSTS.TCM.ReproSteps"]},
                               headers={**ado_headers(), "Content-Type": "application/json"}, timeout=60)
            if not rb.ok:
                continue
            batch = rb.json().get("value", [])
        except Exception as e:  # noqa: BLE001 - skip this batch, keep the dedup we have
            print(f"    (dedup batch {i // 200} errored: {e}; skipping)", file=sys.stderr)
            continue
        for wi in batch:
            f = wi.get("fields", {})
            locs = {loc.strip().lower() for loc in re.findall(r"<code>([^<]+)</code>",
                    f.get("Microsoft.VSTS.TCM.ReproSteps", "") or "")}
            locs.discard("")
            locs.discard("unknown")
            bugs.append({"id": wi["id"], "title": f.get("System.Title", ""), "locations": locs})
    print(f"  dedup scan: {len(bugs)} existing open code-audit bug(s)")
    return bugs


def dedup_matches(client: Anthropic, tickets: list[dict], existing: list[dict]) -> dict:
    """Ask the model which new tickets are the SAME vulnerability as an existing
    open bug. Returns {ticket_index: existing_id}. Biased to create-when-unsure;
    fail-open (returns {} on error) so a hiccup never suppresses findings."""
    if not existing or not tickets:
        return {}
    ex = "\n".join(f"#{b['id']} {b['title']}  [locations: {', '.join(sorted(b['locations'])) or 'n/a'}]"
                   for b in existing)
    new = "\n".join(
        f"[{i}] {t['title']} — locations: {', '.join(sorted(ticket_filelines(t))) or 'n/a'}\n"
        f"    {(t['members'][0].get('summary', '') if t['members'] else '')}"
        for i, t in enumerate(tickets)
    )
    try:
        resp = client.messages.create(
            model=MODEL, max_tokens=4096, system=DEDUP_SYSTEM,
            tools=[DEDUP_TOOL], tool_choice={"type": "tool", "name": "match_existing"},
            messages=[{"role": "user", "content": f"# EXISTING OPEN BUGS\n{ex}\n\n# NEW TICKETS\n{new}"}],
        )
        _track(resp)
    except Exception as e:  # noqa: BLE001
        print(f"  (dedup match failed; creating all: {e})", file=sys.stderr)
        return {}
    out: dict = {}
    valid_ids = {b["id"] for b in existing}
    for b in resp.content:
        if getattr(b, "type", None) == "tool_use" and b.name == "match_existing":
            for m in (b.input or {}).get("matches", []):
                ti, ex_id = m.get("ticket_index"), m.get("existing_id")
                if isinstance(ti, int) and 0 <= ti < len(tickets) and ex_id in valid_ids:
                    out[ti] = ex_id
    return out


def _fill_required(fields: dict, resp: "requests.Response") -> list[str]:
    """Read ADO's RuleValidationErrors and add a placeholder for any field flagged
    required/empty that we haven't set, so we can retry. Returns the refs added."""
    try:
        errs = resp.json().get("customProperties", {}).get("RuleValidationErrors", []) or []
    except Exception:  # noqa: BLE001
        return []
    added = []
    for e in errs:
        ref = e.get("fieldReferenceName")
        flags = (e.get("fieldStatusFlags") or "").lower()
        if ref and ("required" in flags or "invalidempty" in flags):
            path = f"/fields/{ref}"
            if path not in fields:
                fields[path] = REQUIRED_PLACEHOLDER
                added.append(ref)
    return added


def bug_title(title: str, marker: str) -> str:
    """Compose 'title [audit-id:…]' within ADO's 255-char System.Title limit,
    truncating ONLY the human title so the marker is never cut off. Dedup itself
    is semantic (see dedup_matches); the marker is a stable human reference kept
    intact so a person can eyeball-match a Bug back to its triaged finding."""
    suffix = f" {marker}"
    return (title or "").strip()[:255 - len(suffix)].rstrip() + suffix


def create_bug(org: str, project: str, area: str, ticket: dict) -> int:
    marker = f"[audit-id:{ticket_id(ticket)}]"
    is_critical = ticket["severity"] == "Critical"
    fields = {
        "/fields/System.Title": bug_title(ticket["title"], marker),
        "/fields/System.AreaPath": area,
        # 'ai-influenced' = roadmap 2.3 Signal 1 (agent self-tags at creation);
        # 'code-audit' keeps these separable from other automations.
        "/fields/System.Tags": f"code-audit; ai-influenced; severity-{ticket['severity']}; web-app",
        # Agile/Scrum Bug rich-text body is Repro Steps, not System.Description.
        # (Basic process: change this to /fields/System.Description.)
        "/fields/Microsoft.VSTS.TCM.ReproSteps": bug_body(ticket, marker),
        # Standard Agile/Scrum Bug fields. SystemInfo is commonly required;
        # ValueArea is a required picklist (Business|Architectural). If your
        # process differs (e.g. Basic, or extra required picklists), adjust here
        # or via TRIAGE_EXTRA_FIELDS.
        "/fields/Microsoft.VSTS.TCM.SystemInfo": REQUIRED_PLACEHOLDER,
        "/fields/Microsoft.VSTS.Common.ValueArea": "Business",
        "/fields/Microsoft.VSTS.Common.Severity": "1 - Critical" if is_critical else "2 - High",
        "/fields/Microsoft.VSTS.Common.Priority": 1 if is_critical else 2,
    }
    fields.update(EXTRA_FIELDS)  # project-specific required fields (picklists/identity)
    url = f"{org}/{project}/_apis/wit/workitems/$Bug?api-version={ADO_API}"
    for attempt in (1, 2):
        patch = [{"op": "add", "path": p, "value": v} for p, v in fields.items()]
        r = requests.post(url, json=patch, headers={**ado_headers(),
                          "Content-Type": "application/json-patch+json"}, timeout=60)
        if r.ok:
            return r.json()["id"]
        # Self-heal once: fill any *other* required-empty fields the process mandates.
        if attempt == 1 and r.status_code == 400:
            added = _fill_required(fields, r)
            if added:
                print(f"    filling required field(s) {added} and retrying", file=sys.stderr)
                continue
        raise RuntimeError(f"ADO create failed HTTP {r.status_code}: {r.text[:600]}")
    raise RuntimeError("ADO create failed after retry")  # unreachable


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit-dir", required=True)
    ap.add_argument("--ian-prompt", required=True)
    ap.add_argument("--severity-floor", default="High", choices=["Critical", "High"],
                    help="only create Bugs at or above this severity "
                         "(High = Critical+High; Critical = Critical only)")
    ap.add_argument("--ado-org", default="")
    ap.add_argument("--ado-project", default="")
    ap.add_argument("--area-path", default="")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--max-create", type=int, default=0,
                    help="create at most N bugs this run (0 = no limit). Use 1 to smoke-test the ADO write path.")
    ap.add_argument("--repo-root", default=".",
                    help="repo root for resolving the context files (default: cwd, where the pipeline runs).")
    ap.add_argument("--context-config", default=None,
                    help="path to the triage-context sidecar JSON (default: triage-context.json next to this script).")
    args = ap.parse_args()

    ian = Path(args.ian_prompt).read_text(encoding="utf-8")
    audit_dir = Path(args.audit_dir)
    docs = enumeration_docs(audit_dir)
    audit_text = read_audit(audit_dir)
    ctx_cfg = Path(args.context_config) if args.context_config else DEFAULT_CONTEXT_CONFIG
    ctx_files, ctx_max = load_context_config(ctx_cfg)
    repo_ctx = load_repo_context(Path(args.repo_root), ctx_files, ctx_max)
    client = Anthropic()  # reads ANTHROPIC_API_KEY
    ian_notes = interpret_with_ian(client, ian, audit_text)
    if ian_notes:
        (audit_dir / "ian-interpretation.md").write_text(ian_notes, encoding="utf-8")
        print("  wrote ian-interpretation.md")
    candidates = extract_findings(client, docs, ian_notes, repo_ctx)
    print(f"Enumerated {len(candidates)} Critical/High candidate(s).")
    overview = overview_text(audit_dir)
    tickets = prioritize_with_ian(client, ian, candidates, overview, repo_ctx)
    # Enforce the severity floor on Ian's in-context re-rating: with the default
    # High this keeps Critical+High; --severity-floor Critical narrows to Critical.
    floor = SEVERITY_RANK[args.severity_floor]
    kept = [t for t in tickets if SEVERITY_RANK.get(t["severity"], 0) >= floor]
    if len(kept) != len(tickets):
        print(f"  --severity-floor {args.severity_floor}: kept {len(kept)}/{len(tickets)} ticket(s).")
    tickets = kept
    print(f"Ian triaged into {len(tickets)} ticket(s) (chains merged, ranked).")
    print(f"Triage LLM cost ≈ ${estimated_cost():.2f} "
          f"({_usage['in']:,} in / {_usage['out']:,} out tokens) — NOT budget-capped.")

    if args.dry_run or not ado_token():
        for t in tickets:
            print(json.dumps({
                "audit_id": ticket_id(t), "priority": t["priority"], "severity": t["severity"],
                "title": t["title"], "rationale": t.get("rationale", ""),
                "members": [m.get("file_line", "?") for m in t["members"]],
            }, indent=2, ensure_ascii=False))
        if not args.dry_run:
            print("WARNING: no ADO token (SYSTEM_ACCESSTOKEN / AZURE_DEVOPS_PAT) — "
                  "printed instead of creating.", file=sys.stderr)
        return 0

    # Creating Bugs needs all three ADO targets; validate up-front so a missing
    # one fails with a clear message instead of an opaque requests/ADO error later.
    missing = [name for name, val in (("--ado-org", args.ado_org),
                                      ("--ado-project", args.ado_project),
                                      ("--area-path", args.area_path)) if not val.strip()]
    if missing:
        sys.exit(f"An ADO token is set but {', '.join(missing)} is empty — pass these "
                 "to create Bugs, or use --dry-run to just print the tickets.")

    org = args.ado_org.rstrip("/")  # System.CollectionUri has a trailing slash -> avoid //
    existing = existing_open_bugs(org, args.ado_project)
    matched = dedup_matches(client, tickets, existing)  # {ticket_index: existing bug id}
    created = skipped = 0
    for i, t in enumerate(tickets):
        if args.max_create and created >= args.max_create:
            print(f"  --max-create {args.max_create} reached; stopping.")
            break
        if i in matched:
            skipped += 1
            print(f"    skip (same vuln as #{matched[i]}): {t['title']}")
            continue
        wid = create_bug(org, args.ado_project, args.area_path, t)
        print(f"  created Bug #{wid} [P{t['priority']} {t['severity']}]: {t['title']}")
        created += 1
    print(f"Done. created={created} skipped(duplicate-of-existing)={skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
