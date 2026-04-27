_: {
  # libvirtd + virt-manager — general VM use (testing NixOS configs,
  # ephemeral environments, isolated sandboxes, occasional Windows VMs
  # without PCIe passthrough). Equivalent of UTM on the Mac, native to
  # Linux. Phase 7 item 10.
  #
  # No PCIe passthrough (VFIO) setup here — separate decision tied to
  # a concrete use case. The MP510 read-only mount in
  # ../../hosts/nori-station/windows-mount.nix covers the only
  # currently-pulling Windows-data workflow.

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      swtpm.enable = true; # TPM emulation for Windows guests
      runAsRoot = false;
      # OVMF (UEFI firmware) ships with QEMU by default in current
      # nixpkgs — the libvirtd.qemu.ovmf submodule was removed.
    };
  };

  programs.virt-manager.enable = true;

  # NixOS module list-merging means this appends to the user's groups
  # set in modules/common/users.nix; no conflict.
  users.users.nori.extraGroups = [ "libvirtd" ];
}
