---
summary: PR-style review walkthrough of the 45-commit aurora migration
  stack landed 2026-06-11. Maps logical PRs to chronological checkpoint
  branches (`cp/NN-*`) so each phase can be reviewed in isolation via
  `git diff cp/NN-prev..cp/NN`.
---

# Aurora migration — PR review stack

The 45 commits between `origin/main` and `main` (HEAD `7f0d3a6`) split
into **9 chronological phases**, each pointed at by a `cp/NN-*` branch
so you can scope `git diff` and `git log` to one phase at a time.

```sh
# what changed in phase N
git diff cp/0(N-1)-prev..cp/0N

# files touched by phase N
git diff --stat cp/0(N-1)-prev..cp/0N

# commits in phase N with full messages
git log cp/0(N-1)-prev..cp/0N
```

Recommended merge sequence = the numerical order of the branches.
Each phase compiles + passes `nix flake check` at its tip (each
intermediate commit too).

---

## cp/01-adrs — design intent + plan (3 commits)

`origin/main..cp/01-adrs`

Pure docs. **Read first.**

- `docs/decisions/0002-aurora-as-family-vault.md` — the *why*. ADR-0002
  sets the structural choice: aurora becomes the always-on family
  vault holding irreplaceable data + family-tier service backends;
  workstation keeps GPU + *arr stack; pi keeps observability. Includes
  the rejected alternatives (full-aurora-migration, full-cloud,
  hybrid-mirror, modest-scope) and *why* each was rejected.
- `docs/decisions/0002-aurora-as-family-vault.md` § visuals — before/
  after topology mermaid diagrams, failure-domain map.
- `docs/plans/2026-06-11-aurora-migration.md` — the *how*.
  Phase-by-phase (P1 through P20). This is the source-of-truth that
  every subsequent commit checks against.
- `docs/plans/2026-06-11-docs-shape-review.md` — meta
  doc-shape review plan.

**Risk:** none. Pure docs.

---

## cp/02-foundation-and-bootstrap — Stage 1 effects + aurora exists (13 commits)

`cp/01-adrs..cp/02-foundation-and-bootstrap`

This phase does two interleaved things that ended up touching enough
shared files to make them inseparable in practice:

1. **Foundation effect modules** (P1 + P1b + P2 + P3 + P4):
   - `modules/effects/service-placement.nix` (NEW) — `nori.services.<X>.{enable,tags,enabled}` registry + `nori.enableServicesByTag`. Lets hosts opt-in by name or by tag.
   - `modules/effects/lan-route.nix` — adds `runsOn` field. Routes now declare cross-host placement; the proxy host (whichever runs Caddy) resolves the upstream via `routeHost` (127.0.0.1 if local, tailnet IP otherwise).
   - `modules/effects/fs.nix` — adds optional `samba = { … }` block per entry; generator emits Samba shares + ownership tmpfiles. Same fs entry stays the source of truth for path + tier + share.
   - **Every `modules/services/*.nix`** wrapped in `mkMerge` + `mkIf cfg.enabled` (commit `714aa10`). Route declarations lift outside the activation gate so the route registry is visible host-wide even when the service itself is disabled (lets proxy hosts know how to route to the backend running elsewhere). **This was a big mechanical refactor — semantically a no-op per host.**
   - `machines/<host>/default.nix` declares its activation set via `nori.services.*.enable = true`. Workstation reproduces today's set exactly.

2. **Aurora bootstrap** (P6 + P13):
   - `machines/aurora/disko-family.nix` (NEW) — Toshiba HDD btrfs layout, 5 family-tier subvols at `/mnt/family/{photos,home-videos,projects,library,archive}`.
   - `machines/aurora/disko-onetouch.nix` (NEW) — declares aurora's OneTouch mount (post-physical-move). The drive itself moved from workstation to aurora during this phase.
   - `modules/services/backup/restic-target.nix` (NEW) — chrooted SFTP user `restic` on aurora so workstation + pi can push restic snapshots over the tailnet. `mkAfter` trick on `openssh.extraConfig` avoids the PrintLastLog trap that wedges the Match block (`c3ba27f`).
   - `.sops.yaml` — aurora added as a recipient; `secrets/*.yaml` re-encrypted for aurora.

**Verify:**
```sh
git diff --stat cp/01-adrs..cp/02-foundation-and-bootstrap
# expect: every modules/services/*.nix touched, plus modules/effects/
# {service-placement,lan-route,fs}.nix and the aurora bootstrap files
```

**Risk:** **moderate.** The mkMerge wrap is mechanical but spans every service. The validation gate per P2 is `nix-diff` per host = empty (semantic-equivalence) — done locally before landing.

---

## cp/03-entry-plane-le — ADR-0003 + ADR-0004 (6 commits)

`cp/02-foundation-and-bootstrap..cp/03-entry-plane-le`

Two architectural pivots, deeply tangled because LE landed via pi.

- **ADR-0003** (`fd6415c`) — HTTP entry plane moves from workstation to **pi**, not aurora. Workstation can sleep without the proxy following along. The addendum at the end captures the loopback-bind constraint that surfaced during testing: backends bound to 127.0.0.1 on workstation can't be proxied from pi; service modules need `bind 0.0.0.0` + a tailnet firewall hole as part of their cutover.
- **ADR-0004** (`364b892`) — TLS via Let's Encrypt wildcard on `home.phibkro.org` (operator's existing domain) instead of an internal CA. ACME DNS-01 against Cloudflare with the existing `cloudflare_acme_token`. Wildcard cert covers all `*.${nori.domain}` services, avoiding per-vhost rate-limit storms.
- **Pi P7 standup** (`ebfc587`) — pi gains Caddy + Authelia + Blocky-authoritative. Pi imports the services bundle; routes get the upstream-resolution treatment from cp/02's P1b refactor.
- **Caddy LE config** (`37527dc`) — `caddy.withPlugins` bakes in `caddy-dns/cloudflare@v0.2.4` (v0.2.1 rejected the `cfut_`-prefixed CF token format). `acme_ca` pinned to LE explicitly so Caddy doesn't fall back to ZeroSSL on transient errors.
- **Transitional `*.nori.lan` redirect** (`22de243`) — Caddy's `*.nori.lan` vhost serves an internal-CA cert + 301-redirects every `<name>.nori.lan` → `<name>.home.phibkro.org`. Family bookmarks keep working while the migration completes; drop when family devices have migrated.
- **Revert pi as lanIp primary** (`acad85e`) — first attempted DNS flip surfaced the loopback-bind issue from the ADR-0003 addendum. Reverted pending per-service rebinding (which happens in `cp/06-cutovers-batch-A` onward).

**Verify:**
```sh
git diff cp/02-foundation-and-bootstrap..cp/03-entry-plane-le -- modules/services/caddy.nix
# the LE pivot + transitional redirect
git diff cp/02-foundation-and-bootstrap..cp/03-entry-plane-le -- machines/pi/default.nix
# pi's new entry-plane services
```

**Risk:** moderate. The LE cert issuance against Cloudflare succeeded in flight; pi's Caddy is standby today. Workstation continues serving until P12 (not in this stack).

---

## cp/04-aurora-p8 — aurora's family-tier service inventory, empty (7 commits)

`cp/03-entry-plane-le..cp/04-aurora-p8`

Aurora declares the full family-tier service inventory with
`enable = true` and zero data. **Each service stands up empty;
`runsOn` still points at workstation for every route, so family
clients keep hitting workstation.** Aurora's stack is dormant
from a user-facing perspective until per-service cutovers in
`cp/06-cutovers-batch-A` + `cp/08-cutovers-batch-B-and-p14`.

Services enabled (in commit order):
- vaultwarden (P8 bellwether — `e76907b`)
- radicale, calibre-web, komga, glance, heim (`c5de13e`)
- immich full stack (server + ML + database + redis, co-located) (`e82bcb0`)
- miniflux (shares immich's postgres) (`4ca2254`)

Plus:
- `d39cc4e` — aurora imports the services bundle for the first time; reveals several modules that were workstation-implicit (btrbk, restic, verify). Gated workstation-only.
- `03a850c` — btrbk gated to workstation by data ownership (the activation script references `/mnt/media/downloads`, workstation-specific path).

**Verify:**
```sh
git diff cp/03-entry-plane-le..cp/04-aurora-p8 -- machines/aurora/default.nix
# aurora's service inventory grows; nori.services list lands
```

**Risk:** low. Empty state, no client traffic. Verifies aurora's service plumbing works.

---

## cp/05-replication-le-cleanup — P5 replication-verifier + drop internal CA artifacts (2 commits)

`cp/04-aurora-p8..cp/05-replication-le-cleanup`

Two unrelated landings that happened consecutively:

- **P5 — `modules/effects/replication.nix`** (`7275f6b`). New effect module with `nori.replicas.<n>.{source,target,mechanism,maxAgeHours}` registry + per-replica verifier oneshot emitted on the target host. Empty registry = zero units, no false negatives. `just test-replicas` lever added to the Justfile. Smoke-passes today (empty registry); becomes load-bearing when P15 wires the btrfs send/receive timer.
- **Drop internal-CA artifacts** (`f190578`). Removes `modules/services/caddy-local-ca.crt` (stale workstation CA) + `NODE_EXTRA_CA_CERTS` env var in `machines/macbook/home.nix` + cert refs in README/NETWORK.md/MODULE_AUTHORING.md/ROADMAP.md/runbook + the add-oidc-client skill's "Caddy's local CA" section. Post-ADR-0004 cleanup.

**Risk:** low. Both are additive/cleanup.

---

## cp/06-cutovers-batch-A — first 4 P11 service migrations (4 commits)

`cp/05-replication-le-cleanup..cp/06-cutovers-batch-A`

Per-service state migration + Nix flip. **Each cutover is the same shape:**
1. Defensive restic snapshot of source state
2. Stop service on workstation
3. Dump sqlite/pg as appropriate; rsync to aurora
4. Restore on aurora; verify loopback
5. Nix: `bind 0.0.0.0` + `runsOn = "aurora"` + aurora firewall hole + workstation `enable = false`
6. Rebuild aurora → workstation → pi, verify via `https://<sub>.home.phibkro.org`

This batch:
- `bdda421` — **vaultwarden** (bellwether). sqlite + rsa_key.pem. Smallest stateful service; validated the cutover loop.
- `9b319a7` — **glance + heim + radicale** (stateless trio). glance/heim regen from Nix; radicale's htpasswd was empty (operator hadn't bootstrapped).
- `ba4e49f` — **miniflux** (postgres). First pg migration; **surfaced the `--no-owner` restore trap** (`psql <db> < dump` run as postgres restores tables postgres-owned; service can't read schema_version; restart-loops). Fix: `ALTER OWNER` sweep over tables + sequences + public schema. Memory entry `[[postgres-ownership-after-dump-restore]]` written.
- `9a04a7f` — **filmder + grafana**. filmder rebuilt-from-public-source; grafana's sessions ephemeral per the existing module's `nori.backups.grafana.skip` declaration.

**Verify:**
```sh
git log cp/05-replication-le-cleanup..cp/06-cutovers-batch-A --stat
# each commit's stat shows the same shape per service
```

**Risk:** moderate. Each cutover had ~minutes of downtime. Every commit message lists the end-to-end verification done (loopback curl + HTTP 200/302 via Caddy → aurora chain).

---

## cp/07-mp510-p9 — wipe MP510 + new btrfs layout (1 commit)

`cp/06-cutovers-batch-A..cp/07-mp510-p9`

**The only irreversible commit in the stack.** `4acf8d2`.

- Operator extracted personal residue from `/Users/piplu` (Google Photos Takeout, CV, work folders) before wipe.
- MP510's 894 GiB Windows partition wiped + reformatted as a single btrfs filesystem `mp510-backup` with 6 subvols:
  - `@backup-local` → `/mnt/mp510-backup-local` (temp; flips to `/mnt/backup-local` in cp/08 after P14 migrates the IronWolf restic data)
  - `@family-replica-{photos,home-videos,projects,library,archive}` → `/mnt/family-replica/*` (btrfs receive endpoints for P15, currently empty)
- `machines/workstation/disko-mp510.nix` (NEW) — by-id pinned to `nvme-Force_MP510_2031826300012953207B` so future kernel/BIOS reordering can't aim disko at the SN750 root.
- `machines/workstation/windows-mount.nix` deleted (NTFS partition gone).

**Verify:**
```sh
git show cp/07-mp510-p9 --stat
# new disko-mp510.nix; windows-mount.nix deleted
```

**Risk:** **only irreversible PR in the stack.** Drive contents gone; defensive operator extraction confirmed beforehand.

---

## cp/08-cutovers-batch-B-and-p14 — calibre+komga + samba prep + P14 rename (5 commits)

`cp/07-mp510-p9..cp/08-cutovers-batch-B-and-p14`

- `53fbfda` — **aurora Samba shares pre-positioned** (post-P12 family bookmark migration prep) + **immich migration runbook** (`docs/runbooks/immich-cutover.md`). samba.nix refactored to be host-aware: the workstation-only `media` whole-drive share + tmpfiles gate on `config.nori.fs ? downloads`; per-fs `samba = { }` blocks via the cp/02 P4 generator. Aurora `disko-family.nix` declares per-fs shares for `/mnt/family/{photos,home-videos,projects,library,archive}`.
- `1878e42` — **calibre-web + komga cutover** (P11 batch B). No data dependency — library was empty on workstation too. Same shape as cp/06's vault cutover.
- `f4a1378` — **`/restore-pg-with-owner-fix` skill + shell script**. First skill in the repo to ship its own executable. Bakes the cp/06 miniflux trap fix into one command for the next pg migration (immich).
- `88e945d` — plan doc P9 ✓ + P10/P11 in-flight markers.
- `5cf10f3` — **P14: rename restic target `ironwolf` → `mp510`** + drop the IronWolf `@restic-local` subvol after rsync'ing its ~57 GiB to MP510 `@backup-local`. Drive-based name matches the `onetouch` convention; "kept ironwolf for historical continuity" was drift, not continuity. Updates: backup target description, comments in restart-policy.nix + open-webui.nix + vaultwarden.nix + navidrome.nix + Justfile (test-backups), docs/reference/storage.md + SERVICES.md.

**Verify:**
```sh
git diff cp/07-mp510-p9..cp/08-cutovers-batch-B-and-p14 -- modules/services/backup/restic.nix
# target rename
git log cp/07-mp510-p9..cp/08-cutovers-batch-B-and-p14 -- modules/services/calibre-web.nix modules/services/komga.nix
# cutover commits
```

**Risk:** moderate. P14 mount swap (atomic via NixOS systemd mount unit name reuse) verified read+write before dropping the source.

---

## cp/09-drift-and-music — TOPOLOGY sweep + observability + music tier (4 commits)

`cp/08-cutovers-batch-B-and-p14..cp/09-drift-and-music` (= `main`)

Audit found drift in the blast radius. Patches:

- `0082462` — **aurora observability gaps + TOPOLOGY.md sweep**.
  - `ntfy-notify.enable = true` on aurora (alerts route directly without depending on workstation).
  - `aurora-ssh` + `aurora-samba` gatus probes added to both workstation's and pi's `nori.gatusProbes` (mutual-observability pattern matching the workstation↔pi shape).
  - `docs/reference/topology.md` aurora row rewritten: was "immich-machine-learning offload"; now full family-vault role description. MP510 drives row updated. Mermaid diagram redrawn. Service-placement table reshuffled per ADR-0002/0003.
- `e333b8d` — **re-enable beszel-agent on aurora** (operator minted the per-host key + pasted into sops) + **pre-position `/mnt/family/library/music` dir** (operator's option A on the navidrome path-tier decision — music sits under library, sibling to books/comics).
- `744504e` — **`${library}/music` tmpfile in `arr/shared.nix`**. Per option A, workstation's @library also holds music at /mnt/media/library/music post-Lidarr-reconfig. Tmpfile guarantees dir + perms survive future rebuilds.
- `7f0d3a6` — **Lidarr BindPaths fix**. Hardened lidarr couldn't see /mnt/media/library/music in its root-folder picker (only /mnt/media/downloads was in BindPaths). Added `${library}/music` to `nori.harden.lidarr.binds`.

**Risk:** low. Doc + small Nix edits + one BindPaths fix. Verified live (operator's Lidarr UI shows both Library + Streaming root folders now).

---

## Working with the stack

```sh
# read this doc
cat docs/plans/2026-06-11-pr-review-stack.md

# inspect any phase
git diff --stat cp/0(N-1)..cp/0N
git log cp/0(N-1)..cp/0N

# checkout a phase to run nix flake check at that point
git checkout cp/0N
nix flake check
git checkout main

# clean up after review
git branch | grep ^.\ \ cp/ | xargs -L1 git branch -D
```

## Skipping ahead

If you trust the cp/01 ADRs and want to spot-check the riskiest pieces:

- **cp/07-mp510-p9** — only irreversible commit
- **cp/06-cutovers-batch-A** + **cp/08-cutovers-batch-B-and-p14** — the actual data migrations
- **cp/03-entry-plane-le** — the LE + pi pivot

cp/02 is the biggest by commit count + file count but the mkMerge wrap is the bulk of it (mechanical, nix-diff equivalent).

## What's NOT in the stack

- P10 (data sync workstation → aurora `/mnt/family/*`) — runs in background; no Nix changes.
- P11 immich cutover — runbook ready (`docs/runbooks/immich-cutover.md`), data move blocked on P10.
- P11 navidrome cutover — music data tier prep landed in cp/09; the actual cutover (data rsync to aurora + state migrate + Nix flip) is a separate session.
- P12 entry-plane DNS flip — operator-gated.
- P15 btrfs send/receive timer — module schema landed in cp/05; the actual sender + timer is a future session.
