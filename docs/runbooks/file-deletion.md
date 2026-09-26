# Single file deletion

**RTO**: <15 min. btrbk snapshots are local + frequent; restore is a copy.

## Symptom

A file or directory got deleted (or overwritten with garbage) and you want it back.

## Find the snapshot

Snapshots live next to the data on the same btrfs filesystem. Workstation root
snapshots keep one week locally; weekly and monthly copies up to six months old
are on the IronWolf. Both are read-only subvolumes with the same layout.

| Subvolume | Last 7 days | Weekly/monthly (IronWolf) |
|---|---|---|
| `/home` | `/.snapshots/home.<timestamp>/` | `/mnt/media/.snapshots/workstation-root/home.<timestamp>/` |
| `/srv/share` | `/.snapshots/share.<timestamp>/` | `/mnt/media/.snapshots/workstation-root/share.<timestamp>/` |
| `/srv/nori` | `/.snapshots/nori.<timestamp>/` | `/mnt/media/.snapshots/workstation-root/nori.<timestamp>/` |
| `/var/lib` | `/.snapshots/lib.<timestamp>/` | `/mnt/media/.snapshots/workstation-root/lib.<timestamp>/` |
| `/mnt/media/photos` | `/mnt/media/.snapshots/photos.<timestamp>/` | — |
| `/mnt/media/home-videos` | `/mnt/media/.snapshots/home-videos.<timestamp>/` | — |
| `/mnt/media/projects` | `/mnt/media/.snapshots/projects.<timestamp>/` | — |
| `/mnt/media/archive` | `/mnt/media/.snapshots/archive.<timestamp>/` | — |

```bash
# List snapshots covering, e.g. /home
sudo ls -1d /.snapshots/home.* /mnt/media/.snapshots/workstation-root/home.*
```

Pick the most recent snapshot whose timestamp is **before** the deletion.

## Copy the file out

```bash
# Read-only file copy from snapshot to live tree
sudo cp -a /.snapshots/home.20260426T0300/nori/notes.md /home/nori/notes.md
```

Or whole subtree:

```bash
sudo cp -aR /.snapshots/home.20260426T0300/nori/work-2025/ /home/nori/work-2025/
```

For files owned by service users, preserve ownership with `cp -a` (which keeps owner/group/mtime). After the restore:

```bash
sudo chown -R <user>:<group> /home/<user>/<path>
```

(only if the snapshot's ownership is wrong for some reason)

## If the snapshot doesn't have it either

The file was deleted before the most recent snapshot. Walk back through older
snapshots, then the IronWolf history:

```bash
sudo ls -1d /.snapshots/home.* | sort  # oldest → newest, last 7 days
sudo ls -1d /mnt/media/.snapshots/workstation-root/home.* | sort  # weekly/monthly
```

If no snapshot covers it, the next layer is restic (whichever backup ran most recently before the deletion).

## Restoring from restic instead

```bash
# List snapshots
sudo restic -r /mnt/backup/user-data \
  --password-file /run/secrets/restic-password \
  snapshots

# Restore one file from a specific snapshot
sudo restic -r /mnt/backup/user-data \
  --password-file /run/secrets/restic-password \
  restore <snapshot-id> --target /tmp/restore --include /home/nori/notes.md
```

Then move from `/tmp/restore/...` to its real path.

The quarterly automated drill uses declared bounded samples because the full
user-data snapshot is larger than the workstation root filesystem. See the
[September 21 user-data drill](../archive/reports/2026-09-21-user-data-recovery-drill.md).
