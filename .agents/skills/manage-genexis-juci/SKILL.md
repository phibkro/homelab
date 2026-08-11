---
name: manage-genexis-juci
description: Safely inspect and change Genexis routers running the JUCI web client through their WebSocket UBUS API. Use for port forwarding, firewall, DHCP, network-device, or other router configuration work when the graphical JUCI interface is broken, fails to persist changes, or needs an auditable programmatic procedure.
---

# Manage Genexis JUCI

Treat router administration as a reviewed transaction. Never improvise live
JSON-RPC writes.

## Required safety contract

1. Draft a credential-free procedure JSON for inspection.
2. Run `python3 .agents/skills/manage-genexis-juci/scripts/juci_procedure.py review <procedure>`.
   Show the normalized summary, SHA-256, calls, rollback, and required grants
   to the operator.
3. Do not create a grant yourself. Materialize only an operator's explicit
   grant, bound to that exact procedure SHA-256 and action IDs.
4. Request a valid JUCI session ID only after approval. Pass it through stdin
   or the script's hidden interactive prompt—never argv, environment, files,
   procedure JSON, logs, or commentary.
5. Run `apply` once. The executor must call `session.destroy` in its finalizer
   on success, failure, interruption, and rollback. Treat unconfirmed
   destruction as overall failure.
6. Report the redacted audit path and destruction result. Never reproduce the
   session ID.

Read [references/api.md](references/api.md) before using an unfamiliar router
method. Read [references/procedure-policy.md](references/procedure-policy.md)
before drafting or approving a procedure.

## Risk classes

Use the executor-enforced minimum; raising risk is allowed, lowering it is not.

| Class | Meaning | Grant |
|---|---|---|
| `harmless-read` | Public, non-sensitive metadata | None |
| `sensitive-read` | Secrets, topology, users, sessions, logs, or configuration | Exact action; response disclosure is separate |
| `mutation` | Reversible state change with executable rollback | Exact action and rollback actions |
| `critical` | Irreversible/destructive action or mutation without reliable rollback | Exact action plus hash-specific confirmation; response disclosure is separate |

Unknown object/method pairs default to `critical`. `uci.get` is always at least
`sensitive-read`; router configuration often contains credentials or exploitable
topology. UCI writes are at least `mutation`. The procedure may not call
`session.login` or `session.destroy`; authorization is handed in and destruction
belongs exclusively to the executor.

The JSON schemas are strict. Keep credentials out of procedure, grant, and
audit paths; the executor rejects common credential fields and endpoint query
strings. Unknown fields are errors rather than ignored metadata.

## Workflow

### 1. Discover without mutating

Fetch the JUCI bundle or use JSON-RPC `list` to confirm the API surface. Do not
assume that two firmware versions expose the same objects.

For configuration-dependent planning, create a read-only procedure first. Let
the operator grant `sensitive-read` and optionally `allow_response`. Its audit
payload hash becomes the mutation procedure's `expect.payload_sha256`
precondition. The read session is destroyed; request a fresh session for apply.

### 2. Draft and review

Keep procedures in an operator-approved temporary or worktree path. Include:

- exact endpoint, object, method, arguments, and declared risk;
- expected UBUS status and state-bound payload hash where applicable;
- explicit `uci.commit` calls;
- executable rollback actions for every reversible mutation;
- post-commit verification reads.

For the complete input shape, adapt
[references/port-forward-https.template.json](references/port-forward-https.template.json).
Its all-zero state hash is intentionally fail-closed; replace it with the hash
from a separately approved discovery read before review.

Run:

```bash
python3 .agents/skills/manage-genexis-juci/scripts/juci_procedure.py review procedure.json
```

Show the output unchanged. If the procedure changes after approval, its hash
changes and the grant becomes invalid.

### 3. Apply with handed-over authorization

After receiving the operator-authored grant and a fresh session ID:

```bash
python3 .agents/skills/manage-genexis-juci/scripts/juci_procedure.py apply procedure.json \
  --grant operator-grant.json \
  --audit juci-audit.json
```

Enter the session ID at the hidden prompt, or pipe exactly one line to stdin.
The executor redacts sensitive and critical responses unless the corresponding
grant sets `allow_response: true`. Keep audit files mode `0600` and out of
version control.

### 4. Verify outside the control plane

Do not equate UCI commit success with service success. Test the resulting
behavior independently—for example, use an off-LAN HTTPS probe for a port
forward and a short packet capture to confirm real client source preservation.

## Failure rules

- Abort before acquiring a session if validation or grants fail.
- On pre-commit failure, invoke `uci.rollback` automatically.
- On post-commit failure, run the approved rollback actions. If none can safely
  restore state, classify the original action `critical` before approval.
- If verification or session destruction fails, return failure even when the
  router accepted the write.
- Never reuse a session ID after an apply attempt.
