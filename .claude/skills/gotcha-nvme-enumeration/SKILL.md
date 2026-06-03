---
name: gotcha-nvme-enumeration
description: USE WHEN editing disko configs, writing destructive disk commands (dd / wipefs / parted / mkfs), or referencing `/dev/nvme*` anywhere — NVMe enumeration swaps across reboots; the WD Black SN750 (NixOS) and Corsair Force MP510 (Windows) swap slots, a re-run of the original disko config WOULD WIPE WINDOWS. Use `/dev/disk/by-id/<model>-<serial>` paths only.
---

# NVMe `/dev` enumeration is unstable

Same physical drive can appear at different `/dev/nvmeNn1` paths between boots. On workstation: at install time the WD Black SN750 was `/dev/nvme0n1` and the Corsair Force MP510 (Windows) was `/dev/nvme1n1`. After the first reboot they swapped — SN750 is now `nvme1n1`, MP510 is now `nvme0n1`.

**Implication**: never reference `/dev/nvmeN` directly in disko configs or destructive commands. Use `/dev/disk/by-id/<model>-<serial>` paths. They follow the hardware. The disko configs in this repo are by-id-pinned for this reason — a re-run with the original `/dev/nvme0n1` config today would wipe Windows.

Re-derive the current mapping any time you're unsure: `ls /dev/disk/by-id/`.

**Never touch the Windows drive** (Corsair Force MP510, by-id `nvme-Force_MP510_2031826300012953207B`). Disambiguate by **model string and by-id**, never by `/dev/nvmeN`.
