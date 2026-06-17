---
summary: Eval-time flake check that catches ExecStart first-tokens which
  don't resolve to /nix/store/ closure paths. Prevents the typo-mass-outage
  incident class (2026-06-03 cf. `.claude/skills/gotcha-systemd-execstart-
  resolves/` once it exists). High-value promotion; needs more design than
  a single sub-sprint can absorb so deferred to a focused session.
status: research seed — Prologue done, gate-passed-A (defer to fresh
  session) on 2026-06-16. Open questions enumerated; scope-down options
  named. Implementation queued.
trigger: 2026-06-16 end-of-session, operator picked "B then C" with B =
  this promotion. Prologue research revealed eval-time mechanism + four
  syntactic variants (ExecStart shape) push this from the assumed
  30-45 min sub-sprint to genuine 1-2h. Operator chose to defer rather
  than over-budget the session.
---

# Spec — `systemd-execstart-resolves` flake check

> **Research seed; not a plan yet.** Captures the Prologue surfaced
> mid-session so the fresh agent inherits the scoping work rather than
> re-deriving it.

## Goal (when sprinted)

Catch the typo-mass-outage incident class at eval time: scan all
`systemd.services.<n>.serviceConfig.ExecStart` (and user-service
equivalents) and assert the first token resolves to a `/nix/store/`
closure path.

**Verifiable by:**
1. Flake check derivation lands; `nix flake check` green
2. Current tree passes (audited 2026-06-16: 10 ExecStart, all use
   `${pkgs.X}/bin/Y` form — should yield zero false positives)
3. Negative test: synthetic `ExecStart = "/usr/bin/missing"` or
   `ExecStart = "bare-binary"` fires the check
4. Promotion register updated; this spec marked graduated

## Why this matters

A typo in `ExecStart` cascades into mass-service-outage on next rebuild
because `switch-to-configuration`'s stop-timeout path doesn't run the
start phase. Caught operationally on 2026-06-03 (cf. roadmap promotion
register entry); the failure mode is silent until restart.

**What this catches:** non-existent binaries, bare names without paths,
system paths instead of closure paths, typos to package names.

**What this does NOT catch:** invalid CLI flags (the 2026-06-03 incident
itself was a `--no-such-flag` style typo on a real binary). That class
needs runtime probing or unit-startup validation — out of scope here.

## Implementation sketch

```nix
let
  # Eval workstation (most services) — expand to all hosts post-v1
  cfg = self.nixosConfigurations.workstation.config;
  services = cfg.systemd.services;

  # Extract first token from ExecStart's two syntactic forms
  firstToken = exec:
    let
      stripped = lib.removePrefix "+" exec;  # systemd "run as service user" prefix
    in
    if builtins.isString stripped
      then lib.head (lib.splitString " " stripped)
    else if builtins.isList stripped
      then builtins.head stripped
    else null;

  isResolved = path: path != null && lib.hasPrefix "/nix/store/" path;

  broken = lib.filterAttrs (name: svc:
    let
      exec = svc.serviceConfig.ExecStart or null;
    in
    exec != null && !(isResolved (firstToken exec))
  ) services;
in
  # If `broken` is non-empty → fail
```

## Syntactic variants (audited 2026-06-16, 10 sites)

| Form | Count | Example |
|---|---|---|
| String, `${pkgs.X}` prefix | 8 | `ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync ${configFlags}"` |
| List via `lib.concatStringsSep` | 2 | `ExecStart = lib.concatStringsSep " " [ "${pkgs.darkhttpd}/bin/darkhttpd" ... ]` |
| `+` prefix (privileged exec) | 1 | `ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart heim-serve.service"` |

The eval-time check sees the post-interpolation value — both list and
string forms reduce to a string at that layer. The `+` prefix must be
stripped before the prefix check.

## Open questions (blocking gate-pass when sprinted)

1. **Per-host scope.**
   - v1 = workstation only (most services; validates mechanism)
   - v2 = all 4 NixOS hosts (workstation + pi + aurora + pavilion)
   - Pavilion is impermanence-rooted, less service-heavy, lower
     priority

2. **Module assertion vs flake-check derivation.**
   - **Module assertion** fires per-host during eval; error message
     attached to the offending service; more localized
   - **Flake check derivation** = dedicated check in `checks.${system}`;
     pattern-matches existing every-service-has-X; cross-host summary
   - Lean: module assertion (matches the `[structural]` invariant rung
     in `docs/invariants.md`)

3. **Exec\* coverage.**
   - v1 = `ExecStart` only (catches the named incident class)
   - Future = `ExecStartPre`, `ExecStartPost`, `ExecStop`,
     `ExecStopPost` (same failure mode, lower frequency)
   - Heim's `ExecStartPost` is the only non-ExecStart Exec\* in the
     tree today

4. **Home-manager user services.**
   - Per the original register entry, in scope:
     `config.home-manager.users.*.systemd.user.services`
   - User services hit the same failure mode but at user-session
     level, not boot-cascade
   - Adds another iteration loop; mechanically straightforward

## When this becomes a sprint

A fresh session with the eval-iteration mechanism design done. Probably
1-2 hours. The four open questions above are the Prologue work —
answered once, execution is straightforward.

Trigger: any of
- An ExecStart typo lands on `main` (forcing function)
- Operator picks it for a focused session
- Sprint 6+ in the agentic-workflow research arc needs a different-
  shape sprint (this would be N=4 under the ceremony, different
  mechanism class than nori.lint promotions)

## References

- `docs/invariants.md` § Promotion register (entry #2 remaining after
  Sprint 4's function-named-subdomains promotion)
- `docs/roadmap.md` § Promotion register
- `.claude/skills/gotcha-systemd-execstart-resolves/` — would
  document the failure mode once the check lands and someone trips it
- Sprint 3 (`feat(checks): Phase 3d — nori.lint TOML registry`) +
  Sprint 4 (`feat(checks): promote function-named-subdomains`) —
  precedents for promotion-via-flake-check; but those are grep-shaped
  and live in `modules/lint/`. This one is eval-shaped and lives in
  the host module system or flake checks directly.
