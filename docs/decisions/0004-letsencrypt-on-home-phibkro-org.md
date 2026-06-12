# ADR-0004: Let's Encrypt + Cloudflare DNS-01 on `home.phibkro.org` (supersedes ADR-0003's internal-CA piece)

- Status: Accepted
- Date: 2026-06-11
- Supersedes: ADR-0003 in part — the *pi-central entry plane* decision remains; the *Caddy internal CA + `*.nori.lan`* portion is replaced by *real LE wildcard certs on `*.home.phibkro.org`*.

## Context

ADR-0003 settled on pi as the HTTP entry plane, with Caddy's internal CA providing TLS for `*.nori.lan`. The internal-CA path has one structural cost: every device that accesses the homelab over HTTPS needs the CA root cert installed once (Mac keychain, iOS profile, Android system trust). For the operator it's one-shot; for family devices it's a hand-holding step every time a new phone or laptop joins. The friction compounds for the small but real set of apps that hardcode HTTPS checks (Node fetch'es with `NODE_EXTRA_CA_CERTS`, Python urllib's verification, mobile apps that don't honour system trust stores).

Two facts changed the picture:

1. **`phibkro.org` is already owned and Cloudflare-hosted.** No new domain registration cost. The existing zone has unused subdomain space (`home.*` was free; the public apps live at `me`, `filmder`, `finnbydel`, `finnbydel-api`, `drinks`, `www`).
2. **Caddy's `caddy-dns/cloudflare` plugin handles DNS-01 challenges trivially.** Token in sops + a single global directive switches every vhost from internal CA to LE-issued, no per-device install needed.

Trade-off discussion in chat surfaced: the only meaningful cost of the LE path is a one-time bookmark migration (`<svc>.nori.lan → <svc>.home.phibkro.org`). The structural wins are large enough that this cost lands as an obvious yes.

## Decision

Use Let's Encrypt for all `*.<nori.domain>` certs, served by Caddy on pi (post-ADR-0003 pivot). Domain is `home.phibkro.org`. Challenge type is DNS-01 against Cloudflare's API. Single wildcard cert `*.home.phibkro.org` covers all routes.

### Mechanism

```
                  ┌───────────────────┐
                  │ Caddy on pi (post │      ┌─────────────────────┐
                  │ ADR-0003 cutover, │─────▶│ acme-v02.api.let-   │
                  │ landed 2026-06-12)│      │ sencrypt.org        │
                  └────────┬───────────┘      └─────────────────────┘
                           │ DNS-01 challenge
                           ▼
                  ┌───────────────────┐      ┌─────────────────────┐
                  │ caddy-dns/cloudfl-│─────▶│ api.cloudflare.com  │
                  │ are plugin v0.2.4 │      │ /client/v4 (writes  │
                  │ (Bearer token)    │      │ _acme-challenge.*   │
                  └───────────────────┘      │ TXT to phibkro.org) │
                                              └─────────────────────┘
```

- **Domain template**: `nori.domain` option (default `"home.phibkro.org"`) replaces every `*.nori.lan` literal. Service modules read `${config.nori.domain}` for vhost names, OIDC redirect URIs, Authelia cookie domain, etc.
- **Wildcard vhost**: lan-route's Caddy generator emits ONE `*.${nori.domain}` block with `@<name> host <name>.${nori.domain}` matchers per route. Caddy issues one wildcard cert covering all subdomains.
- **DNS resolution**: Blocky's `customDNS.mapping` is authoritative on the LAN/tailnet for `*.home.phibkro.org → nori.lanIp`. Public DNS has no A records for `home.*` — the homelab stays internal-only. CF's authoritative DNS holds only the TXT records ACME needs (Caddy creates + removes them per challenge).
- **Cloudflare API token**: dedicated `cloudflare_acme_token` in sops.apps.yaml, scope `Zone | DNS | Edit` + `Zone | Zone | Read` on the `phibkro.org` zone only. Separate from the operator's `cloudflare_api_token` (used by app-deploy flows).
- **Forced issuer**: `acme_ca https://acme-v02.api.letsencrypt.org/directory` pins LE; Caddy's default tries ZeroSSL first which doubled the issuance traffic on the first attempt.

### Per-device install: gone

LE root certs (ISRG Root X1) ship pre-trusted on every modern device. Mac/iOS keychain, Android, Windows, every Linux distro. No keychain dance, no profile install, no `NODE_EXTRA_CA_CERTS` env var. New devices joining the family work immediately.

## Consequences

### Positive

- **No per-device CA install.** The single biggest source of friction for the homelab's family-tier is eliminated.
- **Green lock everywhere, including iOS/Safari "HTTPS only" mode.** Family apps stop showing "not secure" badges.
- **One cert renewal cycle every 60 days for the entire homelab.** A wildcard cert covers ~30 vhosts; one ACME flow per cycle (or one re-issue on certificate add). Caddy auto-renews ~30 days before expiry.
- **Operator-already-owns-the-tooling.** Cloudflare account, zone, sops infrastructure all pre-existed. Setup cost was hours not days.
- **Tighter token scope than the operator's existing CF token.** `Zone | DNS | Edit` on `phibkro.org` only. Worst-case compromise of the pi-side ACME token only lets an attacker manipulate DNS records under one zone (can't touch Workers, Pages, Account settings).

### Constraints

- **One-time bookmark migration cost.** Every family device + saved login + Mac keychain entry that targeted `*.nori.lan` needs updating to `*.home.phibkro.org`. Mitigated by Blocky keeping (optionally) the old names as 301-redirect aliases during transition.
- **Cert renewal depends on Cloudflare API reachability.** If CF API is down (unlikely; their uptime is good) or the API token gets revoked, Caddy's auto-renewal fails. LE issues 90-day certs and Caddy starts retrying 30 days before expiry — a 60-day grace window before traffic actually breaks. Loud and predictable failure mode.
- **DNS-01 challenge requires outbound HTTPS from the Caddy host.** Pi/workstation both have this; no change needed.
- **`*.home.phibkro.org` names are unreachable from outside the LAN/tailnet.** This is by design (split-horizon DNS; public records intentionally absent) but worth being explicit: a phone on cellular data with Tailscale off won't reach the homelab.

### Structurally enforced

- **Wildcard cert means no cert-add-friction.** Adding `nori.lanRoutes.foo = { … }` doesn't trigger an ACME flow — Caddy already has the wildcard. Per-route adds become free.
- **Renewal is monotonic.** One cert, one renewal cycle, one alert path if it fails (existing OnFailure → ntfy on the caddy.service unit).
- **Domain rename is a one-attribute change.** `nori.domain = "elsewhere.example.com"` re-templates every consumer.

### Reversibility

The internal-CA path is recoverable: `services.caddy.globalConfig = "local_certs";` + rebuild, plus re-installing `caddy-local-ca.crt` per device (which most family devices probably still have from the prior config). The schema (`nori.domain`, the wildcard vhost generator, the sops token wiring) all stay neutral — they just point at a different issuer. ADR-0003 reversibility (flipping back to workstation-entry-plane via `nori.services.caddy.enable` on a different host) also stays valid.

## Alternatives considered

### Keep Caddy's internal CA on `*.nori.lan`

ADR-0003's choice. Rejected because the per-device install friction was the largest single source of family-tier friction, and the operator already had every prerequisite for the LE path (domain, CF account, sops infrastructure). The structural cost of the migration (one-time bookmark rename) is bounded and one-time; the structural cost of the internal-CA path (every new device needs CA install) is unbounded and ongoing.

### Drop HTTPS entirely (HTTP-only over tailnet/LAN)

Surfaced in chat. Rejected because: (1) Authelia OIDC requires HTTPS per the OAuth 2.1 spec; dropping HTTPS breaks SSO for every family-tier app that uses it (Vaultwarden, Open WebUI, Miniflux, Navidrome). (2) Modern browser features (Web Crypto, Service Workers, secure cookies) gate on HTTPS origins. (3) iOS Safari's "HTTPS only" default mode requires per-site exemption. The "is tailnet/LAN really exposed?" honest answer is "data secrecy: no, but server-identity verification + browser-features matter regardless".

### Use a real domain with public DNS pointing to RFC1918 IPs

A variant on LE where public DNS *does* resolve `*.home.phibkro.org`, just to a non-routable IP. Rejected because it adds DNS-misdirection complexity without rent — the split-horizon (Blocky-internal-authoritative + public-records-absent) is simpler and achieves the same "reachable from LAN/tailnet only".

### Hetzner Storage Box + ACME (offsite + LE)

The previously-killed Hetzner path from ADR-0002 (offsite restic) and LE are independent; this ADR doesn't speak to off-site backups. If Hetzner is ever re-introduced, the cert path here doesn't need to change.

## Implementation notes (lessons for future similar pivots)

1. **Caddy plugin version matters.** v0.2.1 of `caddy-dns/cloudflare` rejected the new `cf(ut|at)_`-prefix token formats CF emits today. v0.2.4 has a updated regex (`legacyCloudflareTokenRegexp` + `newCloudflareTokenRegexp`) that accepts both. Pin the plugin to a version explicitly known to handle current CF token formats.

2. **CF dashboard "User API Tokens" page emits the cfut_ format.** What dashboard docs call an "Account API Token" is what CF actually issues as a User API Token with permission-scope. The token's *prefix* is informational; what matters is the permission set + zone scope. The Caddy plugin's strict format check (pre-v0.2.4) was the only thing that cared about the prefix.

3. **Per-vhost certs are a rate-limit risk.** Caddy issues one cert per vhost name by default. With 30 vhosts and Caddy retrying parallel on startup, CF's auth endpoints rate-limited us during initial testing. The wildcard refactor eliminates this: one cert covers everything.

4. **Pin LE explicitly via `acme_ca`.** Caddy's default tries ZeroSSL first; on transient failure it falls back to LE. Two issuers = double the API calls = doubled rate-limit exposure. Pinning LE-only is one line and removes the ambiguity.

5. **sops with a different file via `sopsFile = path`.** The existing `secrets/apps.yaml` (for personal-app deploy secrets) was a natural home for the CF token; the per-secret `sopsFile` override worked cleanly without disturbing `secrets/secrets.yaml`'s default scope.

## See also

- ADR-0003 — pi-central entry plane decision; this ADR refines the TLS portion of that.
- `modules/effects/lan-route.nix` § `nori.domain` and the wildcard Caddy vhost generator.
- `modules/services/caddy.nix` § `withPlugins`, `acme_dns`, `acme_ca`, sops token wiring.
- `docs/superpowers/plans/2026-06-11-aurora-migration.md` — P7 standup on pi inherits this Caddy config wholesale.
