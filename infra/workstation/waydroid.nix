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
  # networking.nftables.enable is false here. But this kernel ships no legacy
  # `ip_tables` module — the host firewall already runs on the nf_tables backend
  # (iptables-nft). So force the nftables waydroid variant, whose net script uses
  # `nft` directly; its NAT/forward rules live in their own table and coexist with
  # the iptables-nft firewall. Avoids flipping the whole host to nftables.enable.
  #
  # ...and patch its dnsmasq to DHCP-only (`--port=0`): Blocky already wildcard-
  # binds 0.0.0.0:53 on this host, so waydroid's own dnsmasq can't grab
  # 192.168.240.1:53 ("address already in use"). Dropping dnsmasq's DNS frees
  # that bind; Blocky then answers the Android container on the bridge IP (verified
  # it serves the 240.x subnet), so DHCP just hands out 240.1 as the resolver via
  # option 6. Android gets DNS — with ad-blocking — and no host DNS is disturbed.
  virtualisation.waydroid.package = pkgs.waydroid-nftables.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      net="$out/lib/waydroid/data/scripts/.waydroid-net.sh-wrapped"
      substituteInPlace "$net" \
        --replace-fail \
          '--listen-address ''${LXC_ADDR} --dhcp-range ''${LXC_DHCP_RANGE}' \
          '--port=0 --dhcp-option=6,''${LXC_ADDR} --listen-address ''${LXC_ADDR} --dhcp-range ''${LXC_DHCP_RANGE}'
    '';
  });

  # Let the Waydroid Android container reach this host's Samba over its bridge,
  # so Symfonium reads the local music library via SMB (→ 192.168.240.1, share
  # `media`, path library/music). Android's FUSE storage can't cross a
  # bind-mount of the library into /storage, so SMB over the bridge is the path.
  # Scoped to waydroid0; Samba's hosts-allow gates the 240.x subnet (samba.nix).
  networking.firewall.interfaces.waydroid0.allowedTCPPorts = [ 445 ];

}
