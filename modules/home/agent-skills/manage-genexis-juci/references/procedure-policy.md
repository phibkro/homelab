# Procedure and grant policy

## Procedure format

Use JSON so the executor can validate and hash one canonical representation.

```json
{
  "schema_version": 1,
  "id": "inspect-firewall-redirects",
  "summary": "Read current port forwards before planning a change",
  "endpoint": "ws://192.168.1.1/",
  "actions": [
    {
      "id": "read-redirects",
      "risk": "sensitive-read",
      "call": {
        "object": "uci",
        "method": "get",
        "args": {"config": "firewall", "type": "redirect"}
      },
      "expect": {"status": 0}
    }
  ],
  "rollback_actions": []
}
```

Each ID must be unique and contain only lowercase letters, digits, and hyphens.
The procedure must not contain passwords, tokens, session IDs, or secret fields.

`expect.payload_sha256` binds a later procedure to the exact canonical payload
observed by an earlier read. Use it on precondition reads before mutations:

```json
"expect": {
  "status": 0,
  "payload_sha256": "64-lowercase-hex-characters"
}
```

Reference a prior action's payload in later arguments only when the whole value
is an expression:

```json
"section": "${actions.add-forward.section}"
```

## Review output

`review` prints the canonical procedure SHA-256, normalized calls, minimum risk,
rollback calls, and a grant template. Any edit invalidates the grant.

## Grant format

The agent may print a template but must not self-author approval. The operator
must explicitly approve the exact hash and action IDs. The agent may transcribe
that approval without expanding it.

```json
{
  "schema_version": 1,
  "procedure_sha256": "<review output>",
  "grants": [
    {
      "action_id": "read-redirects",
      "risk": "sensitive-read",
      "allow_response": true
    }
  ]
}
```

`allow_response` is required to expose a sensitive or critical payload in the
audit. If false or omitted, only its canonical SHA-256 is retained. Critical
calls use this rule because an unknown method may be a sensitive read as easily
as a destructive write.

Critical actions require this exact additional value:

```text
APPROVE CRITICAL <procedure-sha256> <action-id>
```

Put it in that grant entry as `confirmation`. A general “approved” statement is
not sufficient.

## Mutation and rollback

A procedure containing `mutation` actions must include executable
`rollback_actions`. Include grants for rollback IDs because they may mutate
committed state. Before the first successful commit, the executor invokes
`uci.rollback` automatically on failure. After a commit, it executes the
approved rollback actions in order.

Every UCI `add`, `set`, `delete`, or `order` must have a matching forward
`uci.commit` for its literal config name. A reversible procedure's rollback
must contain both a compensating write and a matching commit for every config
committed by the forward path. The validator rejects incomplete transactions.

If no reliable rollback exists, classify the action and every dependent commit
as `critical`; explain the irreversible consequence in the procedure summary.

Rollback actions may refer to successful forward-action results. For example,
an added anonymous UCI section can be deleted using its returned section name,
then the rollback can commit the same config.

## Audit output

The executor creates the audit file with mode `0600`. It includes:

- procedure ID and SHA-256;
- normalized calls and UBUS statuses;
- full harmless/mutation responses;
- redacted sensitive responses unless disclosure was granted;
- rollback attempts and outcome;
- verification failure details;
- session-destruction confirmation.

The writer rejects a symlink audit target and resets an existing audit file to
mode `0600`. Keep audits outside version control. They can still disclose router
topology and mutation arguments even when response bodies are redacted.
