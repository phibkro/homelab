# Hindsight memory archive

Hindsight was removed from the workstation (2026-10-11). The NixOS units, the
tunnel route, the inventory entry and the client bindings are gone. Only the
memories remain, as an inactive archive.

Still pending (external effects, each needs operator approval): `just pi::deploy`
for the Pi entry plane, and `bun run deploy` in `src/infra/cloudflare` to delete
the Cloudflare resources (OriginDns, Portal, PortalDns, PortalPolicy, Server,
ServerPolicy). Until then they exist in Cloudflare and in the Alchemy state.

The embedded PostgreSQL 18 instance is at
`/home/nori/.pg0/instances/hindsight-embed-chatlog-pilot` (about 170 MB with its
binaries in `/home/nori/.pg0/installation`, version 18.1.0). It was shut down
cleanly (no `postmaster.pid`). Do not delete or move `/home/nori/.pg0` unless
you intend to discard the memories. Reopening the data needs PostgreSQL 18.

Removed on 2026-10-11: the uv package cache `/home/nori/.cache/hindsight-uv`, the
model cache `/home/nori/.cache/hindsight-xdg`, the uv tool directory
`/home/nori/.local/share/hindsight`, and the user unit
`~/.config/systemd/user/chatlog-hindsight.service`.

The Restic `user-data` job includes `/home` and does not exclude `.pg0`, so the
source policy covers this database. `src/inventory/recovery-evidence.nix` also
records evidence for the `user-data` job. The inventory's workstation root
snapshot policy is separate; actual backup freshness and restoreability for this
specific PostgreSQL instance were not verified.
