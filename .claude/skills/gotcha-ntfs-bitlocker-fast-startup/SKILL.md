---
name: gotcha-ntfs-bitlocker-fast-startup
description: USE WHEN adding `fileSystems."<path>".fsType = "ntfs3"` for a Windows partition and mount fails with "wrong fs type" or "volume is dirty" — two independent causes. (1) BitLocker enabled (Win11 default); blkid reports `crypto_LUKS` not `ntfs`. (2) Fast Startup leaves dirty journal; ntfs3 refuses to mount even read-only. Boot Windows + Restart (not Shutdown), or disable Fast Startup.
---

# NTFS read-only mounts: BitLocker + Fast Startup

Two independent failure modes when adding a `fileSystems."<path>".fsType = "ntfs3"` entry pointing at a Windows partition:

1. **BitLocker.** Win11 enables device encryption by default on supported hardware. `blkid` on a BitLocker-encrypted partition reports `crypto_LUKS` or no `TYPE` rather than `ntfs`. The `ntfs3` driver can't read encrypted partitions; mount fails with `wrong fs type`. Verify before declaring the mount: `blkid /dev/disk/by-id/...-part3` should report `TYPE="ntfs"`. If not, suspend BitLocker from Windows or use `dislocker`.

2. **Fast Startup dirty journal.** Win11's default Shutdown is actually a hibernation-to-disk; the NTFS volume is left with a dirty journal flag. `ntfs3` refuses to mount dirty volumes even read-only as of kernel 6.18. Symptom on first boot: mount fails with "wrong fs type" or "volume is dirty". Fix: boot Windows, choose Restart (not Shutdown) which forces a clean shutdown; OR uncheck "Turn on fast startup" in Power options for a permanent fix.

See `docs/runbooks/inspect-windows-drive.md` for the full procedure.
