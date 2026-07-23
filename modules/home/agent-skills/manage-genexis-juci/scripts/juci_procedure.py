#!/usr/bin/env python3
"""Review and execute policy-bound JUCI/UBUS procedures."""

from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any
from urllib.parse import urlparse


RISK_ORDER = {
    "harmless-read": 0,
    "sensitive-read": 1,
    "mutation": 2,
    "critical": 3,
}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
SID_RE = re.compile(r"^[0-9a-fA-F]{32}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
REF_RE = re.compile(r"^\$\{actions\.([a-z0-9-]+)((?:\.[A-Za-z0-9_-]+)*)\}$")
FORBIDDEN_KEYS = {
    "access_token",
    "api-key",
    "api_key",
    "authorization",
    "cookie",
    "credential",
    "credentials",
    "passphrase",
    "password",
    "passwd",
    "private-key",
    "private_key",
    "psk",
    "refresh_token",
    "secret",
    "session-id",
    "session_id",
    "sid",
    "token",
    "ubus_rpc_session",
}
PROCEDURE_KEYS = {
    "schema_version",
    "id",
    "summary",
    "endpoint",
    "actions",
    "rollback_actions",
}
ACTION_KEYS = {"id", "risk", "call", "expect"}
CALL_KEYS = {"object", "method", "args"}
EXPECT_KEYS = {"status", "payload_sha256"}
GRANT_KEYS = {"schema_version", "procedure_sha256", "grants"}
GRANT_ENTRY_KEYS = {"action_id", "risk", "allow_response", "confirmation"}

HARMLESS_CALLS = {
    ("juci.unauthenticated", "username"),
    ("juci.unauthenticated", "autocomplete"),
}
SENSITIVE_CALLS = {
    ("session", "list"),
    ("uci", "configs"),
    ("uci", "get"),
    ("juci.firewall", "excluded_ports"),
}
MUTATION_CALLS = {
    ("uci", "add"),
    ("uci", "set"),
    ("uci", "delete"),
    ("uci", "order"),
    ("uci", "commit"),
    ("uci", "rollback"),
}


class ProcedureError(RuntimeError):
    pass


def reject_unknown_keys(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise ProcedureError(f"{label} contains unknown fields: {', '.join(unknown)}")


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def value_sha256(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ProcedureError(f"cannot load {path}: {exc}") from exc


def contains_forbidden_key(value: Any) -> str | None:
    if isinstance(value, dict):
        for key, nested in value.items():
            if key.lower() in FORBIDDEN_KEYS:
                return key
            found = contains_forbidden_key(nested)
            if found:
                return found
    elif isinstance(value, list):
        for nested in value:
            found = contains_forbidden_key(nested)
            if found:
                return found
    return None


def minimum_risk(call: dict[str, Any]) -> str:
    pair = (call.get("object"), call.get("method"))
    if pair in HARMLESS_CALLS:
        return "harmless-read"
    if pair in SENSITIVE_CALLS:
        return "sensitive-read"
    if pair in MUTATION_CALLS:
        return "mutation"
    return "critical"


def validate_action(action: Any, *, rollback: bool = False) -> dict[str, Any]:
    if not isinstance(action, dict):
        raise ProcedureError("each action must be an object")
    reject_unknown_keys(action, ACTION_KEYS, "action")
    action_id = action.get("id")
    if not isinstance(action_id, str) or not ID_RE.fullmatch(action_id):
        raise ProcedureError(f"invalid action id: {action_id!r}")
    risk = action.get("risk")
    if risk not in RISK_ORDER:
        raise ProcedureError(f"{action_id}: invalid risk {risk!r}")
    call = action.get("call")
    if not isinstance(call, dict):
        raise ProcedureError(f"{action_id}: call must be an object")
    reject_unknown_keys(call, CALL_KEYS, f"{action_id}.call")
    obj = call.get("object")
    method = call.get("method")
    args = call.get("args", {})
    if not isinstance(obj, str) or not obj or not isinstance(method, str) or not method:
        raise ProcedureError(
            f"{action_id}: object and method must be non-empty strings"
        )
    if not isinstance(args, dict):
        raise ProcedureError(f"{action_id}: call.args must be an object")
    if obj == "session" and method in {"login", "destroy"}:
        raise ProcedureError(
            f"{action_id}: session.{method} is reserved to the executor"
        )
    floor = minimum_risk(call)
    if RISK_ORDER[risk] < RISK_ORDER[floor]:
        raise ProcedureError(f"{action_id}: {obj}.{method} requires at least {floor}")
    expect = action.get("expect", {"status": 0})
    if not isinstance(expect, dict) or not isinstance(expect.get("status", 0), int):
        raise ProcedureError(f"{action_id}: expect.status must be an integer")
    reject_unknown_keys(expect, EXPECT_KEYS, f"{action_id}.expect")
    payload_hash = expect.get("payload_sha256")
    if payload_hash is not None and (
        not isinstance(payload_hash, str) or not SHA_RE.fullmatch(payload_hash)
    ):
        raise ProcedureError(
            f"{action_id}: expect.payload_sha256 must be lowercase SHA-256"
        )
    if rollback and risk not in {"mutation", "critical"}:
        raise ProcedureError(
            f"{action_id}: rollback actions must be mutation or critical"
        )
    return {
        "id": action_id,
        "risk": risk,
        "minimum_risk": floor,
        "call": {"object": obj, "method": method, "args": args},
        "expect": expect,
    }


def validate_procedure(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise ProcedureError("procedure must be a JSON object")
    reject_unknown_keys(raw, PROCEDURE_KEYS, "procedure")
    forbidden = contains_forbidden_key(raw)
    if forbidden:
        raise ProcedureError(
            f"procedure contains forbidden credential key {forbidden!r}"
        )
    if raw.get("schema_version") != 1:
        raise ProcedureError("schema_version must be 1")
    procedure_id = raw.get("id")
    if not isinstance(procedure_id, str) or not ID_RE.fullmatch(procedure_id):
        raise ProcedureError(
            "procedure id must use lowercase letters, digits, and hyphens"
        )
    summary = raw.get("summary")
    if not isinstance(summary, str) or not summary.strip():
        raise ProcedureError("summary must be a non-empty string")
    endpoint = raw.get("endpoint")
    if not isinstance(endpoint, str):
        raise ProcedureError("endpoint must be a string")
    parsed = urlparse(endpoint)
    if (
        parsed.scheme not in {"ws", "wss"}
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        raise ProcedureError(
            "endpoint must be a credential-free ws:// or wss:// URL without query or fragment"
        )
    actions_raw = raw.get("actions")
    rollback_raw = raw.get("rollback_actions", [])
    if not isinstance(actions_raw, list) or not actions_raw:
        raise ProcedureError("actions must be a non-empty array")
    if not isinstance(rollback_raw, list):
        raise ProcedureError("rollback_actions must be an array")
    actions = [validate_action(action) for action in actions_raw]
    rollback_actions = [
        validate_action(action, rollback=True) for action in rollback_raw
    ]
    all_ids = [action["id"] for action in actions + rollback_actions]
    if len(all_ids) != len(set(all_ids)):
        raise ProcedureError("action and rollback IDs must be unique")
    has_mutation = any(action["risk"] == "mutation" for action in actions)
    if has_mutation and not rollback_actions:
        raise ProcedureError(
            "mutation procedures require executable rollback_actions; otherwise classify them critical"
        )
    uci_write_methods = {"add", "set", "delete", "order"}
    forward_write_configs = {
        action["call"]["args"].get("config")
        for action in actions
        if action["call"]["object"] == "uci"
        and action["call"]["method"] in uci_write_methods
    }
    forward_commit_configs = {
        action["call"]["args"].get("config")
        for action in actions
        if action["call"]["object"] == "uci" and action["call"]["method"] == "commit"
    }
    rollback_write_configs = {
        action["call"]["args"].get("config")
        for action in rollback_actions
        if action["call"]["object"] == "uci"
        and action["call"]["method"] in uci_write_methods
    }
    rollback_commit_configs = {
        action["call"]["args"].get("config")
        for action in rollback_actions
        if action["call"]["object"] == "uci" and action["call"]["method"] == "commit"
    }
    if (
        None
        in forward_write_configs
        | forward_commit_configs
        | rollback_write_configs
        | rollback_commit_configs
    ):
        raise ProcedureError("UCI write and commit calls require a literal config name")
    missing_forward_commits = forward_write_configs - forward_commit_configs
    if missing_forward_commits:
        raise ProcedureError(
            "UCI writes lack matching forward commits: "
            + ", ".join(sorted(missing_forward_commits))
        )
    if has_mutation:
        missing_rollback_writes = forward_commit_configs - rollback_write_configs
        missing_rollback_commits = forward_commit_configs - rollback_commit_configs
        if missing_rollback_writes:
            raise ProcedureError(
                "rollback lacks compensating writes for: "
                + ", ".join(sorted(missing_rollback_writes))
            )
        if missing_rollback_commits:
            raise ProcedureError(
                "rollback lacks matching commits for: "
                + ", ".join(sorted(missing_rollback_commits))
            )
    return {
        "schema_version": 1,
        "id": procedure_id,
        "summary": summary.strip(),
        "endpoint": endpoint,
        "actions": actions,
        "rollback_actions": rollback_actions,
    }


def required_grants(
    procedure: dict[str, Any], procedure_hash: str
) -> list[dict[str, Any]]:
    grants = []
    for action in procedure["actions"] + procedure["rollback_actions"]:
        if action["risk"] == "harmless-read":
            continue
        grant = {"action_id": action["id"], "risk": action["risk"]}
        if action["risk"] in {"sensitive-read", "critical"}:
            grant["allow_response"] = False
        if action["risk"] == "critical":
            grant["confirmation"] = f"APPROVE CRITICAL {procedure_hash} {action['id']}"
        grants.append(grant)
    return grants


def validate_grants(
    raw: Any, procedure: dict[str, Any], procedure_hash: str
) -> dict[str, dict[str, Any]]:
    needed = required_grants(procedure, procedure_hash)
    if not needed:
        return {}
    if not isinstance(raw, dict) or raw.get("schema_version") != 1:
        raise ProcedureError("grant must be a schema_version 1 object")
    reject_unknown_keys(raw, GRANT_KEYS, "grant")
    if raw.get("procedure_sha256") != procedure_hash:
        raise ProcedureError("grant is not bound to this procedure SHA-256")
    entries = raw.get("grants")
    if not isinstance(entries, list):
        raise ProcedureError("grant.grants must be an array")
    by_id: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("action_id"), str):
            raise ProcedureError("each grant entry needs an action_id")
        reject_unknown_keys(entry, GRANT_ENTRY_KEYS, "grant entry")
        if entry["action_id"] in by_id:
            raise ProcedureError(f"duplicate grant for {entry['action_id']}")
        by_id[entry["action_id"]] = entry
    for required in needed:
        action_id = required["action_id"]
        entry = by_id.get(action_id)
        if entry is None or entry.get("risk") != required["risk"]:
            raise ProcedureError(
                f"missing exact {required['risk']} grant for {action_id}"
            )
        if (
            required["risk"] == "critical"
            and entry.get("confirmation") != required["confirmation"]
        ):
            raise ProcedureError(f"invalid critical confirmation for {action_id}")
        if "allow_response" in entry and not isinstance(entry["allow_response"], bool):
            raise ProcedureError(f"{action_id}: allow_response must be boolean")
    unexpected = sorted(set(by_id) - {item["action_id"] for item in needed})
    if unexpected:
        raise ProcedureError(
            f"grant contains unexpected action IDs: {', '.join(unexpected)}"
        )
    return by_id


def resolve_references(value: Any, context: dict[str, Any]) -> Any:
    if isinstance(value, dict):
        return {
            key: resolve_references(nested, context) for key, nested in value.items()
        }
    if isinstance(value, list):
        return [resolve_references(nested, context) for nested in value]
    if not isinstance(value, str):
        return value
    match = REF_RE.fullmatch(value)
    if not match:
        if "${actions." in value:
            raise ProcedureError(f"references must occupy the whole value: {value}")
        return value
    action_id, suffix = match.groups()
    if action_id not in context:
        raise ProcedureError(f"reference uses unavailable action {action_id}")
    resolved = context[action_id]
    for part in [item for item in suffix.split(".") if item]:
        if not isinstance(resolved, dict) or part not in resolved:
            raise ProcedureError(f"reference path not found: {value}")
        resolved = resolved[part]
    return resolved


class RpcClient:
    def __init__(self, endpoint: str, sid: str, timeout: int = 30):
        self.endpoint = endpoint
        self.sid = sid
        self.timeout = timeout
        self.request_id = 0

    def call(self, obj: str, method: str, args: dict[str, Any]) -> dict[str, Any]:
        self.request_id += 1
        request = {
            "jsonrpc": "2.0",
            "method": "call",
            "params": [self.sid, obj, method, args],
            "id": self.request_id,
        }
        try:
            result = subprocess.run(
                ["websocat", "-1", "-t", "--protocol", "ubus-json", self.endpoint],
                input=canonical(request) + "\n",
                text=True,
                capture_output=True,
                timeout=self.timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ProcedureError(f"WebSocket call failed: {exc}") from exc
        if result.returncode != 0:
            raise ProcedureError(
                f"websocat failed with exit {result.returncode}: {result.stderr.strip()}"
            )
        lines = [line for line in result.stdout.splitlines() if line.strip()]
        if not lines:
            raise ProcedureError("router returned no JSON-RPC response")
        try:
            response = json.loads(lines[-1])
        except json.JSONDecodeError as exc:
            raise ProcedureError("router returned invalid JSON-RPC") from exc
        if response.get("error") is not None:
            raise ProcedureError(f"JSON-RPC error: {response['error']}")
        rpc_result = response.get("result")
        if (
            not isinstance(rpc_result, list)
            or not rpc_result
            or not isinstance(rpc_result[0], int)
        ):
            raise ProcedureError("router returned an invalid UBUS result")
        return {
            "status": rpc_result[0],
            "payload": rpc_result[1] if len(rpc_result) > 1 else None,
        }


def audit_response(
    result: dict[str, Any], action: dict[str, Any], grant: dict[str, Any] | None
) -> Any:
    payload = result["payload"]
    disclose = action["risk"] not in {"sensitive-read", "critical"} or bool(
        (grant or {}).get("allow_response")
    )
    if disclose:
        return payload
    return {"redacted": True, "sha256": value_sha256(payload)}


def run_action(
    client: RpcClient,
    action: dict[str, Any],
    context: dict[str, Any],
    grants: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    call = action["call"]
    args = resolve_references(call["args"], context)
    result = client.call(call["object"], call["method"], args)
    expected = action["expect"]
    if result["status"] != expected.get("status", 0):
        raise ProcedureError(
            f"{action['id']}: expected UBUS status {expected.get('status', 0)}, got {result['status']}"
        )
    payload_hash = value_sha256(result["payload"])
    if expected.get("payload_sha256") and payload_hash != expected["payload_sha256"]:
        raise ProcedureError(
            f"{action['id']}: response payload SHA-256 precondition failed"
        )
    context[action["id"]] = result["payload"]
    return {
        "id": action["id"],
        "risk": action["risk"],
        "call": {"object": call["object"], "method": call["method"], "args": args},
        "status": result["status"],
        "payload_sha256": payload_hash,
        "response": audit_response(result, action, grants.get(action["id"])),
    }


def write_secure_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        raise


def read_sid() -> str:
    if sys.stdin.isatty():
        sid = getpass.getpass("JUCI session ID: ").strip()
    else:
        sid = sys.stdin.readline().strip()
    if not SID_RE.fullmatch(sid) or sid == "0" * 32:
        raise ProcedureError(
            "session ID must be a non-default 32-character hexadecimal token"
        )
    return sid


def review(procedure: dict[str, Any], procedure_hash: str) -> dict[str, Any]:
    return {
        "procedure_id": procedure["id"],
        "summary": procedure["summary"],
        "endpoint": procedure["endpoint"],
        "procedure_sha256": procedure_hash,
        "actions": procedure["actions"],
        "rollback_actions": procedure["rollback_actions"],
        "required_grants": required_grants(procedure, procedure_hash),
    }


def apply(
    procedure: dict[str, Any],
    procedure_hash: str,
    grants: dict[str, dict[str, Any]],
    audit_path: Path,
) -> int:
    sid = read_sid()
    client = RpcClient(procedure["endpoint"], sid)
    context: dict[str, Any] = {}
    audit: dict[str, Any] = {
        "procedure_id": procedure["id"],
        "procedure_sha256": procedure_hash,
        "success": False,
        "actions": [],
        "rollback": {"attempted": False, "actions": []},
        "session_destroyed": False,
    }
    committed = False
    uci_mutation_attempted = False
    failure: str | None = None
    try:
        for action in procedure["actions"]:
            if minimum_risk(action["call"]) == "mutation":
                uci_mutation_attempted = True
            entry = run_action(client, action, context, grants)
            audit["actions"].append(entry)
            if (
                action["call"]["object"] == "uci"
                and action["call"]["method"] == "commit"
            ):
                committed = True
        audit["success"] = True
    except (Exception, KeyboardInterrupt) as exc:
        # Interruptions are failures too: restore staged/committed UCI state
        # before the unconditional session-destruction finalizer runs.
        failure = str(exc) or type(exc).__name__
        audit["failure"] = failure
        if uci_mutation_attempted:
            audit["rollback"]["attempted"] = True
            try:
                if committed:
                    if not procedure["rollback_actions"]:
                        raise ProcedureError(
                            "committed state has no executable rollback"
                        )
                    for action in procedure["rollback_actions"]:
                        audit["rollback"]["actions"].append(
                            run_action(client, action, context, grants)
                        )
                else:
                    result = client.call("uci", "rollback", {})
                    audit["rollback"]["actions"].append(
                        {"id": "automatic-uci-rollback", "status": result["status"]}
                    )
                    if result["status"] != 0:
                        raise ProcedureError(
                            f"automatic uci.rollback returned {result['status']}"
                        )
                audit["rollback"]["success"] = True
            except (Exception, KeyboardInterrupt) as rollback_exc:
                audit["rollback"]["success"] = False
                audit["rollback"]["failure"] = (
                    str(rollback_exc) or type(rollback_exc).__name__
                )
    finally:
        try:
            destroyed = client.call("session", "destroy", {})
            audit["session_destroyed"] = destroyed["status"] == 0
            if not audit["session_destroyed"]:
                audit["session_destroy_failure"] = f"UBUS status {destroyed['status']}"
        except (Exception, KeyboardInterrupt) as destroy_exc:
            audit["session_destroy_failure"] = (
                str(destroy_exc) or type(destroy_exc).__name__
            )
        sid = ""  # shorten in-process lifetime
        client.sid = ""
        if not audit["session_destroyed"]:
            audit["success"] = False
            failure = failure or "session destruction was not confirmed"
            audit["failure"] = failure
        write_secure_json(audit_path, audit)
    output = {
        "procedure_id": procedure["id"],
        "procedure_sha256": procedure_hash,
        "success": audit["success"],
        "audit": str(audit_path),
        "session_destroyed": audit["session_destroyed"],
    }
    print(json.dumps(output, indent=2, sort_keys=True))
    return 0 if audit["success"] else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    review_parser = subparsers.add_parser(
        "review", help="validate and render an inspectable plan"
    )
    review_parser.add_argument("procedure", type=Path)
    apply_parser = subparsers.add_parser("apply", help="execute an approved procedure")
    apply_parser.add_argument("procedure", type=Path)
    apply_parser.add_argument("--grant", type=Path)
    apply_parser.add_argument("--audit", type=Path, required=True)
    args = parser.parse_args()

    if shutil.which("websocat") is None and args.command == "apply":
        raise ProcedureError("websocat is required for apply")
    raw = load_json(args.procedure)
    procedure = validate_procedure(raw)
    procedure_hash = value_sha256(raw)
    if args.command == "review":
        print(json.dumps(review(procedure, procedure_hash), indent=2, sort_keys=True))
        return 0
    needed = required_grants(procedure, procedure_hash)
    if needed and args.grant is None:
        raise ProcedureError("this procedure requires --grant")
    grant_raw = load_json(args.grant) if args.grant else None
    grants = validate_grants(grant_raw, procedure, procedure_hash)
    return apply(procedure, procedure_hash, grants, args.audit)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProcedureError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
