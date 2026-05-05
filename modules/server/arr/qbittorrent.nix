{
  config,
  lib,
  pkgs,
  ...
}:

{
  # qBittorrent — torrent download client for the *arr stack. WebUI only
  # (no desktop GUI per the homelab's server/client separation).
  #
  # Default WebUI port is 8080 which collides with Open WebUI; remapped
  # to 8083. Torrent listen port (29170) is the default; firewall stays
  # default-deny — incoming peer connections are not currently accepted
  # (would need an inbound port forward on the residential router AND
  # an explicit firewall rule). Outgoing peer connections still work.
  #
  # First-run setup (one-shot, after rebuild):
  #   1. Visit https://downloads.nori.lan — Caddy forward-auth gates
  #      browser access via Authelia; qBittorrent's own login is
  #      bypassed for localhost (the Caddy hop) per the preStart below.
  #   2. Save paths + auth-bypass + ban-prevention all declarative
  #      (preStart). Operator only needs to set:
  #        Connection → Listening port: 29170 (or whatever you prefer)
  #   3. Sonarr/Radarr/Lidarr point their qBittorrent download-client
  #      config at http://localhost:8083 — username/password fields can
  #      be left blank since localhost connections skip qBittorrent's
  #      auth entirely (LocalHostAuth=false in the preStart). The
  #      qBittorrent WebUI password (printed once in journalctl on
  #      first start) only gates non-localhost access — defense-in-depth
  #      for SSH-tunnel-to-backend recovery scenarios.
  #   4. Each *arr's download client config sets a category for its
  #      grabs (tv-sonarr, movies-radarr, music-lidarr) — qBittorrent
  #      tags each download with the category, the *arr scans
  #      .downloads/complete on import, hardlinks finished items into
  #      its library subdir.
  services.qbittorrent = {
    enable = true;
    webuiPort = 8083;
    user = "qbittorrent";
    group = "qbittorrent";
    openFirewall = false;
  };

  # qBittorrent doesn't accept env-var config like Servarr does — its
  # state lives in qBittorrent.conf (Qt INI format). preStart edits a
  # handful of keys idempotently before the daemon reads them. Python's
  # configparser handles the backslash-in-key pattern qBittorrent uses
  # (`WebUI\LocalHostAuth`, `Session\DefaultSavePath`) cleanly;
  # sed-based alternatives need ugly escaping.
  #
  # [Preferences] keys (auth + reverse-proxy compat):
  #   LocalHostAuth=false     localhost connections (Caddy proxy on
  #                           workstation) skip the qBittorrent login.
  #                           Forward-auth at Caddy is the user gate.
  #   HostHeaderValidation=false  accept Host: downloads.nori.lan from
  #                                Caddy without complaint
  #   CSRFProtection=false    works fine through Caddy reverse proxy
  #   BanDuration=0           don't lock the IP after failed logins
  #   MaxAuthenticationFailCount=99999  defense in depth for above
  #
  # [BitTorrent] keys — split paths by IO pattern:
  #
  #   Session\DefaultSavePath=<streaming>/.downloads/complete
  #     COMPLETE goes on the IronWolf @streaming subvolume — must be
  #     same-subvolume as the *arr libraries (movies/, shows/, music/)
  #     for the *arr → library hardlink to work (btrfs hardlinks don't
  #     cross subvolumes; cross-subvol falls back to copy+delete which
  #     breaks seeding).
  #
  #   Session\TempPath=/var/lib/qBittorrent/incomplete
  #     INCOMPLETE goes on the SN750 NVMe (root FS, @var-lib subvol)
  #     under qBittorrent's StateDirectory. Random writes from peers
  #     stay off the spinning HDD; cross-device move on completion
  #     adds 1-10 min copy per finished torrent (one-time cost,
  #     doesn't break seeding — qBittorrent seeds from DefaultSavePath
  #     after the move). HDD wear-isolation + faster downloads at
  #     gigabit+ link speeds. Trade documented in the module header.
  #
  #   Session\TempPathEnabled=true     keep the split active
  systemd.services.qbittorrent.preStart = lib.mkAfter ''
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
              # COMPLETE on @streaming (same subvol as *arr libraries
              # for hardlink-on-import).
              r'Session\DefaultSavePath': '${config.nori.fs.streaming.path}/.downloads/complete',
              # INCOMPLETE on NVMe (qBittorrent StateDirectory) for IO
              # isolation + HDD wear-isolation. Cross-device copy on
              # completion is the trade.
              r'Session\TempPath':        '/var/lib/qBittorrent/incomplete',
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

  # Group membership — `media` is the cross-service shared group on the
  # streaming subvolume. Every *arr + the download client are members so
  # hardlinks across .downloads/complete → movies/shows just work.
  users.users.qbittorrent.extraGroups = [ "media" ];

  # qBittorrent needs the @streaming subvolume for incomplete + complete
  # download staging; /var/lib/qbittorrent for state (auto-created by
  # the service, covered by the StateDirectory upstream).
  nori.harden.qbittorrent.binds = [ config.nori.fs.streaming.path ];

  # Exposed at https://downloads.nori.lan via Caddy. Auto-monitored at /
  # (qBittorrent's WebUI returns 401 without auth which Gatus reads as
  # service-up; that's fine — we just want to know the process answers).
  nori.lanRoutes.downloads = {
    port = 8083;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "qBittorrent";
      icon = "si:qbittorrent";
      group = "Acquire";
      description = "Download client";
    };
  };

  # Pattern A — torrent state, resume data, *arr-tied categories.
  # Static `qbittorrent` user; real path with capital Q.
  nori.backups.qbittorrent.paths = [ "/var/lib/qBittorrent" ];
}
