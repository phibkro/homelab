# Agent onboarding test

A fresh agent (no prior session context) should be able to answer these from `CLAUDE.md` plus on-demand reads of files it references. If the agent has to invent details or reach for tribal knowledge, the test failed — and the wrap-up rubric ("On every structural change", "On session end") needs adjusting.

## Why this exists

Wrap-up has a set value (the rubric in CLAUDE.md) but no measure. Without a measurement mechanism, the loop is open and drift accumulates silently. This file is the measure: a fresh agent's actual performance against expected shape, run periodically, indicating doc gaps as failures.

See "On every structural change" + "On session end" in CLAUDE.md for the rubric this tests.

## How to run

Dispatch a subagent (or fresh Claude session) with this prompt:

> You are a fresh agent with zero prior context on this homelab project. Read `CLAUDE.md` first to orient. Then for each numbered question below, give a terse answer (~3 bullet points) using only files reachable from CLAUDE.md's routing table. Cite the source file for each answer.
>
> Don't read the "Expected (shape)" sections until AFTER you've answered them — those are grading rubrics, not hints.
>
> If information seems missing, note that as a potential gap rather than inventing. The test exists to surface gaps.

Then compare answers to **Expected (shape)** below. Failures classify into:

- **Knowledge gap** — info isn't documented anywhere → add it
- **Routing gap** — info is documented but not reachable from CLAUDE.md's routing → fix routing
- **Foregrounding gap** — reachable but not where the agent looks first → reposition in CLAUDE.md

All three are wrap-up failures; fix and re-run.

---

## Q1: Service placement — what runs where?

**Tests**: topology mental model (highest-frequency knowledge).

**Question**: For each of these, name the host(s) it runs on and the one-line reason: Beszel hub, ntfy server, Blocky, Caddy, Authelia, Jellyfin, ntfy `notify@` template.

**Expected (shape)**:
- Beszel hub → nori-pi (appliance survives workhorse outages — forensics use case)
- ntfy server → nori-pi (alert plane survives workhorse outages; Caddy on station reverse-proxies)
- Blocky → both (station self-hosted, Pi forwarder; mutual DNS resilience)
- Caddy → nori-station (workhorse; internal CA bound here)
- Authelia → nori-station (SSO; cross-host token validation cost not worth it)
- Jellyfin → nori-station (media volume + GPU)
- ntfy `notify@` template → both (each host posts to ntfy.sh with its own hostname)

**Source**: CLAUDE.md "Current state → Topology + service placement".

---

## Q2: Placement rule — workhorse vs appliance

**Tests**: the bias / decision rule.

**Question**: How do you decide if a new service belongs on the workhorse host or the appliance host?

**Expected (shape)**:
- Default = workhorse
- Appliance only when fate-sharing breaks the function (observability, alerting, DNS — must survive workhorse failure)
- Pi has 8 GiB + anti-write storage; not for heavy state or daily writes

**Source**: CLAUDE.md "What's the bias → Workhorse-by-default, appliance-by-exception".

---

## Q3: Adding a new HTTPS service

**Tests**: convention for service module shape.

**Question**: You're adding a service `widget` that serves HTTP on port 9000. What abstractions and files do you touch?

**Expected (shape)**:
- New file `modules/server/widget.nix`
- Enable the upstream module (`services.widget.enable = true`)
- Default-deny FS hardening: `nori.harden.widget = { binds = [...]; readOnlyBinds = [...]; };` (`every-service-has-fs-hardening` flake check enforces presence)
- `nori.lanRoutes.widget = { port = 9000; monitor = { }; };`
- `nori.backups.widget = { paths = [...] | skip = "..."; };`
- Append to `modules/server/default.nix` imports

**Source**: PROCEDURES.md "How to add a new service".

---

## Q4: Cross-host reference

**Tests**: registry pattern (introduced in commit `444423f`).

**Question**: You see this in a service module. Is it right? If wrong, what's the fix?

```nix
nori.lanRoutes.widget = {
  port = 9000;
  host = "100.100.71.3";   # nori-pi tailnet IP
};
```

**Expected (shape)**:
- Wrong — IP literal
- Should use `config.nori.hosts.nori-pi.tailnetIp` (the topology registry)
- Registry schema: `modules/lib/hosts.nix`; values: `flake.nix` `identityFor`
- Topology coupling lives in the host name in the lookup, not in the IP

**Source**: CLAUDE.md "Current state → Topology", `modules/lib/hosts.nix` header.

---

## Q5: Backup intent — schema + placement

**Tests**: backup contract + host-aware assertion.

**Question**: What does `nori.backups.<n>` require, and when do you use `paths` vs `skip`? What's the constraint on appliance hosts?

**Expected (shape)**:
- Exactly one of `paths` or `skip` (assertion enforces; never both, never neither)
- `paths = [ ... ]` for content to back up
- `skip = "<reason>"` for explicit opt-out (covered elsewhere, stateless, intentionally re-derivable)
- Appliance hosts (`role = "appliance"`) cannot use `paths` — host-aware assertion fails eval (anti-write storage posture)

**Source**: `modules/lib/backup.nix` (schema + assertions), CLAUDE.md "Current state".

---

## Q6: FS hardening abstraction

**Tests**: `nori.harden` shape + the principle behind it.

**Question**: How does a service module declare default-deny FS-namespace hardening today? What's the principle, and what enforces that you don't forget?

**Expected (shape)**:
- `nori.harden.<systemd-unit-name> = { binds = [...]; readOnlyBinds = [...]; protectHome = true|false|null; };` (schema in `modules/lib/harden.nix`)
- Generator emits `ProtectHome = mkForce true` + `TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ]` + `BindPaths` + `BindReadOnlyPaths` on the systemd unit
- `protectHome = null` skips the directive (preserves upstream NixOS module's value, e.g. syncthing where upstream is opinionated)
- Principle: default-deny FS namespace; compromised service can't browse host paths it doesn't need
- Enforcement: `every-service-has-fs-hardening` flake check fails the build if any `modules/server/*.nix` (outside the excluded list) lacks a `nori.harden.<n>` declaration

**Source**: CONVENTIONS.md "Filesystem hardening", DESIGN.md "Default-deny filesystem access", `modules/lib/harden.nix`.

---

## Q7: DynamicUser symlink trap

**Tests**: critical gotcha awareness.

**Question**: A service `foo` declared with `DynamicUser = true` has state at `/var/lib/foo`. You write `nori.backups.foo.paths = [ "/var/lib/foo" ]`. What happens?

**Expected (shape)**:
- Backup snapshot is empty (3 files / 0 bytes) — restic stores symlinks AS symlinks
- `/var/lib/foo` is a symlink to `/var/lib/private/foo`
- Fix: `nori.backups.foo.paths = [ "/var/lib/private/foo" ]`
- The DynamicUser-symlink assertion in `modules/lib/backup.nix` catches this at eval time (lists known DynamicUser services explicitly)

**Source**: gotchas.md "DynamicUser StateDirectory", `modules/lib/backup.nix` assertion.

---

## Q8: Adding a new host

**Tests**: filesystem-as-source-of-truth model (registry refactor).

**Question**: Walk through adding a new host called `nori-foo` (workhorse, tailnet IP `100.99.0.5`, no static LAN lease).

**Expected (shape)**:
- Create folder: `mkdir hosts/nori-foo`
- Add `identityFor.nori-foo = { tailnetIp = "100.99.0.5"; lanIp = null; role = "workhorse"; };` in `flake.nix`
- Write `hosts/nori-foo/default.nix` (imports + concerns) and `hardware.nix` — don't redeclare `networking.hostName` (injected from folder name)
- Add host's age public key to `.sops.yaml`, run `sops updatekeys secrets/secrets.yaml`
- First boot + `tailscale up`

**Source**: PROCEDURES.md "How to add a new host".

---

## Q9: NVMe safety — hard rule

**Tests**: project's hardest rule.

**Question**: You need to write a disko config for a new NVMe drive. What's the rule, and why?

**Expected (shape)**:
- Use `/dev/disk/by-id/...` paths, never `/dev/nvmeN`
- NVMe enumeration is unstable across reboots — `nvme0n1` was the NixOS root at install, became Windows after a reboot
- Ignoring this risks wiping the wrong drive
- Verify by-id mapping via `ls /dev/disk/by-id/` before any destructive command

**Source**: CLAUDE.md "Hard rules", gotchas.md "NVMe enumeration", DESIGN.md "Permanent constraints".

---

## Q10: Process meta — when to update CLAUDE.md

**Tests**: per-change rubric awareness.

**Question**: You just landed a structural refactor (e.g., introduced a new abstraction or pattern). What do you do for a fresh agent's sake before moving on?

**Expected (shape)**:
- Apply the "On every structural change" rubric — don't wait for session end
- Stale active examples in CLAUDE.md / DESIGN.md → fix immediately (highest-cost class)
- Pattern used twice or more → codify as "How to ..." in PROCEDURES.md
- New convention agents should follow → CONVENTIONS.md, ideally backed by a flake check / module assertion
- Hard-won mistake → gotchas.md
- Cross-session fact (preferences, project state, host topology) → memory

**Source**: CLAUDE.md "On every structural change".

---

## Scoring

- **9-10 correct in shape** → wrap-up was comprehensive
- **7-8 correct** → identify which doc tier missed; fix the gap class and retest
- **< 7** → doc tree has structural gaps; revisit "On session end" rubric thoroughness, possibly add categories

A "correct" answer covers the shape's load-bearing points (not exact wording). Phrasing differences are fine; missing or wrong concepts aren't.

## Cadence

Run after any of:
- Major structural refactor (new abstraction, registry, cross-host pattern, etc.)
- A session where the user pushed back on "is this clear enough for a fresh agent?"
- Quarterly check-in (every ~10-20 sessions at hobby cadence)

When new patterns land that don't fit existing questions, add a question. The test should grow with the project; ~10-15 questions is the right size, beyond which retire questions for stable knowledge.
