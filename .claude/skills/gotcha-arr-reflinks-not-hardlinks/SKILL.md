---
name: gotcha-arr-reflinks-not-hardlinks
description: USE WHEN seeing two-inode different-uid file pairs in qBittorrent → *arr library (Sonarr/Radarr/Lidarr) on btrfs and considering dedup — they're already reflinks (shared extents, zero extra bytes); a "dedup" script frees nothing (verified 1.6 TiB → 0 bytes saved). Fix going forward: `serviceConfig.UMask = "0002"` for qBittorrent so `link(2)` succeeds and real hardlinks land.
---

# *arr "copies" on btrfs are reflinks, not hardlinks — and look identical to plain copies

The *arr stack (Sonarr/Radarr/Lidarr) imports from qBittorrent's complete dir into its library subvolume. The intended path on btrfs is hardlink-on-import (same inode, no extra bytes). What actually happens: `link(2)` fails silently due to a kernel security check, and *arr falls back to `cp --reflink=auto` (FICLONE ioctl). On btrfs the reflink occupies zero additional bytes (shared extents) — but `stat` reports two distinct inodes, often with different `uid`s. **This looks identical to a plain copy.** Hit 2026-05-15.

The chain:

1. `fs.protected_hardlinks = 1` (kernel default) — `link(2)` only succeeds when the caller owns the source file **or** has read+write on it.
2. qBittorrent writes finished files with default umask `0022` → mode `0644`, owned by `qbittorrent:media`.
3. *arr (e.g. radarr, uid 275) is in group `media` (read), but group bits are `r--` (no write).
4. Kernel returns EPERM on `link()` → *arr's fallback chain (`useHardlinks` → `useReflinks` → copy) silently advances one step.
5. On btrfs, FICLONE succeeds → reflink. On any other FS, plain copy.

**Diagnostics:**

- Battle Royale's library file showed `dev=64 ino=5518 uid=275`; the seeding copy showed `dev=64 ino=5513 uid=989`. The smoking gun for "this was a fresh `open(O_CREAT)+write`, not `link()`": `uid` differs. A real hardlink preserves the source's `uid`.
- To tell reflink vs plain copy: `btrfs filesystem du <file>`. Reflink → `Exclusive: 0.00B, Set shared: <full size>`. Plain copy → `Exclusive: <full size>, Set shared: 0.00B`. Hardlink — `btrfs fi du` reports the file with `nlink>1` once.
- `find <dir> -links 1` is **not** an orphan-detection heuristic in this setup — reflinks look like singletons.

**Fix going forward** — `systemd.services.qbittorrent.serviceConfig.UMask = "0002";` (live in `modules/services/arr/qbittorrent.nix`). Files land mode `0664`; `media`-group members satisfy the kernel write-check; `link()` succeeds; library entries become true hardlinks (nlink≥2, same uid as source).

**The trap to avoid** — don't try to "free space by deduping" the library when you see two-inode, different-uid pairs. If `btrfs fi du` says `Exclusive: 0`, the extents are already shared and there's nothing to recover. A script that replaces reflinks with hardlinks frees zero bytes (verified 2026-05-15: 1855 file ops, 1.6 TiB of apparent size relinked, `df` unchanged). The disk-pressure causes are elsewhere — see `docs/runbooks/storage-full.md`.
