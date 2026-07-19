---
date: 2026-07-20
branch: feat/architecture-simplification
status: implementation complete; awaiting operator PR review
governing_spec: docs/specs/2026-07-19-architecture-simplification-design.md
---

# Architecture simplification migration report

## Outcome

The repository now has one pure, secret-free control plane for hosts, explicit
profiles, workloads, datasets, site namespaces, product artifact contracts,
deployment targets, and presentation catalogs. NixOS evaluates only selected
runtime modules; cross-host consumers receive typed inventory rather than
forcing every workload implementation into every host graph.

No host was switched, no router/DNS/Cloudflare setting was mutated, no secret
was changed, and no external product repository was modified.

## Landed boundaries

| Boundary | Result |
|---|---|
| Inventory | Explicit five-host catalog, workload manifests, profiles, datasets, site policy, public-safe projection |
| Workloads | Manifest/runtime split for every workload; Arr remains one intentionally coupled cluster |
| Platform | Host/profile-selected adapters; legacy service registry, tag activation, and global service bundle removed |
| Machines | NixOS and standalone Mac targets derive from one inventory; hardware/storage remain local realizations |
| Home Manager | Core, PC, desktop, creative, development, and agentic capabilities compose explicitly |
| Rice | `nori.hyprRice.enable` is the public interface; scripts/Lua/generated configuration stay private |
| Data | FLAC is canonical music; Navidrome serves Subsonic and transcodes Opus/MP3 on demand |
| Products | Filmder and Heim declare governed `legacy-host-build` exceptions; new consumers require immutable artifacts |
| Deployment | Read-only planner derives affected build attributes and backend-before-entry-plane activation order |
| Presentation | Minimal status and access-tiered portal JSON derive from endpoint manifests without topology/secrets |
| Domains | Canonical and deprecated namespaces have one source; Glance emits canonical links and legacy HTTP aliases redirect |
| Recovery | Entry-plane endpoint identity follows `site.entryPlaneHost`; an assertion keeps it aligned with the sole entry-plane profile host |
| Agent lifecycle | Claude Code and Codex share a repository post-edit Nix formatter/static-diagnostic hook |
| Documentation | Current architecture, deployment boundary, work lifecycle, and follow-up product scope are explicit |

## Verification evidence

Completed during implementation:

- per-phase `nix flake check` gates and structured architecture-baseline checks;
- all flake outputs and checks evaluate with `nix flake check --no-build`;
- focused Statix, deadnix, format, generated-doc, custom-DNS, presentation, dataset,
  artifact, deployment, system-profile, and public-inventory checks;
- Home Manager package/file/session-path/Git/direnv parity across all five homes;
- music ingest fixture: 42 assertions passed;
- semantic deployment-plan fixtures, including workload-narrowing and
  conservative unknown-path behavior;
- isolated Pi VM evaluation after the site-policy change.
- final read-only Fable 5 architecture review: conditional SHIP; its stale
  Pi-failover blocker and two minor prose findings were corrected.
- eval-only Pi failover drill in a disposable tree: moving `entry-plane` and
  `site.entryPlaneHost` to workstation produced a valid workstation system
  derivation and deployment target `["workstation"]`; the unchanged production
  architecture baseline correctly rejected the intentional temporary topology.

The final release boundary additionally builds all host targets and the four VM
checks serially to stay within workstation memory. Exact final commands and PR
check status belong in the pull request, not as a mutable claim here.

## Deliberate follow-ups

- Build and host the actual public status page and authenticated family portal
  from `status-json`/`portal-json`; define planned-maintenance announcements,
  registration UX, and generated tutorials in that product change.
- Replace Filmder and Heim activation-time Git builds with immutable release
  artifacts in their owning repositories.
- Consider a deployment framework only after the thin planner's semantics prove
  insufficient.
- Extract the rice or agent tooling only after a second consumer or independent
  release cadence exists.

## Rollback

The branch is organized as one concern per commit. Before activation, rollback
is simply closing the PR or reverting the affected commit range. After a future
activation, each host retains its previous NixOS generation; backends should be
rolled back before Pi when reversing a routing change. The presentation and
deployment packages are read-only and can be reverted independently.
