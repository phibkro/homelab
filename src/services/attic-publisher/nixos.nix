{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cache = config.nori.inventory.routes.cache;
  localCache = lib.elem "attic" config.nori.inventory.currentWorkloads;
  localCacheDependencies = lib.optionals localCache [ "attic-cache-bootstrap.service" ];
  atticClientConfig = pkgs.writeTextDir "attic/config.toml" ''
    default-server = "nori"

    [servers.nori]
    endpoint = "https://${cache.hostname}/"
    token-file = "${config.sops.secrets.attic-push-token.path}"
  '';
  atticPush = pkgs.writeShellApplication {
    name = "nori-cache-push";
    text = ''
      export XDG_CONFIG_HOME=${atticClientConfig}
      exec ${lib.getExe pkgs.attic-client} push nori "$@"
    '';
  };
in
{
  sops.secrets.attic-push-token = {
    sopsFile = inputs.self + "/secrets/shared-runtime.yaml";
    key = "attic_push_token";
    owner = "root";
    mode = "0400";
  };

  environment.systemPackages = [ atticPush ];

  systemd.services.attic-cache-seed = {
    description = "Publish the active system closure to the homelab Attic cache";
    wants = [ "network-online.target" ] ++ localCacheDependencies;
    after = [ "network-online.target" ] ++ localCacheDependencies;
    requires = localCacheDependencies;
    environment.XDG_CONFIG_HOME = atticClientConfig;
    restartTriggers = [ config.sops.secrets.attic-push-token.sopsFile ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe pkgs.attic-client} push nori --jobs 2 /run/current-system";
      Restart = "on-failure";
      RestartMode = "direct";
      RestartSec = "60s";
    };
  };

  systemd.services.attic-cache-watch = {
    description = "Publish new Nix store paths to the homelab Attic cache";
    wants = [ "network-online.target" ] ++ localCacheDependencies;
    after = [ "network-online.target" ] ++ localCacheDependencies;
    requires = localCacheDependencies;
    environment.XDG_CONFIG_HOME = atticClientConfig;
    restartTriggers = [ config.sops.secrets.attic-push-token.sopsFile ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe pkgs.attic-client} watch-store nori --jobs 2";
      Restart = "on-failure";
      RestartMode = "direct";
      RestartSec = "60s";
    };
  };

  systemd.timers.attic-cache-seed = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2m";
      OnUnitActiveSec = "1d";
      Unit = "attic-cache-seed.service";
    };
  };
  systemd.timers.attic-cache-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2m";
      Unit = "attic-cache-watch.service";
    };
  };

  nori.harden.attic-cache-seed = { };
  nori.harden.attic-cache-watch = { };

  nori.backups.attic-cache-seed = {
    workload = "attic-publisher";
    skip = "Publisher has no persistent state; the selected store closure is the source.";
  };
  nori.backups.attic-cache-watch = {
    workload = "attic-publisher";
    skip = "Publisher has no persistent state; the selected store closure is the source.";
  };
}
