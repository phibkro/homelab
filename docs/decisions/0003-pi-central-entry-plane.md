# ADR-0003: Pi-central HTTP entry plane (supersedes ADR-0002's aurora-entry-plane choice)

- Status: Accepted
- Date: 2026-06-11
- Supersedes: ADR-0002 in part — the *family vault* + *workstation-as-compute* pieces remain; only the *entry plane* role moves from aurora to pi.

## Context

ADR-0002 placed both the HTTP entry plane (Caddy + Authelia + Blocky-authoritative) AND the family/data vault role on **aurora**. The reasoning was "aurora is always-on family-tier hardware; co-locate". During the foundation refactors (P1, P1b, P2, P3, P4) the assumption was re-examined and two structural pressures surfaced:

1. **Caddy's internal-CA model doesn't share cleanly across hosts.** Workstation's Caddy generates a local-CA root cert at `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`; aurora's Caddy would generate its own, distinct cert. Clients trust workstation's CA per-device (one-time install). Adding aurora as a second issuer either requires (a) syncing the CA private key between hosts via sops (rotating-secret chore + duplicate-key concern), (b) running ACME against a real public DNS (impossible for `*.nori.lan` without public ownership), or (c) every client trusting *both* CAs (doubles the per-device install drift). None earn rent.

2. **Aurora's failure profile is laptop-class** — lid close, wifi flap, suspend-resume bugs, kernel experiments. Putting the family SSO + entry plane on aurora means a botched aurora rebuild takes down family password access (Vaultwarden), calendars (Radicale), RSS (Miniflux). Pi's failure profile is *appliance-class* — rare, loud, and isolated to the appliance plane.

The P1b route-lift refactor (just landed) proved cross-host route declarations work via `nori.lanRoutes.<X>.runsOn`: any host with the route registry resolves `routeHost` to `127.0.0.1` if local, the appropriate tailnet IP otherwise. The proxy host doesn't need to co-locate with every backend. That unlocks the alternative: **pi as the sole entry plane, aurora as pure backend**.

## Decision

Move Caddy + Authelia + Blocky-authoritative-#1 to **pi**. Aurora remains the family/data vault but serves family-tier service *backends* only (Vaultwarden, Immich, Radicale, Miniflux, Glance, Heim, Calibre-web, Komga, Navidrome). Workstation stays sleep-friendly compute (unchanged from ADR-0002).

```
BEFORE (ADR-0002)                            AFTER (this ADR)
─────────────────────────────────────        ─────────────────────────────────────
┌─ pi ──────────────────────────────┐        ┌─ pi ──────────────────────────────┐
│ DNS forwarder, observability,     │        │ DNS authoritative #1.             │
│ alerting, Tailscale subnet+exit.  │        │ Caddy + Authelia (entry plane).   │
│                                   │        │ Observability, alerting, subnet.  │
└───────────────────────────────────┘        └───────────────────────────────────┘

┌─ aurora ──────────────────────────┐        ┌─ aurora ──────────────────────────┐
│ Family vault.                     │        │ Family-tier service BACKENDS.     │
│ Caddy + Authelia + Blocky-auth.   │        │ /mnt/family + service state.      │
│ Family-tier services.             │        │ NO Caddy / Authelia / Blocky-auth.│
└───────────────────────────────────┘        └───────────────────────────────────┘

┌─ workstation ─────────────────────┐        ┌─ workstation ─────────────────────┐
│ Sleep-friendly compute (Ollama,   │        │ Sleep-friendly compute            │
│ Jellyfin, *arr, downloads).       │        │ (unchanged).                      │
│ Cold replica of /mnt/family/*.    │        │                                   │
└───────────────────────────────────┘        └───────────────────────────────────┘
```

### Per-host role

- **Pi** — always-on appliance. **HTTP entry plane** (Caddy + Authelia + Blocky-authoritative-#1 — the previous Blocky-forwarder role retires). DNS, observability, alerting, Tailscale subnet+exit (unchanged from ADR-0002). The runsOn-resolver does the cross-host proxying.
- **Aurora** — always-on family/data vault. `/mnt/family/*` primary (P6 landed). Family-tier service *backends*: Vaultwarden, Radicale, Miniflux, Glance, Heim, Immich (server + DB + ML), Calibre-web, Komga, Navidrome. OneTouch backup target (P13 landed). **No Caddy, no Authelia, no Blocky-authoritative.**
- **Workstation** — sleep-friendly compute (Ollama, Jellyfin, `*arr` bundle, qBittorrent, Stremio, `@downloads`). Cold replica of `/mnt/family/*` on MP510. WoL-wake when media access happens. Unchanged from ADR-0002.
- **Pavilion** — agent quarantine + weekly tertiary irreplaceable-media replica. Unchanged.

### Replication topology

Unchanged from ADR-0002. Four host-level copies across four failure domains (aurora HDD → workstation MP510 cold replica → OneTouch restic vault on aurora → weekly pavilion subvol replica). Residual risk (total-apartment loss) operator-accepted.

## Consequences

### Positive

- **Single Caddy instance, single CA.** No cross-host cert sync, no dual-trust install on family devices. Pi's `/var/lib/caddy` is the single source of TLS truth for `*.nori.lan`.
- **Entry plane joins fate with appliance plane.** Pi already owns DNS, alerts, observability — adding HTTP entry plane continues the pattern rather than splitting "network functions" across two always-on hosts.
- **Aurora's failure modes stop affecting the entry path.** Lid close, wifi drop, suspend hang on aurora: family SSO still works, Vaultwarden web UI shows a 502 only for the duration. Recovery from aurora outage = wake aurora; no Authelia/Caddy bootstrap involved.
- **Pi-central is structurally symmetric.** Pi = network, aurora = data, workstation = compute. Each host plays one role; mental model is short. Service-placement decisions look at the role enum, not at fate-sharing exceptions.
- **Caddy on pi proxies via runsOn.** Each route's backend resolves to workstation-tailnet or aurora-tailnet automatically; service moves stay flag-flips on `nori.services.<X>.enable`.

### Constraints

- **Pi failure becomes the SPOF for the entry path.** All family-tier HTTPS goes dark if pi dies; observability + alerting also gone. Mitigation: pi's appliance posture (read-only SD card, minimal mutation cycle, no kernel experiments) keeps failures rare; recovery is "flash a new SD card from the homelab repo + restore Authelia's user database from restic". Operator-accepted trade-off for the fate-sharing cleanup.
- **Pi's RAM budget tightens slightly.** Caddy + Authelia add ~150 MB resident over current observability stack. Pi 4 8 GB has headroom; verify with process-exporter after deploy.
- **Tailnet ACLs need updating.** Aurora's family-tier service ports (8222 Vaultwarden, 2283 Immich, etc.) must be reachable from pi's tailnet IP. The current ACL grants pi → workstation (Caddy proxy direction); a mirror pi → aurora rule is needed once family-tier services move to aurora.

### Structurally enforced

- **Routes know their backend.** `nori.lanRoutes.<X>.runsOn` (landed in P1b) is the single source of "which host runs this route". Pi's Caddy generator resolves to `tailnetIp` per route; no manual upstream lists.
- **Service placement is declarative.** `nori.services.<X>.enable` on the host that runs it. P12 cutover = enable family-tier on aurora, unset on workstation; the lan-route, OIDC, samba, and backup generators all re-aim automatically.
- **Shares follow drives.** `nori.fs.<X>.samba` (landed in P4) emits Samba shares on whichever host imports the disko entry. If `/mnt/family/photos` ever moves further, the share moves with it.

### Reversibility

- The schema (`nori.services`, `nori.lanRoutes.runsOn`, `nori.fs.samba`) is host-neutral. Flipping back to aurora-entry, workstation-entry, or some other host-entry is `nori.services.{caddy,authelia,blocky}.enable` on the destination + Tailscale DNS push order change. No structural refactor required.
- Pi's appliance posture means standing back up after an SD card fail is hours, not days; recovery doesn't depend on this ADR being correct.

## Alternatives considered

### Keep ADR-0002's aurora-entry choice

The original answer. Rejected because:

- Cross-host CA problem (above) — solving it adds moving parts that earn no rent.
- Aurora's laptop-class failure modes co-locating with family SSO violates the fate-sharing principle the ADR itself cites.

### Both hosts run Caddy with a sops-shared CA

Sync workstation's local-CA root key + cert to aurora via sops; each Caddy uses the shared CA. Rejected because:

- The CA private key landing in sops creates a long-lived secret that requires rotation discipline (sops re-encrypt on host turnover, careful key-revocation playbook). Today's homelab has zero such material; introducing one for this is over-engineering.
- Caddy's internal-CA bootstrap is opinionated about owning the CA file — sharing it across hosts is undocumented territory.

### Aurora as entry plane with ACME from a real domain

Rent a domain, point DNS at aurora's tailscale-funnel or LAN, run Caddy with ACME. Rejected because:

- `*.nori.lan` is intentionally LAN-local; introducing a real domain extends the attack surface without addressing the original SPOF concern.
- Operating cost (~12 EUR/yr for the domain) for marginal value.

### Stay workstation-central — undo the migration

Reverse course, accept idle 250 W and family SPOF on workstation. Rejected — defeats the original aurora migration's two motivating problems (power + SPOF).

## See also

- ADR-0002 — original aurora-entry-plane choice; the family-vault + workstation-as-compute portions of that ADR remain in force. The HTTP entry plane is what this ADR overrides.
- `docs/superpowers/plans/2026-06-11-aurora-migration.md` — migration plan; **P7 lands on pi** not aurora; P12 cutover swaps Tailscale DNS push order to pi primary.
- `modules/effects/lan-route.nix` § `runsOn` (P1b)
- `modules/effects/service-placement.nix` § `enabled` (P1)
- `modules/effects/fs.nix` § `samba` (P4)
- `docs/TOPOLOGY.md` — needs update to reflect pi-central post-migration role
