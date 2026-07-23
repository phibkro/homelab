#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).with_name("juci_procedure.py")
SPEC = importlib.util.spec_from_file_location("juci_procedure", MODULE_PATH)
assert SPEC and SPEC.loader
juci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(juci)


def base_procedure(actions, rollback_actions=None):
    return {
        "schema_version": 1,
        "id": "test-procedure",
        "summary": "Exercise executor safety behavior",
        "endpoint": "ws://192.168.1.1/",
        "actions": actions,
        "rollback_actions": rollback_actions or [],
    }


class FakeClient:
    responses = []
    calls = []

    def __init__(self, endpoint, sid):
        self.endpoint = endpoint
        self.sid = sid

    def call(self, obj, method, args):
        type(self).calls.append((obj, method, args))
        if obj == "session" and method == "destroy":
            return {"status": 0, "payload": None}
        if not type(self).responses:
            raise AssertionError(f"unexpected call {obj}.{method}")
        response = type(self).responses.pop(0)
        if isinstance(response, BaseException):
            raise response
        return response


class ProcedureTests(unittest.TestCase):
    def setUp(self):
        FakeClient.responses = []
        FakeClient.calls = []

    def test_unknown_calls_default_to_critical(self):
        raw = base_procedure(
            [
                {
                    "id": "reboot-router",
                    "risk": "mutation",
                    "call": {"object": "system", "method": "reboot", "args": {}},
                }
            ],
            [
                {
                    "id": "rollback-placeholder",
                    "risk": "mutation",
                    "call": {"object": "uci", "method": "rollback", "args": {}},
                }
            ],
        )
        with self.assertRaisesRegex(juci.ProcedureError, "requires at least critical"):
            juci.validate_procedure(raw)

    def test_schema_rejects_unknown_fields(self):
        raw = base_procedure(
            [
                {
                    "id": "read-username",
                    "risk": "harmless-read",
                    "call": {
                        "object": "juci.unauthenticated",
                        "method": "username",
                        "args": {},
                    },
                    "operator-note": "ignored fields must not bypass review",
                }
            ]
        )
        with self.assertRaisesRegex(juci.ProcedureError, "unknown fields"):
            juci.validate_procedure(raw)

    def test_endpoint_rejects_query_credentials(self):
        raw = base_procedure(
            [
                {
                    "id": "read-username",
                    "risk": "harmless-read",
                    "call": {
                        "object": "juci.unauthenticated",
                        "method": "username",
                        "args": {},
                    },
                }
            ]
        )
        raw["endpoint"] = "wss://192.168.1.1/?auth=hidden"
        with self.assertRaisesRegex(juci.ProcedureError, "without query or fragment"):
            juci.validate_procedure(raw)

    def test_mutation_requires_executable_rollback(self):
        raw = base_procedure(
            [
                {
                    "id": "add-rule",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "add",
                        "args": {"config": "firewall", "type": "redirect"},
                    },
                }
            ]
        )
        with self.assertRaisesRegex(
            juci.ProcedureError, "require executable rollback_actions"
        ):
            juci.validate_procedure(raw)

    def test_uci_writes_require_forward_and_rollback_commits(self):
        raw = base_procedure(
            [
                {
                    "id": "add-rule",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "add",
                        "args": {"config": "firewall", "type": "redirect"},
                    },
                }
            ],
            [
                {
                    "id": "remove-rule",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "delete",
                        "args": {"config": "firewall", "section": "cfg123"},
                    },
                }
            ],
        )
        with self.assertRaisesRegex(juci.ProcedureError, "forward commits"):
            juci.validate_procedure(raw)

    def test_critical_confirmation_is_exact(self):
        raw = base_procedure(
            [
                {
                    "id": "reboot-router",
                    "risk": "critical",
                    "call": {"object": "system", "method": "reboot", "args": {}},
                }
            ]
        )
        procedure = juci.validate_procedure(raw)
        digest = juci.value_sha256(raw)
        grant = {
            "schema_version": 1,
            "procedure_sha256": digest,
            "grants": [
                {
                    "action_id": "reboot-router",
                    "risk": "critical",
                    "confirmation": "approved",
                }
            ],
        }
        with self.assertRaisesRegex(
            juci.ProcedureError, "invalid critical confirmation"
        ):
            juci.validate_grants(grant, procedure, digest)
        grant["grants"][0]["confirmation"] = f"APPROVE CRITICAL {digest} reboot-router"
        self.assertIn("reboot-router", juci.validate_grants(grant, procedure, digest))

    def test_grant_is_hash_and_action_bound(self):
        raw = base_procedure(
            [
                {
                    "id": "read-firewall",
                    "risk": "sensitive-read",
                    "call": {
                        "object": "uci",
                        "method": "get",
                        "args": {"config": "firewall"},
                    },
                }
            ]
        )
        procedure = juci.validate_procedure(raw)
        digest = juci.value_sha256(raw)
        grant = {
            "schema_version": 1,
            "procedure_sha256": digest,
            "grants": [
                {
                    "action_id": "read-firewall",
                    "risk": "sensitive-read",
                    "allow_response": False,
                }
            ],
        }
        validated = juci.validate_grants(grant, procedure, digest)
        self.assertIn("read-firewall", validated)
        grant["procedure_sha256"] = "0" * 64
        with self.assertRaisesRegex(juci.ProcedureError, "not bound"):
            juci.validate_grants(grant, procedure, digest)

    def test_critical_response_requires_separate_disclosure(self):
        result = {"status": 0, "payload": {"possibly": "sensitive"}}
        action = {"risk": "critical"}
        redacted = juci.audit_response(result, action, {"allow_response": False})
        self.assertEqual(redacted["redacted"], True)
        self.assertNotIn("possibly", redacted)
        disclosed = juci.audit_response(result, action, {"allow_response": True})
        self.assertEqual(disclosed, result["payload"])

    def test_audit_writer_enforces_private_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.json"
            audit_path.write_text("old")
            os.chmod(audit_path, 0o644)
            juci.write_secure_json(audit_path, {"safe": True})
            self.assertEqual(audit_path.stat().st_mode & 0o777, 0o600)

    def test_sensitive_read_failure_destroys_without_rollback(self):
        raw = base_procedure(
            [
                {
                    "id": "read-firewall",
                    "risk": "sensitive-read",
                    "call": {
                        "object": "uci",
                        "method": "get",
                        "args": {"config": "firewall"},
                    },
                    "expect": {"status": 0, "payload_sha256": "0" * 64},
                }
            ]
        )
        procedure = juci.validate_procedure(raw)
        digest = juci.value_sha256(raw)
        grants = {
            "read-firewall": {
                "action_id": "read-firewall",
                "risk": "sensitive-read",
                "allow_response": False,
            }
        }
        FakeClient.responses = [{"status": 0, "payload": {"values": {}}}]
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.json"
            with (
                mock.patch.object(juci, "RpcClient", FakeClient),
                mock.patch.object(sys, "stdin", io.StringIO("1" * 32 + "\n")),
            ):
                result = juci.apply(procedure, digest, grants, audit_path)
            audit = json.loads(audit_path.read_text())
        self.assertEqual(result, 1)
        self.assertFalse(audit["rollback"]["attempted"])
        self.assertTrue(audit["session_destroyed"])
        self.assertEqual(FakeClient.calls[-1][:2], ("session", "destroy"))
        self.assertNotIn(("uci", "rollback", {}), FakeClient.calls)

    def test_interrupt_rolls_back_staged_mutation_and_destroys(self):
        action = {
            "id": "interrupted-write",
            "risk": "mutation",
            "call": {
                "object": "uci",
                "method": "set",
                "args": {"config": "firewall"},
            },
            "expect": {"status": 0},
        }
        procedure = {
            "id": "interrupt-test",
            "endpoint": "ws://192.168.1.1/",
            "actions": [action],
            "rollback_actions": [],
        }
        FakeClient.responses = [{"status": 0, "payload": None}]
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.json"
            with (
                mock.patch.object(juci, "RpcClient", FakeClient),
                mock.patch.object(juci, "run_action", side_effect=KeyboardInterrupt),
                mock.patch.object(sys, "stdin", io.StringIO("3" * 32 + "\n")),
            ):
                result = juci.apply(procedure, "0" * 64, {}, audit_path)
            audit = json.loads(audit_path.read_text())
        self.assertEqual(result, 1)
        self.assertTrue(audit["rollback"]["success"])
        self.assertTrue(audit["session_destroyed"])
        self.assertEqual(FakeClient.calls[-2], ("uci", "rollback", {}))
        self.assertEqual(FakeClient.calls[-1][:2], ("session", "destroy"))

    def test_precommit_mutation_failure_rolls_back_then_destroys(self):
        raw = base_procedure(
            [
                {
                    "id": "add-rule",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "add",
                        "args": {"config": "firewall", "type": "redirect"},
                    },
                    "expect": {"status": 0},
                },
                {
                    "id": "set-rule",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "set",
                        "args": {
                            "config": "firewall",
                            "section": "${actions.add-rule.section}",
                            "values": {"enabled": "1"},
                        },
                    },
                    "expect": {"status": 0},
                },
                {
                    "id": "commit-rule",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "commit",
                        "args": {"config": "firewall"},
                    },
                    "expect": {"status": 0},
                },
            ],
            [
                {
                    "id": "remove-rule",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "delete",
                        "args": {
                            "config": "firewall",
                            "section": "${actions.add-rule.section}",
                        },
                    },
                },
                {
                    "id": "commit-rollback",
                    "risk": "mutation",
                    "call": {
                        "object": "uci",
                        "method": "commit",
                        "args": {"config": "firewall"},
                    },
                },
            ],
        )
        procedure = juci.validate_procedure(raw)
        digest = juci.value_sha256(raw)
        grants = {
            action["id"]: {"action_id": action["id"], "risk": action["risk"]}
            for action in procedure["actions"] + procedure["rollback_actions"]
        }
        FakeClient.responses = [
            {"status": 0, "payload": {"section": "cfg123"}},
            {"status": 5, "payload": None},
            {"status": 0, "payload": None},
        ]
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.json"
            with (
                mock.patch.object(juci, "RpcClient", FakeClient),
                mock.patch.object(sys, "stdin", io.StringIO("2" * 32 + "\n")),
            ):
                result = juci.apply(procedure, digest, grants, audit_path)
            audit = json.loads(audit_path.read_text())
        self.assertEqual(result, 1)
        self.assertTrue(audit["rollback"]["success"])
        self.assertEqual(FakeClient.calls[-2], ("uci", "rollback", {}))
        self.assertEqual(FakeClient.calls[-1][:2], ("session", "destroy"))


if __name__ == "__main__":
    unittest.main()
