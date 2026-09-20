---
summary: Move the dashboard to Pi and eight SSD-local services to Adelie while workstation keeps media and backup storage.
date: 2026-09-20
status: frozen; source implementation authorized; activation operator-gated
owner: operator
---

# Three-host service migration

## Goal

The homelab uses three active machines with explicit duties:

| Host | Duty |
|---|---|
| Pi | HTTP, DNS, identity, monitoring, alerts, and Glance entry plane |
| Adelie | SSD-local applications, databases, and Nix cache server |
| Workstation | Desktop, media compute, IronWolf data, and OneTouch backup target |

IronWolf and OneTouch stay attached to workstation. No media workload moves in this change.

## Workload cutover

Glance moves from workstation to Pi.

These service realizations move from workstation to Adelie:

- `attic`
- `filmder`
- `grafana`
- `heim`
- `miniflux`
- `radicale`
- `stremio`
- `vaultwarden`

Attic publication is separate from the Attic server. Each NixOS workhorse publishes its own store to the Adelie server.

Adelie also gets the existing log-forwarder and alert-publisher agents. These are host-local agents, not relocated singletons.

## Placement boundary

Inventory and workload manifests are the only placement source.

- Pi selects Glance through its `entry-plane` tag.
- Adelie has an `application-service-host` tag.
- The eight application manifests select that tag.
- Media and portable-disk workloads remain selected by workstation tags.
- Caddy routes each service to the host selected by inventory.

No handwritten route or second host list can override this placement.

## Secret boundary

Adelie gets one host-specific encrypted runtime file. It contains only values
that Adelie consumes exclusively:

- Attic server credentials
- Filmder TMDB token
- Grafana and Miniflux secrets
- Raw OIDC client values for Miniflux and Vaultwarden
- A unique Restic password and Adelie backup SSH key

The shared runtime file is the single source for the Attic push token and ntfy
alert topic consumed by both NixOS hosts. The existing network file remains the
single source for the shared Akkar Wi-Fi credential.

Workstation keeps only credentials consumed exclusively by remaining
workstation services.

The Adelie file is encrypted to the operator identities and Adelie's verified host identity. It is not encrypted to the workstation host identity.

## State and backup boundary

Before service cutover, copy or restore these authoritative states:

| Service | Authoritative state |
|---|---|
| Miniflux | PostgreSQL logical dump |
| Radicale | `/var/lib/radicale` |
| Stremio | `/var/lib/stremio` |
| Vaultwarden | `/var/lib/vaultwarden` and its consistent SQLite snapshot |

Attic chunks are re-derivable. A fresh server can reuse the existing signing
key and token authority. Copying its cache is optional. Grafana is provisioned
from the flake; its SQLite database contains only disposable session state.
Filmder and Heim rebuild from their public source repositories.

Adelie writes encrypted Restic backups through a dedicated, restricted SFTP account on workstation. The account is chrooted to Adelie's OneTouch namespace. Pi uses a separate account and namespace.

## Per-service gates

Keep Pi routes on workstation while Adelie is prepared. The first Adelie
activation creates users, databases, and state directories. Root-owned
`ConditionPathExists` gates keep all four writable targets stopped until their
authoritative state arrives.

| Service | Source gate | Transfer | Target gate |
|---|---|---|---|
| Attic | Keep workstation server live | No cache copy; reuse the encrypted signing and token authority | Start `atticd`, run cache bootstrap, and push one path |
| Filmder | None | No state copy; build as the unprivileged credential-free builder | Confirm the bundle has no TMDB bearer, then return HTTP 200 through the runtime proxy |
| Grafana | None | No state copy | Return `/api/health` locally with provisioned dashboards |
| Heim | None | No state copy | Complete the source build and return HTTP 200 locally |
| Miniflux | Stop workstation Miniflux after a fresh PostgreSQL logical dump | Copy the dump, then restore it into Adelie's local `miniflux` database | Compare user and feed counts, then pass `/healthcheck` |
| Radicale | Stop workstation Radicale | Copy `/var/lib/radicale` and set Adelie's `radicale` ownership | Authenticate and read one existing calendar and contact |
| Stremio | Stop workstation Stremio | Copy `/var/lib/stremio` and set Adelie's `stremio` ownership | Confirm the preserved server identity and return HTTP 200 |
| Vaultwarden | Stop workstation Vaultwarden after a consistent SQLite snapshot | Copy `/var/lib/vaultwarden` and `/var/backup/vaultwarden`, then set Adelie's `vaultwarden` ownership | Sign in, open one item, and pass `/alive` |

For each stateful target, create
`/var/lib/nori/migration/<service>-ready` only after its transfer or restore
passes. Then start and verify that service. The gate is absent on first
activation, so source and target cannot start together by default.

After a source service stops, do not restart it unless that service rolls back.
Do not expose an empty target through Pi.

Glance has no state transfer. The Pi role renders configuration from inventory,
validates it with Glance's `config:print`, starts the container, and requires a
local HTTP 200 before convergence succeeds.

The receiver account does not exist until the final workstation activation.
A separate `/var/lib/nori/migration/backups-ready` condition keeps all Adelie
backup jobs stopped. Create it only after the receiver activation and transport
check. Keep all preserved source state until one target backup and its metadata
check complete.

## Cutover sequence

1. Build the Adelie and workstation NixOS closures, then run the Pi checks.
2. Generate Pi inventory and validate every route target.
3. Verify OneTouch is mounted on workstation.
4. Activate Adelie with all four stateful gate files absent while Pi still
   routes to workstation.
5. Run each per-service source and transfer gate.
6. Create one service gate, start its Adelie unit, and pass its target gate.
7. Repeat step 6 for each remaining stateful service.
8. Apply the Pi role and verify Glance and all public routes.
9. Activate workstation to remove old singleton units and add the restricted
   Adelie backup receiver.
10. Verify backup transport, create `backups-ready`, and run one backup for each
    Adelie repository.
11. Inspect all four repositories on OneTouch.
12. Keep preserved workstation state until the acceptance checks complete.

Do not remove source state during cutover. Do not run both writable copies of a
service at the same time.

## Rollback

Rollback is a whole-cohort operation. The previous workstation generation and
Pi inventory both contain the complete pre-migration placement, so a selective
generation rollback would start duplicate writable services.

1. Stop all eight Adelie service units.
2. Remove all four Adelie stateful ready gates and `backups-ready`.
3. Runtime-mask all nine pre-migration workstation source units.
4. Restore the previous workstation generation while those units stay masked.
5. Restore every write made on the four Adelie stateful targets after cutover.
6. Unmask and start all nine workstation source units.
7. Restore the complete prior Pi inventory. This removes Pi Glance and repoints
   all routes as one operation.
8. Verify every public route through Pi.

Never overwrite a newer writable copy with older preserved state. Never restore
only one source unit from the pre-migration generation.


## Acceptance

The change is complete when:

1. Inventory realizes Glance only on Pi.
2. Inventory realizes the eight named services only on Adelie.
3. Workstation realizes none of those nine singleton services.
4. Attic publishers exist on both NixOS workhorses, but the Attic server exists only on Adelie.
5. Adelie can decrypt only its host runtime and the explicit shared runtime and network files.
6. Workstation cannot decrypt Adelie's runtime file through its host identity.
7. Adelie's authoritative state has explicit backups to its OneTouch SFTP namespace.
8. Generated Caddy and Gatus targets use Pi for Glance and Adelie's tailnet address for the eight services.
9. Pi configuration passes its checks, and both NixOS closures build from committed source.
10. Each moved service passes a local health check and its public HTTPS journey.
11. One Adelie Restic backup completes and its repository is visible on OneTouch.
12. IronWolf, OneTouch, `/mnt/media`, and `/mnt/backup` remain absent from Adelie's mounts.

## Excluded

- Moving any IronWolf dataset or media service
- Running media services across a remote IronWolf mount
- Moving Jellyseerr, Prowlarr, or Recyclarr
- Enabling Adelie's GPU workloads
- Repartitioning any disk
- Removing preserved workstation state before acceptance
