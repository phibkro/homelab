{ config, lib, pkgs, ... }:

# rust-motd config for laptop hosts (pavilion, aurora). Renders a
# polar-codename banner + live system specs into /var/lib/rust-motd/
# motd on demand. NO automatic timer — regenerate manually with:
#
#     sudo systemctl start rust-motd.service
#
# Result lands at /var/lib/rust-motd/motd which sshd's PrintMotd
# picks up on each interactive login (path comes via
# users.motdFile set by enableMotdInSSHD).
#
# Only enabled when imported, so non-laptop hosts that don't import
# this fall back to the static codename banner in
# modules/common/base.nix's environment.etc.motd.

let
  self = config.nori.hosts.${config.networking.hostName} or null;
  codename = if self != null then (self.codename or config.networking.hostName) else config.networking.hostName;
in
{
  programs.rust-motd = {
    enable = true;
    enableMotdInSSHD = true;
    # Cadence for the systemd timer's auto-regen. Daily is reasonable
    # — laptop MOTD content (uptime, services, load avg) is
    # non-critical-real-time; force-regen with `sudo systemctl start
    # rust-motd.service` (or the `motd` alias just dumps the cached
    # last render) when you want it now.
    refreshInterval = "1d";
    settings = {
      banner = {
        # toilet brings its own ANSI colour codes through filters —
        # rust-motd's single-colour wrap would clobber that.
        color = "white";
        # Pick a font + filter pair at random and render the codename.
        # $RANDOM is bash's LCG seeded from PID — under rust-motd's
        # systemd unit the PID space is tiny and predictable, so rolls
        # cluster on the same value. /dev/urandom is the kernel CSPRNG;
        # two bytes via od is genuinely unpredictable and still ~µs.
        command = ''
          fonts=(mono9 smblock smmono9 future term smbraille)
          filters=(border metal gay "metal:border" "border:gay" crop)
          rand() { od -An -N2 -tu2 /dev/urandom | tr -d ' '; }
          f=''${fonts[$(rand) % ''${#fonts[@]}]}
          F=''${filters[$(rand) % ''${#filters[@]}]}
          ${pkgs.toilet}/bin/toilet -f "$f" -F "$F" '${codename}'
          echo '(${config.networking.hostName}) — ${self.role or "?"}'
        '';
      };

      uptime = {
        prefix = "Uptime";
      };

      # CPU load — 1/5/15-minute averages. rust-motd's only CPU-side
      # component (no direct % utilisation widget; `load_avg` is what
      # ships, mirrors what `uptime` shows). `:.2` precision is Rust's
      # format syntax — caps the long floats at two decimal places.
      load_avg = {
        format = "Load    1m  {one:.2}   ·   5m  {five:.2}   ·   15m  {fifteen:.2}";
      };

      memory = {
        swap_pos = "beside"; # 'below' | 'beside' | 'none'
      };

      filesystems = {
        root = "/";
      };

      last_login = {
        # Operator-level access only — root logins are noise (root is
        # ssh-key for nixos-anywhere deploys, hits twice on every
        # rebuild, no auth-anomaly value).
        nori = 2;
      };

      service_status = {
        # Universal core — present on every NixOS host in the lab.
        # Hosts add their own entries (laptop wifi via iwd, immich-ml
        # on aurora, caddy/jellyfin on workstation, blocky/gatus on
        # pi, etc) by extending programs.rust-motd.settings.service_status
        # in their own default.nix.
        sshd = "sshd";
        tailscaled = "tailscaled";
      };
    };
  };

  # Auto-refresh on the upstream-recommended cadence (every refreshInterval,
  # = 1d in our settings above, dialed up here per-host if desired).
  # Operator can still force-regen at any time:
  #   sudo systemctl start rust-motd.service
  # Or — convenient alias below — just type `motd`.

  # `motd` always re-renders before dumping — there's no value in a
  # stale view, and the render is sub-second. Wrapper (not shellAlias)
  # so it works in every shell.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "motd" ''
      sudo systemctl start rust-motd.service && cat /var/lib/rust-motd/motd
    '')
  ];
}
