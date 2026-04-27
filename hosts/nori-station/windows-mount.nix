_: {
  # MP510 (Windows NVMe) read-only mount. Lets the desktop session
  # browse / copy off the Windows partition without booting Windows.
  # Stays within DESIGN.md's "never touch the Windows drive" hard rule:
  # `ro` means the kernel rejects writes — there is no path through
  # which this mount can mutate the partition. Phase 7 item 1.
  #
  # by-id path is the only safe identifier here — /dev/nvmeN
  # enumeration swaps across reboots (see docs/gotchas.md). part3 is
  # the Windows C: NTFS partition (893.6 GB, label "Corsair MP510");
  # part1=ESP, part2=MSR, part4=WinRE.
  #
  # If Windows shut down via Fast Startup (Win11 default), the NTFS
  # volume carries a dirty journal flag and ntfs3 will refuse the
  # mount. Recovery: boot Windows, choose Restart (not Shutdown), let
  # it shut down cleanly, then this mount succeeds at next boot. See
  # docs/runbooks/inspect-windows-drive.md.

  boot.supportedFilesystems = [ "ntfs" ];

  fileSystems."/mnt/windows-ro" = {
    device = "/dev/disk/by-id/nvme-Force_MP510_2031826300012953207B-part3";
    fsType = "ntfs3";
    options = [
      "ro" # read-only at the kernel; the in-tree ntfs3 driver
      "nofail" # missing partition doesn't block boot
      "uid=1000" # nori
      "gid=100" # users
      "umask=0022" # rwxr-xr-x dirs, rw-r--r-- files (visible to nori)
    ];
  };
}
