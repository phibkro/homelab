---
date: 2026-07-19
status: accepted — governing design for feat/architecture-simplification
owner: operator
advisory_lead: Claude Code Fable 5
implementation_branch: feat/architecture-simplification
summary: Split global workload metadata from local runtime realization; compose hosts and homes from explicit profiles; keep effects as small typed intent interfaces; derive deployment, visibility, status, and docs from one inventory.
---

# Design — concern-oriented homelab architecture

## Decision summary

Evolve the repository around four layers with one-way dependencies:

```text
inventory / catalog
  hosts · profiles · workloads · datasets · endpoints · audiences
        │
        ▼
platform
  typed schemas · policy · networking · IAM · storage · backup
  observability · secrets · capabilities
        │
        ▼
profiles
  explicit reusable compositions for systems and users
        │
        ▼
realizations
  physical hosts · workload runtimes · hardware · local deviations
```

The key structural change is to split workload catalog metadata, which must be
visible across hosts, from workload runtime implementation, which must be
evaluated only on hosts that run it. A pure inventory compiler resolves explicit
host profiles before NixOS module evaluation, selects the required runtime
modules, and injects a typed, secret-free projection under `nori.inventory`.

Preserve the existing effect pattern where it is already the narrowest useful
interface. `nori.backups`, `nori.harden`, filesystem intent, and route policy
remain declarative inputs consumed by adapters. They do not become one giant
workload object.

Use this rule throughout:

> Imports choose identity and capability. Options tune selected concerns.
> Collected effects declare cross-cutting intent. Tags describe; they do not
> deploy.

This is one behavior-preserving migration delivered as staged commits on
`feat/architecture-simplification`. The operator reviews the complete pull
request before any production activation.

## Context

The repository's conceptual boundaries are already good:

- `modules/services/` owns hosted workloads.
- `modules/infra/` owns the hosting platform.
- `modules/machines/` owns composition and hardware realization.
- `modules/home/` owns operator user-space configuration.
- `nori.<effect>` registries turn one declaration into several generated
  configurations.

The evaluated module graph is less isolated than that conceptual model:

- the universal base imports almost every infrastructure implementation;
- workstation, Aurora, and Pi import every service implementation so each can
  see the complete HTTP route registry;
- activation is then recovered through `nori.services.<name>.enabled` gates;
- untyped tags can theoretically activate future services implicitly;
- route declarations must live outside runtime gates, a convention that has
  already produced distributed-registry visibility defects;
- host files contain workload placement, user integration, hardware policy,
  operational prose, and local exceptions together;
- the desktop package list groups unrelated capabilities merely because they
  happen to have a GUI;
- deployment and documentation maintain parallel inventories that can drift.

The result works, but implementation details leak upward. Adding or moving one
service requires understanding import visibility, placement gates, routes,
backups, Caddy, Blocky, Gatus, dashboards, and host rebuild fan-out.

## Problem definition

### Goal

Make the homelab understandable and safely changeable through a small set of
typed, composable interfaces while preserving all current system behavior.

The migration is complete when:

1. every hosted workload has one secret-free catalog manifest and a separate
   local runtime realization;
2. each host evaluates only the workload and platform implementations selected
   by its explicit profiles;
3. cross-host consumers read the typed inventory rather than relying on every
   host importing every workload implementation;
4. host files reduce to identity, hardware/storage realization, profile
   selection, and genuine deviations;
5. system and Home Manager profiles express reusable capabilities without
   making machine identity implicit in arbitrary package lists;
6. deployment host lists, route/status projections, dashboards, and future
   onboarding documentation derive from the same inventory;
7. active planning has one canonical lifecycle and stale architecture claims
   are removed or mechanically checked;
8. all NixOS and Home Manager configurations, checks, and behavior projections
   pass before the operator reviews the pull request.

### Hard constraints

- No production `switch`, router mutation, DNS mutation, secret mutation, or
  external product-repository mutation is part of this PR.
- Preserve the current dirty worktree and all unrelated branches.
- Keep the branch reviewable: one concern per commit; every commit green.
- Maintain default-deny network exposure, filesystem hardening, backup intent,
  and secret boundaries at every phase.
- Do not select NixOS module imports from `config`; imports are resolved from
  pure inventory data before module evaluation.
- Catalog projections contain references and policy, never secret values.
- No implicit deployment by tags, directory discovery, or naming convention.
- Public-service changes remain separately operator-gated even when their
  metadata moves into the inventory.
- A large rename is not an architectural outcome. Existing directory names may
  remain when changing them would add churn without improving dependency
  direction or interfaces.

### Values

In priority order:

1. correctness and reversibility;
2. narrow, typed public interfaces;
3. explicit composition;
4. local ownership of implementation details;
5. generated cross-cutting views;
6. simplicity of routine additions and moves;
7. low ceremony and low migration churn.

## Concern boundaries

A concern earns a separate module or package boundary when it owns at least one
of the following:

- a distinct invariant or security boundary;
- authoritative data or a persistence lifecycle;
- an independent test surface;
- a distinct change or release cadence;
- an interface consumed by more than one realization;
- a failure domain or deployment lifecycle;
- implementation complexity that callers should not need to understand.

A category name alone is insufficient. Folder boundaries may represent either
tight implementation coupling (`arr/`) or an explicit composition surface
(`profiles/`); the directory's public contract must say which.

Use the following extraction ladder:

```text
private functions/files
  → internal module/package
  → typed reusable profile
  → independently versioned repository
```

Move to a separate repository only when independent release/version ownership
or reuse is real. A package boundary inside this repository captures most of
the benefit earlier.

## Target architecture

### 1. Pure inventory and compiler

Introduce pure Nix inventory data that can be consumed before NixOS module
evaluation:

```text
inventory/
  default.nix
  hosts.nix
  profiles.nix
  workloads.nix
  datasets.nix
lib/
  inventory.nix
```

The exact paths may adapt to existing conventions; the separation is the
decision. The internal workload entry has this shape:

```nix
{
  jellyfin = {
    runtimeModule = ../modules/services/jellyfin/runtime.nix;

    metadata = {
      kind = "service";
      criticality = "important";
      capabilities = [ "gpu.video" ];

      endpoints.media = {
        port = 8096;
        audience = "family";
        reachability = "internet";
        authentication = {
          mode = "native";
          reason = "TV and mobile clients use Jellyfin credentials";
        };
        presentation = {
          title = "Jellyfin";
          group = "Consume";
          icon = "si:jellyfin";
        };
      };
    };
  };
}
```

`runtimeModule` is compiler-private. The factory removes implementation paths
and injects only validated metadata into the read-only public projection:

```nix
nori.inventory = {
  currentHost = "workstation";
  hosts = { ... };
  profiles = { ... };
  workloads = { ... };
  datasets = { ... };
};
```

The compiler:

1. expands each host's explicit profile list;
2. produces the set of platform and workload modules to import;
3. derives resolved workload placement from the hosts selecting a workload;
4. validates required capabilities and placement cardinality;
5. injects the secret-free resolved inventory;
6. exports machine-readable JSON for deployment and documentation tools.

The first version supports singleton placement. Replication, failover, and load
balancing are added only with a concrete workload requiring them, using a typed
sum rather than an overloaded list.

### 2. Explicit profiles

Profiles are reviewed, named compositions. Adding a new workload does not alter
any profile automatically; deploying it requires an explicit profile or host
change.

Initial system profiles:

```text
base
entry-plane
family-vault
media-compute
observability-hub
observability-agent
backup-client
backup-target
desktop
agent-host
```

A profile may contain:

- platform module imports;
- workload identifiers;
- required host capabilities;
- profile-level defaults that remain overrideable by the realization.

Tags remain available as descriptive catalog fields for search, generated docs,
visibility, and policy queries. `nori.enableServicesByTag` is removed after all
consumers migrate.

Host realization files should converge on:

```nix
{
  nori.host.profiles = [
    "base"
    "media-compute"
    "desktop"
    "observability-agent"
    "backup-client"
  ];

  imports = [
    ./hardware.nix
    ./storage.nix
  ];

  # Local deviations only.
}
```

### 3. Catalog and runtime split

Workload ownership remains local while visibility is separated:

```text
modules/services/jellyfin/
  manifest.nix     pure catalog entry
  runtime.nix      NixOS service, users, secrets, local effects
  default.nix      optional convenience composition
```

Manifest responsibilities:

- stable workload identifier;
- endpoint and presentation metadata;
- audience, reachability, and authentication posture;
- capability requirements and criticality;
- public-safe status/documentation metadata.

Runtime responsibilities:

- upstream NixOS service configuration;
- users, groups, packages, units, and timers;
- secret references;
- local filesystem bindings;
- backup and hardening declarations;
- runtime-specific resource tuning.

The manifest must be safe to evaluate for every host and in documentation/CI
contexts. The runtime is imported only on resolved placement hosts.

### 4. Platform schemas, adapters, and policy

Each large infrastructure concern keeps one narrow public option family but
splits internal reasons to change:

```text
modules/infra/networking/
  schema.nix
  policy.nix
  adapters/
    caddy.nix
    blocky.nix
    gatus.nix
    cloudflare.nix
    dashboard.nix
```

Equivalent internal divisions apply to backup and observability. This is not an
instruction to create tiny files mechanically. Split where an adapter can be
selected by a profile or tested independently.

The endpoint inventory becomes the source consumed by networking adapters. The
current `nori.lanRoutes` interface may remain as a compatibility projection
during migration, then become internal or be renamed once every consumer reads
the inventory. There is never a phase with two hand-maintained route sources.

Local effects such as `nori.backups` and `nori.harden` remain adjacent to the
runtime because only the placement host needs them. They are not moved into the
global manifest merely for visual uniformity.

### 5. Home Manager capability profiles

Keep the existing system/user/project scope rule and refine the user layer by
capability:

```text
modules/home/profiles/
  core.nix
  pc.nix
  desktop/
    wayland-session.nix
    productivity.nix
    communication.nix
    research.nix
  creative/
    video.nix
    audio.nix
  development/
    global-tools.nix
    agentic-tools.nix
```

- `creative.video`: DaVinci Resolve, HandBrake, FFmpeg, playback validation,
  and `resolve-remux`.
- `creative.audio`: Audacity and future production tools.
- `research`: Zotero, Obsidian, and paper-oriented clients.
- `development.global-tools`: editor, Git/GitHub, task runner, Nix inspection.
- language runtimes and compilers remain in project dev shells unless they are
  genuinely general-purpose interactive tools;
- agent runtimes, provider skills, sandboxing, and agent policy form a separate
  security-sensitive profile rather than leaking into generic development.

Extract the repeated Home Manager-as-NixOS wrapper into a shared system profile.

### 6. Hyprland rice as an internal product

Give the rice a package/module boundary before considering another repository:

```text
hypr-rice/
  package.nix
  module.nix
  lib/
  commands/
  tests/
```

Expose policy-level options only, for example:

```nix
programs.nori-rice = {
  enable = true;
  defaultLayout = "dwindle";
  palette.enable = true;
  bindings.extra = [ ];
};
```

Lua internals, generated Hyprland configuration, and command implementation are
private. Separate-repository extraction is a later decision triggered by
independent releases or a second consumer, not part of this PR.

### 7. Dataset-centered domains

Applications that share authoritative files compose through typed datasets
rather than hard-coded paths or broad groups:

```nix
nori.inventory.datasets.music = {
  valueTier = "irreplaceable";
  canonicalFormat = "flac";
  producers = [ "lidarr" "music-ingest" ];
  consumers = [ "navidrome" ];
  derivedFormats = [ ];
};
```

The private/local projection resolves concrete paths and filesystem grants.

For music, preserve FLAC as the canonical master and let Navidrome transcode and
cache on demand. A persistent Opus derivative is introduced only if measured
offline-client requirements cannot be met by Subsonic download/transcode
behavior. Acquisition, canonical storage, transformation, streaming, and
offline delivery remain separate stages with explicit contracts.

Apply the same pattern incrementally to photos, papers, manga, books, and home
video when it removes real path or ownership duplication.

### 8. Product and deployment boundaries

Personal application repositories own source, dev shells, tests, builds,
releases, and product roadmaps. The homelab owns only deployment concerns:

- immutable artifact version;
- runtime configuration and secret references;
- domain and access policy;
- persistence and migrations;
- monitoring and resource policy.

This PR introduces the consumer interface and records existing activation-time
Git builds as explicit legacy exceptions. It does not mutate Filmder, Heim, or
other external repositories. Migrating each product to a flake package, release
archive, or pinned image requires its own repository change and review.

The deployment control plane derives its host set from the inventory and
converges on one flow:

1. select an explicit source (`path:` for reviewed working state or a Git
   revision for a release);
2. derive affected hosts from changed profiles, manifests, and adapters;
3. build every affected host before activation;
4. enter maintenance state;
5. activate backends before entry-plane routing changes;
6. run internal and external acceptance checks;
7. clear maintenance or roll back.

The branch may add planning and build tooling, but it does not activate hosts.
A larger deployment framework is adopted only if a thin inventory-driven
wrapper cannot provide these semantics.

### 9. Documentation and work lifecycle

Use one active work artifact per outcome:

```text
docs/roadmap.md             outcome-level backlog
docs/work/active/<slug>.md  problem + design + plan + evidence
docs/decisions/             durable hard-to-reverse decisions
docs/reference/             current truth
docs/runbooks/              executable operations and recovery
```

This design remains under `docs/specs/` because it is the accepted migration
contract for an already-established repository convention. The migration will
decide whether adopting `docs/work/active/` is worth the move; it will not
create another parallel tree without retiring an existing one.

At completion, temporary execution detail is removed or archived through Git;
durable decisions move to ADRs, current facts to reference docs, and executable
failure handling to runbooks. Top-level generated `plans/` are either promoted
into the canonical roadmap/work item or treated as disposable output.

Because this repository commits through branches and operator-reviewed pull
requests, workflow documentation should call the unit a `change` or `feature`
where no actual PR exists and reserve `PR` for branch review.

## Dependency rules

The desired dependency direction is:

```text
pure inventory ────────────────┐
     │                         │
     ▼                         ▼
platform schemas          flake factory
     │                         │
     ▼                         ▼
selected adapters       selected runtime modules
     │                         │
     └──────────┬──────────────┘
                ▼
          host realization
```

Rules:

- inventory cannot depend on evaluated NixOS `config`;
- platform cannot import machine realizations;
- manifests cannot depend on runtime service options or secrets;
- runtime modules may consume platform options and the resolved inventory;
- hosts compose profiles and hardware but do not reproduce service metadata;
- generated docs and deploy tools consume public inventory projections;
- external products do not depend on this homelab repository.

## Migration plan

### Phase 0 — baseline and guardrails

- Rebase the branch on the latest accepted `origin/main` before implementation.
- Capture evaluated behavior projections for every NixOS and Home Manager host:
  enabled units, routes, firewall ports, packages, backup jobs, filesystem
  declarations, users/groups, timers, and generated adapter configuration.
- Add a comparison harness where existing tests do not already cover these.
- Repair obviously stale architectural claims encountered in the governing
  paths; do not begin a repository-wide prose rewrite.

Gate: all existing checks pass and baseline artifacts are reproducible.

### Phase 1 — inventory spine with no behavior change

- Add pure host/profile/workload inventory types and compiler.
- Project the existing machine registry into `nori.inventory`.
- Export public-safe inventory JSON.
- Keep all existing imports and activation gates temporarily.

Gate: evaluated system behavior is unchanged; new inventory assertions pass.

### Phase 2 — Jellyfin vertical pilot

- Split Jellyfin manifest from runtime.
- Generate its route/dashboard/status metadata from the manifest.
- Select its runtime through resolved placement.
- Prove Pi sees the endpoint without importing the Jellyfin runtime.
- Compare all pre/post Jellyfin behavior projections.

Gate: no duplicate route source, no route visibility regression, no runtime on
non-placement hosts.

### Phase 3 — migrate every workload

- Convert workloads incrementally in coherent groups.
- Preserve tightly coupled stacks as units where their runtime coupling is real.
- Remove the full service implementation bundle from hosts.
- Remove per-host `nori.services.<name>.enable` declarations after replacement.
- Retire `nori.enableServicesByTag`.

Gate: every workload is catalog/runtime split; every host imports only its
resolved runtimes; all backup/hardening/route invariants remain green.

### Phase 4 — platform profiles and host realizations

- Split universally imported platform schemas from selectable adapters.
- Introduce the initial system profiles.
- Move repeated Home Manager integration into a shared profile.
- Reduce host files to profiles, hardware/storage, and deviations.
- Correct stale topology and host-role narratives.

Gate: host role/capability assertions pass; no adapter runs on an unselected
host; host behavior projections remain equivalent.

### Phase 5 — user capability profiles and rice boundary

- Split desktop packages by capability.
- Separate creative, research, general development, and agentic tooling.
- Package Hyprland rice internals behind a small Home Manager interface while
  retaining its test suite.

Gate: Home Manager package/config projections remain equivalent unless an
explicitly documented cleanup removes a proven duplicate or dead package.

### Phase 6 — datasets, products, deployment, and documentation

- Introduce dataset metadata only where an existing cross-service contract uses
  it, starting with music.
- Add the immutable-artifact consumer interface and mark legacy builders.
- Derive deployment inventory and affected-host build plans.
- Align the roadmap/work lifecycle and remove stale parallel current-truth
  claims.
- Generate public-safe projections needed by future status and onboarding work.

Gate: one host inventory source; one endpoint source; deployment planning and
documentation projections contain no secrets.

### Phase 7 — final verification and PR

- Run formatter, lint, flake checks, eval tests, VM/e2e tests, shell/Lua tests,
  generated-doc freshness checks, and builds for every host and standalone
  Home Manager configuration.
- Review the entire branch against this document with the advisory product
  lead.
- Produce a per-phase change report, explicit deferred items, migration map,
  and rollback notes.
- Open one pull request for operator review.

No production activation occurs before that review.

## Full-migration definition

"Full migration" for this pull request means every in-repository host, workload,
platform consumer, Home Manager composition, deployment inventory consumer, and
current architecture document uses the new concern model or an explicitly named
compatibility adapter with a removal condition.

It does not mean silently changing external product repositories, redesigning
service behavior, replacing working applications, changing public exposure, or
deploying the resulting NixOS generations. Those are distinct changes with
their own authority and acceptance tests.

Compatibility exceptions permitted at merge must include:

- owner;
- reason;
- exact removal trigger;
- test preserving their current behavior.

## Verification strategy

### Static and evaluation checks

- inventory schema and referential integrity;
- profile expansion and cycle detection;
- workload placement cardinality;
- required host capabilities;
- no runtime module selected on an unintended host;
- one endpoint identifier and port owner;
- audience/reachability/authentication policy;
- every stateful runtime has backup intent;
- every runtime has filesystem capability intent;
- public projections contain no secret-shaped fields or store paths to secret
  material;
- documentation and deployment host sets equal the inventory host set.

### Behavioral projections

For each host compare before and after:

- enabled NixOS services, sockets, timers, users, groups, and firewall ports;
- routes, upstreams, TLS/auth policy, DNS records, probes, and dashboards;
- backup jobs, include paths, schedules, and targets;
- filesystem declarations and hardening binds;
- Home Manager packages, files, and program configuration;
- generated Caddy, Blocky, Gatus, Authelia, and observability inputs where
  practical.

Exact derivation identity is preferred when achievable. When refactoring causes
an intentional derivation change, compare the relevant structured behavior and
record the reason.

### Runtime simulation

Extend the existing VM/e2e topology tests to prove:

- the entry plane can route to a backend whose runtime module it never imports;
- moving a workload changes placement through one explicit composition edit;
- internal/public and operator/family visibility remain distinct;
- disabling/removing a profile removes its adapters and runtimes cleanly;
- generated inventory is sufficient for deployment planning and public-safe
  documentation without evaluating secrets.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Building an elaborate internal orchestrator for four hosts | Start with pure attrsets and small compiler functions; add types only for real invariants. |
| Creating a god workload manifest | Global manifest contains only cross-host metadata; backup, hardening, users, units, and secrets stay local. |
| Hidden deployment through profiles | Profiles list workload IDs explicitly; adding a workload never changes a profile automatically. |
| Import selection creates Nix fixed-point recursion | Resolve module paths from pure inventory before `lib.nixosSystem`; never from `config`. |
| Behavior drift during broad refactor | Golden structured projections, one concern per commit, green gates at every phase. |
| Documentation rewrite overwhelms architecture work | Update governing/current truth only; Git archives temporary execution detail. |
| Branch diverges while other homelab features land | Rebase at phase boundaries and rerun the full baseline comparison. |
| Public or secret policy leaks into generated outputs | Public-safe projection allowlist plus negative secret-field tests. |

## Reversibility

Each phase lands as independently reviewable commits. Compatibility projections
allow old and new consumers to coexist only while migrating, but there is one
authoritative input at every point.

Rollback units:

- Phase 1 can be reverted without workload behavior changes.
- The Jellyfin pilot can revert independently before bulk migration.
- Each coherent workload group can revert while compatibility projection
  remains.
- Host/profile conversion follows runtime migration and can revert per host.
- Home capability and rice changes are independent from server architecture.
- Deployment/docs projections do not participate in activation and can revert
  independently.

## Advisory product-lead charter

Claude Code Fable 5 acts as an advisory director/captain for this migration.
The role is intentionally read-only unless the operator later expands it.

Responsibilities:

- protect the Goal, Constraints, Values, and full-migration definition;
- challenge scope creep, decorative abstraction, and rename-only work;
- review every phase boundary for architectural coherence and product value;
- maintain a short decision/deviation ledger against this design;
- ask whether each interface is the smallest one that hides real complexity;
- ensure family/operator experience and operational safety remain visible while
  implementation structure changes;
- recommend stop/rework when a phase passes tests but violates the design.

Authority:

- advisory lead may recommend, challenge, or place an advisory hold;
- Codex remains responsible for implementation, evidence, and reporting;
- the operator owns scope, material trade-offs, merge approval, and production
  activation;
- disagreement is recorded with alternatives and evidence, not resolved by
  silent drift.

Cadence:

1. initial design review;
2. Jellyfin-pilot review;
3. workload-migration midpoint review;
4. host/profile and Home Manager boundary review;
5. final whole-branch review before PR.

## Alternatives rejected

### Keep importing all service modules and improve gate discipline

Rejected because route/catalog visibility and runtime realization have
different audiences. A convention requiring route declarations outside every
runtime gate remains an avoidable distributed-state trap.

### Put everything into one `nori.workloads.<name>` option

Rejected because it would centralize local users, units, secrets, backup paths,
and filesystem implementation in a global manifest. That exposes more surface
instead of hiding it.

### Use tags as the primary profile system

Rejected because untyped tags make future additions implicitly affect existing
hosts. Explicit named profile membership is more reviewable.

### Dynamically discover modules from directory names

Rejected because filesystem convention is a weak deployment interface and makes
renames behaviorally significant. The inventory is explicit and validated.

### Split Hyprland rice and agent tooling into repositories immediately

Rejected until independent release cadence or reuse justifies the operational
cost. Internal package/profile boundaries come first.

### Adopt a deployment framework before inventory cleanup

Rejected because a framework would automate the current duplicate inventory and
global-coupling model. Derive the deployment contract first, then evaluate tools
against it.

## Follow-up decisions

The migration may need focused ADRs for:

- the final inventory schema if it becomes a long-lived external interface;
- replicated workload placement semantics;
- adoption of a deployment framework;
- extraction of Hyprland rice or agentic tooling into separate repositories;
- persistent derived music formats;
- the product artifact contract shared across Filmder, Heim, and future apps.

These decisions are not prerequisites for the initial inventory spine or
Jellyfin pilot.
