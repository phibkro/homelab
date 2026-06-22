{
  config,
  lib,
  pkgs,
  ...
}:

/*
  stremio — Stremio Server (the streaming-server backend that pairs
  with the Stremio web/desktop client). Operator-personal; tailnet-only
  at https://stremio.nori.lan.

  ── Why a hand-rolled module ─────────────────────────────────────
  nixpkgs dropped `stremio` 2026-02-11 (depended on the vulnerable
  qt5-webengine) and there's no `services.stremio-server` module. The
  replacement `stremio-linux-shell` is a UI shell only, not the
  server binary. Upstream officially distributes `server.js` as a
  self-contained Node bundle at dl.strem.io — fetchurl as a
  fixed-output derivation and run with pkgs.nodejs.

  ── Pairing flow ─────────────────────────────────────────────────
  Stremio Web (https://web.stremio.com) won't talk to a plaintext
  server — mixed-content rule. Caddy fronts our server with a valid
  nori.lan cert (operator's clients trust the local CA via the same
  mechanism that makes immich-cli + claude-code MCP fetches work),
  so the client points at https://stremio.nori.lan as its streaming
  server URL and the handshake succeeds.

  ── State + env ──────────────────────────────────────────────────
  APP_PATH=/var/lib/stremio holds the per-server cert + identifier
  that clients pair with on first connect. NO_CORS disables the CORS
  check since Caddy's reverse-proxy origin differs from the client
  origin.
*/

let
  version = "4.20.12";
  serverJs = pkgs.fetchurl {
    url = "https://dl.strem.io/server/v${version}/desktop/server.js";
    sha256 = "04xcishc3hw9iq7z29igc1083flwhp7ynz07n9gb7ry643fz69x5";
  };
  servePort = 11470;
in
lib.mkMerge [
  {
    nori.services.stremio.tags = [ "media-server" ];

    nori.lanRoutes.stremio = {
      port = servePort;
      runsOn = "workstation";
      audience = "operator";
      monitor = { };
      dashboard = {
        title = "Stremio";
        icon = "si:stremio";
        group = "Consume";
        description = "Streaming backend (pair via web.stremio.com)";
      };
    };
  }
  (lib.mkIf config.nori.services.stremio.enabled {
    users.users.stremio = {
      isSystemUser = true;
      group = "stremio";
      home = "/var/lib/stremio";
      description = "Stremio Server";
    };
    users.groups.stremio = { };

    systemd.services.stremio = {
      description = "Stremio Server (streaming backend for Stremio clients)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        APP_PATH = "/var/lib/stremio";
        HOME = "/var/lib/stremio";
        NO_CORS = "1";
      };

      serviceConfig = {
        Type = "simple";
        User = "stremio";
        Group = "stremio";
        StateDirectory = "stremio";
        StateDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/stremio";

        ExecStart = "${pkgs.nodejs}/bin/node ${serverJs}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    nori.harden.stremio = {
      binds = [ "/var/lib/stremio" ];
    };

    # Service tier — losing the cert/identifier just forces a re-pair, but
    # the dir is tiny so it's free to back up.
    nori.backups.stremio = {
      include = [ "/var/lib/stremio" ];
      tier = "service";
    };
  })
]
