# Inspect the Windows drive (MP510) from NixOS

The Corsair Force MP510 is the Windows NVMe and is **never** written
to from NixOS (DESIGN.md hard rule). This runbook covers the
read-only access path.

## Default state

`/mnt/windows-ro` is a read-only mount of the Windows C: partition,
declared in `hosts/nori-station/windows-mount.nix`. It comes up at
boot via `fileSystems.<name>` and survives reboots. The kernel
`ntfs3` driver enforces read-only at the syscall layer — no path
through this mount can mutate the partition.

```
$ ls /mnt/windows-ro
'$Recycle.Bin'  'Documents and Settings'  PerfLogs  Program Files
'Program Files (x86)'  ProgramData  Recovery  Users  Windows ...
```

Files appear owned `nori:users` (mount-time `uid=1000,gid=100,umask=0022`)
so the desktop session reads them without sudo. Thunar shows the
location in its sidebar; drag-drop copies into `/mnt/media/...` work
as a normal file-manager operation.

## Verify partition layout (before edits)

```
sudo blkid /dev/disk/by-id/nvme-Force_MP510_2031826300012953207B-part*
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL \
  /dev/disk/by-id/nvme-Force_MP510_2031826300012953207B
```

Expected: part1 = vfat ESP, part2 = MSR (no FS), **part3 = ntfs C:
~893 GB, label "Corsair MP510"**, part4 = ntfs WinRE ~505 MB. If the
layout differs (Windows reinstall, drive cloned, BitLocker enabled),
do not edit `windows-mount.nix` until the new shape is understood.

**BitLocker check:** if `blkid` reports `TYPE=BitLocker` or no
`TYPE=` at all on part3, BitLocker is on. Read-only mount via ntfs3
won't work. Either suspend BitLocker from Windows (`manage-bde -off
C:`, wait for decryption) or use `dislocker` for read-only access
through a virtual block device — separate decision, not this mount.

## If the mount fails at boot

Symptom: `journalctl -u systemd-fsck@... --boot` or
`mount /mnt/windows-ro` reports `wrong fs type, bad option, bad
superblock` or `volume is dirty`.

Most common cause: **Windows shut down via Fast Startup**. Win11
defaults Fast Startup to on; on shutdown, Windows hibernates the
kernel to a hiberfil.sys and leaves the NTFS journal in a "dirty"
state. ntfs3 refuses to mount dirty volumes even read-only as of
kernel 6.18.

Fix:

1. Boot Windows from the firmware menu.
2. From the Start menu, choose **Restart** (not Shutdown). Restart
   bypasses Fast Startup and shuts down cleanly.
3. After Windows finishes its shutdown sequence, power off and boot
   back into NixOS.
4. The mount succeeds at next boot.

Permanent fix (optional): in Windows, Settings → System → Power →
"Choose what the power buttons do" → uncheck "Turn on fast startup".
After this, Shutdown is also a clean shutdown.

## Imperative override (drive offline / temporary disable)

If the drive is removed or the mount needs temporarily-disabled,
`nofail` already keeps boot from blocking. To suppress the
mount-failed unit entirely on a single boot:

```
sudo systemctl mask mnt-windows\\x2dro.mount
# ... do work ...
sudo systemctl unmask mnt-windows\\x2dro.mount
sudo systemctl start mnt-windows\\x2dro.mount
```

Don't edit `windows-mount.nix` for this — `nofail` handles missing
hardware gracefully on its own.

## What's safe

- Read any file via `cat`, `cp`, file managers, etc.
- Copy off into `/mnt/media/projects/_from-mp510/` or anywhere else
  on btrfs.
- Inspect partition tables, file system metadata, NTFS attributes.

## What's not safe (and not possible)

- Writes — kernel rejects them. `touch /mnt/windows-ro/x` returns
  `Read-only file system`.
- Anything that changes BitLocker state, partition tables, or
  filesystem journals on the MP510.
- Switching the mount to read-write. That's a different decision
  (separate from this runbook); do not "just try" `rw` to see what
  happens.
