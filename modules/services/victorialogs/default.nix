{ config, lib, ... }:

{
  # Cross-host lanRoute for VictoriaLogs running on pi. Daemon lives
  # in ./server.nix (imported only by pi); this file is imported by
  # Caddy-running hosts via modules/server/default.nix and declares
  # the https://logs.nori.lan reverse-proxy.
  #
  # Named default.nix (not route.nix) so the every-service-has-{harden,
  # backup}-intent flake checks' shared `*/default.nix` exclude applies
  # — this file owns no systemd unit and has no on-disk state, so
  # declaring harden/backup intent here would be dishonest.
  #
  # The vlogs-host coupling lives in the nori.hosts registry — if
  # VictoriaLogs ever relocates, update flake.nix `identityFor`
  # instead of this file.
  nori.lanRoutes = lib.mkIf config.services.caddy.enable {
    logs = {
      port = 9428;
      runsOn = "pi";
      monitor.path = "/health";
      audience = "operator";
    };
  };
}
