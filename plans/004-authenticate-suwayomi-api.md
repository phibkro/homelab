# Plan 004: Require Suwayomi authentication on every exempt API request

> **Executor instructions**: This change crosses an authentication boundary and can break Mihon/Tachiyomi or OPDS clients. Implement the application-auth path first, prove unauthenticated requests are rejected, then validate a real client before declaring completion. Do not remove the Authelia exemption without understanding non-browser client behavior.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- modules/services/suwayomi.nix secrets/secrets.yaml scripts/regen-test-secrets.sh tests/secrets/test.yaml tests/e2e-suwayomi-auth.nix flake.nix docs/roadmap.md`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/003-enforce-real-unit-hardening.md` (serializes shared `flake.nix` edits)
- **Category**: security
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

The `manga` family route exempts all `/api/*` requests from Authelia because non-browser clients cannot follow the login redirect. Suwayomi's own Basic authentication is disabled, so the exemption currently means no per-user or application authentication at all. A tailnet family member can reach API operations on a service with writable access to the irreplaceable manga library.

Keep the client-compatible exemption, but make it safe by enabling Suwayomi's supported Basic authentication with a SOPS-delivered password. Verify both sides of the boundary: no credentials are rejected; valid credentials reach the API.

## Current state

- `modules/services/suwayomi.nix:15-27` sets `audience = "family"`, enables forward auth, and exempts `/api/*`.
- `modules/services/suwayomi.nix:77-87` enables the server but does not configure Basic auth.
- `modules/services/suwayomi.nix:90-101` grants writable access to `${config.nori.fs.library.path}/manga`.
- `modules/infra/networking/default.nix:758-766` implements exemptions with Caddy's `not path`, so exempt requests bypass Authelia before proxying.
- The pinned NixOS Suwayomi module supports a secret-file-safe path:

```nix
# nixos/modules/services/web-apps/suwayomi-server.nix:84-105
basicAuthEnabled = mkEnableOption ...;
basicAuthUsername = mkOption { ... };
basicAuthPasswordFile = mkOption { type = nullOr path; ... };
```

The module exports the file contents only at runtime through `TACHIDESK_SERVER_BASIC_AUTH_PASSWORD` (`suwayomi-server.nix:196-225`), so the password does not enter the Nix store.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Edit production secret | `sops secrets/secrets.yaml` | encrypted file saved |
| Regenerate fixture without rotating its test identity | `bash scripts/regen-test-secrets.sh --reuse-key` | only `tests/secrets/test.yaml` changes; exit 0 |
| Build focused VM test | `nix build --no-link .#checks.x86_64-linux.e2e-suwayomi-auth` | exit 0 |
| Build Aurora | `nix build --no-link .#nixosConfigurations.aurora.config.system.build.toplevel` | exit 0 |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `modules/services/suwayomi.nix`
- `secrets/secrets.yaml` — encrypted edit only
- `scripts/regen-test-secrets.sh`
- `tests/secrets/test.yaml` — encrypted generated fixture
- `tests/e2e-suwayomi-auth.nix` — create
- `flake.nix`
- `docs/roadmap.md` — deployment note only if still marked undeployed

**Out of scope**:

- Replacing Authelia or changing the `family` audience model.
- Adding per-family-member Suwayomi accounts; Basic auth is an application credential for API-capable clients.
- Changing Komga or calibre-web exemptions.
- Internet-public exposure or firewall expansion.
- Storing a raw password in Nix, the Nix store, a command line, a test log, or git.

## Git workflow

- Use the dispatcher's isolated worktree if provided.
- Do not deploy, commit, or push without operator authorization.
- Suggested commit: `fix(suwayomi): authenticate exempt api requests`.

## Steps

### Step 1: Add the production SOPS declaration and application auth

In `modules/services/suwayomi.nix`, inside the enabled branch:

1. declare `sops.secrets.suwayomi-basic-auth-password` with:
   - owner `suwayomi`;
   - group `suwayomi`;
   - mode `0400`;
   - `restartUnits = [ "suwayomi-server.service" ];`;
2. set:

```nix
services.suwayomi-server.settings.server = {
  basicAuthEnabled = true;
  basicAuthUsername = "nori";
  basicAuthPasswordFile = config.sops.secrets.suwayomi-basic-auth-password.path;
};
```

Merge these keys with the existing server settings rather than creating a second conflicting block.

Update the exemption comment: `/api/*` is safe only because Suwayomi itself requires Basic auth there. Do not claim that clients authenticate themselves unless the configuration enforces it.

**Verify**:

```bash
nix eval --json \
  .#nixosConfigurations.aurora.config.services.suwayomi-server.settings.server.basicAuthEnabled
nix eval --raw \
  .#nixosConfigurations.aurora.config.services.suwayomi-server.settings.server.basicAuthPasswordFile
```

Expected: `true` and a `/run/secrets/...` path, never `/nix/store/...`.

### Step 2: Add the production secret without exposing it

Generate a unique credential in the operator password manager, then add `suwayomi-basic-auth-password` through `sops secrets/secrets.yaml`. Do not use an existing Authelia, Unix, or API password.

If no authorized SOPS editor is available, STOP and ask the operator to add the named key. The executor may complete code and test-fixture changes but must not mark the plan done.

**Verify**:

```bash
sops filestatus secrets/secrets.yaml
git diff -- secrets/secrets.yaml
```

Expected: encrypted content only.

### Step 3: Extend the real-shape test-secret generator

First add a `--reuse-key` mode to `scripts/regen-test-secrets.sh`. In that mode the script must:

- require the existing `tests/keys/test-age.txt`, `tests/keys/test-age.pub`, and `tests/.sops.yaml`;
- extract/reuse their current test recipient;
- skip key generation and skip rewriting those three identity files;
- regenerate only `tests/secrets/test.yaml`.

The default no-argument mode must retain its current full-regeneration behavior.

Then generate a deterministic-shape but non-production Suwayomi Basic-auth test password and include it in `tests/secrets/test.yaml`. Follow the existing generator's pattern: generation is the source of truth; do not hand-maintain a second test value.

**Verify**:

```bash
git diff --quiet -- tests/keys/test-age.txt tests/keys/test-age.pub tests/.sops.yaml
bash scripts/regen-test-secrets.sh --reuse-key
git diff --quiet -- tests/keys/test-age.txt tests/keys/test-age.pub tests/.sops.yaml
sops filestatus tests/secrets/test.yaml
```

Expected: both `git diff --quiet` commands exit 0; only the encrypted fixture changes.

### Step 4: Add a focused NixOS authentication test

Create `tests/e2e-suwayomi-auth.nix` following `tests/e2e-restic-backup.nix` for real sops-nix fixture setup and `tests/e2e-multi-host.nix` for HTTP assertions.

The VM must import the real Suwayomi service module and its required infra modules, enable the service, provide a writable synthetic `nori.fs.library.path`, and decrypt the test password through the real SOPS fixture.

Required subtests:

1. `suwayomi-server.service` reaches active and opens its configured port.
2. POST exactly `{"query":"query { __typename }"}` with `Content-Type: application/json` to `http://127.0.0.1:8088/api/graphql` without `Authorization`; assert HTTP `401`.
3. Read the test credential inside the VM without printing it, repeat the same POST with `curl --user nori:"$(< /run/secrets/suwayomi-basic-auth-password)"`, assert HTTP `200`, and assert the response JSON contains a non-null `.data.__typename`.
4. Assert the rendered service config contains the environment-variable placeholder rather than the raw password.

Wire the test as `e2e-suwayomi-auth` in `flake.nix` beside the other E2E checks.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.e2e-suwayomi-auth
```

Expected: all subtests pass.

### Step 5: Build and validate the real clients

Build Aurora and run the full gate before deployment:

```bash
nix build --no-link .#nixosConfigurations.aurora.config.system.build.toplevel
nix flake check --print-build-logs
```

After operator-approved deployment:

1. from Aurora, POST the exact GraphQL request `{"query":"query { __typename }"}` to `https://manga.${config.nori.domain}/api/graphql` without credentials and confirm HTTP `401`;
2. from Aurora, repeat with `curl --user nori:"$(< /run/secrets/suwayomi-basic-auth-password)"` without printing the credential; confirm HTTP `200` and `.data.__typename` in the JSON response;
3. browser route still redirects through Authelia and then loads Suwayomi;
4. configure one Mihon/Tachiyomi or OPDS client with the Basic credential;
5. browse, refresh, and start one harmless test operation;
6. confirm no credential appears in Caddy, Suwayomi, or systemd logs.

Do not mark done until one real non-browser client works. If the chosen client cannot send HTTP Basic auth, STOP and report the incompatibility instead of reopening the unauthenticated exemption.

## Test plan

- Layer 2 real module test with real sops-nix fixture:
  - unauthenticated API rejected;
  - valid Basic auth accepted past authentication;
  - service starts with secret-file injection.
- Production build for aurora.
- Runtime journey through Caddy, Authelia browser flow, and one actual API client.

## Done criteria

- [ ] Suwayomi Basic auth is enabled with a SOPS password file.
- [ ] Raw credentials never enter Nix expressions, store paths, logs, or git.
- [ ] `/api/*` remains exempt from Authelia only because application auth is enforced.
- [ ] Focused E2E test proves unauthenticated rejection and authenticated access.
- [ ] Aurora build and full flake check pass.
- [ ] One real Mihon/Tachiyomi or OPDS client works after deployment.
- [ ] Browser access still works through Authelia.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- the pinned NixOS module no longer supports `basicAuthPasswordFile`;
- enabling Basic auth writes the raw password into `/nix/store`;
- no authorized SOPS editor is available;
- the real client cannot send Basic auth;
- the API path required by the client is outside `/api/*` or uses a transport not covered by Caddy;
- satisfying the client appears to require disabling authentication again.

## Maintenance notes

- Any future `forwardAuth.exemptPaths` addition must name the downstream authentication mechanism and ship a negative unauthenticated test.
- Reviewers should look for credentials in generated config and process arguments, not only in source.
- Consider a later schema-level `exemptPathsRequiresOwnAuthReason` contract if another exemption incident occurs; do not build that abstraction in this app-specific fix.
