{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mapAttrsToList
    ;
in
{
  # nori.gatusProbes — manual Gatus endpoints for things that don't
  # fit the auto-generated nori.lanRoutes.<n>.monitor path. Used for:
  #   * non-HTTP probes — TCP DNS (port 53), SMB (445), SSH (22)
  #   * cross-host probes — workstation watching pi over tailnet, pi
  #     watching workstation over LAN; alerts still fire when the
  #     other host's Gatus is wedged
  #
  # Same Reader+collected-Writer shape as the rest of the nori.<X>
  # effect family. Hosts declare probes inline; this generator emits
  # services.gatus.settings.endpoints with the standard ntfy alert tail
  # (failure-threshold=3, send-on-resolved=true) baked in.
  #
  # Coexists with modules/effects/lan-route.nix's auto-Gatus endpoints
  # via list merging — lan-route uses lib.mkAfter so its entries land
  # after the manual probes; both contribute to the same final list.

  options.nori.gatusProbes = mkOption {
    default = { };
    description = ''
      Manual Gatus endpoints. Attribute name = endpoint name; value
      defines the probe. Defaults match the cross-host TCP-CONNECTED
      pattern that's the common case; override per probe for HTTP
      status checks etc.
    '';
    example = lib.literalExpression ''
      {
        blocky-dns.url = "tcp://127.0.0.1:53";
        pi-ssh.url = "tcp://''${config.nori.hosts.pi.tailnetIp}:22";
        station-caddy = {
          url = "https://status.${config.nori.domain}";
          interval = "120s";
          conditions = [ "[STATUS] == 200" ];
        };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          url = mkOption {
            type = types.str;
            description = "Probe URL — `tcp://host:port` for connection probes, `https://host` for status probes.";
          };
          interval = mkOption {
            type = types.str;
            default = "60s";
          };
          conditions = mkOption {
            type = types.listOf types.str;
            default = [ "[CONNECTED] == true" ];
            description = "Gatus condition expressions — `[CONNECTED] == true` for TCP, `[STATUS] == 200` for HTTP, etc.";
          };
          failureThreshold = mkOption {
            type = types.int;
            default = 3;
          };
        };
      }
    );
  };

  config = mkIf (config.nori.gatusProbes != { }) {
    services.gatus.settings.endpoints = mapAttrsToList (name: cfg: {
      inherit name;
      inherit (cfg) url interval conditions;
      alerts = [
        {
          type = "ntfy";
          failure-threshold = cfg.failureThreshold;
          send-on-resolved = true;
        }
      ];
    }) config.nori.gatusProbes;
  };
}
