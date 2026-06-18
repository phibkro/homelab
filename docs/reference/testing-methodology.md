---
summary: How testing works in this homelab — the three-layer pyramid
  (eval / nixosTest / runtime introspection), when to reach for which,
  the red-green-refactor workflow per layer, speed budgets that make
  TDD viable, and the fixture + stub conventions that keep tests
  honest. Companion to `runtime-tests.md` which covers the live-system
  introspection layer in detail.
---

# Testing methodology

The homelab has THREE distinct test layers. They differ in speed,
scope, and what failures they catch. Knowing which to reach for is
the difference between "TDD works here" and "tests are theatre."

```
                                speed         scope               catches
─────────────────────────────────────────────────────────────────────────
1. eval        nix eval            sub-second   pure declarative    schema invariants,
   tests       expression                       module composition  eval-time errors,
                                                                    cross-option asserts

2. nixosTest   pkgs.testers        30s-5min     boot-time + first   unit-startup failures,
               .runNixOSTest                    100ms of runtime    multi-module compose,
                                                                    bare-name ExecStart,
                                                                    sops-fixture wiring

3. runtime     just test-<X>       seconds      live deployed       intent-vs-actual drift,
   introspection                                system               silent staleness
                                                                    (backup gaps,
                                                                    routing desync)
```

## When to write which

```
                                  decision tree
                                  ─────────────────
                                          │
                       ┌──────────────────┴──────────────────┐
                       │                                     │
              "is this a pure eval-                "does the failure
              time invariant?"                     surface at boot?"
                       │                                     │
              ┌────────┴────────┐                  ┌────────┴────────┐
             yes               no                 yes               no
              │                 │                  │                 │
       1. eval test       (next gate)        2. nixosTest    3. runtime introspection
                                                              (just test-<X>)
```

Examples in this homelab:

| Failure | Layer | Why |
|---|---|---|
| "schema requires field X" | eval | option default + assertion fires at eval; no VM needed |
| "two services bind same port" | eval | port-conflict assertion at eval time |
| "appliance host can't have local restic target" | eval | placement assertion (already exists) |
| "ExecStart resolves to /nix/store/" | nixosTest | unit must actually try to start |
| "blocky binds :53" | nixosTest | port-binding is runtime behavior |
| "lanRoutes → caddy vhost emits valid config" | nixosTest | requires caddy to parse it |
| "restic snapshot < 25h old" | runtime | depends on actual schedule firing on the live host |
| "process-exporter publishing for workstation" | runtime | requires real scrape from real VM |
| "Caddy serves https://<name>.nori.lan with 200" | runtime | DNS + TLS + service all live together |

## Speed budgets — the load-bearing constraint

TDD's red-green-refactor cycle assumes the test runs in seconds, not
minutes. **The speed budget per layer is what makes the layer
viable** — not "we'd LIKE it fast", but "above this threshold, the
cycle breaks and developers stop running tests."

```
layer                      budget    if exceeded
────────────────────────────────────────────────────────────────────
eval                        < 5s     refactor; you're forcing
                                     realization or evaluating
                                     too much

nixosTest                  < 5min    split into smaller per-service
                                     tests OR use driverInteractive
                                     for the iteration loop

runtime introspection       <30s    each `just test-X` should land
                                     in seconds; >30s means you're
                                     polling too many things
```

The 5min nixosTest budget is generous because the first build is
expensive (downloads + closure realization). **The IMPORTANT speed
metric is the warm-cache rebuild — that should be <60s**, otherwise
iteration loops die.

## Red-green-refactor per layer

### Eval tests (layer 1)

```
RED       write the assertion in tests/eval/<concern>.nix; nix-instantiate
          --eval the expression; expect a specific error string OR a
          specific value.

GREEN     add the module / option / assertion that makes the
          expression resolve correctly.

REFACTOR  consolidate; ensure the test still passes on the cleanest
          implementation.
```

Eval tests look like:

```nix
# tests/eval/lanroute-port-uniqueness.nix
let
  config = ... eval a NixOS config with two routes on the same port ... ;
in
  assert (config exists →  this should fail eval);
  "ok"
```

Run: `nix-instantiate --eval tests/eval/lanroute-port-uniqueness.nix`.
Sub-second. Add to flake checks via `runCommand`.

### nixosTest (layer 2)

```
RED       write the subtest in tests/<scenario>.nix; the subtest's
          assertion calls a method or checks a unit state that doesn't
          yet exist. Run via driverInteractive — the testScript
          fails with a clear error.

GREEN     add the configuration / module that makes the assertion
          pass. Re-run via driverInteractive (no rebuild needed).

REFACTOR  promote shared setup into a fixture file; ensure the
          testScript reads operator-naturally.
```

Key practice for layer 2: **driverInteractive for the inner loop**.
Once the test driver is built ONCE, you iterate on testScript fragments
without rebuilding — the difference between a sub-second feedback
loop and a 5-minute coffee break.

```bash
nix run .#checks.x86_64-linux.<test-name>.driverInteractive
# inside:
#   start_all()
#   pi.wait_for_unit("blocky.service")
#   pi.shell_interact()    # drop into VM shell to poke
```

### Runtime introspection (layer 3)

```
RED       write the probe in Justfile (`just test-<X>`); it queries
          live VictoriaMetrics / systemd / restic / etc. and asserts
          the declared intent landed. Initial run shows the gap.

GREEN     fix the live system OR fix the declaration. Re-run; assert
          passes.

REFACTOR  factor common queries; document the lever (leverage /
          volatility / opacity / blast-radius) the test covers.
```

Full guidance for layer 3 lives at [`runtime-tests.md`](./runtime-tests.md).
That doc names the four-lever framework for deciding whether a runtime
test pays off; this doc cross-references it.

## Where tests live

```
tests/                          pre-deploy tests
  eval/<concern>.nix             eval-only assertions (sub-second)
  e2e-<scenario>.nix             nixosTest (slow but high-confidence)
  fixtures/<name>.nix            shared fixtures (sops-stub, fake-acme,
                                  fake-ntfy, etc)

Justfile                        runtime introspection recipes
  test-hypr                      Hyprland keybind registry
  test-backups                   restic units + per-target snapshots
  test-routes                    Caddy route + DNS + HTTPS
  test-observability             VM scrape + process-exporter +
                                  heartbeat + gatus probes
  test-replicas                  per-replica verifier oneshot
  test                           composite of all of the above

lint/checks/                    static lint scripts (different concern)
flake.nix § checks.<system>     all of the above wired as flake checks
```

## TDD workflow for adding a service

The canonical "add a new homelab service" flow (combining
`/add-service` skill + this methodology):

```
1.  RED at layer 1   write tests/eval/<service>-schema.nix asserting
                     `config.services.<service>.<important-option>` =
                     the expected default OR a specific value.

2.  Make module      write modules/services/<service>.nix with just
                     enough to make the eval succeed.

3.  GREEN at layer 1  nix-instantiate --eval passes.

4.  RED at layer 2   add a subtest in tests/e2e-<service>.nix asserting
                     `<host>.wait_for_unit("<service>.service")`.

5.  Run driver       nix run .#checks.x86_64-linux.<test>.driverInteractive
                     start_all() ; pi.wait_for_unit(...) shows the
                     unit is in failed state OR doesn't exist.

6.  Make it start    fix module config until the subtest passes via
                     driverInteractive (no rebuild between iterations).

7.  GREEN at layer 2  nix build .#checks.x86_64-linux.<test> passes
                     cold.

8.  Layer 3 if needed if `nori.<X>.<service>` is a registry effect
                     (leverage), add a runtime probe to `just
                     test-<concern>`. Most services don't need this —
                     they're single-effect.

9.  Wire as gate     add the new test to flake.nix:checks.${system}
                     so CI runs it.
```

The whole loop should be < 30 min for a simple service, dominated by
the first nixosTest build (subsequent iterations are sub-second via
driverInteractive).

## Fixture conventions

Shared fixtures live at `tests/fixtures/`. Each one represents a SINGLE
external dependency or test concern:

| Fixture | Replaces | Why |
|---|---|---|
| `sops-stub.nix` | sops-nix activation | tests don't have access to operator's age key |
| `fake-acme.nix` (future) | Let's Encrypt + Cloudflare DNS-01 | tests use Caddy's `local_certs` |
| `fake-ntfy.nix` (future) | ntfy.sh publish endpoint | a local Python http.server on :8080 |
| `fake-hc-io.nix` (future) | healthchecks.io | catches pi heartbeat without real internet |

Convention: each fixture has a **single responsibility** + a **header
comment explaining the contract** (what schema it stubs, what
behaviours it does NOT simulate). Multiple fixtures compose via
imports.

## Anti-patterns to avoid

```
✗ test the implementation, not the behavior
  bad: assert config.systemd.services.blocky.serviceConfig.User == "blocky"
  good: assert pi.succeed("dig +short test.lan @127.0.0.1") returns expected IP

✗ slow test in the inner loop
  bad: every iteration requires a full 5min rebuild
  good: use driverInteractive; nix flake check picks up the slow tests as
        the OUTER (CI) gate

✗ mock everything
  bad: stub every nori.<X> option so the test sees nothing real
  good: stub ONLY external deps (sops, real network endpoints); use the
        real homelab modules and config

✗ test in the wrong layer
  bad: write a nixosTest to assert schema validity (slow, indirect)
  good: write an eval test for it (sub-second, direct)

✗ test the framework, not your code
  bad: "blocky responds to DNS queries" (that's testing nixpkgs blocky)
  good: "OUR homelab's lanRoutes → blocky.customDNS auto-generation
         produces correct mappings" (testing the homelab's contribution)

✗ leave runtime tests unwired
  good: every runtime test is in `just test` (the composite); CI runs
         them periodically against the live deployment
```

## The TDD invariant

```
"If a test you'd want to write doesn't fit any of the three layers,
 you're describing a SOCIAL convention, not a verifiable property —
 promote it to docs/invariants.md as `[prose: unchecked]` and move on."
```

This is the rule that keeps tests from sprawling. Eval / nixosTest /
runtime are EXHAUSTIVE for "things the computer can check"; anything
else is documentation, not a test. The promotion register in
`invariants.md` is where those live.

## Companion docs

```
docs/reference/runtime-tests.md         Layer 3 in depth: the four-lever
                                         framework, what `just test-X`
                                         recipes exist, where to add new
                                         ones.

docs/reference/agentic-workflow.md      Per-PR ceremony; the Prologue
                                         includes specifying TDD layer
                                         per concern.

docs/invariants.md                      Where unchecked-but-load-bearing
                                         claims live until a layer can
                                         pick them up.

.claude/skills/add-service/             The "add a service" skill walks
                                         the TDD flow above explicitly.
```
