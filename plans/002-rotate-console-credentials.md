# Plan 002: Replace committed placeholder console credentials with host-scoped SOPS files

> **Executor instructions**: Follow this plan exactly. Never print, paste into logs, or commit a password or password hash. Run every verification gate before proceeding. Stop on any condition listed below rather than improvising. Update this plan's status in `plans/README.md` when complete unless the dispatcher owns the index.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- modules/machines/aurora/default.nix modules/machines/pavilion/default.nix secrets/secrets.yaml secrets/pavilion.yaml lint/rules.toml tests/eval/console-password-files.nix flake.nix`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/001-isolate-pavilion-sops.md`
- **Category**: security
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

Aurora and pavilion currently share a documented temporary placeholder console password hash committed in Nix. The account is `nori`, a wheel member, and wheel has passwordless sudo, so recovery authentication becomes a direct path to root. Password SSH is disabled, but local PAM boundaries and physical console access remain.

The correct state is one independently generated password per host, with only the salted hash delivered through SOPS at activation. The repository should contain neither a reusable hash nor a fallback placeholder.

## Current state

- `modules/machines/pavilion/default.nix:288-295` labels the credential temporary and configures `users.users.nori.hashedPassword` inline.
- `modules/machines/aurora/default.nix:340-345` uses the same temporary pattern.
- `modules/machines/base/users.nix:9-16` places `nori` in `wheel`.
- `modules/machines/base/users.nix:35-41` sets `security.sudo.wheelNeedsPassword = false`.
- NixOS' `hashedPasswordFile` option reads one salted `mkpasswd` hash from a file at activation. The upstream option definition is in `nixos/modules/config/users-groups.nix:376-387` and explicitly exists to avoid storing the hash in the Nix store.
- Plan 001 establishes `secrets/pavilion.yaml` as pavilion-private and keeps `secrets/secrets.yaml` privileged but inaccessible to pavilion.

Target configuration shape:

```nix
sops.secrets.<host>-console-password-hash = {
  neededForUsers = true;
  mode = "0400";
};
users.users.nori.hashedPasswordFile =
  config.sops.secrets.<host>-console-password-hash.path;
```

Use separate secret names and separate generated passwords for aurora and pavilion.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Insert one hash — **operator action inside the private SOPS editor, never an executor-captured tool call** | In Vim opened by `sops`, use `:read !nix shell nixpkgs#mkpasswd --command mkpasswd -m yescrypt`, then join the inserted line to the YAML key | the hash moves directly from `mkpasswd` into the encrypted editor buffer without terminal/transcript output |
| Edit privileged hash | `sops secrets/secrets.yaml` | encrypted file saved |
| Edit pavilion hash | `sops secrets/pavilion.yaml` | encrypted file saved |
| Evaluate password source | `nix eval --raw .#nixosConfigurations.<host>.config.users.users.nori.hashedPasswordFile` | `/run/secrets/<host>-console-password-hash` |
| Build hosts | `nix build --no-link .#nixosConfigurations.aurora.config.system.build.toplevel .#nixosConfigurations.pavilion.config.system.build.toplevel` | exit 0 |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `modules/machines/aurora/default.nix`
- `modules/machines/pavilion/default.nix`
- `secrets/secrets.yaml` — encrypted edit only
- `secrets/pavilion.yaml` — encrypted edit only
- `lint/rules.toml`
- `tests/eval/console-password-files.nix` — create
- `flake.nix` — wire the eval test

**Out of scope**:

- SSH authorized keys, root SSH policy, wheel membership, or `wheelNeedsPassword`.
- Workstation or pi account passwords.
- Password-manager policy or choosing the human-readable passwords for the operator.
- Removing console recovery access. This plan preserves it safely.
- Reusing one password or hash across hosts.

## Git workflow

- Use the dispatcher's isolated worktree when executing through `/improve execute`.
- Otherwise do not create branches, commit, or push without operator instruction.
- Suggested commit: `fix(auth): move console hashes behind host-scoped sops`.
- Never include generated hashes in commit messages, review text, test fixtures, or terminal transcripts.

## Steps

### Step 1: Add a source guard before changing credentials

Add a `nori.lint` rule in `lint/rules.toml` that rejects inline `users.users.*.hashedPassword =` declarations under `modules/`. The message must direct authors to `hashedPasswordFile` backed by SOPS. Scope the pattern narrowly enough not to reject documentation that names the option.

Use the existing TOML rule registry described at `docs/invariants.md:98-114`; do not add a standalone grep derivation.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.lint
```

Expected before removing the old lines: the check fails and cites both host files. This is the required RED state.

### Step 2: Generate two independent replacement credentials

The operator must choose and record two different recovery passwords in the real password manager. The operator—not an executor whose shell output is captured—must open each file with `sops` in the configured Vim editor, type the YAML key, and use Vim's `:read !nix shell nixpkgs#mkpasswd --command mkpasswd -m yescrypt` so the generated line enters the encrypted editor buffer directly. Join the inserted hash onto the YAML key before saving. Do not run `mkpasswd` as a standalone captured shell command.

Insert:

- `aurora-console-password-hash` in `secrets/secrets.yaml`;
- `pavilion-console-password-hash` in `secrets/pavilion.yaml`.

Remove Plan 001's `bootstrap-placeholder` from `secrets/pavilion.yaml` in the same edit. The encrypted value must be one line containing only the salted hash. Do not use shell variables, redirections, clipboard history, or a plaintext temporary file. If the executor is not authorized to operate SOPS, STOP and ask the operator to complete this step.

**Verify**:

```bash
sops filestatus secrets/secrets.yaml
sops filestatus secrets/pavilion.yaml
git diff -- secrets/secrets.yaml secrets/pavilion.yaml
```

Expected: both files report encrypted; diff shows ciphertext and metadata only.

### Step 3: Consume the hash files during user creation

In each host module:

1. ensure the module function includes `config`;
2. declare the host-specific SOPS secret with `neededForUsers = true` and `mode = "0400"`;
3. replace inline `hashedPassword` with `hashedPasswordFile` pointing at the rendered secret;
4. update the comment to state that the recovery password is host-specific, SOPS-delivered, and must be validated at the console after deployment.

`neededForUsers = true` is load-bearing: user creation occurs before normal `/run/secrets` installation.

**Verify**:

```bash
for h in aurora pavilion; do
  printf '%s: ' "$h"
  nix eval --raw ".#nixosConfigurations.$h.config.users.users.nori.hashedPasswordFile"
  printf '\n'
done
```

Expected:

```text
aurora: /run/secrets-for-users/aurora-console-password-hash
pavilion: /run/secrets-for-users/pavilion-console-password-hash
```

Accept the exact sops-nix users-stage prefix emitted by the current version; reject any `/nix/store/...` path or null value.

### Step 4: Add an eval regression test

Create `tests/eval/console-password-files.nix` following `tests/eval/route-invariants.nix`:

- evaluate the real aurora and pavilion configurations or a minimal module fixture that imports their account declarations;
- assert `hashedPassword == null` on both hosts;
- assert `hashedPasswordFile` points to the expected rendered SOPS secret path;
- assert the two paths and secret names differ;
- return a short `ok — ...` string or throw a diagnostic.

Wire it into `flake.nix` as `eval-console-password-files` using the existing `runCommandLocal` pattern at `flake.nix:1001-1042`.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.eval-console-password-files
nix build --no-link .#checks.x86_64-linux.lint
```

Expected: both exit 0.

### Step 5: Build and perform the real recovery journey

Build both host closures first:

```bash
nix build --no-link \
  .#nixosConfigurations.aurora.config.system.build.toplevel \
  .#nixosConfigurations.pavilion.config.system.build.toplevel
```

After operator-approved deployment, test **one host at a time**:

1. keep an existing SSH session open;
2. use a physical or virtual TTY to log in as `nori` with the new host-specific password;
3. run `sudo true` and confirm passwordless sudo still works;
4. confirm the other host's password does not authenticate on this host;
5. only after success deploy and test the second host.

This live verification cannot be replaced by eval or VM tests because the feature exists specifically for console recovery.

## Test plan

- Static lint: inline `hashedPassword` under `modules/` is forbidden.
- Eval test: both hosts consume different SOPS-backed `hashedPasswordFile` paths and no inline hash.
- Build: aurora and pavilion toplevels.
- Runtime journey: real TTY login on each host, independently, with an existing SSH session retained as rollback access.

## Done criteria

- [ ] No inline `users.users.*.hashedPassword` remains under `modules/`.
- [ ] Aurora and pavilion use distinct SOPS secret names and distinct operator-selected passwords.
- [ ] Pavilion's hash lives in the pavilion-only recipient domain from Plan 001.
- [ ] Both affected host closures build.
- [ ] `eval-console-password-files` and `lint` pass.
- [ ] `nix flake check --print-build-logs` passes.
- [ ] Operator verifies console login and recovery access on both hosts.
- [ ] No password or hash is present in git diff, logs, comments, or plan updates.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop and report if:

- Plan 001 is not complete or pavilion can still decrypt `secrets/secrets.yaml`;
- an authorized SOPS editor is unavailable;
- the password manager does not yet contain both replacement passwords;
- the evaluated `hashedPasswordFile` lands in `/nix/store`;
- `neededForUsers` is unsupported by the pinned sops-nix version;
- a host cannot be tested through a real console while a rollback SSH session remains open;
- changing the credential requires altering SSH or sudo policy.

## Maintenance notes

- Console recovery credentials are host identities, not shared operator configuration. Generate a new one when a host is repurposed or transferred.
- Reviewers should verify the absence of inline hashes without requesting the replacement values.
- The lint rule is the durable enforcement; comments are only rationale.
