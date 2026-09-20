{
  config,
  lib,
  pkgs,
  ...
}:

let
  enabled = (import ./manifest.nix).active;
  downloads = config.nori.inventory.routes.downloads;
  qbtConfig = "/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf";
  qbtConfigure = pkgs.writeText "qbt-configure.py" ''
    import configparser
    import os
    from pathlib import Path
    import sys
    import tempfile

    default_save_path = sys.argv[2]
    pi_subnet = sys.argv[3]

    conf = Path(sys.argv[1])
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(conf, encoding="utf-8")

    sections = {
        "Preferences": {
            r"WebUI\LocalHostAuth": "false",
            r"WebUI\HostHeaderValidation": "false",
            r"WebUI\CSRFProtection": "false",
            r"WebUI\BanDuration": "0",
            r"WebUI\MaxAuthenticationFailCount": "99999",
            r"WebUI\AuthSubnetWhitelist": pi_subnet,
            r"WebUI\AuthSubnetWhitelistEnabled": "true",
        },
        "BitTorrent": {
            r"Session\DefaultSavePath": default_save_path,
            r"Session\TempPath": "/var/lib/qBittorrent/qBittorrent/incomplete",
            r"Session\TempPathEnabled": "true",
        },
    }
    for section, values in sections.items():
        if section not in parser:
            parser.add_section(section)
        for key, value in values.items():
            parser[section][key] = value

    descriptor, temporary = tempfile.mkstemp(prefix=".qBittorrent.conf.", dir=conf.parent, text=True)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            parser.write(output, space_around_delimiters=False)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, conf)
        directory = os.open(conf.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
  '';
in
{
  /*
    qBittorrent — torrent download client for the *arr stack. WebUI only
    (no desktop GUI per the homelab's server/client separation).

    Default WebUI port is 8080 which collides with Open WebUI; remapped
    to 8083. Torrent listen port (29170) is the default; firewall stays
    default-deny — incoming peer connections are not currently accepted
    (would need an inbound port forward on the residential router AND
    an explicit firewall rule). Outgoing peer connections still work.

    First-run setup (one-shot, after rebuild):
      1. Visit https://downloads.home.phibkro.org — Caddy on Pi applies
         Authelia before proxying to qBittorrent on the workstation.
      2. Save paths and access policy are enforced before each start without
         replacing retained UI state. Operator only needs to set:
           Connection → Listening port: 29170 (or whatever you prefer)
      3. Sonarr/Radarr/Lidarr point their qBittorrent download-client
         config at http://localhost:8083 — username/password fields can
         be left blank since localhost connections skip qBittorrent's
         auth entirely (LocalHostAuth=false in the preStart). The
         qBittorrent WebUI password (printed once in journalctl on
         first start) only gates non-localhost access — defense-in-depth
         for SSH-tunnel-to-backend recovery scenarios.
      4. Each *arr's download client config sets a category for its
         grabs (tv-sonarr, movies-radarr, music-lidarr) — qBittorrent
         tags each download with the category, the *arr scans
         .downloads/complete on import, hardlinks finished items into
         its library subdir.
  */
  services.qbittorrent = {
    enable = enabled;
    webuiPort = downloads.port;
    user = "qbittorrent";
    group = "qbittorrent";
    openFirewall = false;
  };

  /*
    qBittorrent has no environment-variable config. The preStart merge creates
    qBittorrent.conf before the first process start, then rewrites only the
    owned keys on later starts. Passwords, listening ports, categories, and
    other qBittorrent-managed state remain intact.

    [Preferences] bypasses qBittorrent auth for localhost clients and the Pi
    entry plane only. Caddy applies forward-auth before proxying from Pi.
    Reverse-proxy compatibility keys stop qBittorrent from refusing Caddy's
    rewritten Host and Origin headers. Other tailnet peers still receive
    qBittorrent's native login.

    [BitTorrent] splits COMPLETE vs INCOMPLETE by IO pattern:

      COMPLETE → @downloads (same subvol as the *arr libraries; btrfs
        hardlinks don't cross subvols and the cross-subvol copy+delete
        fallback breaks seeding).

      INCOMPLETE → SN750 NVMe under the qbittorrent-owned Qt profile
        dir (/var/lib/qBittorrent/qBittorrent/incomplete). The outer
        /var/lib/qBittorrent/ is root-owned (upstream module doesn't set
        StateDirectory=); pointing TempPath one level higher fails every
        file_open with EACCES — caught 2026-05-07. Random peer writes
        stay off the HDD; cross-device move on completion is the trade.

      FAILURE MODE — the wedge: if @downloads fills (Jellyseerr request
      burst, no cull), qBittorrent can't finalize-move partials → they
      pile up on SN750 forever until both drives hit 100% together. Hit
      2026-05-14 (572 GiB of partials across 29 torrents). Mitigations:
      disk-alert.nix pages at 85%/95% on both filesystems; sonarr/
      radarr/lidarr first-run setup directs the operator to set
      MinimumFreeSpaceWhenImporting in each UI (lives in their sqlite,
      not config.xml, so not env-overridable). Recovery procedure:
      docs/runbooks/storage-full.md.
  */

  /*
    Process umask = 0002 so finished files land mode 0664 (group-writable)
    instead of the default 0644. Required for the *arr → library
    hardlink-on-import: with `fs.protected_hardlinks=1` (kernel default),
    link(2) only succeeds if the caller owns the source file OR has
    read+write on it. *arr users share the `media` group with qBittorrent
    but not the UID, so group-writable files satisfy the kernel check
    and the library entry becomes a hardlink to the seeding copy instead
    of a second full copy on disk. Caught 2026-05-15: Battle Royale had
    two distinct inodes (uid=qbittorrent for the seeding copy, uid=radarr
    for the library file), proving link() had silently fallen back to
    copy — every torrent in @downloads stored twice (~2.9T doubled).
  */

  systemd.services.qbittorrent = lib.mkIf enabled {
    serviceConfig.UMask = "0002";
    preStart = lib.mkAfter ''
      install -d -m 0755 \
        /var/lib/qBittorrent/qBittorrent/config \
        /var/lib/qBittorrent/qBittorrent/incomplete
      if [ ! -e ${lib.escapeShellArg qbtConfig} ]; then
        install -m 0600 /dev/null ${lib.escapeShellArg qbtConfig}
      fi
      ${pkgs.python3}/bin/python3 ${qbtConfigure} \
        ${lib.escapeShellArg qbtConfig} \
        ${lib.escapeShellArg "${config.nori.fs.downloads.path}/.downloads/complete"} \
        ${lib.escapeShellArg "${config.nori.inventory.hosts.pi.tailnetIp}/32"}
    '';
  };

  systemd.tmpfiles.rules = lib.mkIf enabled [
    "d /var/lib/qBittorrent/qBittorrent/incomplete 0755 qbittorrent qbittorrent -"
  ];

  users.users = lib.mkIf enabled {
    qbittorrent.extraGroups = [ "media" ];
  };

  nori.harden.qbittorrent = lib.mkIf enabled {
    binds = [ config.nori.fs.downloads.path ];
  };

  /*
    Exclude `incomplete/` — re-derivable (peers re-send chunks) and
    historically ballooned the backup repo to 560+ GiB of dead chunks
    pinned by snapshots referencing a bygone full-incomplete state.
    Live state without it is ~31 MiB.
  */
  nori.backups.qbittorrent =
    if enabled then
      {
        include = [ "/var/lib/qBittorrent" ];
        exclude = [ "/var/lib/qBittorrent/qBittorrent/incomplete" ];
      }
    else
      {
        skip = "Service paused by operator; retained state and existing snapshots are unchanged.";
      };
}
