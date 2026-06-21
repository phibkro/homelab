---
generated: true
source: flake.nix § packages.docs-lan-route
regenerate: nix build .#docs-lan-route
---

# `nori.lanRoutes` — generated reference

Two-section artifact:

 1. Networking-concern overview — RFC 145 doc-comments
    extracted from `modules/infra/networking/default.nix`.
 2. `nori.lanRoutes.<name>.*` schema reference — option
    fields extracted via `nixosOptionsDoc`.

The hand-written `network.md` keeps the WHY + patterns;
this artifact carries the WHAT (schema details).

Networking concern — the lan-route registry + its adapters.

`default.nix` carries `nori.lanRoutes` (schema + collection +
Caddy vhost / Blocky DNS / Gatus monitor / Authelia OIDC-secret
generators). Adapter siblings:

 - `caddy.nix`        — Caddy reverse-proxy daemon
 - `blocky.nix`       — Blocky DNS daemon (authoritative for
                        `*.${domain}` on LAN/tailnet)
 - `gatus-probe.nix`  — per-route monitor schema fragment
                        (consumed inline by lan-route)

Authelia (the OIDC daemon) is access-concern, not networking;
lives at `modules/infra/access/` (Phase 3d). lan-route generates
the sops-templated OIDC secrets here; authelia consumes them.

## Three zones, default-deny

| Zone | What's there | Default posture |
|---|---|---|
| **localhost** | Services bind here unless explicitly exposed | Closed to outside |
| **tailnet** | Personal devices + family. SSH, Samba, `*.${domain}` HTTPS, direct service ports | Closed by default; Caddy on 80+443 + Samba on 445 are the only globally-open tailnet ports |
| **public internet** | Personal apps that need public exposure live at Cloudflare edge (Pages + Workers + D1) | **Homelab serves nothing publicly** by default. Tailscale Funnel is the prototyped path if anything ever needs to land public traffic |

The Cloudflare edge apps (phibkro.org apex, filmder, drinks-app,
finnbydel-app, heim) live as Pages (static) + Workers+D1 (stateful).
The homelab keeps tailnet-only copies of `filmder` + `heim` via
`nori.lanRoutes` for fast internal access. A `cloudflared` Tunnel
approach was decommissioned 2026-05-08.

## DNS architecture

```mermaid
flowchart LR
    device[tailnet device] -->|DNS query| ts[Tailscale stub 100.100.100.100]
    ts -->|global-nameserver push| pi_blocky[Pi Blocky · authoritative]
    pi_blocky -->|"*.${nori.domain}"| host_map["*.${nori.domain} → pi LAN IP<br/>auto-generated from nori.lanRoutes"]
    pi_blocky -->|other| upstream[1.1.1.1 / 9.9.9.9]
    classDef primary fill:#3a5,stroke:#2a4,color:#fff
    class pi_blocky primary
```

Pi runs Blocky in **self-hosted mode** — auto-generates the
`*.${domain}` customDNS map from `nori.lanRoutes` (every route
name resolves to pi's LAN IP, since pi is the Caddy host).
Tailscale's global-nameserver push points tailnet devices at pi.
LAN-only devices (smart TV, guest phones) are NOT covered — they
keep using whatever the router pushes. Workstation's Blocky is
also self-hosted as a fallback secondary (resolves the same map;
LAN-side resilience for if pi is down).

Why Tailscale push, not router DHCP: the ISP-shipped Genexis EG400
locks DHCP DNS settings out of the user-facing admin UI. Router-
side DNS replacement requires either bridge-mode activation by
phone request + a second router, or double-NAT with a downstream
router. Neither set up; Tailscale push is the zero-hardware-cost
workaround.

**Bootstrap loop hazard:** workstation's `/etc/resolv.conf` points
at Tailscale's stub (100.100.100.100); Tailscale forwards back to
workstation's Blocky; Blocky can't resolve its own outbound URLs
(blocklist sources, DoH endpoints) before serving DNS.
`services.blocky.settings.bootstrapDns` MUST be set to direct
upstream IPs. Codified in `.claude/skills/gotcha-blocky-bootstrap-
loop/`.

## Caddy + TLS + naming

Caddy terminates TLS for every `<name>.${domain}` with a
**Let's Encrypt wildcard cert** (`*.${domain}`) obtained via ACME
DNS-01 against Cloudflare. The wildcard avoids per-vhost issuance
+ the LE rate-limit storm that would follow. ISRG roots ship pre-
trusted on every modern device — no per-device CA install, no Mac
keychain dance, no Node `NODE_EXTRA_CA_CERTS` env var. See
ADR-0004 for the rationale.

The Cloudflare API token lives in sops (`cloudflare_acme_token`);
Caddy's `withPlugins` bakes in `caddy-dns/cloudflare`. The
`nori.domain` option is the single source of truth — every vhost
name, Authelia cookie domain + issuer URL, and OIDC redirect URI
reads from it.

Transitional `*.nori.lan` redirect: pi's Caddy still serves
`*.nori.lan` (Caddy internal CA) and 301-redirects to the same
path under `home.phibkro.org`. Drop this block from `caddy.nix` +
the parallel entries in `blocky` customDNS once family bookmarks
have migrated.

## Naming: function over brand

`chat.${domain}` not `open-webui.${domain}`. `media` not
`jellyfin`. The brand changes (Uptime Kuma → Gatus); the function
doesn't. Brand-named only when the brand IS the identity (`auth`
for Authelia, `samba`). Enforced by the
`lint.functionNamedSubdomains` TOML rule.

# Networking concern — overview {#sec-functions-library-networking}


## `homelab.networking.options.nori.domain` {#function-library-homelab.networking.options.nori.domain}

`nori.lanRoutes` — single source of truth for services exposed
under `*.${domain}`. Each entry generates ALL of:

 - Caddy vhost reverse-proxying `<name>.<domain>` → backend port
 - Blocky customDNS mapping `<name>.<domain>` → `config.nori.lanIp`
 - Gatus monitor (if `monitor` is non-null)
 - Tailnet firewall hole (if `exposeOnTailnet`)
 - sops raw + hash secrets + env-file template (if `oidc` is
   set) — Authelia client list assembly lives in
   `modules/infra/access/authelia.nix`, reading back
   `config.nori.lanRoutes` from here. Hash material stays in
   sops; the authelia config-filter injects it at runtime.

Service modules declare routing inline alongside their config:

```nix
nori.lanRoutes.chat = {
  port = 8080;
  oidc = {
    clientName  = "Open WebUI";
    redirectPath = "/oauth/oidc/callback";
  };
};
```



## nori.domain

Parent DNS domain for the homelab’s ` *.<domain> ` services.
Single source of truth: vhost names, Authelia cookie domain,
Authelia issuer URL, OIDC redirect URIs, Caddy ACME wildcard all
read this rather than hardcoding the literal.

Split-horizon DNS: Blocky is authoritative for ` *.<domain> ` on the
LAN/tailnet (resolves to ` nori.lanIp `); public DNS for the same
names has no A records, so the homelab is reachable only on the
LAN/tailnet. Caddy obtains real Let’s Encrypt certs via DNS-01
using the existing Cloudflare token in sops, so family devices
see a green lock with no per-device CA install.

Renaming requires:

 - Family/operator bookmark updates from old to new domain.
 - Authelia OIDC client redirect URI re-trust (each client
   declared via ` nori.lanRoutes.<X>.oidc ` re-emits its
   authorized URIs from ` ${name}.${domain} ` automatically).
 - Tailscale DNS-search-domain push to include the new domain
   so unqualified hostnames keep resolving on tailnet clients.

See ADR-0004 for the rationale (pre-existing phibkro.org +
Cloudflare-hosted DNS made the LE path cheaper than internal CA).



*Type:*
string



*Default:*

```nix
"home.phibkro.org"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanIp



LAN IP that \*.nori.lan names resolve to. Derived from the
nori.hosts registry as “the unique host with role=workhorse
and a non-null lanIp” (see modules/infra/hosts.nix). When
a future second workhorse with a static LAN lease lands, the
derivation fails eval — surfaces the ambiguity instead of
silently picking workstation.

Previously the workhorse’s tailnet IP, which silently required
every client to be on tailnet to reach any service — a sharp
edge for LAN-resident devices that can’t or don’t run tailscale
(chromecasts, printers, occasional guest devices). Using the
LAN IP lets those clients hit services directly. Tailnet
clients off-LAN still reach the same address via Pi’s subnet
route advertisement (services.tailscale.useRoutingFeatures =
“server” in modules/machines/pi/default.nix); the client side needs
–accept-routes set in its tailscaled config.

Consumers: Blocky’s forwarder mode (modules/infra/networking/blocky.nix)
and the Blocky DNS generator below. Both want a single “where
does \*.nori.lan live” address.



*Type:*
string



*Default:*

```nix
# the unique workhorse-with-lanIp from config.nori.hosts;
# eval-fails if zero or more than one matches.

```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes



Services to expose under \*.nori.lan via Caddy reverse proxy +
Blocky DNS. Attribute name = subdomain; value declares the
backend.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  jellyfin = { port = 8096; };
  chat = { port = 8080; };
  ai = { port = 11434; };
}

```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.audience



Who this route is for. Documents intent + drives the
auth-stacking principle:

 - operator — admin-only management UIs (the \*arr stack,
   qBittorrent, Beszel admin, Syncthing). Tailnet
   membership IS the auth; layering Authelia on top
   duplicates the network-perimeter guarantee for no
   per-user-state value, while making Authelia uptime
   load-bearing for operator workflows.

 - family — services with per-user state inside the app
   (Jellyfin watch progress, Immich photos, Jellyseerr
   request history, Open WebUI chat, Vaultwarden vaults,
   Navidrome playlists). Native OIDC propagates the
   user identity into the app — that’s the value-add.
   Where native OIDC isn’t clean (Komga, calibre-web),
   forward-auth gates browser access at Caddy.

 - public — intentionally open dashboards (home/Glance,
   status/Gatus) and the SSO portal itself (auth/
   Authelia). Tailnet trust is the only gate; auth
   inside these would defeat their purpose.

Enforced (eval-time assertion below): audience=family
requires either an ` oidc ` or ` forwardAuth ` block, or
an explicit ` noAuthReason ` string naming why neither
fits.



*Type:*
one of “operator”, “family”, “public”



*Default:*

```nix
"operator"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.dashboard



If set, this route appears on the Glance dashboard
(https://home.nori.lan) — both as an uptime-monitor dot
and as a grouped bookmark. The URL is derived from the
route name as ` https://<name>.nori.lan `; only metadata
lives here. Glance consumes the whole nori.lanRoutes
attrset and renders entries with ` dashboard != null `.

Routes that should NOT appear on the dashboard (e.g.
cross-host backend lanRoutes whose canonical entry-point
lives elsewhere, or services intentionally hidden from
the family-facing landing page) leave ` dashboard = null `.



*Type:*
null or (submodule)



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.dashboard.allowInsecure



Pass through to Glance’s monitor ` allow-insecure `
flag. Needed for routes whose backend cert isn’t
trusted by Glance’s HTTP client (e.g. Syncthing’s
WebUI redirect through Caddy’s internal CA).



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.dashboard.description



One-line blurb shown beneath the bookmark.
Function-oriented (“Movies, shows, music —
server-rendered”), not feature-list.



*Type:*
string

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.dashboard.group



Bookmark group. Order on the dashboard follows
the enum order, not declaration order — Consume
first (most-clicked), Admin last.



*Type:*
one of “Consume”, “Acquire”, “Personal”, “Projects”, “Admin”

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.dashboard.icon



Glance icon spec. Two prefixes:
si:<slug>  Simple Icons (most brand logos)
sh:<slug>  selfh.st icons (homelab brands
that Simple Icons doesn’t carry —
Calibre-web, Komga, Beszel, …)



*Type:*
string

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.dashboard.title



Brand / display name shown on the dashboard
(e.g. “Jellyfin”). The route name is appended
as a parenthetical for the monitor widget —
“Jellyfin (media)”.



*Type:*
string

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.exposeOnTailnet



Open the backend port on the tailnet, bypassing Caddy.
Default closed — Caddy on 443 is the canonical entry
point. Opt in only when something needs direct port
access (legacy clients, programmatic tools that don’t
handle Caddy’s internal CA).



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.forwardAuth



If set, gate this route via Authelia forward-auth at the
Caddy layer. Caddy asks Authelia’s ` /api/verify ` whether
the request’s session cookie is valid before forwarding;
if not, Authelia issues a 302 to the portal. The session
cookie at \*.nori.lan covers every forward-auth’d route —
log in once at https://auth.nori.lan, navigate to any
gated service without re-auth.

Used for services that don’t have native OIDC client
support (the \*arr stack, qBittorrent). Trade vs ` oidc `:

 - ` oidc `         — per-user identity inside the app;
   requires the app to support OIDC.
 - ` forwardAuth `  — uniform Authelia gate at Caddy; the
   app sees only the proxy, no per-user
   identity propagated. Works for any
   HTTP service.

` exemptPaths ` lets app-to-app API calls (Sonarr → Prowlarr,
Bazarr → Sonarr) bypass the auth check — those flows use
the app’s own API key, not the user session, and would
break under cookie-based forward-auth.

Authelia uptime becomes load-bearing: an Authelia outage
returns 502 for every forward-auth’d route. SSH-tunnel to
the backend port directly as the recovery escape hatch.
See modules/infra/access/authelia.nix for the upstream.



*Type:*
null or (submodule)



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.forwardAuth.exemptPaths



Path globs that bypass forward-auth. Format is
Caddy path-matcher syntax (` /api/* `, ` /api/v3/* `,
etc.). Default ` /api/* ` covers the \*arr stack and
most other apps that namespace their API.
Override per-service when the API path is
non-standard.



*Type:*
list of string



*Default:*

```nix
[
  "/api/*"
]
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.monitor



If set, auto-generate a Gatus endpoint probing the route’s
backend directly (bypasses Caddy, tests just the service).
Set to ` { } ` to use defaults; override ` path ` for non-/
health endpoints (e.g. ollama needs /api/tags).



*Type:*
null or (submodule)



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.monitor.conditions



Gatus condition expressions (see
[https://gatus.io/docs/conditions](https://gatus.io/docs/conditions)). Each must
hold for the probe to pass. Default checks HTTP
status; override for richer probes (header
match, body regex, response time).



*Type:*
list of string



*Default:*

```nix
[
  "[STATUS] == 200"
]
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.monitor.failureThreshold



Consecutive failed probes before Gatus fires an
alert. 3 absorbs transient blips without delaying
a real outage long.



*Type:*
signed integer



*Default:*

```nix
3
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.monitor.interval



How often Gatus runs the probe. systemd-style
duration string (` 60s `, ` 5m `, ` 1h `).



*Type:*
string



*Default:*

```nix
"60s"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.monitor.path



Path appended to the backend URL for the probe.



*Type:*
string



*Default:*

```nix
"/"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.noAuthReason



Set to a one-line reason when audience=family but neither
` oidc ` nor ` forwardAuth ` applies. Forces the operator to
name why; forces future readers to see it. Empty string
is invalid — set it or set one of the auth blocks.

Legitimate today:

 - radicale  — CalDAV/CardDAV clients can’t follow
   forward-auth redirects (htpasswd-only)
 - jellyfin  — mobile/TV clients bypass cookie-based
   forward-auth; native SSO plugin has
   sharp historical edges



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"CalDAV clients can't follow forward-auth redirects"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.oidc



If set, this route gets:

 - an Authelia OIDC client entry (assembled by
   modules/infra/access/authelia.nix from this declaration)
 - a sops secret named ` oidc-<name>-client-secret `
 - a sops env-file template named ` oidc-<name>-env `
   containing ` <secretEnvName>=<raw> `, ready to wire as
   systemd EnvironmentFile in the consuming module.

Set to ` null ` (default) for routes that don’t use SSO.
Mutually exclusive in practice with ` forwardAuth ` —
prefer ` oidc ` when the app supports it (per-user
identity), ` forwardAuth ` otherwise.



*Type:*
null or (submodule)



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.oidc.authorizationPolicy



Authelia access-control policy: ` one_factor `, ` two_factor `, or a custom-named policy.



*Type:*
string



*Default:*

```nix
"one_factor"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.oidc.clientName



Display name shown on Authelia consent screen.



*Type:*
string

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.oidc.redirectPath



Path appended to https://<name>.nori.lan to form
the OIDC redirect URI. Service-specific:
Open WebUI:  /oauth/oidc/callback
PocketBase:  /api/oauth2-redirect
Vaultwarden: /identity/connect/oidc-signin



*Type:*
string

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.oidc.scopes



OIDC scopes the client may request. Add
` offline_access ` for services that need refresh
tokens (e.g. Vaultwarden).



*Type:*
list of string



*Default:*

```nix
[
  "openid"
  "profile"
  "email"
  "groups"
]
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.oidc.secretEnvName



Env-var name written to the generated env file.
Defaults to OAUTH_CLIENT_SECRET (Open WebUI’s
convention). Override per service:
Vaultwarden: SSO_CLIENT_SECRET
Some others: OPENID_CLIENT_SECRET / OIDC_CLIENT_SECRET



*Type:*
string



*Default:*

```nix
"OAUTH_CLIENT_SECRET"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.port



Backend TCP port (validated 0-65535 at eval time).



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.runsOn



Name of the homelab host that runs this route’s backend
service (matches a ` nori.hosts.<name> ` registry key).
Generators resolve to:

 - ` 127.0.0.1 ` when ` runsOn ` matches the host evaluating
   the route (Caddy proxies to the local loopback)
 - ` config.nori.hosts.<runsOn>.tailnetIp ` otherwise
   (Caddy proxies cross-host over tailnet)

This is the mechanism that lets route declarations live
outside the ` mkIf cfg.enabled ` gate in each service module
— every host that imports the module sees the route in
` nori.lanRoutes `, but the backend resolves to the right
address per host. Encodes the pi-central entry plane
shape: pi’s Caddy serves every route; backends live on
whichever host fits (workhorse vs always-on vault).

Why location-policy is coupled with route registration
here, not extracted: location is implicit-from-import-site
for host-confined services; it becomes explicit only when
a service crosses machines, which IS the act of declaring
an HTTP route. The three concerns (service / route /
location) degenerate at host-local and unify at
cross-machine. See
` docs/reports/2026-06-17-runson-coupling-analysis.md `
for the full analysis + algebraic forward-extension
(failover / loadbalance / sequential).



*Type:*
string



*Example:*

```nix
"aurora"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.scheme



Backend scheme. Most services run plain HTTP; Caddy terminates TLS.



*Type:*
one of “http”, “https”



*Default:*

```nix
"http"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.upstreamHostHeader



Optional rewrite of the ` Host ` request header before
forwarding to the upstream. By default Caddy forwards
the original Host (the public ` <n>.nori.lan `), which
most backends accept. Set this when the backend
validates Host as a DNS-rebinding defence and rejects
anything other than its bind address — Hermes’ dashboard
is the canonical case: it binds to 127.0.0.1:9119 and
rejects requests whose Host header isn’t a loopback name.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"127.0.0.1:9119"
```

*Declared by:*
 - `modules/infra/networking`



## nori.lanRoutes.<name>.upstreamOriginHeader



Optional rewrite of the ` Origin ` header before forwarding
WebSocket / fetch upgrade requests. Paired companion to
` upstreamHostHeader `: apps that validate ` Host ` against
their bind address as a DNS-rebinding defence usually
run the same check on the WebSocket ` Origin ` field too
(since FastAPI HTTP middleware doesn’t fire for WS
upgrades, the check is re-implemented at the WS handler).
Hermes’ embedded chat PTY is the canonical case —
without this rewrite, the chat WebSocket upgrade refuses
with ` origin_mismatch origin=https://… bound=127.0.0.1 `.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"http://127.0.0.1:9119"
```

*Declared by:*
 - `modules/infra/networking`


