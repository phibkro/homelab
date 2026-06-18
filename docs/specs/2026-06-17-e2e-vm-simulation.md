---
date: 2026-06-17
status: Phases 1-6 EXECUTED 2026-06-18; Phase 7 (ntfy + OnFailure path) deferred
executed-as:
  - Phase 1   cc9d1d4   pi-alone framework smoke (scope-down — see
                        phase-1-scope-down below)
  - Phase 2   9fd2163   sops-stub fixture + homelab blocky module
                        with lanRoutes → customDNS auto-generation
                        validated end-to-end
  - Phase 3   0390b39   gatus + heartbeat observability services
                        added; validates timer-driven unit
                        activation pattern under sops-stub
  - Phase 4   68bd30b   caddy entry-plane added with internal CA
                        (no real ACME contact, plain pkgs.caddy
                        instead of cloudflare-plugin variant);
                        sops-stub extended with templates + placeholder
                        for caddy's CF_API_TOKEN template wiring
  - Phase 5b  ca55db1   testing methodology doc (3-layer pyramid)
                        + 2 layer-1 eval checks (sub-second) +
                        just e2e-shell / just test-eval recipes.
                        Establishes the TDD inner-loop ergonomics.
  - Phase 6   pending   real sops + authelia. Replaces sops-stub
                        with the actual sops-nix module against a
                        committed test age key + committed sops-
                        encrypted test.yaml containing real-shape
                        secrets (argon2id user hash, RSA OIDC issuer
                        key, 32B random for jwt/session/storage/hmac,
                        authelia-generated PBKDF2 for OIDC client
                        secret hash). Authelia reaches active +
                        binds :9091; /api/health responds OK. Layer-1
                        eval tests migrated to real sops too.
                        sops-stub.nix deleted. Test cycle: 20s warm.

phase-5-superseded-by-6: Phase 5's authelia attempt with option-schema
  stubs failed because authelia parses every secret at startup. Phase 6
  fixed it by stopping the stubbing — use real sops-nix against real
  test data. The lesson became the methodology doc's "Real values,
  not stubs" section: stubbing IS lying about composition; if you can
  generate real-shape test data, you should.

phase-7-deferred: ntfy / OnFailure-handler integration. Currently
  ntfy-channel + ntfy-publisher-token are stub values in test.yaml
  so modules that reference them eval cleanly; ntfy itself is NOT
  enabled in the VM. A future Phase 7 would stand up a real ntfy
  server in-VM, intentionally fail a unit, and assert a notification
  lands. That validates the OnFailure → notify@ pipe end-to-end.
phase-1-scope-down: original Phase 1 was "blocky + gatus + beszel-hub
  from real pi config + sops fixture". Discovered mid-execution that
  the homelab module graph requires pervasive sops-secret reads at
  activation time; building a proper test-key fixture layer was
  genuine Phase 2 work, not Phase 1 polish. Pivoted to a framework
  smoke: minimal NixOS config + bare nixpkgs blocky module +
  customDNS resolution check. Phase 2 then folded gatus + ntfy +
  caddy + authelia coverage back in via the sops-stub approach
  (option-schema fake, not real decryption — see fixtures/sops-
  stub.nix). Real homelab blocky.nix + lanRoutes registry pipeline
  validated; phases 3+ pick up gatus/caddy/authelia (each needs
  additional fixture work beyond the option stub).
seed: operator question 2026-06-17 ("is it possible to simulate our homelab system? end-to-end testing before application")
summary: Adopt `pkgs.nixosTest` as the end-to-end pre-flight for inter-host wiring. QEMU boots the host trees inside a synthetic network, a Python driver exercises the entry-plane / routing / observability seams that single-host `nh os test` cannot cover. Phased: phase 1 (pi-alone smoke) → phase 2 (pi + workstation routing) → phase 3 (all 3 NixOS hosts) → phase 4 (push-gate integration). Explicitly NOT a replacement for `nh os test`, real-host journey verification, or the push gate's diff review — it's an additional safety net for the regression class "entry-plane silently broke X".
---

# End-to-end VM simulation (spec)

The homelab's current pre-flight is `nh os test` (single-host activation, no boot menu pollution). It catches "does this rebuild break this host?". It does NOT catch "does this rebuild silently break the *wiring between* hosts": entry-plane routing flips, cross-host DNS, Authelia upstream changes, Gatus probe contracts, backup endpoints, ntfy alert delivery. Those regressions surface in prod or in `git log` after the fact.

`pkgs.nixosTest` is the canonical Nix primitive for closing that gap: it boots N NixOS VMs in QEMU on a synthetic network and runs a Python `testScript` against them. Inter-host wiring becomes verifiable at evaluation time.

## Why

```
problem                                  symptom
─────────────────────────────────────────────────────────────────
inter-host wiring is unverified          incident 2026-06-03 class:
until prod                               ExecStart resolved wrong;
                                         a caddy upstream regressed
                                         silently; gatus probe URLs
                                         drift after a service moves
                                         host. nh os test cannot
                                         catch any of these because
                                         they involve >1 host.

push-gate review is human-grep over      operator scans `git log -p
the diff                                 origin/main..HEAD` to spot
                                         entry-plane regressions.
                                         Works; slow; misses subtle
                                         coupling.

routing changes are bimodal              either green (works) or
                                         red (broken in prod). No
                                         pre-flight that boots the
                                         minimal closure end-to-end.

aurora migration P-series ran the        most P-* gates were operator-
real journey on real hosts               run on real hardware. That
                                         was correct for the
                                         migration BUT means each
                                         phase carried real-host
                                         downtime as the failure mode.
```

The `nixosTest` primitive solves exactly this — *minus* the things that depend on hardware QEMU can't model (NVENC, USB, real tailnet, NVIDIA, ZFS-on-USB). Those stay on real-host verification.

## The cut

```
single-host activation     →  nh os test       (already in place)
inter-host wiring          →  nixosTest        (THIS SPEC)
real-hardware journey      →  manual / runbook (already in place)
real-tailnet OAuth         →  manual           (already in place)
real-backup endpoints      →  restic / btrbk   (already in place)
```

Three layers, three primitives. `nixosTest` plugs the middle gap.

## What `nixosTest` is

```nix
pkgs.nixosTest {
  name = "homelab-routing-smoke";

  nodes = {
    pi = { config, pkgs, ... }: {
      imports = [
        ./modules/common
        ./modules/infra
        ./modules/services
        # synthetic host identity (no real tailnet)
        ./tests/fixtures/pi-fixture.nix
      ];
      nori.services.caddy.enable = true;
      nori.services.blocky.enable = true;
      nori.enableServicesByTag = [ "entry-plane" ];
    };

    workstation = { ... }: {
      imports = [ ./modules/common ./modules/infra ./modules/services
                  ./tests/fixtures/workstation-fixture.nix ];
      nori.enableServicesByTag = [ "compute" ];
    };
  };

  testScript = ''
    start_all()
    pi.wait_for_unit("caddy.service")
    pi.wait_for_unit("blocky.service")
    workstation.wait_for_unit("multi-user.target")

    # entry-plane resolves a known route
    workstation.succeed("curl -sfI https://status.test.lan/")

    # DNS authoritative — pi resolves a synthetic LAN name
    workstation.succeed("dig +short station.test.lan @pi | grep -E '^[0-9]'")

    # Gatus probe contract — health page returns 200
    workstation.succeed("curl -sf http://pi:8080/api/v1/endpoints/status")
  '';
}
```

Wrapped as a flake check or runnable derivation:

```bash
nix build .#checks.x86_64-linux.e2e-routing-smoke
# or interactively
nix run .#nixosTests.e2e-routing-smoke.driverInteractive
```

## What it gets you

```
real         ✓ qemu-kvm VMs, real systemd, real units start
             ✓ real package closures, real config evaluation
             ✓ real network: synthetic bridge between nodes
             ✓ real journal, real logs, real OOMs
             ✓ machine.wait_for_unit / succeed / fail / screenshot

cost         ~30-90s per phase 1 run (single VM, no closure rebuild)
             ~2-4min per phase 3 run (3 VMs, parallel boot)
             RAM: ~2 GB per VM during run (configurable)
             Disk: ephemeral overlays; closure cached after first build

ergonomics   testScript is Python — assertions are direct
             driverInteractive drops you to a shell into each VM
             screenshots / journal dumps on failure (auto)
             reproducible: same Nix inputs → same VM state
```

## What it WILL NOT catch

```
✗ NVENC / nvidia-gpu-exporter — QEMU has no NVIDIA
✗ USB enumeration / IronWolf — no real USB
✗ tailnet routing / Authelia real OAuth — no real tailnet
✗ disko by-id paths — no real /dev/disk/by-id
✗ btrbk replication over ssh+tailnet — synthetic only
✗ services that READ sops at runtime — need test-key fixture
✗ real internet — DNS, HTTPS to public CAs
✗ NVIDIA Wayland edge cases — no display
✗ jellyfin transcode — no GPU
```

Real-host journey continues to own these. The spec is explicit: nixosTest IS the inter-host wiring net; nothing more.

## Phasing

### Phase 1 — pi-alone smoke (single-node nixosTest)

```
nodes      pi-only
checks     systemd targets: caddy, blocky, gatus
           caddy serves a synthetic vhost
           blocky resolves a synthetic LAN zone
           gatus self-probe returns 200
fixtures   tests/fixtures/pi-fixture.nix  (synthetic identity)
           tests/fixtures/sops-test-key   (decryptable dummy secrets)
target     nix build .#checks.x86_64-linux.e2e-pi-smoke
gate       wires into `nix flake check` (12th check)
runtime    ≤60s on workstation
```

DoD: `nix flake check` passes locally; the check fires on a deliberate caddy/blocky breakage.

### Phase 2 — pi + workstation routing (two-node)

```
nodes      pi + workstation
checks     entry-plane: workstation curls https://status.test.lan/ via pi
           backwards probe: pi resolves station.test.lan via Blocky
           audience policy: operator route reachable; family route 401 without OIDC
           lan-route registry: every defined route serves at /
target     nix build .#checks.x86_64-linux.e2e-routing
runtime    ≤3min
```

DoD: deliberately misconfiguring `nori.lanRoutes.<X>.runsOn` breaks the test;
correcting it passes.

### Phase 3 — all-3 NixOS hosts (full triad)

```
nodes      pi + aurora + workstation
checks     family-vault posture: aurora hosts vaultwarden, immich, calibre-web
           workhorse posture: workstation hosts arr/, jellyfin (sans GPU stubbed)
           cross-host backup: aurora → workstation MP510 stub (synthetic
                              btrbk over network, NOT real subvol replication)
           observability fan-in: workstation + aurora ship metrics to pi
target     nix build .#checks.x86_64-linux.e2e-full
runtime    ≤6min
```

DoD: vaultwarden migration between aurora and workstation breaks if
fate-sharing class shifts.

### Phase 4 — push-gate integration

```
local pre-push    phase 1 + 2 in `.githooks/pre-push` (opt-in)
                  fast (≤4min total)
flake check       phase 1 only (mandatory; runs in `nix flake check`)
just recipe       `just e2e [phase]` for interactive use
                  `just e2e-shell` opens driverInteractive
gating policy     phase 1: mandatory (CI-equivalent)
                  phase 2: pre-push opt-in (operator's local hook)
                  phase 3: on-demand (slow; before risky restructures)
```

DoD: a regression that would have shipped under phase-0 status quo is
caught by phase 2 in the operator's pre-push.

## Fixtures — the awkward part

`nixosTest` needs a fixture layer because the real homelab depends on:

```
real input              test fixture
─────────────────────────────────────────────────────────
sops decryption key     dummy age key checked into
                        tests/fixtures/ (intentional)
tailnet identity        synthetic /etc/hosts + lanIp overrides
DNS root                point Blocky at a synthetic upstream
public ACME             internal Caddy issuer (test-only)
USB / disk paths        SKIP (out of scope for inter-host nets)
GPU device              SKIP (out of scope)
```

The fixture layer lives at `tests/fixtures/` (NEW directory). One fixture
file per host overrides identity + secrets paths; the rest of the module
tree imports cleanly. Fixtures must NOT touch `nori.services` activation;
the spec is "real config minus identity + secrets".

Open question Q1: should fixtures live at `tests/fixtures/` (top-level)
or `modules/tests/fixtures/` (consistent with modules-as-root)? Bias:
top-level — `modules/` is *config to deploy*; `tests/` is *checks against
that config*. Different concerns.

## Goal / Constraints / Values

**Goal (verifiable):** `nix flake check` runs an e2e-pi-smoke check that
verifies caddy + blocky + gatus start, serve, and probe each other on a
single QEMU VM. Wrong routing config makes the check fail with a
useful error.

**Constraints (hard invariants):**

- C1. MUST run on workstation (x86_64-linux). Build host = test host.
- C2. MUST NOT require real secrets. Dummy sops fixture is mandatory.
- C3. MUST NOT touch real tailnet, real DNS, real ACME. All synthetic.
- C4. MUST be a flake check (`.#checks.x86_64-linux.<name>`). Not a
      bash script. Reproducibility is non-negotiable.
- C5. MUST NOT extend per-host runtime by >60s for phase 1, >4min for
      phase 2. Slow checks erode willingness to run.

**Values (soft invariants):**

- V1. Prefer driverInteractive ergonomics — operator drops into a VM
      shell when a check fails, not greps logs.
- V2. Prefer phase-1-mandatory over phase-3-mandatory — fast cheap
      checks compound; slow expensive checks get skipped.
- V3. Prefer test-script reads like operator intent ("workstation curls
      pi over LAN-route X") over Python plumbing.

## Cost

```
build          phase 1: ~5-10min first time (closure), ~30s cached
               phase 2: ~10-15min first time, ~90s cached
               phase 3: ~15-25min first time, ~3min cached
fixture work   tests/fixtures/sops-test-key  (one-time)
               tests/fixtures/<host>-fixture.nix  (one per host;
                                                 ~20-50 lines each)
maintenance    each new nori.lanRoutes entry → test the route in
               phase 2; ~3 lines of testScript
               each new service → add to phase 3 if cross-host wire
risk           CI tightens; intentional misconfigs fail the check
               (this is the value, not a cost)
```

## Non-goals

- NOT a replacement for `nh os test`. Different concern (single-host
  activation vs inter-host wiring).
- NOT a replacement for the push gate diff review. The push gate stays
  mandatory; e2e is additional.
- NOT a real-tailnet test. The OAuth flow stays in real-host journey.
- NOT a perf or load test. nixosTest is not benchmarked.
- NOT replacing the existing flake checks (every-service-has-fs-hardening,
  forbidden-patterns, …). They run at eval; e2e runs at boot.

## Open questions

```
Q1   tests/ at top-level or modules/tests/?
     → bias: top-level. Different concern from "config to deploy".

Q2   sops test-key in repo (decryptable plaintext) or per-clone?
     → bias: in repo. The "leak" surface is dummy data by construction;
       the key is named `tests/fixtures/sops-test-key` and never
       used in prod. Document the constraint loudly in the fixture
       file's header.

Q3   how synthetic should DNS be?
     → bias: full synthetic. Test zone is `test.lan`; Blocky configured
       authoritative for it; nothing reaches real DNS.

Q4   does phase 3 model the macbook?
     → bias: NO. Mac is home-manager-only, never a NixOS module
       consumer. Out of scope for nixosTest by construction.

Q5   how do we model pavilion?
     → bias: NOT in phase 1-3. Pavilion is agent quarantine, has no
       routing or backup concerns. Optional phase 5 for impermanence
       verification specifically.

Q6   phase 1 check name?
     → bias: `e2e-pi-smoke`. Phase 2 = `e2e-routing`. Phase 3 =
       `e2e-full`. Three-tier naming visible in `nix flake show`.

Q7   should the existing flake checks adopt the same nixosTest
     primitive (e.g. systemd-execstart-resolves)?
     → out of scope. systemd-execstart-resolves is eval-time
       introspection; nixosTest is boot-time. Different tools for
       different layers.

Q8   when does this conflict with `nh os test`?
     → never. `nh os test` is per-host activation against the operator's
       active config. nixosTest is eval-time of synthetic configs against
       the testScript. They cover orthogonal layers.

Q9   modules with hardware deps (NVIDIA, GPU exporter) — how do they
     coexist in a QEMU host?
     → fixture overrides. Each fixture file sets
       `hardware.opengl.enable = lib.mkForce false` and similar.
       Modules that gate on `config.hardware.<X>` skip in the fixture.
```

## Phase ordering

```
0   spec   (this doc)
1   pi-alone smoke + fixture layer
       lands sops test-key, tests/fixtures/, first nixosTest
       12th flake check
2   routing two-node
       phase 2 check; pre-push hook (opt-in)
3   full triad
       phase 3 check; on-demand
4   integration polish
       just recipe, driverInteractive, doc the "what fails how" loop
```

## Migration shape

```
phase 1 lands as a single PR:
  + tests/fixtures/sops-test-key
  + tests/fixtures/pi-fixture.nix
  + tests/e2e-pi-smoke.nix
  + flake.nix:   add `e2e-pi-smoke` to checks
  + docs/reference/runtime-tests.md: section "e2e tests"
  ~ Justfile:    add `just e2e` recipe (target phase 1)

phase 2 lands as a second PR after phase 1 stabilizes; same shape.
phase 3 likewise. Each phase is verifiable independently.
```

## Reversibility

`nixosTest` is opt-in by design; each phase adds a flake check that can
be disabled by removing one attribute. No load-bearing config depends on
the test layer. Reversibility is trivially perfect: delete `tests/` and
remove the check entries from `flake.nix`. Cost paid is fixture
authorship.

## Predecessor / successor

- Builds on: the modules-as-root restructure (clean import shape makes
  fixtures easier to author), the Stage 3-5 generator pipeline (the
  fixture pattern is a sibling of the docs-fresh "synthetic input →
  reproducible output" loop).
- Enables: future "before this risky change, run phase 3 first" workflow.
  Pairs naturally with `docs/specs/2026-06-17-machine-capabilities.md`
  once placement-resolver lands — the resolver's outputs become directly
  testable in phase 3 (which host gets which service).
- Does not block: any current outstanding work. Pure addition.
