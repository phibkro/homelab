{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkMerge [
  {
    nori.services.qbittorrent.tags = [ "media-server" ];

    # Gatus reads qBittorrent's 401-without-auth at / as service-up, which
    # is the intent here — we just want to know the process answers.
    nori.lanRoutes.downloads = {
      port = 8083;
      runsOn = "workstation";
      exposeOnTailnet = true; # pi's Caddy proxies cross-host over tailnet
      monitor = { };
      audience = "operator";
      dashboard = {
        title = "qBittorrent";
        icon = "si:qbittorrent";
        group = "Acquire";
        description = "Download client";
      };
    };
  }
  (lib.mkIf config.nori.services.qbittorrent.enabled {
    /*
      qBittorrent — torrent download client for the *arr stack. WebUI only
      (no desktop GUI per the homelab's server/client separation).

      Default WebUI port is 8080 which collides with Open WebUI; remapped
      to 8083. Torrent listen port (29170) is the default; firewall stays
      default-deny — incoming peer connections are not currently accepted
      (would need an inbound port forward on the residential router AND
      an explicit firewall rule). Outgoing peer connections still work.

      First-run setup (one-shot, after rebuild):
        1. Visit https://downloads.nori.lan — Caddy forward-auth gates
           browser access via Authelia; qBittorrent's own login is
           bypassed for localhost (the Caddy hop) per the preStart below.
        2. Save paths + auth-bypass + ban-prevention all declarative
           (preStart). Operator only needs to set:
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
      enable = true;
      webuiPort = 8083;
      user = "qbittorrent";
      group = "qbittorrent";
      openFirewall = false;
    };

    /*
      qBittorrent has no env-var config; state lives in qBittorrent.conf
      (Qt INI). preStart idempotently rewrites the keys below via Python
      configparser — it handles Qt's backslash-in-key (`WebUI\…`) cleanly,
      sed needs ugly escaping.

      [Preferences] disables qBittorrent's own auth + ban for localhost so
      Caddy forward-auth is the only browser gate; reverse-proxy compat
      keys (HostHeaderValidation/CSRFProtection) just stop qBittorrent
      refusing Caddy's rewritten Host/CSRF posture.

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
    systemd.services.qbittorrent.serviceConfig.UMask = "0002";

    systemd.services.qbittorrent.preStart = lib.mkAfter ''
      # qBittorrent doesn't auto-create Session\TempPath; if it's # multi-line: ok
      # missing, every incomplete file_open hits "Permission denied"
      # because the parent doesn't exist either (caught 2026-05-07).
      mkdir -p /var/lib/qBittorrent/qBittorrent/incomplete

      ${pkgs.python3}/bin/python3 ${pkgs.writeText "qbt-configure.py" ''
        import configparser, glob, sys
        candidates = glob.glob('/var/lib/qBittorrent/**/qBittorrent.conf', recursive=True)
        if not candidates:
            print('qbt-configure: qBittorrent.conf not yet present (first start) — skipping', file=sys.stderr)
            sys.exit(0)
        conf = candidates[0]
        cp = configparser.ConfigParser()
        cp.optionxform = str  # preserve case + backslash in keys
        cp.read(conf)

        sections = {
            'Preferences': {
                r'WebUI\LocalHostAuth': 'false',
                r'WebUI\HostHeaderValidation': 'false',
                r'WebUI\CSRFProtection': 'false',
                r'WebUI\BanDuration': '0',
                r'WebUI\MaxAuthenticationFailCount': '99999',
            },
            'BitTorrent': {
                # COMPLETE on @downloads (same subvol as *arr libraries
                # for hardlink-on-import).
                r'Session\DefaultSavePath': '${config.nori.fs.downloads.path}/.downloads/complete',
                # INCOMPLETE on NVMe (qBittorrent StateDirectory) for IO
                # isolation + HDD wear-isolation. Cross-device copy on
                # completion is the trade.
                r'Session\TempPath':        '/var/lib/qBittorrent/qBittorrent/incomplete',
                r'Session\TempPathEnabled': 'true',
            },
        }
        for section, kv in sections.items():
            if section not in cp:
                cp.add_section(section)
            for k, v in kv.items():
                cp[section][k] = v

        with open(conf, 'w') as f:
            # Qt INI uses `key=value` with no spaces; configparser default is
            # `key = value`. space_around_delimiters=False matches Qt's format.
            cp.write(f, space_around_delimiters=False)
      ''}
    '';

    users.users.qbittorrent.extraGroups = [ "media" ];

    nori.harden.qbittorrent.binds = [ config.nori.fs.downloads.path ];

    /*
      Exclude `incomplete/` — re-derivable (peers re-send chunks) and
      historically ballooned the backup repo to 560+ GiB of dead chunks
      pinned by snapshots referencing a bygone full-incomplete state.
      Live state without it is ~31 MiB.
    */
    nori.backups.qbittorrent = {
      include = [ "/var/lib/qBittorrent" ];
      exclude = [ "/var/lib/qBittorrent/qBittorrent/incomplete" ];
    };
  })
]
