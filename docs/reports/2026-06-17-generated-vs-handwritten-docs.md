---
date: 2026-06-17
summary: Side-by-side comparison of generated vs handwritten docs after the option-E experiment landed (file-level /** */ extraction + narrative migration into modules/infra/networking/default.nix + modules/machines/default.nix). Verdict — generated docs CAN carry module-scoped narrative; cross-module synthesis still needs handwritten authoring.
---

# Generated vs handwritten docs — after the E experiment

## What we tested

Option E from the earlier analysis: bring narrative + diagrams INTO doc-comments and see if generated docs can carry "almost the whole story." Implementation in commits `a874b47` (presentation fixes) → `0bd2559` (file-level /** */ extraction + content migration).

Two pairs to compare:

```
networking concern             topology concern
─────────────────────────────  ──────────────────────────────
docs/reference/network.md      docs/reference/topology.md
   ↕ compare with                 ↕ compare with
docs/generated/lan-route.md    docs/generated/topology.md
```

## Sizes

```
                              handwritten   generated
────────────────────────────────────────────────────
networking concern            145 lines    1024 lines
topology concern              182 lines     334 lines
─────────────────             ─────────    ─────────
total                         327 lines    1358 lines
```

The 4x size on generated is **schema reference** (per-option documentation
of every `nori.lanRoutes.<name>.<field>` and `nori.hosts.<name>.<field>`).
That's the part handwritten can't carry at all without duplication that
drifts.

## Networking concern — section-by-section

### What network.md has, lan-route.md now also has

| Section | Status | Where in generated |
|---|---|---|
| Zones (3-row table) | ✓ migrated | top of file-level docstring |
| `nori.lanRoutes` overview | ✓ already had | `nori.lanRoutes` option description |
| Function-over-brand naming | ✓ migrated | dedicated `## Naming` section |
| Dashboard enrollment | ✓ already had | `dashboard` sub-option descriptions |
| Audience trust model | ✓ already had | `audience` option description |
| Caddy + TLS + LE wildcard | ✓ migrated | dedicated `## Caddy + TLS + naming` |
| DNS architecture mermaid | ✓ migrated | dedicated `## DNS architecture` |
| Default-deny firewall | ~ partial | covered by zones table, not standalone |

### What network.md has that lan-route.md DOESN'T

| Section | Why it can't migrate |
|---|---|
| **Authelia OIDC overview** | Authelia is access-concern (`modules/infra/access/`), not networking. A full overview belongs in that module's docstring, not networking's |
| **Tailscale** | Separate module (`modules/infra/networking/tailnet-appliance.nix`); fragmenting the overview across two extraction sites loses cohesion |
| **Access summary** (SSH/Samba/snapshot table per FS path) | This is about filesystem access, not network. Cross-cuts disko + samba + btrbk modules — no single home in code |

```
verdict: 6/9 sections fully migrated, 1 partial, 2 stuck
networking concern E coverage:  ~78%
```

### What survives in network.md as load-bearing

- **Authelia OIDC overview** (until we extract from access concern in a future pass)
- **Tailscale topology table** (host roles + advertised routes)
- **Access summary** (FS-cross-cut)
- **SPOF mitigation note** (heartbeat to healthchecks.io)

Decision: handwritten network.md trims to these cross-module concerns; the
zones, DNS, Caddy, naming sections become redundant copies of the generated
content.

## Topology concern — section-by-section

### What topology.md has, generated/topology.md now also has

| Section | Status | Where in generated |
|---|---|---|
| Topology mermaid graph | ✓ migrated | top of file-level docstring |
| Failure domain independence | ✓ migrated | inline with topology graph |
| Service-implicit-until-lan-route'd (tier principle) | ✓ migrated | dedicated section |
| Topology registry rationale | ✓ already had | `nori.hosts` option description |
| Hosts-at-a-glance table | ✓ already had | hand-rolled from `config.nori.hosts` values |
| Cross-host references via `config.nori.hosts.<X>.tailnetIp` pattern | ✓ implicit | enforced by `forbidden-patterns` check; option descriptions reference it |

### What topology.md has that generated/topology.md DOESN'T

| Section | Why it can't migrate |
|---|---|
| **Pi posture** (anti-write storage, NVMe enumeration warning) | Lives in `modules/machines/pi/hardware.nix`. Could be extracted by adding pi/hardware.nix as a third docs-topology section, but conceptually it's a per-host concern, not a topology-as-a-whole concern |
| **Service placement table** (14 rows × why-each-service-is-where) | Spans every service module. Each row references multiple files. No single home in code; this IS the cross-module synthesis the handwritten doc is for |
| **Cross-host services (split-module pattern)** | Same issue — spans beszel, ntfy, immich-ml, hermes |
| **GPU access pattern** | Lives in `modules/infra/capabilities/gpu.nix`. Belongs in a docs-capabilities generator (not built yet) |
| **Resource caps** | Cross-module (multiple service modules) |
| **Operator facts** (single user, sudo policy, repaste history) | Not really code-related |
| **Workstation drives** | Deferred to structure-by-tier restructure per current note |
| **Adding a host** | Covered by `/add-host` skill |

```
verdict: 4/12 sections migrated; 8 stuck (mostly cross-module)
topology concern E coverage:  ~33%
```

### What survives in topology.md as load-bearing

- **Service placement table** (cross-module decision history)
- **Cross-host services / split-module pattern**
- **GPU access pattern** (until we add docs-capabilities)
- **Resource caps**
- **Operator facts** (single user, sudo, repaste, etc.)
- **Pi posture details** (until we add docs-machines that includes per-host hardware.nix extracts)

## Cross-cutting observations

### Generated docs win at

```
1. drift-by-construction        every option type/default/description
                                derives from code; can't go stale
2. completeness                 every `nori.X.<field>` documented; the
                                handwritten doc would never enumerate
                                all 20+ lanRoute fields
3. machine-readable             nixosOptionsDoc output is the basis for
                                man pages, IDE hover, future LLM tooling
4. mermaid + tables             markdown renders these natively in
                                doc-comments; no quality loss vs
                                handwritten
```

### Generated docs still lose at

```
1. cross-module synthesis       service placement, GPU access, resource
                                caps need handwritten authoring (no
                                single code home)
2. operator-facing prose        access summary, "single user nori"
                                facts — these don't tie to any module
3. content prioritization       schema reference treats `port` and
                                `dashboard.allowInsecure` with equal
                                weight; the handwritten doc can
                                emphasize what matters
4. cohesion across modules      Authelia OIDC fragments across
                                networking + access docstrings;
                                handwritten can synthesize
```

## The honest verdict

```
networking concern E coverage  ~78%
topology concern E coverage    ~33%
weighted average               ~55% of handwritten content can live in
                               code
```

**The E experiment partially works.** Module-scoped narrative + diagrams
migrate cleanly. Cross-module synthesis does not — and that's where the
handwritten docs were already concentrated value.

### Recommended split going forward

```
generated docs (docs/generated/)
  - module overview + mental model (single concern)
  - architecture diagrams tied to one module
  - per-option schema reference
  - hosts-at-a-glance (value-table)

handwritten docs (docs/reference/)
  - cross-module synthesis
    · service placement
    · cross-host service patterns
    · GPU + resource caps
    · access summary (FS cross-cut)
  - operator-facing prose
    · who can SSH where
    · what's the daily-driver UX
  - decision history that doesn't fit one option description
    · ADR pointers + their why-now context
```

network.md and topology.md both shrink ~50% if we move the migrated
sections out. They keep their cross-module synthesis sections + become
the "where to look for the why behind multi-module decisions."

The hand-written + generated pair stays valuable, with a clearer
contract:

```
"have a question about ONE module?"      → docs/generated/<concern>.md
"have a question about multiple modules?" → docs/reference/<concern>.md
"need an option's exact type/default?"    → docs/generated/<concern>.md
```

### What to do next (not in this commit)

```
1. trim network.md to cross-module sections only
   (drop the zones + DNS + Caddy + naming sections — generated carries them)

2. trim topology.md to cross-module sections only
   (drop topology graph + tier principle + failure-domain — generated
    carries them)

3. (optional) add docs-capabilities generator extracting from
   modules/infra/capabilities/{gpu,default}.nix — pulls GPU access
   pattern into a generated artifact too

4. (optional) extend docs-topology to extract per-host hardware.nix
   docstrings — would pull Pi posture into the generated doc

5. (decision) the E experiment is a SUCCESS for module-scoped content
   but DOES NOT eliminate handwritten authoring. Update
   docs/reference/documentation-writing.md to reflect the
   "module-scoped → code; cross-module → handwritten" rule
```

The drift-killer property is genuinely improved: every option and every
module's overview is now derived from code. The remaining handwritten
authoring is concentrated on content that fundamentally can't be derived
from a single module — and that's the right place for human judgment.
