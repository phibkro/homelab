# Plan 001: Isolate pavilion from privileged SOPS secrets

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the **STOP conditions** occurs, stop and report; do not improvise. When done, update this plan's row in `plans/README.md` unless the reviewer who dispatched you owns the index.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- .sops.yaml secrets/README.md secrets/secrets.yaml secrets/apps.yaml secrets/beszel-agent.yaml secrets/pavilion.yaml modules/infra/observability/beszel/agent.nix lint/checks/sops-recipient-boundaries.sh flake.nix`
>
> If any in-scope file changed, compare the excerpts below with the live code. A semantic mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

Pavilion is the deliberately low-trust agent-quarantine host, but its persisted SSH host key is currently an age recipient for every encrypted file under `secrets/`. Root compromise, physical loss, or a sandbox escape therefore crosses the quarantine boundary into entry-plane, family-vault, application, and backup credentials. Pavilion needs one public Beszel agent key, not the entire privileged secret domain.

The correct model is separate cryptographic recipient domains. Put the shared Beszel **public** key in its own all-host encrypted file, keep privileged files inaccessible to pavilion, and mechanically test the policy so a future `sops updatekeys` cannot silently undo the boundary.

## Current state

- `.sops.yaml:25-42` defines one recipient group for every `secrets/*.yaml` file. The pavilion age key appears in the same group as Mac, workstation, pi, and aurora.
- `modules/machines/base/sops.nix:23-40` configures each host to decrypt with `/etc/ssh/ssh_host_ed25519_key` and defaults all declarations to `secrets/secrets.yaml`.
- `modules/machines/pavilion/default.nix:17-20` explicitly persists pavilion's SSH host keys across reboots.
- `modules/infra/observability/beszel/agent.nix:66-83` declares only `beszel-hub-pubkey` through SOPS. That value is a public trust key, but all hosts currently obtain it from the privileged default file.
- `secrets/README.md:14-17` says the current broad regex automatically covers every new YAML file. This documentation must change with the policy.

Relevant current shape:

```yaml
# .sops.yaml:33-42
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          # all hosts, including pavilion
```

```nix
# modules/infra/observability/beszel/agent.nix:72-83
sops.secrets.beszel-hub-pubkey = {
  mode = "0400";
};
services.beszel.agent.environmentFile =
  config.sops.secrets.beszel-hub-pubkey.path;
```

Repository conventions to preserve:

- Secret files are committed only in SOPS-encrypted form.
- Per-secret routing uses `sopsFile`, as documented in `secrets/README.md:19-32`.
- Do not print, log, paste into a plan, or commit any decrypted value.
- Security boundaries should be enforced by a flake check, not prose alone (`docs/invariants.md:13-31`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Edit encrypted files | `sops secrets/<file>.yaml` | editor closes and file remains encrypted |
| Re-key a file | `sops updatekeys secrets/<file>.yaml` | exit 0; recipient metadata updated |
| Inspect host secret declarations | `nix eval --json .#nixosConfigurations.pavilion.config.sops.secrets --apply builtins.attrNames` | only pavilion-consumed declarations listed |
| Build affected hosts | `nix build --no-link .#nixosConfigurations.pavilion.config.system.build.toplevel .#nixosConfigurations.aurora.config.system.build.toplevel .#nixosConfigurations.pi.config.system.build.toplevel .#nixosConfigurations.workstation.config.system.build.toplevel` | exit 0 |
| Full gate | `nix flake check --print-build-logs` | exit 0, all checks pass |

## Scope

**In scope**:

- `.sops.yaml`
- `secrets/README.md`
- `secrets/secrets.yaml` — encrypted edit only
- `secrets/apps.yaml` — recipient metadata update only if policy requires it
- `secrets/beszel-agent.yaml` — create, encrypted
- `secrets/pavilion.yaml` — create as the encrypted pavilion-private domain
- `modules/infra/observability/beszel/agent.nix`
- `lint/checks/sops-recipient-boundaries.sh` — create
- `flake.nix` — wire one check

**Out of scope**:

- Rotating application, OIDC, backup, or infrastructure credential values. This plan changes who can decrypt them. If pavilion's host private key is suspected exposed, STOP and request a dedicated operator-led rotation inventory.
- Changing pavilion's sandbox, Tailscale ACLs, SSH policy, or impermanence configuration.
- Moving unrelated secrets between `secrets.yaml` and `apps.yaml`.
- Reproducing any secret or key value in commits, test logs, plan updates, or review comments.

## Git workflow

- When dispatched through `/improve execute`, use the isolated worktree branch supplied by the dispatcher.
- Otherwise do not create, switch, commit, push, or open a PR unless the operator asks.
- Match Conventional Commits, e.g. `fix(secrets): isolate pavilion recipient domain`.
- Never use a bare `git commit` on a shared tree; commit by pathspec if committing is authorized.

## Steps

### Step 1: Define explicit recipient domains

Replace the catch-all creation rule in `.sops.yaml` with ordered, non-overlapping rules:

1. `secrets/beszel-agent.yaml` — recipients: operator recovery identities plus all NixOS hosts, including pavilion. This file may contain only the Beszel hub public key.
2. `secrets/pavilion.yaml` — recipients: operator recovery identities plus pavilion. Reserve this file for future pavilion-private material, including Plan 002's console password hash.
3. Privileged homelab files (`secrets/secrets.yaml` and `secrets/apps.yaml`) — existing privileged recipients, **excluding pavilion**.

Create `secrets/pavilion.yaml` in the SOPS editor during this step. Because SOPS needs a non-empty document, initialize it with one clearly temporary key named `bootstrap-placeholder`; Plan 002 must remove that key when it adds the real pavilion console-hash entry. The placeholder value must contain no credential material.

Use anchored regexes. Do not retain `secrets/.*\.yaml$`, because it makes a future file silently inherit the broadest trust set.

**Verify**:

```bash
perl -ne 'print if /path_regex|pavilion/' .sops.yaml
```

Expected: three explicit rule families are visible; pavilion appears only in the Beszel-agent and pavilion-private groups, not the privileged group.

### Step 2: Move the Beszel public key to its dedicated encrypted file

This step requires an authorized SOPS editor identity.

1. Create `secrets/beszel-agent.yaml` in the SOPS editor with a temporary non-secret scalar at `beszel-hub-pubkey` so the encrypted file exists.
2. Transfer the existing scalar directly through an anonymous pipe; `sops decrypt --extract` emits the JSON-encoded scalar that `sops set --value-stdin` expects:

   ```bash
   sops decrypt --extract '["beszel-hub-pubkey"]' secrets/secrets.yaml \
     | sops set --value-stdin secrets/beszel-agent.yaml '["beszel-hub-pubkey"]'
   ```

3. Verify the destination key decrypts without displaying it: `sops decrypt --extract '["beszel-hub-pubkey"]' secrets/beszel-agent.yaml >/dev/null`.
4. Only after that succeeds, remove the old copy with `sops unset secrets/secrets.yaml '["beszel-hub-pubkey"]'`.
5. Run `sops updatekeys` for all affected encrypted files so their embedded recipient metadata matches `.sops.yaml`.

The plaintext may exist only inside the two SOPS processes and their anonymous kernel pipe. Never place it in shell arguments, command substitution, shell history, terminal output, clipboard managers, editor registers, or a plaintext file.

If the executor cannot decrypt the existing file, STOP and ask the operator to perform this exact encrypted-file move. Do not invent a replacement key: agents on all hosts must continue trusting the existing Beszel hub.

**Verify**:

```bash
sops filestatus secrets/secrets.yaml
sops filestatus secrets/apps.yaml
sops filestatus secrets/beszel-agent.yaml
sops filestatus secrets/pavilion.yaml
```

Expected: every file, including `secrets/pavilion.yaml`, reports encrypted. `git diff -- secrets/*.yaml` must show encrypted ciphertext/metadata only, never readable values. Confirm the new file's visible metadata contains only the pavilion-private recipient group.

### Step 3: Route the Beszel declaration explicitly

Change `modules/infra/observability/beszel/agent.nix` to accept `inputs` and set:

```nix
sops.secrets.beszel-hub-pubkey = {
  sopsFile = inputs.self + "/secrets/beszel-agent.yaml";
  mode = "0400";
};
```

Keep `environmentFile` and the DynamicUser ownership rationale unchanged.

**Verify**:

```bash
for h in workstation aurora pi pavilion; do
  nix eval --raw ".#nixosConfigurations.$h.config.sops.secrets.beszel-hub-pubkey.sopsFile"
  printf '\n'
done
```

Expected: every output ends in `/secrets/beszel-agent.yaml`.

### Step 4: Add a recipient-boundary check

Create `lint/checks/sops-recipient-boundaries.sh`. It must fail when:

- the privileged creation rule includes the pavilion alias;
- `secrets/secrets.yaml` or `secrets/apps.yaml` embedded SOPS recipient metadata contains pavilion's age recipient;
- `secrets/beszel-agent.yaml` is absent or lacks the pavilion recipient;
- the Beszel agent declaration does not explicitly route to `secrets/beszel-agent.yaml`;
- a catch-all `secrets/.*\.yaml` rule returns.

The check must inspect only public policy and encrypted metadata. It must never invoke `sops -d` or emit encrypted payload fields.

Wire it as `checks.x86_64-linux.sops-recipient-boundaries` in `flake.nix`, following `routing-coherence` at `flake.nix:763-782`: `runCommandLocal`, explicit native inputs, run the script, `touch $out`.

**Verify**:

```bash
bash lint/checks/sops-recipient-boundaries.sh .
nix build --no-link .#checks.x86_64-linux.sops-recipient-boundaries
```

Expected: both exit 0. Temporarily adding pavilion to the privileged rule must make the script fail; revert the deliberate break immediately.

### Step 5: Update the operator documentation

Update `secrets/README.md`:

- replace the broad-regex statement at lines 14-17 with the three recipient domains;
- add `beszel-agent.yaml` and `pavilion.yaml` to the file table;
- explain that adding a file requires choosing a trust domain explicitly;
- document the exact `sops updatekeys` commands per file;
- state that pavilion must never become a recipient for `secrets.yaml` or `apps.yaml`.

Do not enumerate secret keys.

**Verify**:

```bash
bash lint/checks/sops-recipient-boundaries.sh .
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- New static boundary test: `lint/checks/sops-recipient-boundaries.sh`.
- Positive cases:
  - privileged files exclude pavilion;
  - Beszel file includes pavilion;
  - Beszel declaration routes explicitly.
- Negative mutation checks, performed locally and reverted:
  - add pavilion to the privileged rule → check fails;
  - restore catch-all regex → check fails;
  - point the module back to the default file → check fails.
- Build all four NixOS hosts to prove each can evaluate the new file routing.
- After deployment, operator-only real journey on pavilion:
  - `systemctl is-active beszel-agent.service` returns `active`;
  - the service reads its environment and reports to the hub;
  - attempting to decrypt `secrets/secrets.yaml` using pavilion's host identity fails. Do not print decrypted output during this test.

## Done criteria

- [ ] Pavilion is absent from privileged SOPS policy and encrypted recipient metadata.
- [ ] `beszel-hub-pubkey` has one authoritative encrypted home: `secrets/beszel-agent.yaml`.
- [ ] Every Beszel agent explicitly consumes that file.
- [ ] The recipient-boundary flake check exists and fails on deliberate policy regressions.
- [ ] All four host toplevels build.
- [ ] `nix flake check --print-build-logs` exits 0.
- [ ] No plaintext secret or key value appears in `git diff` or logs.
- [ ] Only in-scope files are modified.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report if:

- no authorized SOPS editor identity is available;
- moving the Beszel key would require printing or temporarily storing its plaintext outside the SOPS editor;
- any host consumes another secret from pavilion's required trust domain;
- SOPS creation-rule matching semantics differ from the ordered rules assumed here;
- an affected encrypted file already has recipient metadata inconsistent with `.sops.yaml` before this change;
- pavilion's host private key may have been copied, exposed, or available outside the intended machine. That requires a separate credential-rotation decision, not silent scope expansion.

## Maintenance notes

- Every future secret file must choose a trust domain explicitly; do not reintroduce a catch-all creation rule.
- Public material may still warrant an encrypted file when runtime delivery needs a file, but it must not drag unrelated secrets across a trust boundary.
- Reviewers should inspect both `.sops.yaml` and the encrypted files' visible recipient metadata.
- Plan 002 depends on this split and places pavilion's replacement console password hash in `secrets/pavilion.yaml`.
