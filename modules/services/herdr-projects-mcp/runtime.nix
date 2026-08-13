{
  config,
  inputs,
  pkgs,
  ...
}:

let
  sourceRoot = "/srv/share/projects/herdr-mcp";
  executionRoot = "/tmp/herdr-mcp-projects";
  stateDir = "/home/nori/.local/state/herdr-mcp/projects";
  storePath = "${stateDir}/facade.sqlite";
  localPort = 9080;
  originPort = 9081;
  originTailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

  originCaddyfile = pkgs.writeText "herdr-projects-mcp-origin.Caddyfile" ''
    {
      admin off
      auto_https off
    }

    # Only the MCP endpoint crosses the tailnet. The Bun origin performs the
    # bearer comparison before parsing or dispatching any MCP input.
    http://:${toString originPort} {
      bind 127.0.0.1 ${originTailnetIp}
      log

      @mcp path /mcp
      handle @mcp {
        reverse_proxy http://127.0.0.1:${toString localPort}
      }

      respond 404
    }
  '';
in
{
  assertions = [
    {
      assertion = (import ./manifest.nix).active;
      message = "The Herdr projects MCP runtime was imported while its manifest is inactive.";
    }
  ];

  sops.secrets.herdr-projects-mcp-bearer-token = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "herdr_projects_mcp_bearer_token";
    owner = "nori";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /home/nori/.local/state/herdr-mcp 0700 nori users -"
    "d ${stateDir} 0700 nori users -"
    "d ${executionRoot} 0700 nori users -"
  ];

  systemd.services.herdr-projects-mcp = {
    description = "Authenticated existing-agent MCP projection for Herdr projects";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      HOME = "/home/nori";
      HERDR_MCP_HERDR_BIN = "${herdrPackage}/bin/herdr";
      HERDR_MCP_HERDR_SESSION = "projects";
      HERDR_MCP_SESSION_ROOT = executionRoot;
      HERDR_MCP_STORE = storePath;
      HERDR_MCP_REGISTRY = "${sourceRoot}/config/herdr-mcp.registry.json";
      HERDR_MCP_HTTP_BEARER_TOKEN_FILE = config.sops.secrets.herdr-projects-mcp-bearer-token.path;
      HERDR_MCP_HTTP_HOST = "127.0.0.1";
      HERDR_MCP_HTTP_PORT = toString localPort;
      HERDR_MCP_HTTP_PATH = "/mcp";
    };
    unitConfig.ConditionPathExists = [
      "${sourceRoot}/src/server/http.ts"
      "${sourceRoot}/node_modules/@modelcontextprotocol/sdk"
      storePath
    ];
    serviceConfig = {
      Type = "simple";
      User = "nori";
      Group = "users";
      WorkingDirectory = sourceRoot;
      ExecStart = "${pkgs.bun}/bin/bun run ${sourceRoot}/src/server/http.ts";
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = false;
      ProtectControlGroups = true;
      ProtectHome = "read-only";
      ProtectKernelLogs = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        stateDir
        executionRoot
      ];
      RestrictSUIDSGID = true;
    };
  };

  systemd.services.herdr-projects-mcp-origin = {
    description = "Tailnet-only proxy for the Herdr projects MCP origin";
    wantedBy = [ "multi-user.target" ];
    after = [ "herdr-projects-mcp.service" ];
    requires = [ "herdr-projects-mcp.service" ];
    environment.HOME = "/run/herdr-projects-mcp-origin";
    serviceConfig = {
      Type = "simple";
      User = "nori";
      Group = "users";
      ExecStart = "${pkgs.caddy}/bin/caddy run --config ${originCaddyfile} --adapter caddyfile";
      Restart = "on-failure";
      RestartSec = "5s";
      RuntimeDirectory = "herdr-projects-mcp-origin";
      RuntimeDirectoryMode = "0700";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectKernelLogs = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictSUIDSGID = true;
    };
  };

  systemd.services.herdr-projects-mcp-relay = {
    description = "Outbound Cloudflare relay for the Herdr projects MCP origin";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "herdr-projects-mcp.service"
    ];
    requires = [ "herdr-projects-mcp.service" ];
    wants = [ "network-online.target" ];
    environment = {
      HERDR_MCP_RELAY_URL = "wss://herdr-projects-relay.philib-krogh-d23.workers.dev/relay/connect";
      HERDR_MCP_RELAY_LOCAL_URL = "http://127.0.0.1:${toString localPort}/mcp";
      HERDR_MCP_HTTP_BEARER_TOKEN_FILE = config.sops.secrets.herdr-projects-mcp-bearer-token.path;
    };
    unitConfig.ConditionPathExists = "${sourceRoot}/src/server/relay.ts";
    serviceConfig = {
      Type = "simple";
      User = "nori";
      Group = "users";
      WorkingDirectory = sourceRoot;
      ExecStart = "${pkgs.bun}/bin/bun run ${sourceRoot}/src/server/relay.ts";
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectHome = "read-only";
      ProtectKernelLogs = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictSUIDSGID = true;
    };
  };

  /*
    No repo of its own. The facade journal sits under /home, which the
    cross-cutting `user-data` job already ships to every target on the same
    03:00 timer at a longer retention (user tier, 14d/4w/12m vs the service
    default 7d/4w/12m). A second job would copy the same bytes twice — and
    against the `onetouch` target it can't even initialize: that repository
    root is aurora's sshd ChrootDirectory (/mnt/backup), which must stay
    root-owned, so restic's MkdirAll at the chroot root is denied and the
    unit failed nightly from 2026-08-11. See
    docs/reports/20260813-030204-restic-backups-herdr-projects-mcp-onetouch-failure.md.
  */
  nori.backups.herdr-projects-mcp.skip = "Facade journal lives at ${stateDir}, inside the /home path the user-data repo already backs up to every target.";
}
