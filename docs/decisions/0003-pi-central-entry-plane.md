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

## Addendum: backends must be tailnet-reachable (2026-06-11 cutover learning)

P7 pi standup succeeded as a parallel-running entry plane. The first attempt to flip DNS to pi surfaced a real constraint that ADR-0003 had glossed over: **the proxy host (pi) needs to actually reach the backends across the tailnet**, but most workstation services bind `127.0.0.1` only (Vaultwarden's `ROCKET_ADDRESS`, Immich's `IMMICH_HOST`, Gatus, Miniflux, Calibre-web, Komga, Navidrome — all loopback). Authelia happens to bind `*` so SSO worked end-to-end through pi; everything else returned 502.

The pi-central architecture demands one of these per backend:

1. **Bind on tailnet (`0.0.0.0` + tailnet firewall port open).** Caddy on pi proxies tailscale0:port. Suitable for services with their own auth (Vaultwarden's master password, Immich's account model) — tailnet ACL is the gate.
2. **Caddy-forward-auth services rebound carefully.** The `*arr` stack relies on Caddy's `forward_auth` for the SSO gate. Direct tailnet exposure bypasses it. Either: keep these on the same host as their proxying Caddy (workstation today, future-pi if pi gains the *arr stack), or accept that forward-auth is moot on tailnet (any tailnet client can hit the backend).
3. **Stay co-located with the proxying Caddy.** Workstation-only services (Ollama, Jellyfin's NVENC, the bulk-download stack) stay where Caddy locally serves them; cross-host proxying doesn't apply.

**Practical sequence**, captured here so future P8/P12 work inherits the pattern: each family-tier service that migrates to aurora gets its bind config + tailnet firewall + `runsOn` flip as one atomic change. Once a critical mass of family-tier routes points at aurora, pi's `nori.lanIp` override + the Tailscale split-DNS flip become the cutover trigger. Doing the rebinding service-by-service during the migration is cleaner than a separate "rebind everything" sweep.

## Addendum: cutover landed (2026-06-12 `0629326`)

The constraints called out in the prior addendum were addressed and the entry-plane flip landed. State at time of cutover:

- Every family-tier service moved to aurora during P11 (vaultwarden, glance, heim, radicale, miniflux, filmder, grafana, calibre-web, komga, navidrome, immich) with `0.0.0.0` binds + tailnet firewall opens.
- Every workstation-resident route (the arr stack, jellyfin, ollama, syncthing, stremio, gatus, hermes) marked `exposeOnTailnet = true`, opening the tailnet firewall hole so pi's Caddy can reverse-proxy them too.
- Hermes refused non-loopback binds; landed via `--insecure` (operator-tier; tailnet ACL is the actual gate). Caddy still rewrites Host/Origin to `127.0.0.1:9119` so the GHSA-ppp5-vxwm-4cf7 mitigation against browser-DNS-rebinding stays in effect.
- syncthing UI re-bound via `services.syncthing.guiAddress` (the XML `settings.gui.address` path doesn't propagate — the systemd ExecStart hardcodes `--gui-address` and overrides it; saved as `[[syncthing-gui-address-cli-override]]` memory).
- `nori.lanIp` derives from pi in `modules/machines/base/default.nix`; `authelia.runsOn` flips to pi.
- Workstation `caddy.enable = false` + `authelia.enable = false`; closure shrinks ~96 MB.
- Tailscale admin UI DNS push order swapped (`home.phibkro.org` row: workstation 100.81.5.122 → pi 100.100.71.3).

End-to-end verified from every tailnet host. The reverted state from the earlier attempt is **superseded** — this is the live configuration.

## See also

- ADR-0002 — original aurora-entry-plane choice; the family-vault + workstation-as-compute portions of that ADR remain in force. The HTTP entry plane is what this ADR overrides.
- `docs/plans/2026-06-11-aurora-migration.md` — migration plan; **P7 lands on pi** not aurora; P12 cutover swaps Tailscale DNS push order to pi primary.
- `modules/infra/networking/default.nix` § `runsOn` (P1b)
- `modules/infra/placement.nix` § `enabled` (P1)
- `modules/infra/storage/default.nix` § `samba` (P4)
- `docs/reference/topology.md` — needs update to reflect pi-central post-migration role

## Addendum: reach mechanism refined (2026-06-23, ADR-0006)

The cutover marked every cross-host route `exposeOnTailnet = true` so pi's Caddy
could reach it — but that flag also opened the backend to *all* tailnet peers,
letting a family/OIDC backend be curled around Authelia. [ADR-0006](0006-appliance-scoped-backend-exposure.md)
decomposes this: cross-host Caddy-reach is now automatic and **appliance-scoped**
(admits only the entry-plane host), and `exposeOnTailnet` reverts to its honest
"all-peer direct access" meaning (forbidden on `family`/`forwardAuth` routes).
The pi-central entry-plane decision itself is unchanged.
