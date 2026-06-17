---
date: 2026-06-17
status: EXECUTED — Phases 0-4 landed 2026-06-17
seed: Stage 2.5 redirect; operator framing 2026-06-17 (PaaS lens + dual-access split)
summary: Restructure the codebase under modules/ as the single root, with services/ (workloads) and infra/<concern>/ (hosting platform) as the load-bearing split. Apply the PaaS lens to name infra sub-concerns; separate audience access from capabilities access. Use default.nix per folder; move enumeration logic into modules/<tree>/default.nix; thin flake.nix to dep-injection.
executed-as:
  - Phase 0   175b822  revert vaultwarden split (wrong axis)
  - Phase 1   0b8c384  backup → modules/infra/backup/
  - Phase 1.5 47d373c  path-coherence flake check
  - Phase 2   280fd7e  flake.nix trim (→ modules/machines + modules/home factories)
  - Phase 3a  ec3a58f  storage → modules/infra/storage/
  - Phase 3b  73a803b  capabilities → modules/infra/capabilities/
  - Phase 3c  3406078  networking → modules/infra/networking/
  - Phase 3d  72022cf  access → modules/infra/access/
  - Phase 3e  f0539e3  observability → modules/infra/observability/
  - Phase 3f  9d63fd5  drain effects/
  - doc-pass  3cc23a9  CLAUDE.md + module-authoring.md + glossary.md +
                       documentation-writing.md aligned
  - Phase 4   <this>   /home → modules/home; /machines → modules/machines.
                       path-coherence refined to skip relative imports;
                       tailnetIp lint scope expanded; chromecast
                       allowlist; 3 generated docs regenerated.
verification: byte-equal nix eval on representative trees per phase;
              all 11 flake checks pass at every commit; 4 NixOS hosts
              unchanged behaviorally.
---

# Modules-as-root restructure (spec)

Stage 2.5 redirect. The vaultwarden concern-split (Stage 2.5 v1) was the wrong axis — it fragmented a service's atomic effect-composition into per-file pieces. This spec lays out the right axis: a clean separation between **workloads** (what the platform hosts) and **infra** (the hosting platform itself), with infra sub-concerns named under the PaaS lens.

## Why

```
problem                                  symptom
─────────────────────────────────────────────────────────────────
modules/infra/ became a dumping        13 files of mixed shapes:
ground for "Nix-y things that aren't     effect handlers, policies,
services"                                registries, leaf config
                                         
the services/ folder mixes               vaultwarden (user-facing)
operator-installed workloads with        sits next to restic
hosting infrastructure                   (infra), Caddy (infra)
                                         and verify (infra). No
                                         conceptual layer marked.

flake.nix grew enumeration logic         mkHost + identityFor +
that belongs to the trees it             hostRegistry + readDir
enumerates                               all in flake.nix; each
                                         tree should own its own
                                         enumeration

cross-host module composition            schema-on-every-host vs
relies on `enable = bool` convention     activation-via-toggle
but the WHY is buried                    pattern not explicit in
                                         docs

"effects" as terminology requires        new agents need
algebraic-effects priors to read         algebraic-effects
                                         vocabulary to grok the
                                         Reader+Writer pattern
```

## The PaaS lens

The homelab IS a hosting provider — it serves vaultwarden, navidrome, immich, et al. on its own compute, with its own storage, networking, access control, observability, and backups. PaaS concerns map onto the homelab's existing structures:

```
PaaS concern             present in homelab as
─────────────────────────────────────────────────────────
compute                  machines (workstation, aurora,
                         pi, pavilion)
storage                  /mnt/family/* + /mnt/media + 
                         /var/lib/* + nori.fs subvol policy
networking               nori.lanRoutes + Caddy + Blocky + 
                         tailnet
audience access (IAM)    Authelia OIDC + tailnet ACL + 
                         audience tag on routes
capabilities access      nori.harden (FS namespace) + 
                         media group + GPU device allocation +
                         CAP_* capabilities
observability            Gatus + VictoriaMetrics + 
                         VictoriaLogs + Beszel + ntfy
backups                  restic + btrbk + verify + OneTouch
secrets management       sops-nix
DNS / certificates       Blocky authoritative + Caddy auto-ACME
```

Strong fit. The lens names categories the codebase already implicitly has.

## The two access concerns (sharper cut)

Conflating these was a mistake in the v1 PaaS sketch.

```
audience access                            capabilities access
("who can reach this service")             ("what can this service do")
─────────────────────────────────────────────────────────────────────
INBOUND direction                          OUTBOUND / LOCAL direction

declarations:                              declarations:
  nori.lanRoutes.<X>.audience                nori.harden.<X>
    (operator | family | public)               (FS namespace)
  nori.lanRoutes.<X>.oidc                    nori.harden.<X>.binds
    (Authelia client config)                   nori.harden.<X>.readOnlyBinds
  nori.lanRoutes.<X>.exposeOnTailnet         media group membership
                                             accelerationDevices
                                               (GPU)
                                             CAP_NET_* / CAP_SYS_*
                                               (systemd Capabilities)

enforced by:                               enforced by:
  Authelia OIDC gates                        systemd FS-namespace
  Caddy access policies                      (BindPaths, TemporaryFileSystem)
  tailscale ACL                              systemd CapabilityBoundingSet
                                             device cgroup (DeviceAllow)
                                             group permissions

PaaS analogue: IAM, ACLs                   PaaS analogue: sidecar
                                           permissions, volume mounts,
                                           device allocations
```

These are two distinct concerns that happen to both contain the word "access" in casual speech. Folder structure separates them:

```
infra/access/         audience access (Authelia, OIDC, audience
                      tag generators)
infra/capabilities/   capabilities access (nori.harden, FS
                      namespace, media group, GPU device
                      allocation, system capabilities)
```

## The cut

```
modules/
  services/                workloads — user-installed applications
                           consuming the platform
    vaultwarden.nix          (REVERT the Stage 2.5 v1 split)
    navidrome.nix
    immich.nix
    ollama.nix
    jellyfin.nix
    calibre-web.nix
    komga.nix
    radicale.nix
    miniflux.nix
    glance.nix
    heim.nix
    filmder.nix
    grafana.nix
    open-webui.nix
    stremio.nix
    syncthing.nix
    arr/                     coupled cluster (folder = coupling)

  infra/                   the hosting platform itself
    backup/
      default.nix            nori.backups schema + collection
      restic.nix             restic adapter
      btrbk.nix              btrbk replication adapter
      verify.nix             verify drill adapter
    networking/
      default.nix            nori.lanRoutes schema + collection
                             + Caddy vhost / Blocky DNS / Gatus
                             monitor generators
      caddy.nix              Caddy daemon
      blocky.nix             Blocky daemon (DNS + authoritative)
      tailnet.nix            tailscale daemon + appliance hardening
    access/                  audience access (IAM)
      default.nix            audience policy assertions; OIDC
                             client generation from
                             nori.lanRoutes.<X>.audience + .oidc
      authelia.nix           Authelia daemon
    capabilities/            capabilities access
      default.nix            nori.harden schema + collection +
                             systemd FS-namespace adapter
      media-group.nix        shared `media` group; gid+UMask
                             coordination
      gpu.nix                GPU device allocation policy (NVIDIA
                             driver pin lives here too)
    observability/
      default.nix            scrape + alert + dashboard schemas
      gatus.nix              Gatus daemon (route monitor + status
                             page)
      victoriametrics.nix    metrics TSDB
      victorialogs.nix       logs ingest
      beszel/                Beszel hub + agent split-module
      node-exporter.nix      Linux metrics
      process-exporter.nix   per-process RSS / CPU
      nvidia-gpu-exporter.nix
      ntfy/                  server + notify client split
      vector.nix             journald → VictoriaLogs shipper
    storage/
      default.nix            nori.fs schema + btrfs subvol
                             generator + replication intent
      disko/                 (if disko configs move here from
                             per-machine — open question)
    hosts.nix                registry: compute-metadata fact table
    placement.nix            cross-cutting policy: appliance ≠
                             paths-backups; agent ≠ nori.backups
    resource-tiers.nix       policy: memory-tier defaults
    restart-policy.nix       policy: systemd restart defaults
    motd.nix                 leaf — or move to machines/base/

  machines/                composition (per-host)
    default.nix              ENUMERATOR — readDir + base injection
                             + mkHost wrapper + identityFor +
                             hostRegistry
    base.nix                 universal NixOS bits (was modules/
                             common/) — or common/ folder if
                             granular split kept
    workstation/
      default.nix
      hardware.nix
      ...
    aurora/
    pi/
    pavilion/
    macbook/                 home-manager-only; no default.nix
                             (readDir filters for default.nix
                             presence — distinguishes NixOS hosts)

  home/                    home-manager / desktop env
    default.nix              ENUMERATOR for homeConfigurations
    base.nix                 desktop env baseline (was modules/
                             desktop/)
    nori/
    hermes/
    claude-code/

  lint/                    meta-tool: code-quality dispatcher
                           (was modules/lint/)
  dev/                     meta-tool: mkDevShell composer
                           (was modules/dev/)
```

## Dependency direction (no cycles)

```
services/      depends on   infra/             (workloads consume platform)
infra/         depends on   machines/, lint/, dev/ helpers
machines/      depends on   (nothing — leaf compute composition)
home/          depends on   machines/          (home-manager runs on a host)
lint/, dev/    depend on    (nothing — meta-tools)
```

Each layer reads the one below; nothing reads upward. The cut enforces this naturally.

## Conventions used (Nix-idiomatic, not personal)

```
default.nix as folder entry              nixpkgs convention
imports = [ ./other ]                    Nix module composition
{ config, lib, pkgs, ... }: shape        NixOS module signature
mkOption / mkMerge / mkIf                NixOS module DSL
nori.<X> namespace prefix                downstream-flake convention
                                         (nixarr, nixos-hardware,
                                         agenix all do this)
RFC 145 /** */ for fn doc                NixOS-wide convention
                                         (in-progress adoption)
nixosOptionsDoc for schema reference     nixpkgs tool
nixdoc for RFC 145 extraction            nixpkgs tool

personal conventions retired
  "effects" as folder name             → infra/ (PaaS terminology)
  "policy.nix" + "config.nix" split    → default.nix per concern
  Stage 2.5 v1 access/storage split    → REVERT; services are atomic
```

## On `services.<X>.enable = true` (architectural note)

The `enable = bool` toggle separates SCHEMA visibility from ACTIVATION. In a multi-host system, every host imports the full `modules/services` bundle to see route declarations and option schemas; only some hosts activate specific daemons via `enable = true`. If imports activated, the cross-host split-module pattern (route schema visible on workstation; daemon running on aurora) collapses.

This is load-bearing. The convention isn't arbitrary — it's the mechanism that makes per-service-folder cross-host wiring work in Nix.

## Open questions (named, not answered)

```
1. infra/networking/ vs infra/networking/lan-route/?
   The nori.lanRoutes schema is dense (~500 LOC). Does it
   warrant its own subfolder under networking/, or stay in
   default.nix?
   
   Lean: stay in default.nix; networking/ already groups
   Caddy + Blocky + tailnet; one more sub-grouping is
   ceremony.

2. capabilities/ — do we promote nori.fs subvol assignments
   here, or keep them in storage/?
   
   nori.fs declares WHERE data lives (storage). The harden
   FS-namespace declares WHAT a service can SEE of that
   data (capabilities). Same fs concept, two angles.
   
   Lean: storage/ owns subvol policy; capabilities/ owns
   per-service FS-namespace harden. They reference each
   other.

3. Authelia + OIDC schema location
   Authelia is the daemon (access/authelia.nix). The OIDC
   client schema is currently nested in nori.lanRoutes.<X>.
   oidc. Two options:
     (α) Keep nested in nori.lanRoutes; access/default.nix
         READS it to generate Authelia client config.
     (β) Promote to nori.oidcClients.<X> as its own option
         family; access/ owns it; networking/lan-route
         REFERENCES it.
   
   Lean (α) — route declares its OIDC profile inline; one
   site to read per route. Splitting adds two declaration
   sites for the same route.

4. modules/common/ → modules/machines/base.nix vs
   modules/machines/common/
   
   Current modules/common/ has ~10 files. Two options:
     (α) machines/base.nix as one file that imports
         common/ subfiles
     (β) machines/common/ folder (10 files) with siblings
         in machines/<host>/default.nix importing
         `../common`
   
   Lean (β) — preserve the granular file split for
   navigability.

5. Where do disko configs go?
   Currently in machines/<host>/disko*.nix. Two options:
     (α) Stay per-machine — disko configs are machine-
         specific
     (β) Promote OneTouch (portable, attaches anywhere) to
         infra/storage/disko/onetouch.nix; per-machine
         non-portable stays in machines/<host>/
   
   Operator's framing: "io could technically be separated
   though its only necessary when the unit is genuinely
   portable like onetouch."
   
   Lean (β) when OneTouch is the precedent; others (NVMe,
   IronWolf-USB) stay per-machine.

6. flake.nix what stays
   After enumeration moves to modules/{machines,home}/
   default.nix:
     stays: inputs, system + pkgs binding, devShells,
            packages.docs-* (move to modules/?), checks
            (move to modules/lint/?), formatter
     leaves: mkHost, identityFor, hostRegistry, machine
            enumeration, home enumeration
   
   Open: do checks.${system} and packages.${system} move
   into modules/, or stay in flake.nix as output wiring?
   Lean stay — they're flake outputs by nature.

7. apps/ vs services/ — final call
   v1 spec suggested rename. Latest framing (operator
   2026-06-17): keep services/; separate infra/. Services
   stays as the workload tree; infra/ contains hosting
   platform.
   
   Confirmed: NO rename. services/ stays.

8. backups for infra/ services themselves
   infra/backup/restic.nix backs up SERVICES. But restic
   itself runs as a systemd timer with its own state
   (cache, lock). Does restic need a backup intent
   declaration?
   
   Current: yes — restic.nix declares nori.backups.restic
   (cache + lock are recoverable; or .skip). Stays the
   same under the new shape.

9. The vaultwarden split — revert as Phase 0?
   Yes. Single-file vaultwarden.nix restored; flake.nix
   exclusions for */access.nix and */observability.nix
   removed; module-authoring.md per-service folder section
   removed.
   
   Confirmed.
```

## Migration phases

This is a multi-PR arc. Don't bulk-execute. Each phase verifies via `nix flake check` + byte-equal eval before proceeding.

```
Phase 0 — clean slate
  - Revert the vaultwarden split (Stage 2.5 v1)
  - Drop module-authoring.md per-service folder section
  - Drop flake.nix */access.nix + */observability.nix +
    */storage.nix exclusions
  - Single commit

Phase 1 — pilot ONE infra concern: backup
  - Move modules/infra/backup/default.nix → modules/infra/backup/
    default.nix
  - Move modules/services/backup/{restic,btrbk,verify}.nix →
    modules/infra/backup/{restic,btrbk,verify}.nix
  - Update imports in machines/<*>/default.nix +
    flake.nix's services bundle
  - Update routing tables in CLAUDE.md / docs/
  - Update docs/reference/services.md backup section
  - Update lint check baseNonServicePatterns paths
  - Update doc-coherence + routing-coherence patterns
  - Verify: nix flake check + eval-equal nori.backups.* +
    systemd.services.restic-backups-* unchanged
  - Single commit

Phase 2 — flake.nix trim
  - Create modules/machines/default.nix with mkHost +
    identityFor + hostRegistry + nixosConfigurations
  - flake.nix imports + re-exports
  - Verify: nix flake check; all hosts still eval; build
    workstation closure still byte-equal
  - Create modules/home/default.nix with
    homeConfigurations.macbook
  - Same verification

Phase 3 — bulk move infra concerns (one PR per concern)
  Order by safety:
    3a. infra/storage/      (nori.fs + replication)
    3b. infra/capabilities/ (harden + media-group + gpu)
    3c. infra/networking/   (lan-route + caddy + blocky + 
                             tailnet)
    3d. infra/access/       (authelia)
    3e. infra/observability/ (Gatus + VictoriaMetrics +
                              VictoriaLogs + Beszel +
                              exporters + ntfy + vector)
  Per concern:
    - File moves
    - Import updates
    - Docs + routing updates
    - Lint check baseNonServicePatterns updates
    - Verify byte-equal eval
    - Single commit per concern

Phase 4 — machines + home rewire (EXECUTED 2026-06-17)
  - /machines/* → modules/machines/* (siblings of the factory's default.nix)
  - /home/* → modules/home/* (siblings of the factory's default.nix)
  - flake.nix:177 machinesPath: ./machines → ./modules/machines
  - modules/home/default.nix:34 ../../machines → ../machines (macbook ref)
  - All other home.nix imports (../../home/X.nix from machines/<host>/)
    PRESERVE because both trees moved by equal depth.
  - Lint scope expansions: diskoUsesById to modules/machines/;
    migrationPhase consolidated to modules/.
  - tailnetIp lint coverage grew to include modules/machines/<host>/;
    chromecast appliance (100.94.135.114) added to allowlist.
  - path-coherence check refined to skip relative-path imports
    (the existing regex captured `home/X.nix` from `../../home/X.nix`
    and false-positived after the move).
  - Doc-comment rewrites: ~120 occurrences of `home/X.nix` and
    `machines/X.nix` updated to the modules-rooted form.
  - 3 generated docs regenerated (lan-route, topology, dev-shell).

Deferred from Phase 4 (separate spec):
  - modules/common/ → modules/machines/common/ or base.nix
    (decision NOT made — `modules/common/` reads cleanly as the
     "shared baseline imported by every NixOS host" and the
     move would obscure that. Keeping it at modules/common/.)
  - modules/desktop/ → modules/home/base.nix (deferred; desktop/
    is NixOS-system-scope, not home-scope; rename only if scope
    clarification surfaces.)

Phase 5 — leaves + meta-tools
  - modules/infra/motd.nix → modules/infra/motd.nix or
    modules/machines/base/
  - modules/lint/ stays
  - modules/dev/ stays
  - modules/infra/ deleted (empty)

Phase 6 — docs cleanup
  - module-authoring.md rewrites for the new shape
  - topology.md / services.md / network.md / storage.md
    /recovery.md all reference new paths
  - documentation-writing.md "Stages 3-5" of adoption table
    refers to the new structure
  - docs-topology + docs-lan-route generators updated for
    new file paths
```

## Verification protocol (Stage 2.5 v1 lesson applied)

For each phase, before committing:

```
1. nix flake check                   all checks pass
2. nix eval before vs after on        byte-equal on impacted hosts
   representative trees
3. nix build workstation closure      byte-equal toplevel
4. nix build aurora closure           byte-equal toplevel
   (if phase touches aurora)
5. nh os test on workstation          activation succeeds (no
                                      systemd unit changes
                                      beyond expectation)
```

Eval-equal verification was load-bearing in the vaultwarden split — it caught the difference between "the code looks the same" and "the evaluation is the same." Same protocol applies per-phase here.

## Out of scope

```
- The R1 diagram generator (depends on this restructure
  but is a separate sprint)
- Promoting nori.observability as its own option family
  (today it's split across nori.lanRoutes.monitor + per-
  service scrape config; promotion is a separate concern)
- Renaming services → apps (operator confirmed: keep
  services; separate infra)
- Moving Caddy/Authelia/Blocky out of "they're really
  apps" framing — they ARE apps with daemons, but
  conceptually they're INFRA; they live in infra/<concern>/
- Promoting backup-tier (value tier) to its own option
  family (defers to a separate spec)
- The OneTouch portable-IO promotion (operator-named but
  defers to Phase 1's storage scope)
```

## Connection to Stage 2 adoption

This spec replaces the Stage 2.5 v1 sketch in `docs/reference/documentation-writing.md`. The adoption table entry for Stage 2.5 should point here once this spec is approved + the revert lands.

```
Stage 2     ✓ pressure test (topology.md absorbs)
Stage 2.5   ◐ this spec (modules-as-root restructure)
Stage 3     □ generator extended (waits for restructure)
Stage 4     □ content migration (multi-sprint, waits)
Stage 5     □ docs-fresh check (waits)
```
