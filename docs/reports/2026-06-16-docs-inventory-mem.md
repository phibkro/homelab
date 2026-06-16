# Docs inventory — SOUL.md + memory (Phase 1, part 2 of 2)

> Findings for the operator's global config + auto-memory. Sibling report (homelab repo docs) at `2026-06-16-docs-inventory.md`.

Scope reviewed:
- `/home/nori/.claude/CLAUDE.md` (SOUL.md — symlink of `home/claude-code/CLAUDE.md`)
- `/home/nori/.claude/projects/-srv-share-projects/memory/MEMORY.md`
- 31 individual memory entries under that same directory

## SOUL.md (`home/claude-code/CLAUDE.md`)

**Drift:**
- L73: example trace cites `4.8 (1M context)` model implicitly elsewhere; SOUL.md itself uses no version. No real drift in SOUL.md, but the `nixpkgs-ai-commit-trailer.md` memory pins `Claude Opus 4.8 (1M context)` as the override target — the active model per system prompt is `claude-opus-4-7`. SOUL.md does not name the version directly, so this is downstream-only.
- L97: "Knob — checkpoint cadence" header includes a leading bracketed annotation `[mine, not universal]`. No drift, but worth surfacing: this is the only personal axiom marked as such; the convention is inconsistent (others are equally personal but unmarked).

**Structural:**
- The file has no top-level table of contents and no anchor scheme; for a doc that's supposed to be the routing axis ("CLAUDE.md is the smallest entrypoint"), it begins to span 100+ lines and reaches for the eye to scan.
- The new "Single source of truth" section (added in `d13f02d`) sits inside PROBLEM SOLVING. Defensible (it's a correctness-by-construction sub-pattern), but its derivation-strength ladder (`generate > test > convention`) overlaps semantically with the homelab repo's separate `docs/reference/enforcement.md` ladder (`prose → comment → test → type`). Two ladders, two domains, no cross-reference. Risk: a fresh reader sees `ENFORCEMENT.md`'s ladder, asks how it relates to `SoT`'s ladder, and finds nothing connecting them.
- "Prefer Multisensory delivery" lives at H2 (top-level) but reads as a sub-rule of "Explain simply and succinctly" (an H3 under PERSONALITY). Either it's a peer-axiom (then it needs to earn the heading) or it's a sub-rule (then it should nest).
- "PERSONALITY" heading collapses two distinct ideas: collaboration mode (partner-not-assistant) and explanation style (succinct + multisensory). The mode/style split would be cleaner as two H2s.

**Alignment:**
- The "name the right answer first" axiom (L69) is internally consistent with the new "single source of truth" axiom (rent-paying: research the right model rather than paraphrasing what you remember). Good.
- "Correctness by construction" (the root) and "Single source of truth" both target the same shape ("make the bad state unrepresentable"). They could collapse into one axiom with two faces, or they could explicitly reference each other. As written, they're presented as parallel siblings, which understates the relation (SoT is the form CbC takes when the bad state is "two facts disagree").
- "Constraints are generative" (L92) shares vocabulary with "name the right answer first" (constraints shrink the space) but uses the word differently — there constraints are operator-stated limits, here they're problem-structural invariants. Two senses of "constraint", one word, adjacent paragraphs. Reader has to disambiguate.
- "Knob — checkpoint cadence" is a self-management heuristic, not a correctness axiom. It earns its keep but reads as out-of-place mid-PROBLEM-SOLVING. Either belongs under a separate "personal practice" heading or under PERSONALITY.
- Tone: file consistently leads with the answer, justifies after. Earns its own bias. No hedging found.

**Health:** SOUL.md mostly walks the talk — it's terse, opinionated, leads with answers. The pressure points are (1) the new SoT axiom doesn't yet cross-link to the homelab's parallel ENFORCEMENT ladder, (2) overlapping "constraint" terminology in adjacent paragraphs, and (3) the file is creeping past the "smallest possible entrypoint" budget the homelab CLAUDE.md aspires to. None of these are bugs; they're alignment drag.

## MEMORY.md (index)

**Drift:**
- **Missing entry:** `restic-stale-lock-recovery.md` exists on disk (created 2026-06-15) and is referenced from the file system but does NOT appear in the MEMORY.md index. Either the index needs the line added, or the file needs deletion if superseded.
- **Missing entry:** `never-decrypt-sops-files.md` exists on disk (referenced from the system context shown to me as the first MEMORY.md line) but the current MEMORY.md file (32 lines, starts with "Tailscale SSH runtime drift") does NOT include it. Confirmed by reading the file directly — line 1 is `tailscale-ssh-runtime-drift`. Index drift.
  - Note: the system-context snapshot of MEMORY.md shown to this agent at session start DID include `never-decrypt-sops-files` as the leading entry. Live file does not. Either the snapshot was stale or the file was truncated. Worth diff-checking before any edit.

**Structural:**
- Entry-description budget overruns. Several lines exceed ~150 chars (the soft cap implied by `writing-memory-entries`); worst offenders:
  - `oh-ledger-spine`: ~260 chars
  - `Alchemy v2 / Effect-4-beta gotchas`: ~250 chars
  - `iteration trio`: ~270 chars
  - `Pattern C2 sqlite race needs flock`: ~270 chars
  - `correctness-first-narrow-by-constraints`: ~250 chars
- Wikilink target mismatches: index uses display name as link text (`[Tailscale SSH runtime drift](tailscale-ssh-runtime-drift.md)`); slug matches filename. Consistent.
- Index claims memories cover "homelab" (via `-srv-share-projects` path) but many entries are about external projects (bang-lang, occupational-health, alchemy, nixpkgs, claw-patrol). The memory store's path-coupling to `/srv/share/projects/` is the structural intent; just worth being aware these aren't homelab-scoped.

**Alignment:**
- Some descriptions paraphrase what the underlying entry already says (the `USE WHEN` + the rest). This is acceptable — the index is a retrieval surface, not the source.
- A handful of index lines bury the lede with `USE WHEN` clauses that read as commentary rather than triggers (`workstation leak hunting`, `OH ledger-spine arc`). Trigger-style is preferred (matches `find-skills` semantics).

**Health:** The index is functional but has at least one missing entry (`restic-stale-lock-recovery`), inconsistent line-length discipline, and a snapshot-vs-live discrepancy for `never-decrypt-sops-files` that the operator should reconcile before any further memory work.

## Individual memory entries

### never-decrypt-sops-files.md
**Drift:** None. References `2026-06-15` correction; current and accurate.
**Structural:** Header description is 600+ chars in the frontmatter (overflows the soft cap by 4×). The `description` field is meant to be the retrieval-trigger line, not a mini-essay. Move the bulk into the body.
**Alignment:** Carries explicit `**Why:**` + `**How to apply:**` per format. Good. Wikilinks reference `[[gotcha-sops-*]]` skills that do exist in homelab. Consistent.
**Health:** Content is sharp and well-grounded. Frontmatter description bloat is the only issue.

### tailscale-ssh-runtime-drift.md
**Drift:** Claims aurora + pavilion cleared as of 2026-06-11. No reason yet to doubt; the file is 4 days old. Operator confirmed in session context that this is stable.
**Structural:** Has its own `## Symptom / ## Why / ## Fix / ## Known-drift hosts` structure — good for a multi-host project memory. Frontmatter description is one tight sentence (good).
**Alignment:** Uses `verify_by` indirectly (the keyscan command). Both `**Why:**`-equivalent and `**How to apply:**`-equivalent present. Conforms to the feedback/project format.
**Health:** Strong project memory; the host-list is the kind of live-state claim that requires periodic re-verification.

### bang-lang-build-reality.md
**Drift:** "tsc pre-existing-red on `main` (commit fb9819e and earlier)" — 13 days old; would need to be re-verified against current bang-lang `main` before being trusted. No way to verify from this scope.
**Structural:** Long but earns the length — single coherent gotcha set. `verify_by` is concrete and runnable.
**Alignment:** Captures present-state of a foreign project (the bang-lang repo). Reference-type memory; correct shape.
**Health:** Project-scoped reference; will go stale eventually as bang-lang's `main` evolves.

### stm-feature-progress.md
**Drift:** Names commit `54b0a27` as the Slice A landing point; this is 13 days old, no way to verify if codegen #4 still next-blocker without entering the bang-lang repo. Likely drift candidate.
**Structural:** Clean — sots / state / remaining sections. Wikilink to `[[bang-lang-build-reality]]` exists and resolves.
**Alignment:** Project-type memory; reasonable shape for in-flight work tracking.
**Health:** Highest staleness-risk in the bang-lang trio because it tracks "next step", which moves fastest.

### oh-debug-endpoint-bug.md
**Drift:** Claims bug FIXED 2026-05-30 (commits `a035249` + `c8ceeec`), with regression test added. Two follow-ups noted: HttpApi-handler-move or HttpLayerRouter.use pattern, neither landed at time of writing. 13 days old.
**Structural:** Strong — root cause + correct fix + landed change all laid out.
**Alignment:** Reference/project memory; conforms.
**Health:** Now serves as a closed-fix postmortem rather than active gotcha. Could be demoted from MEMORY.md to a project-doc reference once the upload-route fix lands.

### alchemy-v2-trial.md
**Drift:** "deploy of occ-health/deploy is live since commit 194daa4" — 13 days old, plausible but unverified. Beta versions specified (`alchemy@2.0.0-beta.45`); upstream betas move fast.
**Structural:** Long-form gotcha catalog. Good shape for the volume of context it captures.
**Alignment:** Reference memory; correct.
**Health:** Aging gracefully but the version pins will go stale on the next Effect 4 beta bump.

### oh-ledger-spine.md
**Drift:** Massive entry; many specific commit and architecture claims about a fast-moving project (occupational-health). 13 days old. "Next = calibration fan-out" claim is the kind that goes stale first.
**Structural:** ~10 KB — by far the longest memory. Reads more like an in-flight design doc than a retrieval index. Frontmatter description is 350+ chars.
**Alignment:** This memory documents content that SHOULD live in the occupational-health repo's `docs/` directory itself (it even cross-references those docs as SoT). Per the SOUL.md `single-source-of-truth` axiom: this memory paraphrases content that has a canonical home. Either it's a thin pointer ("see oh repo `docs/specs/...`") OR the canonical content moved here without the original being updated.
**Health:** Largest SoT violation in the memory tree; treat as a candidate for severe trimming → pointer-only.

### nixpkgs-ai-commit-trailer.md
**Drift:** Trailer convention itself is stable; but the entry hard-codes `Claude Opus 4.8 (1M context)` as the "global default" being overridden. The active model is `claude-opus-4-7` (per system context); the global convention has therefore drifted.
**Structural:** Tight feedback memory. Good shape.
**Alignment:** Carries `**Why:**` + `**How to apply:**`. Format-conformant.
**Health:** The model-version reference is the staleness vector; the policy itself is durable.

### mental-models-vs-heuristics.md
**Drift:** None — this is a doctrine/principle memory, not a code-state claim.
**Structural:** Clean. Carries `**Rule** / **Why** / **How to apply**`.
**Alignment:** Conforms to feedback format. Wikilinks resolve.
**Health:** Durable principle memory; no risk vector.

### usb-drive-host-reboot-recovery.md
**Drift:** None. Reproducible technical observation.
**Structural:** Clean. Has the right shape.
**Alignment:** Carries `**Why:**` + `**How to apply:**` + a "when this likely doesn't apply" guard. Excellent.
**Health:** Strong durable reference memory.

### nixpkgs-darwin-verification.md
**Drift:** SSH details (`nori@100.102.29.85`, `~/nixpkgs` clone) are operational claims that could drift. Names PR #528150 (ollama 0.30.5). 11 days old.
**Structural:** Clean. Reference-style.
**Alignment:** Carries the format. Good.
**Health:** Durable; the only live-state claim is the Mac's tailnet IP + clone path.

### nixpkgs-package-pin-idioms.md
**Drift:** None — coding-convention memory.
**Structural:** Two-rule structure with examples. Long but earned.
**Alignment:** Carries `**Why:**` + `**How to apply:**`. Cross-references peer memories.
**Health:** Durable.

### claw-patrol-origin.md
**Drift:** Names "Packaging state (2026-06-05) — Not in nixpkgs" — could be checked against current nixpkgs. Project release date (2026-05-21) is durable; "Hermes still has full egress" is operational state and likely still true.
**Structural:** Clean: what / why-it-applies / packaging-state / next-steps.
**Alignment:** Project-type memory used as a project-pointer (the actual project is at `clawpatrol.dev`). Right shape.
**Health:** Will drift the moment clawpatrol lands in nixpkgs or a community flake.

### nixos-anywhere-first-install-gotchas.md
**Drift:** Names pavilion install date 2026-06-05. Five gaps documented; none are code-state-specific. Persistent learnings.
**Structural:** Multi-section memory laid out as a pre-flight checklist. Good.
**Alignment:** Carries the format adjacent to each rule. Has an explicit "promote to gotcha skill at install 3" graduation criterion — promotion-aware.
**Health:** Durable; if/when promoted to a `gotcha-` skill, this memory should be deleted.

### sqlite-backup-vacuum-into.md
**Drift:** Pattern C2 is referenced — still alive in `modules/services/backup/restic.nix`. Verified indirectly via `pattern-c2-sqlite-race-flock`. Concrete examples cite `navidrome / open-webui / vaultwarden`, all live.
**Structural:** Clean — what-doesn't-work / what-works / why / how.
**Alignment:** Carries format. Cross-links peer `[[pattern-c2-sqlite-race-flock]]`.
**Health:** Durable; the pairing with the flock memory is a coherent pattern.

### just-remote-tailnet-hostnames.md
**Drift:** Includes `tailnet ACL ssh: action: accept` switch as of 2026-06-07. Operator may have reverted/changed; not verifiable from this scope.
**Structural:** Three-sub-section memory (host-key drift / Tailscale-SSH variant / `just` not present). Lengthy but each addresses a distinct failure mode.
**Alignment:** Carries the format throughout.
**Health:** The middle section's claim about the ACL is the most likely staleness vector.

### process-exporter-needs-ptrace.md
**Drift:** "Pattern wired permanently in `modules/services/node-exporter.nix`" — verifiable. Claim stands as long as that module hasn't been refactored.
**Structural:** Tight. Right size for the concept.
**Alignment:** Carries format. Cross-referenced from `workstation-leak-hunting`.
**Health:** Durable.

### workstation-leak-hunting.md
**Drift:** Claims open-webui was paused via `services.open-webui.enable = false`. Operator may have re-enabled. "Cap on heavy services deferred until ≥7d of data lands (ROADMAP outstanding item)" — needs a ROADMAP check.
**Structural:** Right shape for a project-state memory: table + queries + why-it-exists.
**Alignment:** Carries format. Cross-references resolve.
**Health:** Mid-life project memory; will need refresh once the leak diagnosis closes.

### iteration-trio-workflow.md
**Drift:** References commit `06df96e` (2026-06-07). Recipe names verified durable. "Related: workstation-leak-hunting uses the same just recipe pattern for query-logs" — `query-logs` is now also a skill (per the available-skills list shown at session start). Cross-ref could promote skill-link instead of memory-link.
**Structural:** Clean. Table + example.
**Alignment:** Format-conformant.
**Health:** Durable; the skill cross-reference is the polish opportunity.

### thunar-archive-needs-backends.md
**Drift:** Commit `473b266` named as source. 9 days old; durable file-manager pattern.
**Structural:** Clean.
**Alignment:** Carries format.
**Health:** Durable.

### pattern-c2-sqlite-race-flock.md
**Drift:** Claims pre-2026-06-11 P14 the target was named `-ironwolf`, renamed to `-mp510` during P14. Verifiable in commit log. References canonical impl in `modules/services/navidrome.nix`.
**Structural:** Strong — race scenario / fix / reference impl.
**Alignment:** Carries format. Paired with `sqlite-backup-vacuum-into` for full picture.
**Health:** Durable.

### rsync-destination-service-ownership.md
**Drift:** P10 photos rsync (2026-06-11) is the worked example; durable. `docs/runbooks/immich-cutover.md` referenced — need to confirm exists.
**Structural:** Long-form feedback memory: symptom / how-to-apply / recovery / pattern-for-immich.
**Alignment:** Carries format. Cross-refs `postgres-ownership-after-dump-restore` correctly.
**Health:** Durable.

### hyprland-lua-mode-dispatcher-syntax.md
**Drift:** References `wayland.windowManager.hyprland.configType = "lua"` — confirmed live. `just test-hypr` recipe confirmed live.
**Structural:** Strong. Multi-section.
**Alignment:** Carries format. Cross-refs resolve.
**Health:** Durable. NOTE: this memory's content also exists as a `gotcha-hyprland-lua-migration` skill (per available-skills list). Possible duplication / promotion candidate.

### feedback-history-in-commits.md
**Drift:** None — doctrine memory.
**Structural:** Clean.
**Alignment:** Carries `**Why:**` + `**How to apply:**`. Format-perfect.
**Health:** Durable.

### snowy-and-testing-framework.md
**Drift:** "M0 done; M1 is read current Stylix config" — fast-moving project. 4 days old. Already says next-target work in PLAN.md, which is the SoT — good shape.
**Structural:** Two-section: testing framework + snowy. Borderline split candidate (two concepts, one file).
**Alignment:** Pointer-style for the snowy half (refs `docs/PLAN.md` as SoT). Project memory.
**Health:** The combined-file structure is the only friction; consider splitting.

### postgres-ownership-after-dump-restore.md
**Drift:** Names miniflux (2026-06-11) and immich (2026-06-12, "handled via /restore-pg-with-owner-fix skill"). MEMORY.md index mentions both. Skill exists per available-skills.
**Structural:** Clean — symptom / why / how to apply / alternative.
**Alignment:** Carries format. Promoted to skill; this memory may now be redundant with the skill.
**Health:** Strong content but DUPLICATION with the `restore-pg-with-owner-fix` skill is a deletion-candidate signal.

### scripted-networking-link-files-inert.md
**Drift:** Workstation `useDHCP = true` claim verifiable. Caught 2026-06-12 with P19 WoL — durable.
**Structural:** Clean.
**Alignment:** Format-conformant.
**Health:** Durable.

### syncthing-gui-address-cli-override.md
**Drift:** "P12 needs pi's Caddy to reverse-proxy sync.home.phibkro.org → workstation:8384 over the tailnet" — needs verification given today's aurora-side syncthing addition (`e615e72`). The route may now point at aurora, not workstation, for the music slice.
**Structural:** Clean.
**Alignment:** Format-conformant.
**Health:** Mid-drift candidate given today's syncthing on aurora.

### correctness-first-narrow-by-constraints.md
**Drift:** Self-references that the principle was added to global CLAUDE.md (`homelab/home/claude-code/CLAUDE.md § "Correctness first; narrow by stated constraints"`). Verified in SOUL.md — the section "Name the right answer first" is the live form (renamed, with the same content). Wikilink `[[homelab-claude-md-bias]]` does NOT resolve to any actual memory.
**Structural:** Clean.
**Alignment:** Per SOUL.md SoT — this memory is now a paraphrase of the live SOUL.md axiom. Per the SoT axiom itself, the canonical version is the SOUL.md section; this memory should point at it, not duplicate it. **SoT violation by the principle the memory itself codifies.**
**Health:** Self-undermining shape: the memory paraphrases what SOUL.md now owns. Either delete (the axiom is in SOUL.md now) or strip to pointer-only.

### restic-stale-lock-recovery.md
**Drift:** Names commit `f43d0fb` ("prepend ExecStartPre unlock to self-heal stale locks") — confirmed in live git log. "Caught 2026-06-15 on workstation media-irreplaceable-onetouch" — current. Includes a full ready-to-submit upstream PR draft.
**Structural:** Strong. Recognition / recovery / why / patch-ready.
**Alignment:** Carries format. **NOT INDEXED IN MEMORY.md** — drift in the index, not the entry.
**Health:** Content is strong; needs to be added to the MEMORY.md index.

## Ranked punch list

### High priority
1. **MEMORY.md index drift:** `restic-stale-lock-recovery.md` is missing; reconcile the `never-decrypt-sops-files.md` snapshot-vs-live discrepancy. Operator must visually confirm whether the live file matches their mental model.
2. **`correctness-first-narrow-by-constraints.md` SoT violation:** the principle now lives in SOUL.md (`Name the right answer first`); the memory paraphrases the doctrine. **Deletion candidate** — replace with a one-line pointer ("see SOUL.md § Name the right answer first") OR delete outright and remove the index line. Wikilink `[[homelab-claude-md-bias]]` to nowhere is broken.
3. **`oh-ledger-spine.md` SoT violation:** the memory paraphrases content that has a canonical home in the occupational-health repo. Strip to pointer-only.
4. **`nixpkgs-ai-commit-trailer.md` model-version reference:** `Claude Opus 4.8 (1M context)` is stale; active model is `claude-opus-4-7`. Generalize the override to "current Claude model" not a version literal.
5. **SOUL.md SoT axiom + homelab ENFORCEMENT ladder:** add a cross-reference. Without it, fresh readers see two ladders with no connection.

### Medium priority
1. **Frontmatter description bloat** across multiple memories (`never-decrypt-sops-files`, `oh-ledger-spine`, `iteration-trio-workflow`, `Pattern C2 sqlite race needs flock`, `Alchemy v2`, `correctness-first-narrow-by-constraints`): rewrite to the ≤150-char retrieval-trigger budget.
2. **`syncthing-gui-address-cli-override.md` drift risk:** today's aurora-side syncthing addition may invalidate the "P12: pi's Caddy → workstation:8384" framing. Verify and update.
3. **`postgres-ownership-after-dump-restore.md` duplication with `/restore-pg-with-owner-fix` skill:** likely deletion candidate, or demote to a skill-pointer.
4. **`hyprland-lua-mode-dispatcher-syntax.md` duplication with `gotcha-hyprland-lua-migration` skill:** consolidate.
5. **SOUL.md "constraint" disambiguation:** adjacent paragraphs use "constraint" with two distinct meanings (operator-stated narrowing vs problem-structural invariants). One-line clarification.
6. **`oh-debug-endpoint-bug.md` graduation:** the bug is fixed; the memory now reads as a postmortem. Either demote out of memory (the project's own docs are the right home) or note "closed" in the entry.

### Low priority
1. **SOUL.md "Prefer Multisensory delivery" heading-level:** nest under PERSONALITY rather than promoting to H2.
2. **`snowy-and-testing-framework.md` split:** two concepts in one memory; cleaner as two.
3. **Index line trigger-style polish:** several MEMORY.md lines bury the lede; rewrite for trigger-first.
4. **`stm-feature-progress.md` re-verification:** 13-day-old "next-step" claim is the most likely stale entry; verify or update.
5. **`nixos-anywhere-first-install-gotchas.md` promotion criterion:** entry already names the trigger (3rd NixOS install); next provisioning of a NixOS host should retire this memory into a `gotcha-` skill.

## Cross-cutting observations

**Pattern 1 — SoT violations cluster at high-leverage memories.** The two largest entries (`oh-ledger-spine`, `correctness-first-narrow-by-constraints`) both paraphrase content that has a canonical home elsewhere. Same pattern: a doctrine or design decision was captured during an active session, then later codified into its proper home (SOUL.md for the doctrine, occupational-health/docs for the design), but the memory was never updated to either point at the canonical version or get deleted. The SoT axiom itself, freshly added to SOUL.md, names this as the failure mode. Memory hygiene is now downstream of an axiom that flags it.

**Pattern 2 — Memory-vs-skill duplication is forming.** At least 3 memories (`hyprland-lua-mode-dispatcher-syntax`, `postgres-ownership-after-dump-restore`, possibly `nixos-anywhere-first-install-gotchas`) now have a parallel skill in the available-skills list. Memories are "retrieval index for things learned"; skills are "executable procedures for things repeated". When a memory's content is now a skill, the memory should retire or shrink to a "see skill X" pointer.

**Pattern 3 — Frontmatter description budget is uniformly overspent.** The `description` field is the retrieval-trigger surface; memories are increasingly using it for executive-summary purposes. The MEMORY.md index already provides a summary; the memory file itself provides the body; the frontmatter description should be a tight ≤150-char trigger. Most entries violate this.

**Pattern 4 — Cross-references are mostly clean, with isolated broken wikilinks.** `[[homelab-claude-md-bias]]` (in `correctness-first-narrow-by-constraints`) doesn't resolve. `[[hermes-harness]]`, `[[nixpkgs-agent-harness]]` are referenced but don't exist as memories. These are "memory-shaped" promises that haven't been materialised. Either materialise or remove the wikilink.

**Pattern 5 — Project-memory staleness is the biggest active risk.** The bang-lang and occupational-health memories are 13 days old; both projects move fast. They name commit SHAs, next-blocker work items, and architectural states that may have moved. If the operator is no longer in those projects daily, these entries trend toward "snapshot at time X" rather than "current state" and should be re-verified before being relied on.

**Pattern 6 — Drift items from THIS session don't yet show up in memory.** The orchestrator named: P15 replication live since 2026-06-11; library/downloads semantic inverted today; `gatus.runsOn = "pi"`; syncthing-on-aurora live; `nori.lanIp = pi.lanIp`. NONE of these landmarks appear in the memory tree. Memory is project-scoped or doctrine-scoped, and recent homelab-shape changes naturally land in repo docs (homelab/docs/) rather than memory. This is the right partition — but worth confirming nothing in memory implicitly contradicts the new state. `syncthing-gui-address-cli-override` is the only entry that touches a today-changed surface; verified non-contradicting but framing is stale.
