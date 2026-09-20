{ pkgs, ... }:

{
  /*
    Waydroid — Android (LineageOS) in an LXC container, integrated with
    the Wayland (Hyprland) session. Runs Android-only apps (Symfonium, and
    anything else gated behind Google-Play licensing) at near-native speed
    — a container against the host kernel, not a full QEMU emulator. The
    module wires the `binder_linux` device + the waydroid-container service.

    Runtime setup AFTER this lands (not declarable — Android image state):
      sudo waydroid init -s GAPPS        # LineageOS image WITH Google Play
      # NVIDIA (RTX 5060 Ti) has no Waydroid GL path → force software render:
      #   waydroid prop set ro.hardware.gralloc default
      # then device-certify the GSF id at google.com/android/uncertified,
      # sign into Google, install the app. See the runbook.
  */
  virtualisation.waydroid.enable = true;
  # The module defaults to pkgs.waydroid (iptables-LEGACY net script) because
  # networking.nftables.enable is false here. This kernel has no legacy
  # `ip_tables` module, while the host firewall already uses the nf_tables
  # backend through iptables-nft. Use Waydroid's nftables network script so its
  # isolated NAT and forwarding table coexists with the host firewall.
  virtualisation.waydroid.package = pkgs.waydroid-nftables;

  # Let the Waydroid Android container reach this host's Samba over its bridge,
  # so Symfonium reads the local music library via SMB (→ 192.168.240.1, share
  # `media`, path library/music). Android's FUSE storage can't cross a
  # bind-mount of the library into /storage, so SMB over the bridge is the path.
  # Scoped to waydroid0; Samba's hosts-allow gates the 240.x subnet (samba.nix).
  networking.firewall.interfaces.waydroid0.allowedTCPPorts = [ 445 ];

}
