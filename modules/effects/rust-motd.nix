{ config, lib, ... }:

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
        color = "cyan";
        # Echo the codename — rust-motd's banner component renders
        # whatever its `command` outputs. Keep it short so it fits
        # on a laptop console even with line-wrapping disabled.
        command = "echo ${codename} \\(${config.networking.hostName}\\) — ${self.role or "?"}";
      };

      uptime = {
        prefix = "Uptime";
      };

      # CPU load — 1/5/15-minute averages. rust-motd's only CPU-side
      # component (no direct % utilisation widget; `load_avg` is what
      # ships, mirrors what `uptime` shows).
      load_avg = {
        format = "Load avg  {one}  {five}  {fifteen}";
      };

      memory = {
        swap_pos = "beside"; # 'below' | 'beside' | 'none'
      };

      filesystems = {
        root = "/";
      };

      last_login = {
        # Show last 2 logins per user; surfaces unexpected access at
        # a glance. Keeping the count small so the MOTD stays brief.
        root = 2;
        nori = 2;
      };

      service_status = {
        # Per-host status — most are universal, immich-machine-
        # learning will be "not found" on hosts that don't run it
        # (rust-motd shows it as "?" rather than failing).
        sshd = "sshd";
        tailscaled = "tailscaled";
        iwd = "iwd";
        # Only present on aurora; harmless on pavilion (shown as
        # not-running).
        immich-ml = "immich-machine-learning";
      };
    };
  };

  # Auto-refresh on the upstream-recommended cadence (every refreshInterval,
  # = 1d in our settings above, dialed up here per-host if desired).
  # Operator can still force-regen at any time:
  #   sudo systemctl start rust-motd.service
  # Or — convenient alias below — just type `motd`.

  # Type `motd` in any shell to dump the current rendered file. The
  # ANSI codes survive cat; if you've aliased cat to bat you'll want
  # `bat --paging=never /var/lib/rust-motd/motd` instead.
  environment.shellAliases.motd = "cat /var/lib/rust-motd/motd";
}
