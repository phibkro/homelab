{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Syncthing — peer-to-peer file sync over tailnet. Replaces "manually
  # rsync between machines" + "stuff in Samba I might want on my laptop
  # too." Each device runs its own Syncthing; folders are negotiated
  # via web UI; sync happens directly between peers (no central server).
  #
  # Runs as user `nori` here so synced folders live in /home/nori (or
  # wherever the user points each shared folder). Per-user state at
  # /home/nori/.config/syncthing.
  #
  # Ports:
  #   8384  WebUI (localhost-only by default; Caddy proxies via
  #         sync.nori.lan)
  #   22000 TCP/UDP peer protocol — opened on tailscale0 below so
  #         other tailnet devices can connect directly
  #   21027 UDP local discovery — LAN only, default-deny tailnet OK
  #
  # First-run:
  #   1. Visit https://sync.nori.lan — Syncthing web UI shows the
  #      device's ID. No login required by default; access is gated by
  #      tailnet trust + Caddy. Optionally set Settings → GUI → user/pass.
  #   2. On other devices (Mac, phone, future laptop): install
  #      Syncthing (brew install syncthing on Mac), open its web UI,
  #      "Add Remote Device" using nori-station's device ID.
  #   3. Share folders by pointing both ends at the same logical
  #      folder ID. E.g. ~/notes shared between Mac and nori-station
  #      lives at /home/nori/notes on this side.
  services.syncthing = {
    enable = true;
    user = "nori";
    group = "users";
    dataDir = "/home/nori"; # per-folder paths set in the WebUI
    configDir = "/home/nori/.config/syncthing";
    openDefaultPorts = false; # we handle ports below explicitly
    overrideDevices = false; # let WebUI manage device list
    overrideFolders = false; # let WebUI manage folder list
    settings.gui = {
      address = "127.0.0.1:8384";
      # No `user`/`password` set here — tailnet trust + Caddy is the
      # gate. Set them in the WebUI if you want a second factor.
    };
  };

  # Peer protocol on tailscale0 only. Default-deny on the WAN-facing
  # interfaces stays in effect; this only opens 22000 between tailnet
  # devices.
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [
      22000
      21027
    ];
  };

  # Default-deny FS hardening — relaxed for /home since Syncthing
  # legitimately reaches into the user's home dir to sync arbitrary
  # paths. `protectHome = null` skips the ProtectHome setting entirely
  # (rather than forcing it false), preserving the upstream NixOS
  # module's value — explicit trade documented at modules/lib/harden.nix.
  nori.harden.syncthing.protectHome = null;

  nori.lanRoutes.sync = {
    port = 8384;
    monitor = { };
  };

  # Syncthing's pairing state + folder config + index DB live at
  # /home/nori/.config/syncthing — already captured by the
  # `user-data` repo (which backs up /home). No separate
  # nori.backups.syncthing repo needed.
  nori.backups.syncthing.skip = "Config + index at /home/nori/.config/syncthing — already covered by the user-data repo (/home).";
}
