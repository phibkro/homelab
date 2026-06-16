# Docs inventory — homelab (Phase 1, part 1 of 2)

> Findings for the homelab repo's docs. Sibling report (SOUL.md + memory) lives at `2026-06-16-docs-inventory-mem.md`.
> Read-only audit per `docs/plans/2026-06-16-docs-deep-sweep.md`. 26 files reviewed (root CLAUDE.md, README.md, 17 `docs/*.md`, 4 ADRs + `decisions/README.md`, 4 superpowers files, 10 runbooks, 2 install docs, 1 onboarding test). Ground-truth drift carried from the spawning brief is treated as authoritative.

## Per-file findings

### CLAUDE.md (root, 116 lines)

**Drift:**
- Lines 5–10 — host table claims aurora runs `vaultwarden, immich, calibre-web, komga, navidrome, …`. Accurate at the family-tier-backends level, BUT the table omits the syncthing-on-aurora addition (today's commits `e615e72` + `c140ec9`). The "Runs" cell is enumerable and will rot the next time a service moves — derivation candidate.
- Line 17 ("Three of the four NixOS hosts (pi, aurora, workstation) import the full `modules/services` bundle and opt into individual services") — verify: pavilion's `cp/02` work imported the bundle on some hosts but `docs/plans/2026-06-11-pr-review-stack.md` PR 6 says `modules/services/beszel/agent.nix` "was never imported on pavilion (it's flat-imports)". So pavilion is the fourth host but does NOT import the bundle — the "three of the four" wording is correct but worth re-stating as "pi, aurora, workstation import the bundle; pavilion flat-imports."
- Lines 73–94 — Docs map tables are duplicated verbatim in `docs/README.md` (acknowledged on line 31 of CLAUDE.md: "`docs/README.md` mirrors these tables"). Two homes, one fact, no derivation — drift candidate per SoT axiom (D-decisions D8 already targets trimming this).
- Line 88 — `docs/PROJECTS.md` is still listed as a tier-2 reference. Per `2026-06-11-docs-shape-review.md` D6, PROJECTS.md should leave homelab and live at `/srv/share/projects/AGENTS.md`. The file itself (frontmatter line 4) acknowledges this: "Canonical here in homelab; symlinked at /srv/share/projects/AGENTS.md". Decision not yet executed.

**Structural:**
- Lines 22–94 are three derived-style tables of file→USE-WHEN routing. These tables are the load-bearing part of CLAUDE.md but they're authored prose, not derived. After D2 lands (`docs/plans/2026-06-11-docs-shape-review.md` § "Migration phases") the flake check will assert consistency with `ls docs/`; today drift is live.
- Lines 28–44 ("Read on session start (mandatory)" + "Topic-triggered reference" + "Drill-down") — three sub-tables under one heading. The single-row "Read on session start" + 14-row "Topic-triggered" mismatch suggests collapsing into one table with a tier column. Existing structural review (D8) already targets this.

**Alignment:**
- "Code is the single source of truth; docs approximate" appears in Hard rules (line 50). This is the axiom from SOUL.md's restructure and CLAUDE.md already inherits it. **Aligned.**
- "Name the most-correct solution before any compromise" (lines 56–61, "What's the bias") is the new axiom from SOUL.md `d01876f` — already incorporated. **Aligned.**
- Tables don't yet honour the "constraints are generative" axiom — the `audience` enum is the canonical example (a constraint that enables an auth-stack decision per route) and could be framed as such in CLAUDE.md or NETWORK.md.

**Health:** Solid load-bearing index. Largest debt is the duplicated routing table with `docs/README.md` and the not-yet-executed D-decisions from 2026-06-11. The hard-rules + bias sections read cleanly and don't gold-plate.

---

### README.md (107 lines)

**Drift:**
- Lines 16 (`gatus` mention in "Resuming work"-related routing — N/A here, but the `Background services` section line 31 lists ntfy as `alert delivery: … for restic/btrbk/Gatus failures` — accurate.
- Lines 91–103 — "Repo shape" mentions `docs/CONCEPTS.md INVARIANTS.md` + `docs/MODULES.md ENFORCEMENT.md`. **`docs/CONCEPTS.md` no longer exists** (became `docs/glossary.md` — see GLOSSARY.md line 14 "Glossary" + INVARIANTS.md line 28 references "CONCEPTS.md" still). **`docs/MODULES.md` no longer exists either** (became `docs/reference/module-authoring.md` — `ls docs/` confirms). README is referencing two stale filenames.
- Line 107 (Status) — "Phases 0–7 done — backup + FS-hardening + LAN-route abstractions cover every service module… `pi` brought up as the appliance host with cross-host service split (Beszel hub + ntfy server)." This is severely understated; ADR-0002/0003/0004 + the aurora migration (P1–P14 done, P15 live, P18+P19+P20 mostly settled per ROADMAP line 13) all post-date this Status block. The whole aurora migration arc is invisible from README.
- Line 7 ("Two live hosts: workstation and pi") — outright drift. Aurora + pavilion are live (aurora is the entry-plane-adjacent family vault per ADR-0003; pavilion runs hermes + beszel-agent). Pre-ADR-0002 wording.

**Structural:**
- README leads with a 1-line summary ("Two live hosts...") that is now wrong. A reader who stops at line 3 leaves with a worldview from before 2026-06.
- "Active services" prose paragraph (line 20) walks through Caddy + LE + Blocky + Tailscale in one wall — appropriate for a README in scope but reads as "the same content in NETWORK.md compressed". Could be a single line + cross-ref.
- "Repo shape" tree (line 73) is mostly accurate but mentions `caddy-local-ca.crt` adjacent stuff implicitly via "Pi runs Blocky as a secondary forwarder…" which has flipped.
- File path mentions are not derived from the filesystem (D2 flake check would catch the stale CONCEPTS.md / MODULES.md names).

**Alignment:**
- The "Code is the single source of truth" axiom is honoured in the "static lists drift" callout (line 22) with a concrete derivation example (`nix eval … nori.lanRoutes`). Good rent.
- Misses the "Name the right answer first" axiom — README leads with the compromise (workstation + pi only) and doesn't name the topology as it actually is.

**Health:** Most-drifted file in scope. The Status block and the "two live hosts" lede need rewriting against ADR-0002/0003/0004 reality. The stale CONCEPTS.md + MODULES.md filenames are mechanical breakages (would be caught by a routing-table flake check).

---

### docs/README.md (69 lines)

**Drift:**
- None — content mirrors CLAUDE.md's tables and is consistent with current filenames in `docs/`. No stale paths.

**Structural:**
- Acknowledged duplication with CLAUDE.md (line 9: "Same tables live in the root `CLAUDE.md`; this file mirrors them for agents that land in `docs/` without that context."). Per D2 + decision deferred at `2026-06-11-docs-shape-review.md` § "Open decisions" #2, the choice is generate-from-filesystem or keep as human mirror. Not yet decided.
- Lines 28–43 (topic-triggered table) repeats the same 14 rows from CLAUDE.md. Two copies of the same fact; SoT violation pending decision.
- The "Adding a doc" footer (lines 59–69) is process documentation — could be its own L3 doc (`docs/contributing-docs.md`) or merged into DOCUMENTATION_WRITING.md.

**Alignment:**
- No alignment issues internal to this file; the duplication itself violates the SoT axiom.

**Health:** Functional but redundant. The duplication is the only real problem; pending the D2 decision.

---

### docs/glossary.md (87 lines)

**Drift:**
- Line 35 — split-module pattern entry says "Live: `beszel`, `ntfy`." VictoriaLogs (vector shipper + pi receiver) is also a cross-host pair (`modules/common/vector.nix` + `services/victorialogs/`); `TOPOLOGY.md` line 130 lists VictoriaLogs in the cross-host table. Minor — could add or just leave the example list non-exhaustive.
- Line 31 ("`nori.<X>`" row) lists "Reader + collected-Writer effect shape" — accurate. Frontmatter line 5 also names "split-module" — accurate.
- No model-vs-heuristic drift visible; the model-vs-heuristic distinction (lines 13–20) matches the SOUL.md framing post-restructure.

**Structural:**
- Tables (lines 25–37, 46–52) and the mermaid (lines 58–64) carry the load well — earning rent.
- Lines 73–87 ("Effect interface deep-dive") — overlap with `docs/reference/runtime-tests.md` § "The architectural correlation worth knowing" which makes the SAME Reader-Writer-shaped-effect claim. Two homes of the architectural pattern; one is canonical (GLOSSARY) and RUNTIME_TESTS should cross-ref instead of restating.
- "Adding an effect" mini-procedure (lines 82–87) is workflow-shaped — could be a skill (`/add-effect`) or move into MODULE_AUTHORING.

**Alignment:**
- "Models make the heuristics make sense" (line 22) matches SOUL.md's prescriptive/descriptive distinction. **Aligned.**
- The "convention not rule" framing (line 74) is the constraints-are-generative axiom in action — the Reader/Writer split isn't structurally prevented but it's the structure that the rest of the system exploits. Worth naming explicitly.

**Health:** One of the cleanest files in scope. The duplicate effect-interface explanation with RUNTIME_TESTS.md is the only structural debt.

---

### docs/invariants.md (85 lines)

**Drift:**
- Line 47 — "`nori.<X>` effects are one input → multiple generators (Reader + collected-Writer interface)" — links to "`CONCEPTS.md` § effect-interface deep-dive". **CONCEPTS.md no longer exists**; the content is in GLOSSARY.md. Stale citation.
- Line 84 (See also) — "`CONCEPTS.md` § enforcement ladder" — same stale citation.
- Line 48 ("Adding `modules/effects/<X>.nix` ships with a `just test-<X>` runtime introspection recipe") — `[prose: unchecked]`. Per ROADMAP line 65 this was promoted to `[law]` 2026-06-07. **The INVARIANTS row hasn't caught up.**

**Structural:**
- Table-driven, well-disciplined. The "At a glance" + "Tiers" + "Promotion work-list" layering is the load-bearing model the rest of the docs reference.
- Citation pattern (lines 76–78) is good — names the convention.
- No derivation possible; this is by-definition curated.

**Alignment:**
- The enforcement ladder IS the operational form of "make the bad state unrepresentable, not detected" — three-boundaries correctness. Could name this explicitly at the top.
- The "Code is the single source of truth" claim at line 51 is tagged `[judgment]` — fair. It's the axiom the whole catalog implements.

**Health:** Load-bearing. Two stale CONCEPTS.md citations to fix and one stale tier on the effects-have-tests claim.

---

### docs/reference/topology.md (171 lines)

**Drift:**
- Line 104 — "HTTP entry plane (Caddy + Authelia) | workstation today, pi post-P12 (ADR-0003)" — **STALE: P12 cutover landed 2026-06-12 per ADR-0003 addendum + aurora-migration report.** Line should read "pi (per ADR-0003, landed `0629326`)". The migration report's "workstation today" comment in caddy.nix that the ROADMAP flagged (Ground-truth #6) is this kind.
- Line 109 — Samba shares row says "aurora (post-P12 cutover, pre-positioned 2026-06-11)". P12 has landed; "post-P12" → "post-cutover landed 2026-06-12". Same drift class.
- Line 106 — "ML inference (Immich machine-learning / PyTorch) | aurora | Co-located with immich-server post-P8; GTX 950M is sufficient. `IMMICH_MACHINE_LEARNING_URL` resolves to aurora's tailnet IP whether immich-server runs on workstation (today, pre-P10) or aurora (post-state-migration)." **Post-P11 immich is fully on aurora. The conditional "whether on workstation (today, pre-P10) or aurora (post-…)" is stale.**
- Line 113 — "DNS authoritative for `*.${nori.domain}` (Blocky self-hosted) | pi | Post-ADR-0003. Workstation's Blocky stays as secondary forwarder until the entry-plane cutover; …" — same pre-cutover framing. Cutover landed.
- Line 117 ("Host-level high-level metrics (`beszel-agent`)") — names workstation + pavilion + aurora. Aurora's beszel-agent was re-enabled in cp/09 (`e333b8d`) — accurate.
- Line 133 — `hermes-agent` table row reads "pavilion (planned) → currently workstation". Accurate but stale tense ("planned"); per cp/09, hermes lives in services bundle and pavilion gets it eventually.
- Aurora row (lines 16) — accurate description of family vault. Doesn't mention syncthing-on-aurora (today's commit) — derivation gap.

**Structural:**
- Tables (lines 14–19, 50–55, 103–119, 127–134) are content-rich and earning rent.
- Mermaid (21–44) — useful, but shows nori.domain proxy arrows from pi to aurora + workstation. Should also show aurora→workstation btrfs send/receive (it's mentioned in text but not in the diagram).
- "Service placement" table (line 103) intermixes current and "post-X" status with footnoted ADR refs — readable but doesn't make the cutover-is-DONE state clear.
- Duplication with SERVICES.md catalog: lines 117 of TOPOLOGY about Beszel agent / node-exporter / process-exporter overlap SERVICES.md catalog. SoT debate — pick one home.

**Alignment:**
- The "fate-sharing breaks the function" framing (line 120) is the model from GLOSSARY. Good cross-ref.
- Workhorse/appliance/agent triad maps cleanly to SOUL.md's principle-then-narrow shape: name the role, name what it survives.
- Missing: the "name the right answer first" lens on placement. Could open with "the most-correct placement is the host where fate-sharing is minimized; then narrow by hardware constraints".

**Health:** High-drift, high-value. Several `pre-P12` and `post-P10` framings need consolidation to "as-of 2026-06-12". Otherwise excellent visual structure.

---

### docs/reference/storage.md (137 lines)

**Drift:**
- Line 36 — Workstation media table header ("Workstation media (IronWolf Pro, btrfs)") + line 42 "Reformatted from exfat in Phase 2 (executed during Phase 5)" — fine; historical fact.
- Lines 41–49 — subvolume table lists `@photos`, `@home-videos`, `@projects`, `@library`, `@archive`, all backed up with snapshot policy. **Per aurora migration P14, the irreplaceable subvols on IronWolf were planned to be dropped; per pr-review-stack cp/09 the photos/library work is in flight. Per ADR-0002 + the report, workstation IronWolf is "trimmed to `@downloads` + `@streaming` only" post-migration.** This table now misrepresents IronWolf's actual contents.
- Line 51 — "@library holds curated content the operator assembled by hand (books, comics)" — aligns with the Ground-truth-inversion: library means manually-curated keepers. But: the orchestrator says "Books and music in workstation library moved to downloads" — the doc should reflect that workstation's IronWolf library is gone or moved (subvol deletion was pending P10 confirmation per the plan; in flight).
- Line 64 — Backup target table: "Seagate OneTouch (physically on aurora; workstation reaches via SFTP) | ext4 | `/mnt/backup/<svc>` | per-service timer (e.g. 04:30)". Accurate (per ADR-0002 P13).
- Line 66 — "Both restic units race on the prepareCommand `.tmp` file → wrapped in `flock` since 2026-06-07. See [[pattern-c2-sqlite-race-flock]]." — accurate.
- Line 96 — "Hetzner off-site planned (ROADMAP)." **STALE.** Per ADR-0002 + addenda: Hetzner explicitly REJECTED. ROADMAP confirms ("P17 Hetzner explicitly rejected per ADR-0002") and STORAGE itself says (line 21 — "System config is covered by the Git mirror to GitHub, not a backup target.") but then line 96 + line 98 column header + lines 102-106 STILL show "Hetzner (off-site, planned)" / "Hetzner Storage Box deferred (ROADMAP)" wording. **Direct contradiction with ADR-0002.**
- Lines 108–112 — "Hetzner Storage Box sizing" section. Whole section is dead per ADR-0002 rejection.
- Line 132 — `nori.fs.<n>` schema "Reader-shaped — declared alongside the host's disko config; each entry pairs a path with a value tier" — accurate.

**Structural:**
- Tables earn their keep. Value-tier table (line 12) cleanly drives the rest.
- The dead Hetzner section (lines 108–112) is a strong "transcribed framework / dead code with comment explaining why" antipattern from DOCUMENTATION_WRITING.md.
- Subvolume tables duplicate disko layout — derive-from-code candidate (the disko file is the SoT).

**Alignment:**
- Value-tier protection tree (frontmatter + § Value tiers) is the "constraints are generative" axiom incarnate: the tier IS the constraint that drives backup/snapshot derivation.
- "Code is the SoT" honoured for `nori.fs` (line 132 names the schema location).

**Health:** Hetzner section is the largest single drift in the file. Subvolume table needs alignment with aurora-migration outcome.

---

### docs/reference/network.md (145 lines)

**Drift:**
- Line 28 — `lanRoutes` is described as generating "**Caddy vhost** at `<name>.nori.lan`". **`.nori.lan` is legacy per ADR-0004.** Should be `<name>.home.phibkro.org` (or `${nori.domain}`).
- Line 29 — "**Blocky DNS** mapping `<name>.nori.lan` → workhorse LAN IP" — same drift; should be `<name>.${nori.domain}` and "→ pi LAN IP" per ADR-0003.
- Line 70 — "The `nori.domain` option (`modules/effects/lan-route.nix`) is the single source of truth" — accurate. But surrounding context (lines 65–73) accurately describes LE + Cloudflare DNS-01 via the wildcard — well-maintained.
- Line 71 — "Transitional `*.nori.lan` redirect: pi's Caddy still serves `*.nori.lan` (Caddy internal CA) and 301-redirects to the same path under `home.phibkro.org`." — **STALE.** Per `a2372ae` ("fix(caddy): drop tls internal on *.nori.lan — HTTP-only deprecation", 2026-06-15), the internal-CA on `.nori.lan` was dropped; only HTTP redirect remains.
- Line 73 — "**Python services** with `certifi`-based clients (open-webui's `httpx`/`requests`/`urllib3`) historically needed `SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"`…" — historical, OK.
- Line 87 — example comment `# networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8096 ];` + `# nori.lanRoutes.media = { port = 8096; monitor = { }; };` — accurate as an example.
- Line 90 — "Pi runs Blocky in **self-hosted mode**" — accurate (post-ADR-0003).
- Line 107 — "Workstation's Blocky is also self-hosted as a fallback secondary (resolves the same map; LAN-side resilience for if pi is down)." — accurate.
- Lines 120–124 — Tailscale role table mentions `pavilion / aurora | regular node | —`. Accurate.
- Line 128 — "**SSH ACL: `action: accept`** (since 2026-06-07)." — accurate.
- Lines 138–144 — Access summary table refers to `/mnt/media/photos` and `/mnt/media/projects` — these are the workstation paths. Post-aurora-migration, `/mnt/family/photos` (aurora) is canonical; workstation has `/mnt/family-replica/photos`. The table should reflect aurora paths or note both hosts.

**Structural:**
- Mermaid (lines 96–105) earns rent. Tables earn rent.
- The `*.nori.lan` examples sprinkled through the doc are a class — single sed sweep over `nori.lan` → `${nori.domain}` would consolidate.
- The "transitional `*.nori.lan` redirect" paragraph (line 71) is a candidate for deletion now that internal-CA is dropped — keep only the HTTP-only redirect line.

**Alignment:**
- The `audience` enum (lines 56–62) is the canonical "constraints are generative" example: a typed constraint drives the auth-stack decision per route. Worth naming explicitly here.
- "Default-deny everywhere" (line 11) is the make-bad-state-unrepresentable axiom.

**Health:** Largely accurate post-LE pivot; the persistent `.nori.lan` examples are the main residue. Three pre-ADR-0004 transitional paragraphs to retire.

---

### docs/reference/services.md (251 lines)

**Drift:**
- Line 21 — "Immich | `services.immich` (VectorChord, Postgres 17) | workstation | `photos.nori.lan` (family)" — **STALE.** Immich landed on aurora P11 (commit `8800d5f`). Route should be `photos.home.phibkro.org` and host should be `aurora`.
- Lines 25–37 — every workstation-resident service has a `<name>.nori.lan` route. Per ADR-0004 these are `<name>.home.phibkro.org` now (the `.nori.lan` survives as a transitional redirect). The catalog should reflect post-ADR-0004 names with `${nori.domain}` or `*.home.phibkro.org` as the canonical form.
- Line 36 — "Radicale | … workstation | `calendar.nori.lan` (family); CalDAV + CardDAV; htpasswd" — Radicale moved to aurora P11. Host = aurora.
- Line 37 — "Syncthing | … workstation | `sync.nori.lan` (operator); peer port 22000 open on tailscale0" — **STALE on host.** Per today's commit `e615e72` syncthing now runs on **both workstation AND aurora** (aurora has its own instance for phone music sync). Plus the `sync.nori.lan` URL is `sync.home.phibkro.org` per ADR-0004.
- Line 40 — "Authelia | `services.authelia.instances.<name>` | workstation" — STALE. Authelia is on pi post-P12.
- Line 39 — "Caddy | `services.caddy` | workstation" — STALE. Caddy is on pi post-P12.
- Line 42 — "Blocky (forwarder) | … pi | LAN via tailnet DNS push" — STALE. Pi runs Blocky **authoritative** per ADR-0003, not forwarder.
- Line 43 — "Blocky (self-hosted) | … workstation | LAN fallback" — accurate as a fallback role.
- Line 44 — "Beszel hub | `services.beszel.hub` | pi | `metrics.nori.lan` (operator); cross-host reverse-proxied via station Caddy" — STALE. Reverse-proxied via pi's Caddy now.
- Line 46 — "Gatus | `services.gatus` | workstation + pi | `status.nori.lan` (public); mutual probes …" — **STALE per today's commit `10d17b8`.** Canonical UI surface flipped from workstation to pi; both still RUN it for mutual monitoring but `status.<domain>` resolves to pi now.
- Line 50 — "Grafana | `services.grafana` | workstation | `ops.nori.lan` (operator)" — STALE. Grafana moved to aurora during P11 (cp/06 commit `9a04a7f`).
- Line 53 — "ntfy server (pi-local) | … pi | `alert.nori.lan` (operator); reserved for future internal-only alerts." — accurate; ntfy hub on pi is pre-positioned.
- Line 55 — "heartbeat | `modules/services/heartbeat.nix` | pi | Dead-man-switch; ping healthchecks.io every 60s. SPOF mitigation" — accurate.
- Line 59 — "immich-machine-learning | `modules/services/immich-ml.nix` (aurora) | **aurora** | RPC only (3003); `IMMICH_MACHINE_LEARNING_URL` on workstation" — STALE. ML is co-located with immich-server on aurora post-P11; `IMMICH_MACHINE_LEARNING_URL` lives on aurora pointing at localhost or on workstation pointing at aurora (depends on whether workstation still has any immich consumer — it shouldn't).
- Line 63 — "restic jobs | `services.restic.backups.<n>` | workstation | Dual-target → `/mnt/backup/` (OneTouch) + `/mnt/backup-local/` (mp510); Hetzner deferred" — STALE on Hetzner ("explicitly rejected"). Also: every host now runs its own restic (aurora got them via P11) — not just workstation.
- Line 64 — "btrbk | `services.btrbk.instances.<n>` | workstation | Local snapshot" — incomplete; aurora has btrbk now too (for P15 sender).

**Structural:**
- The catalog table (lines 13–69) is 50+ rows. **Highest-density derived-list-in-prose violation in the codebase.** Every row is derivable from `nix eval … nori.lanRoutes` + a "where does it run" filter. Should be auto-generated (ROADMAP § "Batch C: generated docs from live config" lines 56 already names this).
- Backup pattern A/B/C section (lines 76–179) — well-structured, canonical impl reference for navidrome is load-bearing.
- Observability mermaid (lines 184–208) — earning rent.
- "About Immich's Postgres" (line 73) is good; but with Immich on aurora, the path examples (`/var/lib/immich/database`) are aurora paths now.

**Alignment:**
- Backup patterns A/B/C are "constraints are generative" — the choice of pattern drives the systemd shape. Good.
- "A service module owns *everything* about its service in one file (no fan-out)" is honoured throughout.
- The catalog as a derived list violates "Code is SoT" — it's prose paraphrasing the registry.

**Health:** **The single most-drifted file in scope.** Three quarters of the service rows have stale host or URL. Catalog derivation should be the highest-priority Phase 3 surgery target.

---

### docs/reference/module-authoring.md (346 lines)

**Drift:**
- Line 70 — Concerns table mentions: "`services/` | …; aurora (whole bundle for family-tier backends); workstation (whole bundle for compute-side services)". Pavilion not listed; line 92 ("`pi` lives as `common +` *flat imports of specific server modules*") matches reality and is consistent with the "three of four import the bundle" claim from CLAUDE.md.
- Line 35 — `modules/effects/` list includes "gatus-probe.nix · resource-tiers.nix · restart-policy.nix · rust-motd.nix · hosts.nix". Order is fine; rerun listing would confirm vs actual `ls`. Also: `hosts.nix` listed twice (line 32 and line 35). Minor.
- Lines 245–250 — DynamicUser table — accurate.
- Line 311 — "On workstation: `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];`" — accurate per current machines/workstation/.

**Structural:**
- Long file (346 lines, largest in scope). Multiple distinct topics: repo structure, FS hardening, sops, packages, dev shells, dev workflow, commit style. **Could split**: e.g., `dev-workflow.md` or `packages-and-shells.md`.
- "Service module template" (lines 107–142) is the kind of derived example that the rent-paying-imitation-loop relies on.
- "Concerns compose host identity" table (lines 70–75) is the cleanest articulation of `modules/<concern>/` semantics in the docs.

**Alignment:**
- "A service module owns *everything* about its service in one file (no fan-out)" (line 107) — the make-illegal-states-unrepresentable axiom at module level.
- The "lowest scope that gets the tool to its actual audience" rule (line 257) is the canonical "name the right answer first; narrow by constraints" trace.
- `mkDevShell` design — composability over single god-modules. Matches GLOSSARY.

**Health:** Long but high-density. Largest action would be split-or-not decision; otherwise low drift.

---

### docs/reference/runtime-tests.md (132 lines)

**Drift:**
- Line 31 — `test-replicas` recipe is listed and described as "(smoke-passes on empty registry)" — accurate. Per the aurora-migration report (PR 10 P15 cp/05 + cp/09), btrbk replication is now live (since 2026-06-12) and per Ground-truth #1, replication is running daily. The test-replicas recipe SHOULD now have a non-empty registry to verify against. The line "smoke-passes on empty registry" was true at P5 landing but isn't anymore. Worth checking against current `nori.replicas` declarations.

**Structural:**
- Excellent visual structure (four levers table + Reader-Writer correlation table + next-targets table).
- Some overlap with GLOSSARY.md's effect-interface deep-dive (the Reader-Writer-shaped subset claim). Cross-ref instead of restating.
- "Real catches, for posterity" (line 112) is high-value institutional memory.

**Alignment:**
- The four-lever framework is the embodiment of "constraints are generative": leverage/volatility/opacity/blast-radius are the constraints; runtime-test viability is the structure they enable.
- "Make the bad state unrepresentable, not detected" → runtime tests are the third boundary in the SOUL.md "three boundaries" model. Could be named explicitly.

**Health:** Cleanest L2 doc in the repo. Minor freshness update for replicas; otherwise solid.

---

### docs/reference/recovery.md (85 lines)

**Drift:**
- Line 18 — "Pi total failure | < 2 hours | Spare USB SSD or reflash from flake. **healthchecks.io alerts off-host** when pi misses 3+ heartbeats" — accurate, post-ADR-0003 pi failure mode includes loss of Caddy + Authelia which is a bigger blast radius than pre-cutover. The line doesn't reflect this.
- Line 19 — "Aurora total failure | degraded only — immich-ml falls back to host CPU via env-var change | Operator updates `IMMICH_MACHINE_LEARNING_URL` on workstation; non-blocking" — **STALE.** Post-P11 aurora total failure takes down the family-tier surface (vaultwarden, immich, etc.). The "degraded only" framing is from when aurora was just immich-ml offload.
- Lines 33–34 — Runbooks table mentions `drive-failure-root.md` referring to "restic restore from `/mnt/backup` USB drives" — `/mnt/backup` is now on aurora (per ADR-0002 P13). Path accurate, host-context shifted.
- Line 36 — "drive-failure-media.md" — IronWolf is now @downloads + @streaming only; restic restore of irreplaceable from `/mnt/backup` lives on aurora. The runbook itself still describes restoring photos/home-videos/projects/archive — works because backups are content-addressed but host-routing is different.
- Line 51 — Permanent constraints includes "**Don't schedule destructive system changes during weeks with Aker demo pressure**" — operator constraint; non-doc-drift but a `[judgment]` claim.

**Structural:**
- RTO table earns rent. Runbook index earns rent.
- "Reactive triggers (no scheduled date)" at line 75 — the "name the trigger to revisit" pattern shows up well; matches the architectural-debt frame in ROADMAP.

**Alignment:**
- The permanent-constraints table (line 50) is exactly "make the bad state unrepresentable" applied to recovery — non-negotiable invariants encoded as text. Could promote to types/asserts where feasible (the `by-id` constraint is already in `gotcha-nvme-enumeration`; the windows-drive constraint is structural via `disko-mp510.nix` by-id pinning).

**Health:** Mostly aligned but the post-ADR-0002/-0003 failure-mode rows haven't been updated.

---

### docs/roadmap.md (88 lines, 13786 bytes — note: bytes/lines ratio = longer-than-counted)

**Drift:**
- Line 13 — "**Aurora migration** … **Outstanding:** P15 (replication — sender + receiver modules drafted `04629a6` + `ba38187`, **awaits operator ssh-key bootstrap**), P19 magic-packet test gated on operator reboot, P20 hypridle re-enable". **CONFIRMED STALE per Ground-truth #1.** P15 is LIVE (running daily since 2026-06-11 18:05 per aurora-migration report PR 10 + ls verification of `/mnt/family-replica/*`).
- Line 13 — Same paragraph: "P16 pavilion tertiary replica future-work; P17 Hetzner explicitly rejected per ADR-0002." — accurate.
- Line 17 — "Full documentation deep-scan (post-aurora-migration)" — this is the trigger for the current sweep. Should eventually be closed.
- Line 32 — "MemoryHigh caps on heavy services" — accurate, current.
- Line 50 — "Remaining SSO candidates" with native OIDC + Skip/problematic split — accurate.
- Line 56 — "Batch C: generated docs from live config" — confirms SoT recognition. **In scope for Phase 2/3 of this very plan.**
- Line 81 — "Suspend-then-hibernate ladder on NVIDIA" — accurate per `5de4cab` + `b77b030`.

**Structural:**
- Section "Outstanding (actionable)" is the load-bearing zone. Long-but-okay narrative per item.
- Architectural debt section (line 79) is the named-compromises-with-a-known-correct-shape pattern. Excellent application of the "name the right answer first; debt = decision to compromise temporarily" axiom from SOUL.md.
- "Promotion register (from INVARIANTS.md)" (line 58) duplicates INVARIANTS § "Promotion work-list". SoT — pick one home.

**Alignment:**
- Architectural debt section is the operationalisation of "Name the most-correct solution before any compromise; name the trigger to revisit." **Strong.**
- "Outstanding" doesn't always lead with the correct answer; some items are pragmatic from the start. Could honour SOUL.md's "Name the right answer first" more explicitly.

**Health:** Largest single stale item (P15 status) but the file overall is well-maintained. The duplicated promotion register is the structural debt.

---

### docs/decisions/0000-rationales.md (42 lines visible — file is 8877 bytes, ~140 logical rows)

**Drift:**
- Line 25 — "Self-hosted Authelia OIDC over Cloudflare Access (reversed 2026-05)" — accurate per ADR-0004 context.
- Line 28 — "**`nixos-26.05` stable channel** (since 2026-06-03; previously unstable)" — accurate per `nixpkgs-downgrade-strands-state` gotcha skill.
- Line 36 — "**Runtime introspection tests** (added 2026-06-07)" — accurate.
- Frontmatter line 4 — "Lifted from the dissolved DESIGN.md (2026-06-03)" — historical preserve, fine.

**Structural:**
- Table-driven, dense, scannable.
- The "decisions/" / "RATIONALES.md" split — per D3 from 2026-06-11-docs-shape-review, RATIONALES becomes `docs/decisions/0000-rationales.md` (meta-index ADR). Not yet executed.
- Each row matches the row-earns-its-keep test (line 39).

**Alignment:**
- Rows trace the "name the right answer + rejected alternative + evidence" shape — directly implementing the SOUL.md "name the right answer first" axiom.
- "When to add a row" (lines 38–40) — explicit promotion test. Good.

**Health:** Solid. The D3 migration is the only structural debt.

---

### docs/reference/documentation-writing.md (130 lines)

**Drift:**
- Line 4 — "Pairs with `MODULES.md` (code shape) and `ENFORCEMENT.md`" — **MODULES.md no longer exists** (became MODULE_AUTHORING.md). Stale citation.
- Line 124 — "References — `MODULES.md` — code shape (this file is its prose-side companion)." — same stale citation.

**Structural:**
- Mermaid + tables earn rent.
- Tables (lines 44–52, 57–63, 96–112) are the canonical "anti-pattern" register in the codebase. Highest leverage doc for the meta-rule "what makes a comment earn rent".
- Line 122 ("Style for prose (the doc-refresh prompt)") is a quote-block of the rule. Could be a callout.

**Alignment:**
- The "Code describes behavior, comments encode intent" core principle (line 14) is the canonical articulation of the make-bad-state-unrepresentable axiom applied to docs.
- "Cross-reference, never duplicate" (line 82) is THE Single-Source-of-Truth axiom verbatim.
- "Bind load-bearing claims to evidence" (line 84) is the bind-to-evidence axiom from SOUL.md.
- The earns-rent vs cut taxonomy (line 44) is the operational form of all three SOUL.md axioms in one table.

**Health:** Very well-aligned with SOUL.md. Two stale `MODULES.md` references are the only fix.

---

### docs/reference/enforcement.md (135 lines)

**Drift:**
- Line 28 — "Conceptual model: see `CONCEPTS.md` § enforcement ladder." — **stale CONCEPTS.md reference** (now GLOSSARY.md).
- Line 105 — Live `nori.<X>` enforcement table looks current; all five rungs listed.

**Structural:**
- Tables (lines 17–26, 30–43, 84–95, 105–116) are dense and earn rent.
- The decision tree at line 84 is the canonical "when to add a rule" oracle. Heavy referenced.
- Section "Promoting a `[prose: unchecked]` claim" (line 120) — duplicates INVARIANTS § "Promotion work-list" + ROADMAP § "Promotion register". **Three homes of the same fact.**

**Alignment:**
- The ladder (line 13) IS the SOUL.md "make the bad state unrepresentable" axiom mapped to a ladder of mechanisms. Three boundaries (types, runtime, knowledge) all present.
- "A check earns its keep when it would have caught a real mistake, not a hypothetical one" (line 102) is the SOUL.md "false positives outweigh real catches" framing.
- Could explicitly cross-ref the SOUL.md three-boundaries frame at the top.

**Health:** Strong alignment, low drift. One stale citation + three-home duplication of the promotion register.

---

### docs/SKILL_INDEX.md (46 lines)

**Drift:**
- Line 23 — "Auto-loaded gotcha skills (35+ of them as of 2026-06-07): each `.claude/skills/gotcha-<short-name>/`…" — number `35+` is plausible per current skill availability; quick `ls` would confirm.
- Line 10–22 — skill list. Cross-checked against the system-injected skill list in the spawn context: matches (`/analyse-system`, `/add-service`, `/add-host`, `/relocate-to-pi`, `/add-oidc-client`, `/query-logs`, `/wrap-session`, `/on-structural-change`, `/audit-documentation`, `/restore-pg-with-owner-fix`). All present and accounted for.

**Structural:**
- Table + section ladder is clean.
- Same content lives in CLAUDE.md routing and `home/claude-code/skills/` directory listings. Could be auto-derived.

**Alignment:**
- "Prose for facts (always-loaded in CLAUDE.md), skills for procedures (load on demand)" (line 46) — the load-on-demand axiom is one form of "context is the scarce resource" from ADR-0001.

**Health:** Clean. Derivation candidate but well-maintained today.

---

### docs/PROJECTS.md (91 lines)

**Drift:**
- Line 4 (frontmatter) — "Canonical here in homelab; symlinked at /srv/share/projects/AGENTS.md." — D6 decision says PROJECTS.md should LEAVE homelab. Not yet executed.
- Line 49 — Per-project cheat-sheet table mentions `snowy` as "M0 done, M1 = read Stylix config" — current per `snowy-and-testing-framework` memory entry.
- Line 56 — `homelab` entry says "changes need `nh os switch` to apply" — accurate.

**Structural:**
- Self-contained table-driven file.
- Per D6, the symlink direction should reverse (canonical at `/srv/share/projects/AGENTS.md`, optional copy here).

**Alignment:**
- "Read the entrypoint first" (line 65) — progressive disclosure rule.
- "Verify by running the real thing, especially for security-adjacent work — and ground claims in the code, not in review prose" (line 73) is the make-bad-state-unrepresentable + bind-claims-to-evidence axiom.

**Health:** Clean content; debt is the D6 migration not yet executed.

---

### docs/reference/capacity-baseline.md (62 lines)

**Drift:**
- Line 32 — Backup repository table lists `media-irreplaceable` as a repo — this is the legacy aurora-pre-migration shape. Per ADR-0002/P14 the structure changed (per-fs irreplaceable backed up via family/* on aurora; mp510 holds backup-local for workstation-side services).
- Line 47 — Hetzner column "deferred until budget allows; column kept for the day it lands" — **STALE** per ADR-0002 rejection of Hetzner. Column is for a dead path.
- Line 61 — "_baseline pending — fill at first review_" — never filled. Schema is the schema; the data isn't there.

**Structural:**
- Schema-shaped file; empty cells are the point.
- Could be machine-driven (a `just capture-baseline` recipe writing into a dated file under `docs/auto/`).

**Alignment:**
- Quarterly review cadence is "iterate-to-stable then codify" — but the doc is purely the schema; no codification has happened.

**Health:** Skeletal. Hetzner column is dead per ADR-0002; first review never happened.

---

### docs/installs/baremetal.md (229 lines)

**Drift:**
- Line 33 — "sudo dd if=~/Downloads/nixos-minimal-25.11.<...>.iso" — **25.11 ISO; nixpkgs is now 26.05** (per CLAUDE.md + RATIONALES.md). The ISO version is the installer's, not the system's — the install ISO from 25.11 can install 26.05 — but the example should match current.
- Line 73 — "/dev/nvme0n1` is `WDS100T3X0C-00SJG0` (WD Black SN750, 931.5 GB) — install target." + line 79 "If any disk is missing or the model strings don't match, **stop** and investigate. The disko config is hardcoded for `/dev/nvme0n1`." — **the disko config is hardcoded for `/dev/disk/by-id/...`, not `/dev/nvme0n1`.** This is a direct contradiction with the `gotcha-nvme-enumeration` skill + CLAUDE.md hard rule. The line should say "the disko config targets by-id; verify the by-id matches".
- Line 200 (deferred section) — references Phase 5 / Phase 2 of the original migration. Historical preservation, fine.
- Line 209 — "**OneTouch as restic target.** Phase 5+ — see `machines/workstation/disko-onetouch.nix`." — **STALE** per ADR-0002 P13: OneTouch physically moved to aurora; disko-onetouch.nix is on aurora now.

**Structural:**
- Long step-by-step (right shape for a runbook).
- Per D5 (`2026-06-11-docs-shape-review.md`), install docs should move to `docs/installs/`.

**Alignment:**
- The "stop and investigate" pattern when disk model strings don't match is good safety — but the disko-uses-nvme0n1 claim is the bad-state-detected-not-prevented antipattern (the by-id pinning prevents the bad state).

**Health:** Two material errors (nvme0n1 disko claim, OneTouch-on-workstation). Otherwise solid step-by-step.

---

### docs/installs/vm.md (119 lines)

**Drift:**
- Line 5 — "Validates the install pipeline against the flake before touching workstation." — historical Phase 3 wording; the workstation is up. Now this doc is for ad-hoc VM testing, not "before touching workstation".
- Line 79 — "nixos-install --flake .#vm-test --no-root-password" — there is no `vm-test` host in the current flake (it was a one-time validation host; almost certainly removed). Would fail.

**Structural:**
- Self-contained step-by-step.
- Per D5, should move to `docs/installs/`.

**Alignment:**
- Useful pattern but the doc currently leads with an obsolete framing (`Phase 3`) and references a non-existent host.

**Health:** Misaligned with current state. Either rewrite for current use case (testing ad-hoc) or retire.

---

### docs/installs/agent-onboarding-test.md (226 lines)

**Drift:**
- Q1 Expected (line 43) — "Caddy → workstation (workhorse; internal CA bound here)" — STALE. Post-ADR-0003/-0004, Caddy is on pi with LE.
- Q1 Expected (line 44) — "Authelia → workstation" — STALE; on pi.
- Q1 Expected (line 47) — "ntfy `notify@` template → both" — should be "every host", three hosts now (workstation, pi, aurora; pavilion may also have it).
- Q2 Expected (line 64) — "Pi has 8 GiB + anti-write storage; not for heavy state or daily writes" — accurate.
- Q3 Source (line 84) — "PROCEDURES.md "How to add a new service"" — **PROCEDURES.md does not exist** in `docs/`. The replacement is `SKILL_INDEX.md` + `/add-service` skill. Stale citation.
- Q6 Source (line 140) — "MODULES.md "Filesystem hardening"" — **MODULES.md no longer exists** (now MODULE_AUTHORING.md).
- Q8 Source (line 173) — "PROCEDURES.md "How to add a new host"" — same stale.
- Q10 Source (line 207) — "CLAUDE.md 'On every structural change'" — the CLAUDE.md routing has this content under "Procedures" + the `/on-structural-change` skill now; not under a "On every structural change" header.

**Structural:**
- Well-shaped: question + expected + source.
- "How to run" prompt + scoring (line 211) is good measure-the-rubric framing.

**Alignment:**
- The whole file IS the bind-claims-to-evidence + amnesiac-team operationalisation. **Strong.**
- The stale Source citations breaks this — the test claims evidence but points at dead artifacts.

**Health:** High structural value but multiple stale Source citations + a few drift-prone Expected answers. **Should be the regression test driving Phase 4 of the deep-sweep plan.**

---

### docs/decisions/0001-agentic-homelab-practices.md (70 lines)

**Drift:**
- Line 38 — "`docs/invariants.md`, `PROCEDURES.md`, `ROADMAP.md`" — PROCEDURES.md doesn't exist. Stale.
- Line 36 — "Skills for procedures, prose for facts. Procedures (`add-service`, `add-host`, `relocate-to-pi`, `on-structural-change`, `wrap-session`, `wrap-feature`) live as skills under `home/claude-code/skills/`" — `wrap-feature` IS listed in the agent-available skills above, and the others are present. **Accurate per the system-injected skill list.**

**Structural:**
- Standard ADR shape, well-formed.

**Alignment:**
- "Heavy docs as code-equivalent" (line 35) is the operationalisation of "Context is the scarce resource; ceremony is read-time pay" (ADR's own three asymmetries).
- "Agents confabulate; 'done' is the dangerous claim" (line 18) maps to SOUL.md's "Code is source of truth; docs approximate" — **shared lineage.**

**Health:** Mostly historical; one stale citation.

---

### docs/decisions/0002-aurora-as-family-vault.md (213 lines)

**Drift:**
- Line 87 — Mermaid replication topology shows `@restic-local` as a now-defunct legacy name (mentioned in lines 14 and the report). Per cp/08 P14, target renamed to `mp510`. The ADR diagram should be checked for stale references.
- Line 14 — "all on workstation, sharing one PSU, one kernel, one room's airflow. One failure domain." + line 14 "restic copies on the OneTouch and `@restic-local` IronWolf subvol" — **historical**, in the Context section describing the pre-state. OK to preserve.
- Line 138 — "**Migration cost is one weekend of operator-supervised work**" — outdated tense; the work landed.

**Structural:**
- ADR shape disciplined. Alternatives Considered (line 152) covers A/B/C/D/E + Hetzner rejection.

**Alignment:**
- The ADR IS the canonical "name the right answer first; rejected alternatives explain why narrowed" pattern. **Strong example for the surgery-phase 'how to align docs'**.

**Health:** Historical preservation file, low active drift. The replication topology diagram could note "as designed; landed per ADR-0003" cross-ref since ADR-0003 partially superseded.

---

### docs/decisions/0003-pi-central-entry-plane.md (138 lines)

**Drift:**
- ADR has TWO addenda (line 108 "backends must be tailnet-reachable" + line 122 "cutover landed"). Excellent forward-looking maintenance.
- Line 141 — "`docs/reference/topology.md` — needs update to reflect pi-central post-migration role" — explicit TODO that has only been partially honoured (TOPOLOGY still has "post-P12" framing per the TOPOLOGY notes above).

**Structural:**
- ADR + addenda pattern is excellent. Could become the template.

**Alignment:**
- The ADR is the "Name the right answer first" applied to a corrected previous answer (ADR-0002's aurora-entry choice). Models the supersede flow cleanly.

**Health:** Self-noted TODO (TOPOLOGY update) is the remaining item.

---

### docs/decisions/0004-letsencrypt-on-home-phibkro-org.md (113 lines)

**Drift:**
- No drift visible. All references match current state.
- Line 113 — "P7 standup on pi inherits this Caddy config wholesale" — confirmed by report.

**Structural:**
- ADR + implementation notes (lines 96–106) is the "lessons learned" preservation pattern, distinct from "design alternatives" — earns rent.

**Alignment:**
- Lead with the right answer (LE) and name the rejected alternative (internal CA) with the structural cost of each. **Strong.**

**Health:** Clean. Reference for ADR shape going forward.

---

### docs/decisions/README.md (63 lines)

**Drift:** None.

**Structural:** Clean template + lifecycle convention.

**Alignment:** "Newer hard-to-revisit decisions become ADRs" is the routing rule for the move-from-RATIONALES-to-decisions migration (D3).

**Health:** Solid.

---

### docs/reports/2026-06-aurora-migration.md (361 lines)

**Drift:**
- Line 80 — "**workstation** | Sleep-friendly compute — `*arr` stack, Ollama, Jellyfin, downloads, cold replica receiver for `/mnt/family/*`. No longer load-bearing for the family-tier surface." — accurate.
- Line 130 (PR 4) — "BEFORE / AFTER" diagram of immich cutover — accurate.
- Line 192 (PR 7) — "Hermes refused non-loopback binds without OAuth" — accurate per cp.
- Line 215 (PR 8) — "Operator action (Tailscale admin UI): DNS push order swapped" — landed.
- Line 246–253 (PR 10 P15 diagram) — replication topology. Per Ground-truth #1, this is LIVE NOW.
- Line 332 — "What was left at session end" with `P18, P19, P20` listed as operator-driven — partially still true per ROADMAP (P19 magic-packet test, P20 hypridle re-enable both still gated on operator).

**Structural:**
- "Arc visualisation" + "PR-by-PR breakdown" + "Memory entries added" is the canonical multi-week-arc report shape. Earns rent.

**Alignment:**
- The report IS evidence-binding for the ADRs — commit-grouped narrative with file lists. **Strong.**

**Health:** Solid but the P15 status carry-over to ROADMAP is stale (per Ground-truth #1 P15 is live, not "first full run in flight").

---

### docs/plans/2026-06-11-aurora-migration.md (243 lines)

**Drift:**
- Line 5 — "Reach a 3-copy replication posture for irreplaceable media (4 copies once Hetzner lands)." — STALE on Hetzner (rejected per ADR-0002).
- Line 21 — "Replication: aurora HDD (live) → workstation MP510 (cold replica, btrfs send/receive) → OneTouch (restic) → Hetzner (future restic). 3-2-1 met locally; off-site achieved when Hetzner lands." — same Hetzner drift.
- Line 187 — "P15 ✓ wired live 2026-06-12 (`2877267`); first full run in flight" — **per Ground-truth #1 the daily run has been running since 2026-06-11 18:05. The "first full run in flight" phrasing is stale.** Subvol list verified populated.
- Line 188 — "P16 | Optional: pavilion weekly tertiary replica" — still planned.
- Line 189 — "P17 | Hetzner Storage Box restic target" — should be marked KILLED per ADR-0002.

**Structural:**
- Plan shape is the canonical "amnesiac-resumable" shape. Earns rent.
- Phase tables are the load-bearing surface.

**Alignment:**
- "Each phase ends in a working system. Validation gate at the end of each must pass before the next begins." (line 149) — the iterate-to-stable-then-codify discipline.

**Health:** Two Hetzner references should be retired. P15 status should reflect live-daily.

---

### docs/plans/2026-06-11-docs-shape-review.md (135 lines)

**Drift:**
- Line 8 — "**Trigger:** Main pass after Phase 17 of the aurora migration (replication + verification stable, architectural moves done)." — Phase 17 was Hetzner which was killed; the trigger should be re-stated.
- Per `2026-06-16-docs-deep-sweep.md`, this plan is **absorbed and extended** by the deep-sweep — should be linked back.

**Structural:**
- Target shape + decisions + open decisions + phasing table. Standard plan shape.

**Alignment:**
- "Depth-in-the-filesystem encodes tier" (line 14) is the canonical "constraints are generative": filesystem-depth IS the constraint that the discoverability axis exploits.

**Health:** Largely superseded by `2026-06-16-docs-deep-sweep.md`; should be cross-linked.

---

### docs/plans/2026-06-11-pr-review-stack.md (282 lines)

**Drift:** None visible — all `cp/NN` branches presumably still exist; commit hashes preserved.

**Structural:** Canonical PR-stack-narrative shape.

**Alignment:** Evidence-bound per-phase — each section names commits, files, and what changed. **Strong evidence-binding.**

**Health:** Historical preservation; low active drift.

---

### docs/plans/2026-05-22-sunshine-remote-host.md (286 lines)

**Drift:**
- Line 32 (Task 1 module code) is preserved as the canonical Sunshine config; whether reality has diverged would need code-comparison.
- Frontmatter says "REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development" — refers to historical superpowers framework; the current homelab uses the locally-named skills.

**Structural:** Task-list / checkbox / step-by-step. Good plan shape.

**Alignment:** Plan-shape mirrors ROADMAP "Outstanding (actionable)" entry for sunshine pairing.

**Health:** Stable; sunshine pairing still in ROADMAP § Outstanding.

---

### docs/specs/2026-05-22-sunshine-remote-host-design.md (97 lines)

**Drift:** None visible — design doc preserved as historical context for the plan above.

**Structural:** Standard design-doc shape.

**Alignment:** Stable.

**Health:** Solid.

---

### Runbooks (10 files in `docs/runbooks/`)

#### bad-config.md (45 lines)
- **Drift:** None.
- **Health:** Clean.

#### file-deletion.md (76 lines)
- **Drift:** Lines 20–22 — `/.snapshots/home.<timestamp>/`, `/.snapshots/var/lib.<timestamp>/`, `/mnt/media/photos/.snapshots/photos.<timestamp>/` paths. The `/mnt/media/photos` is the workstation path; with aurora as family vault, the canonical photos snapshot location is `/mnt/family/photos/.snapshots/` on aurora.
- **Structural:** Clean step-by-step.
- **Health:** Path tables need a column for "(workstation)" vs "(aurora)" per host.

#### service-corruption.md (89 lines)
- **Drift:** Line 35 (Pattern B — Immich) example targets `sudo -u postgres psql immich` — post-P11 this is on aurora not workstation. Line 30 cross-references `https://media.nori.lan/health` — stale URL (now `media.home.phibkro.org`).
- **Health:** Same per-host-context drift; needs host-aware examples.

#### drive-failure-root.md (122 lines)
- **Drift:** Line 81 — "**Two local targets, both alive in a single-SSD-failure scenario** — OneTouch + Ironwolf are independent USB drives." — STALE. Per P13/P14: OneTouch is on aurora, IronWolf restic was renamed to `mp510` and moved to NVMe. Line 91 — "Same restore via Ironwolf if OneTouch is offline: `restic -r /mnt/backup-local/...` (Ironwolf btrfs)" — the path `/mnt/backup-local` is now MP510, not IronWolf.
- Line 102 — Hetzner mention "(Hetzner off-site, when configured — deferred per ROADMAP)" — STALE per ADR-0002 rejection.
- **Structural:** Solid step-by-step.
- **Health:** Backup-target naming needs ironwolf→mp510 sweep + Hetzner removal.

#### drive-failure-media.md (87 lines)
- **Drift:** Line 12 — "Photos, home-videos, projects, archive subvolumes — backed up by restic to OneTouch (and Pi/Hetzner when those land). Recoverable." — Hetzner stale; Pi-as-target was always deferred per Pi posture (anti-write); the OneTouch on aurora is the canonical target now.
- Line 48 — "/mnt/backup/media-irreplaceable" — repo name; per cp/08 P14 the names changed.
- **Structural:** Clean.
- **Health:** Same drift class as root.

#### inspect-windows-drive.md (102 lines)
- **Drift:** Line 12 — "`/mnt/windows-ro` is a read-only mount of the Windows C: partition, declared in `machines/workstation/windows-mount.nix`. It comes up at boot via `fileSystems.<name>` and survives reboots." — **STALE: per cp/07 P9 + the pr-review-stack PR 7 entry, `machines/workstation/windows-mount.nix` was DELETED. The Windows partition is gone (MP510 wiped + reformatted as btrfs).**
- **Whole runbook is for a partition that no longer exists.** Either retire entirely or reframe as "inspecting historical Windows data extracted to other locations".
- **Health:** Dead runbook. Should be deleted or repurposed.

#### grafana-oidc-bootstrap.md (132 lines)
- **Drift:** Line 5 — "Switch Grafana from anonymous-Admin (current) to Authelia OIDC." — Grafana now lives on aurora. Lines 113–122 — "just remote aurora rebuild" + `ssh nori@aurora.saola-matrix.ts.net 'sudo systemctl stop grafana'` — accurate per current placement.
- **Health:** Solid; forward-direction runbook for active work.

#### ntfy-auth-bootstrap.md (141 lines)
- **Drift:** Line 35 — `nix shell nixpkgs#openssl -c openssl rand -base64 24 | tr -d '/+=' | head -c 32 | sed 's/^/ntfy_/'` — accurate. Line 61 — `61ef770` ("feat(ntfy): provision publisher-token sops secret") landed today per git log — the token provisioning is partially done. The runbook should reflect post-`61ef770` state.
- **Health:** In-flight runbook; check current state.

#### pi-failure.md (82 lines)
- **Drift:** Line 7 — "`https://*.home.phibkro.org` either times out (Caddy gone) or resolves to NXDOMAIN (Blocky gone via the Tailscale DNS push)." — accurate post-ADR-0003.
- Line 32 — "Option B — swap to spare SD card / USB SSD" — accurate.
- Line 50 — "Option C — temporary tailnet DNS failover" — accurate.
- Line 53 — "Option D — promote workstation to entry plane" — accurate fallback.
- **Health:** Best-aligned-with-current-state runbook in the directory.

#### immich-cutover.md (179 lines)
- **Drift:** None — runbook captures the cutover that was performed; preserved as the "how it was done" reference.
- **Health:** Historical reference; could move to runbooks-archive.

#### storage-full.md (110 lines)
- **Drift:** Line 16 — "Sonarr/Radarr/Lidarr `MinimumFreeSpaceWhenImporting` setting" — accurate.
- Line 47 — "qBittorrent partials" — accurate path.
- Line 99 — `https://downloads.nori.lan` — STALE URL.
- **Health:** Minor URL drift.

#### tailscale-acl.md (70 lines)
- **Drift:** None visible. The static export approach is accurate; references the snapshot file.
- **Health:** Solid.

---

## Ranked punch list

### High priority (drift causing operator-visible wrongness or load-bearing claim staleness)

1. **SERVICES.md catalog rewrite.** ~50 row drifts (Caddy/Authelia/Grafana/Immich/Radicale/Syncthing all wrong host; every `<X>.nori.lan` URL is post-ADR-0004 stale). Single highest-impact doc fix. **Resolution path: machine-generate from `nix eval … nori.lanRoutes` per ROADMAP § Batch C.**

2. **README.md "Status" + "Two live hosts" lede.** Pre-aurora-migration reality. New readers leave with wrong worldview. Plus stale `CONCEPTS.md` + `MODULES.md` paths.

3. **TOPOLOGY.md "post-P12" / "today, pre-P10" framings.** Several rows still describe pending cutovers as if pending. P12 landed 2026-06-12.

4. **ROADMAP.md P15 status + STORAGE.md / aurora-migration.md / pi-failure runbook Hetzner references.** All say "Hetzner planned/deferred"; ADR-0002 says rejected.

5. **agent-onboarding-test.md stale Sources.** `PROCEDURES.md`, `MODULES.md`, "On every structural change" header — all dead. Plus Q1 Expected has stale "Caddy → workstation" / "Authelia → workstation".

6. **NETWORK.md `<name>.nori.lan` examples** sprinkled through the doc (line 28, 71, 87, 90). Post-ADR-0004 should be `${nori.domain}`.

7. **STORAGE.md IronWolf subvolume table** (lines 41–49) lists `@photos`/`@home-videos`/`@projects`/`@library`/`@archive` as live on workstation IronWolf. Per ADR-0002 these are aurora-only post-migration; workstation has only `@downloads` + `@streaming`.

8. **baremetal-install.md "disko hardcoded for /dev/nvme0n1"** (line 79). Direct contradiction with `gotcha-nvme-enumeration` hard rule.

9. **inspect-windows-drive.md is for a partition that no longer exists** (MP510 was wiped per cp/07 P9). Retire or repurpose.

10. **RECOVERY.md "Aurora total failure: degraded only"** (line 19). Family-tier surface now lives there.

### Medium priority (structural issues blocking new readers)

1. **Three-home duplication of the promotion register** (INVARIANTS § work-list, ROADMAP § promotion register, ENFORCEMENT § promoting). Pick one canonical home.
2. **CLAUDE.md ↔ docs/README.md routing table duplication.** D2 flake check is the resolution path; not yet executed.
3. **GLOSSARY § Effect interface deep-dive ↔ RUNTIME_TESTS § Architectural correlation.** Same Reader-Writer claim in two places; cross-ref instead.
4. **`CONCEPTS.md` / `MODULES.md` stale references everywhere.** GLOSSARY/MODULE_AUTHORING renames happened but inbound links didn't. Single-file sed candidate.
5. **D-decisions from 2026-06-11-docs-shape-review.md never executed.** Filesystem still flat. The deep-sweep plan absorbs this; needs to actually move files.
6. **PROJECTS.md migration to `/srv/share/projects/AGENTS.md`** (D6) not executed.
7. **Install docs grouping** (D5) not executed — `baremetal-install.md`, `vm-install.md`, `agent-onboarding-test.md` still at `docs/` top level.

### Low priority (polish, redundancy, style)

1. **INVARIANTS line 47 effects-have-tests still tagged [prose: unchecked]** — promoted to `[law]` 2026-06-07 per ROADMAP. Update the tag.
2. **vm-install.md references non-existent `vm-test` host** — retire or rewrite.
3. **capacity-baseline.md Hetzner column** — drop.
4. **Sunshine plan/spec docs** — preserve as-is; sunshine pairing still open.
5. **Frontmatter consistency** — some docs use `summary:` only; others add `tags:`. Pick a convention.
6. **MODULE_AUTHORING.md length** (346 lines) — consider splitting dev-workflow + packages into separate L2 docs.
7. **DOCUMENTATION_WRITING.md + ENFORCEMENT.md `CONCEPTS.md` cross-refs** — fix to GLOSSARY.md.

---

## Cross-cutting observations

1. **The aurora migration (P1–P14, P15 live) is the dominant drift source.** ~70% of high-priority drift items are post-2026-06-12 reality that documents didn't catch up to. The migration moved Caddy + Authelia + Blocky-authoritative + family-tier services from workstation→pi+aurora, and most reference docs still say "workstation". The migration report + ADRs + ROADMAP entries DID update; the L2 reference docs (SERVICES, TOPOLOGY, NETWORK, RECOVERY) and the install/runbook L3 docs did NOT.

2. **`*.nori.lan` is everywhere despite ADR-0004.** Search: NETWORK.md (~5 instances), SERVICES.md (~30 instances in route column), runbooks (~3 instances), agent-onboarding-test.md (≥2 instances). The `nori.domain` variable is the SoT but the doc literals weren't templated. **Single sed sweep** would catch most; the few that should stay (historical narration, transitional-period explanation) need keeping by hand.

3. **`CONCEPTS.md` → `GLOSSARY.md` + `MODULES.md` → `MODULE_AUTHORING.md` renames left inbound link rot.** README.md, INVARIANTS.md, DOCUMENTATION_WRITING.md, ENFORCEMENT.md, decisions/0001, agent-onboarding-test.md all still reference the old names. Mechanical fix.

4. **Hetzner Storage Box appears in ~7 docs as planned/deferred/future.** ADR-0002 explicitly rejected it. The reject only updated ROADMAP and the plan; the rest didn't get the memo. **Single multi-file sweep**.

5. **The "service catalog" + "subvolume table" + "host table" + "skill list" are the four classic derived-list-in-prose violations.** Each lives in 2–4 places and drifts. ROADMAP § Batch C names the resolution for at least the service catalog (`nix eval` + `docs/auto/*.md`). The same approach extends to the other three.

6. **D-decisions from `2026-06-11-docs-shape-review.md` are the structural backbone the deep-sweep absorbs.** D1 (GLOSSARY+INVARIANTS to root), D2 (routing-vs-filesystem flake check), D3 (RATIONALES→0000-rationales ADR), D4 (flatten superpowers), D5 (group installs), D6 (PROJECTS leaves), D7 (case unification), D8 (CLAUDE.md trim). All visible in the doc; none executed. **Phase 3 of the deep-sweep is the execution.**

7. **Runbook drift class — paths/URLs date from one specific pre-migration moment.** `/mnt/media/photos` (workstation) vs `/mnt/family/photos` (aurora); `*.nori.lan` vs `*.home.phibkro.org`; `Ironwolf` restic target vs `mp510`. The runbooks weren't kept in lockstep with the migration. **Mechanical sweep with host-context awareness**.

8. **The `code-is-source-of-truth` axiom is honoured where the code path is obvious (`nori.lanRoutes` registry in NETWORK, `nori.fs` in STORAGE) but violated in the static catalogs.** The asymmetry is "we name the schema location for the abstraction" + "we then write the catalog by hand". Closing the gap = making the catalog auto-generate (ROADMAP § Batch C).

9. **Three-boundaries correctness from SOUL.md surfaces explicitly in INVARIANTS + ENFORCEMENT but is not named.** The five-rung ladder IS the three-boundaries model + judgment overflow. Naming it at the top of INVARIANTS + ENFORCEMENT would close the loop with SOUL.md.

10. **The deep-sweep plan (`2026-06-16-docs-deep-sweep.md`) does NOT need new structural decisions — it needs to execute the D-decisions that already exist + apply the content drift sweep**. The Phase 2 "restructure decisions" listed in the plan are largely re-confirmations of 2026-06-11 decisions; the genuinely-new questions are alignment-codification (ADR vs DOCUMENTATION_WRITING fold) and memory restructure scope.

---

## Notes for Phase 2

- **Catalog derivation is high-leverage.** Single biggest fix is auto-generating SERVICES.md (or its successor) from `nix eval … nori.lanRoutes`. Also covers TOPOLOGY.md placement table and STORAGE.md subvolume table by the same mechanism.
- **The `nori.domain` template should sweep through prose examples.** Find: every `*.nori.lan` in docs that ISN'T historical context; replace with `${nori.domain}`.
- **MODULES.md / CONCEPTS.md stale references are a one-line global find-replace.** Don't overthink.
- **Hetzner mentions sweep** — find every "Hetzner" in docs, classify (decision-ref keep / future-plan delete / historical preserve).
- **The `docs/installs/agent-onboarding-test.md` IS the regression test.** Once Phase 3 lands, re-run this with a fresh subagent. Failures classify into knowledge / routing / foregrounding per the test's own rubric.
