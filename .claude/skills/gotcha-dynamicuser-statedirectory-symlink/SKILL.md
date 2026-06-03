---
name: gotcha-dynamicuser-statedirectory-symlink
description: USE WHEN configuring restic backups (or any tool that respects symlinks) for a DynamicUser service (open-webui, ollama, ntfy-sh, gatus, beszel-hub, jellyseerr, prowlarr, glance) — `/var/lib/<svc>` is a symlink, actual data at `/var/lib/private/<svc>`. restic stores symlinks AS symlinks → 0-byte snapshot. Use `/var/lib/private/<svc>` paths directly.
---

# DynamicUser StateDirectory: `/var/lib/<n>` is a symlink, not the data

Services declared with `DynamicUser = yes` in their NixOS module (open-webui, jellyseerr, prowlarr, ntfy-sh, beszel-hub, gatus, glance, ollama) have systemd put the actual state at `/var/lib/private/<n>` and create a SYMLINK at `/var/lib/<n>` pointing to it. Looks transparent until restic.

**restic stores symlinks AS symlinks by default** — no `--follow-symlinks` flag exists in restic. Pointing `services.restic.backups.<n>.paths = [ "/var/lib/<n>" ]` at a DynamicUser service produces a snapshot containing just the symlink record (3 files, 0 bytes) instead of the actual data.

We hit this in production: `restic stats latest` on the open-webui repo showed 0B / 3 files for months before anyone noticed, despite daily backups running successfully.

**Fix**: declare paths as `/var/lib/private/<n>` directly for DynamicUser services. The `nori.backups.<n>` abstraction (modules/effects/backup.nix) is the call site; per-module backup declarations encode the right path. Bash file ops (sqlite3, cp, etc.) in `prepareCommand` blocks DO follow symlinks, so prepareCommand source paths can use either path.

```nix
# Wrong (silent 0-byte snapshot for DynamicUser services):
nori.backups.open-webui.paths = [ "/var/lib/open-webui" ];

# Right:
nori.backups.open-webui.paths = [ "/var/lib/private/open-webui" ];
```

Verify a snapshot is real: `sudo nix shell nixpkgs#restic --command restic -r /mnt/backup/<n> --password-file /run/secrets/restic-password stats latest`. Total size in bytes should match the actual data.

See also [[gotcha-dynamicuser-ownership]] for the broader DynamicUser ownership trickery.
