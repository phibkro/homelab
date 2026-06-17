---
date: 2026-06-17
summary: K6 audit — side-by-side diff of topology.md (pre-K5) vs (post-K5 topology.md + generated topology-generated.md). What survived, what was lost, what's deferred.
---

# Topology co-location audit (K6)

Stage 2 pressure test deliverable. Diffs `topology.md` at commit `7e8c134` (Sprint 6 baseline) against the new shape: hand-curated `topology.md` + auto-generated `topology-generated.md`.

## Headline result

```
                              lines     fate
  ──────────────────────────────────────────────────────
  was: topology.md            171       (single file)

  is:  topology.md            180       (curated/meta)
       topology-generated.md  226       (auto-derived)
  ──────────────────────────────────────────────────────
  total                       406       net +135 lines
```

Line count grew. Per-doc clarity grew more — the curated file no longer carries the hosts-table schema-as-prose; the generated file is rebuilt from `nori.hosts` values. **The split is the point**, not the brevity.

## Cleanly co-located (the wins)

```
SoT before                  SoT after                       method
──────────────────────────────────────────────────────────────────
Hosts table (prose dup)     nori.hosts values + schema      nixosOptionsDoc
                                                            + hand-rolled
                                                            value walk
nori.hosts schema in prose  modules/effects/hosts.nix       option descriptions
                            options                         (already there;
                                                            now generator-
                                                            picked-up)
Pi posture (prose dup)      machines/pi/hardware.nix        inline # comments
                            inline comments                 (already there;
                                                            topology.md points
                                                            at code)
NVMe by-id rationale        machines/workstation/disko.nix  inline # comments
                            inline comments                 (already there;
                                                            re-flagged below)
```

## Lost cleanly (justified removals)

These dropped because the upstream/derivation source carries the truth:

```
                                  before                           after
────────────────────────────────────────────────────────────────────────────
OS column (per-host)              hand-typed "NixOS 26.05"          implicit;
                                  per row                           all hosts
                                                                    run nixos-26.05
                                                                    (would
                                                                    surface as a
                                                                    flake-input
                                                                    derivation if
                                                                    needed)
Arch column (per-host)            hand-typed                        derivable from
                                                                    nixpkgs.host-
                                                                    Platform; could
                                                                    extend the schema
                                                                    if cell needed
USB-then-SD boot order            prose snippet                     code reality
(BOOT_ORDER=0xf41)                                                  (nixos-hardware
                                                                    raspberry-pi-4
                                                                    + imageMedia
                                                                    bake the
                                                                    EEPROM order;
                                                                    not declarative
                                                                    in our tree)
```

The BOOT_ORDER line is mildly worth keeping somewhere — it's the operator-knowledge that the Pi was REIMAGED to boot USB-first. Not currently in any `.nix` file. Recommend a one-line `# Pi was reimaged to boot USB-first…` comment in `machines/pi/hardware.nix` if/when re-imaging procedure comes up again. **Not a blocker.**

## Lost — gap (needs follow-up)

```
                                  before              after          status
──────────────────────────────────────────────────────────────────────────────
macbook row                       in hosts table      MISSING        gap
                                  ("(no role)")       (macbook is
                                                      not in
                                                      identityFor —
                                                      home-manager
                                                      only)
Workstation drives table          in topology.md      DEFERRED       expected
                                  prose               (spec)         per K5
NVMe enumeration warning          in topology.md      MISSING from   gap
("nvme0n1 was root,               prose               topology.md
post-reboot they swapped")                            entirely
                                                      (code has
                                                      it inline)
```

### Gap 1 — macbook row

The hosts-at-a-glance table used to include the Mac as `(no role)`. The generated artifact only walks `nori.hosts` which excludes macbook (Mac runs standalone home-manager, not under `nixosConfigurations`).

Three resolution paths, none touched in this sprint:

```
(α)  Add a `nori.machines` registry distinct from `nori.hosts` —
     `hosts` stays NixOS-only; `machines` includes non-NixOS.
     Generator walks `machines`. Operator-facing table is
     complete; placement assertions still key off `hosts.role`.

(β)  Leave macbook out of the topology table; mention in §intro
     prose ("plus a Mac on standalone home-manager"). Already
     done in current topology.md.

(γ)  Wire the standalone home-manager configurations into
     `machines/macbook/` with a synthetic role like `daily-driver`.
     Costs schema change for one entry; no functional benefit.
```

**Recommend (β)** — operator already gets the message from the §intro line; the table's job is hosts-under-the-flake-config-system, which is what NixOS hosts are.

### Gap 2 — NVMe enumeration warning

The line "NVMe enumeration is unstable across reboots — `nvme0n1` was NixOS root at install time; post-reboot the drives swapped" is the load-bearing rationale for `/dev/disk/by-id/...` everywhere in disko configs. It's also a hard rule in CLAUDE.md ("Never touch `nvme0n1` without verifying the model string via `/dev/disk/by-id/`").

The rationale IS in code: `machines/workstation/disko.nix:46-51` inline comment carries it. But `topology.md` dropped its summary — losing the cross-doc surfacing.

**Recommend**: add one summary line in `topology.md` § Pi posture (since it's the operator-facing rule), and leave the load-bearing rationale in disko.nix. **Fix in this commit before closing K6.**

## Deferred to R3 (structure-by-tier spec)

Captured here so they land in the spec when R3 writes:

```
1.  Workstation drives table — disko schema is the SoT; surfacing
    needs the storage-policy concern shape (walk disko.devices.*
    and emit subvol tree). Not "extend nori.hosts" — disko already
    owns the data, just need a generator that knows where to look.

2.  Service placement table — cross-effect view (services × lan-route
    × observability). No single module owns the "where + why" join.
    Either (α) add description to runsOn; aggregate via module-
    system walk, or (β) extract location-policy as its own
    concern.

3.  GPU access pattern — `config.nori.gpu.nvidiaDevices` is the SoT;
    could be promoted to an option with description (nixosOptionsDoc
    extracts it). Similar to lan-route surface.

4.  Resource caps table — per-service cap rationale; if each
    service module had a `cap = { value, reason }` field, the
    generator could walk + emit. Today the rationale lives in
    inline comments scattered across modules.
```

## Verdict for K7

The pressure test landed three signal results:

```
SIGNAL                                              READS AS
──────────────────────────────────────────────────────────────────
Config-dump dominant sections (hosts table,         CONVENTION SCALES
schema) cleanly co-locate via nixosOptionsDoc       (Stage 2 ✓)
+ small hand-rolled value walks.

Code-already-has-it sections (Pi posture, NVMe      ALREADY WORKING —
by-id) prove the convention isn't novel; the gap   topology.md was
was that topology.md duplicated what code already   the dupe, not the
said.                                               source

Cross-effect sections (service placement, drives,   CONVENTION INSUFFICIENT
GPU, caps) RESIST co-location at module-as-shipped  ALONE — restructure
because no single module owns the cross-effect      needed (R3 spec)
question.
```

Recommendation: **keep the convention; commit to the structure-by-tier restructure as the follow-on.** Both halves of K7 ("keep" + "with restructure followup").

## NVMe warning fix (executed in this commit)

Adding back the operator-facing rule in `topology.md § Pi posture`:

```
**NVMe enumeration is unstable across reboots.** Disko configs
target `/dev/disk/by-id/...` paths; never touch `nvme0n1`
without verifying the model string. See
`.claude/skills/gotcha-nvme-enumeration/`.
```

This isn't strictly Pi posture but it's load-bearing and lives in CLAUDE.md as a hard rule — the operator-facing surface should re-state it.
