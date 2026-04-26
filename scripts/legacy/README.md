# Legacy scripts

Pre-Phase-5 Ubuntu-era scripts. The paths and assumptions inside these
scripts (`/home/nori/services`, `/home/nori/.ollama`, `/dev/sdaN`, exfat
backup target, etc.) reflect the old Ubuntu host that nori-station
replaced. They will not run correctly on NixOS.

Kept here as forensics / reference. Don't run them.

| Script | Purpose | Replaced by |
|---|---|---|
| `backup.sh` | Phase-1 rsync of service state to OneTouch exfat | `modules/services/backup-restic.nix` (real backup pipeline; restic to `/mnt/backup`) |
| `dd-ubuntu.sh` | Phase-1 raw disk image of Ubuntu root | disko-from-day-zero (`hosts/nori-station/disko.nix`) makes the whole host re-derivable from the flake |
| `partclone-ubuntu.sh` | Phase-1 partclone image of Ubuntu root partitions | same as above |

Anything you'd reach for these scripts to do today, do declaratively in
the flake instead.
