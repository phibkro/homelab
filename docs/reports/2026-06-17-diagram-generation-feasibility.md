---
date: 2026-06-17
summary: R1 — feasibility of generating topology diagrams from Nix code. D2 vs mermaid as a target. What meta-structure the code would need. Verdict.
---

# Diagrams-from-code feasibility (R1)

Stage 2 recon. Operator framing: "investigate if it's possible to generate diagrams from code to avoid drift, but some semantic details might be lost without additional meta-structure in the code. may also investigate if its easier to generate diagrams with D2 instead of mermaid."

## Current state

```
mermaid blocks across docs:
  docs/glossary.md                          1
  docs/reference/documentation-writing.md   1
  docs/reference/network.md                 1
  docs/reference/services.md                1
  docs/reference/topology.md                1   ← the candidate
  ────────────────────────────────────────────
  total                                     5
```

All five are hand-drawn. The topology.md diagram is the densest — proxy edges, scrape edges, backup edges, internet exits, SSH paths.

```
Edges currently in topology.md mermaid block:
  pi   --proxy-->  aurora
  pi   --proxy-->  workstation
  W    --send/recv-->  W       (intra-host btrfs send/receive)
  aurora       --scraped by-->  pi
  workstation  --scraped by-->  pi
  pavilion     --scraped by-->  pi
  pi   --heartbeat-->  Internet
  Mac  -.SSH-.->  pi
  Mac  -.SSH-.->  aurora
  Mac  -.SSH-.->  workstation
```

10 edges. Each one ALREADY exists implicitly in code:

```
edge type     where it's encoded in the Nix tree
─────────────────────────────────────────────────────────────────
proxy         nori.lanRoutes.<X>.runsOn — proxy host runs Caddy
                (pi); runsOn names the backend (aurora/workstation)
                ⇒ edge (Caddy-host, runsOn-host) per route
scrape        modules/services/node-exporter.nix +
                modules/services/beszel/agent.nix +
                modules/common/vector.nix (journald → VictoriaLogs)
                — scrape target == pi tailnet IP
                ⇒ edge (scraping-host, pi) per scraper
backup        modules/services/backup/btrbk.nix targets +
                workstation-side @family-replica-* subvols
                ⇒ edge (sender-host, receiver-host)
heartbeat     modules/services/heartbeat.nix → healthchecks.io
                ⇒ edge (pi, Internet)
SSH (Mac)     not in code; it's ambient operator-knowledge
                that the daily-driver SSHes into anything
                ⇒ cannot derive without a registry
```

**All four code-derivable edge types share one shape**: `(originHost, targetHost, kind)`. A Nix module-system walk can collect all four into a unified edges list and emit either mermaid or D2.

## D2 vs mermaid as target

```
                    mermaid              D2
                    ────────────────────────────────────────────
  rendering         GitHub-native        needs CLI/server
  in-tree           inline ```mermaid    inline ```d2
                                         (no GitHub native)
  CLI               npm @mermaid-js/      d2 binary in nixpkgs
                    mermaid-cli           (0.7.1 available)
  generated-first   afterthought          designed for it
                    DSL                   (idiomatic from
                                          composition / themes)
  grouping          subgraph (no nest)    containers (deep nest,
                                          themed per scope)
  edge styling      arrowhead + label;    typed arrows + animated
                    limited theming       traffic-like edges
  layout            ELK / Mermaid auto    ELK / D2's own (tala
                                          for nicer layouts)
  community         huge; GitHub default  smaller; growing
  install in        node + npm            single Go binary
  CI/dev shell      ecosystem             (lighter)
  our existing      5 hand-drawn blocks   none yet
  investment
```

D2's pitch is "diagrams as code, by design" — its DSL composes (you can `import` snippets, theme containers, declare typed connections). mermaid's pitch is "render anywhere GitHub renders". For OUR use case:

- **GitHub-rendering matters**: docs/ is read via GitHub UI when the operator views the repo from a phone or browser. Mermaid renders inline; D2 doesn't (would render as code block).
- **Generated-first matters too**: if the goal is "no drift, ever," the DSL should compose cleanly. Mermaid generates fine but the output is monolithic; D2 generates with structure (containers per tier).

## Required meta-structure for code-driven topology

Today's tree IS most of the way there:

```
PRESENT
  - nori.lanRoutes.<X>.runsOn  ← proxy edges
  - node-exporter / beszel-agent / vector targets  ← scrape edges
  - nori.backups + btrbk-replication  ← backup edges
  - heartbeat module → healthchecks.io  ← external edges

ABSENT (would need adding)
  - Tier annotation per host (appliance / workhorse / agent)
    ← already in nori.hosts.<name>.role; can be promoted to a
    container/subgraph grouping at generation time
  - Operator SSH paths
    ← could be inferred from authorized_keys or expressed as a
    nori.machines.<X>.operatorSshFrom = [ "macbook" ] field;
    OR just drop the SSH edges (low signal — operator already
    knows they SSH into things)
  - Edge label / semantic
    ← lan-route runsOn doesn't currently say "proxy"; that's
    implied by Caddy being on the appliance. Promote to a
    typed value (edge = "proxy" | "scrape" | "backup") or
    derive from module category (services/backup/ → backup;
    common/vector → scrape; etc.)
```

Total schema additions: 1-2 fields, OR pure inference from module location. The latter (inference) is more drift-resistant — adding a backup module under `services/backup/` automatically marks new edges as backup; no parallel string to keep in sync.

## Generator sketch

```nix
# pseudo
let
  hosts = config.nori.hosts;
  routes = config.nori.lanRoutes;

  proxyEdges = lib.mapAttrsToList (name: r: {
    from = caddyHost;
    to = r.runsOn;
    kind = "proxy";
    label = name;
  }) routes;

  scrapeEdges = ...; # walk node-exporter / beszel-agent / vector configs
  backupEdges = ...; # walk btrbk-replication + nori.backups

  allEdges = proxyEdges ++ scrapeEdges ++ backupEdges;

  d2Source = ''
    ${lib.concatStringsSep "\n" (map renderHostContainer
      (lib.groupBy (h: hosts.${h}.role) (lib.attrNames hosts)))}

    ${lib.concatStringsSep "\n" (map renderEdge allEdges)}
  '';
in pkgs.writeText "topology.d2" d2Source
```

Build into `nix build .#diagram-topology` → outputs `topology.d2` (DSL) AND `topology.svg` (rendered via `d2` binary in nativeBuildInputs).

## Hybrid recommendation

```
keep mermaid for           → operator-curated overviews where the
                             diagram IS the framing, not a derived
                             fact (e.g. glossary.md "fate-sharing"
                             illustration, agentic-workflow phase
                             arrows, network.md split-module
                             pattern)

generate D2 for            → topology.md (factual edges:
                             proxy + scrape + backup + heartbeat)

side-by-side until         → topology.md keeps the hand-drawn
proven                       mermaid AND links to a generated D2
                             SVG; if the D2 SVG converges to "same
                             as mermaid but without drift," drop the
                             hand-drawn version
```

## Verdict

**Feasible-with-restructure** — the meta-structure already mostly exists. Adding a generator is one Nix function + one D2 binary call. The structure-by-tier restructure (R3) is the prerequisite that makes the edge-source modules legible enough to walk reliably (today, scrape edges are scattered across `services/node-exporter.nix`, `services/beszel/agent.nix`, `common/vector.nix` — restructure unifies them under `observability-policy`).

```
Sequence for adoption:
  1. Structure-by-tier restructure (R3) lands
  2. Walk-edges generator written + `nix build .#diagram-topology`
  3. Side-by-side trial: D2 SVG renders alongside hand-drawn mermaid
  4. If D2 covers operator-needs, drop hand-drawn
  5. Apply same generator shape to network.md / services.md split-module
     diagrams
```

Costs:
- Operator-side: review the generated D2 output; doesn't render natively on GitHub (need to look at SVG)
- Build-side: `d2` binary in flake `nativeBuildInputs` — single Go binary, 8-12 MiB; trivial.
- Drift-side: zero if the generator walks reliably.

## What stays hand-drawn

Diagrams whose structure IS the message (not derivable from code):

```
- glossary.md fate-sharing illustration   conceptual
- agentic-workflow.md phase arrows         workflow
- documentation-writing.md amnesiac loop   conceptual
- network.md split-module shape            architectural pattern
- services.md backup pattern A/B/C         architectural pattern
```

These are not snapshots of runtime state. They are illustrations of invariants and patterns the operator wants the reader to see. Drift isn't possible if the diagram IS the spec.

## Out of scope (named, not done)

- Migrate the 4 non-topology hand-drawn mermaid diagrams to D2 (no payoff; they're not drift-prone)
- Animate D2 edges by traffic class (could; operator-curiosity only)
- Auto-include the diagram in `topology-generated.md` (Stage 3+: needs the structure-by-tier restructure to land first)
