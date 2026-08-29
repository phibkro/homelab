{
  config,
  inputs,
  pkgs,
  ...
}:

let
  devShareRoute = builtins.fromJSON (
    builtins.readFile ../../../infra/cloudflare/routes/dev-share.json
  );
  tunnelId = devShareRoute.tunnelId;
  hindsightHostname = "hindsight-origin.phibkro.org";
  projectsHostname = "projects-origin.phibkro.org";
  hindsightOriginPort = config.nori.lanRoutes.memory-origin.port;
  projectsOriginPort = config.nori.lanRoutes.projects-origin.port;

  tunnelConfig = pkgs.writeText "mcp-origin-cloudflared.yaml" ''
    tunnel: ${tunnelId}
    credentials-file: ${config.sops.secrets.mcp-origin-cloudflared-credentials.path}
    protocol: quic
    metrics: 127.0.0.1:9079

    ingress:
      - hostname: ${hindsightHostname}
        service: http://127.0.0.1:${toString hindsightOriginPort}
      - hostname: ${projectsHostname}
        service: http://127.0.0.1:${toString projectsOriginPort}
      - hostname: ${devShareRoute.hostname}
        service: http://${devShareRoute.originHost}:${toString devShareRoute.originPort}
      - service: http_status:404
  '';
  devShareCore =
    pkgs.runCommand "dev-share-core"
      {
        nativeBuildInputs = [
          pkgs.rustc
          pkgs.stdenv.cc
        ];
      }
      ''
        rustc --edition=2024 --test ${../../../tools/dev-share.rs} -o dev-share-tests
        ./dev-share-tests
        mkdir -p $out/bin
        rustc --edition=2024 ${../../../tools/dev-share.rs} -o $out/bin/dev-share
      '';
  devShareCaddyConfig = pkgs.writeText "dev-share.Caddyfile" ''
    {
      admin off
      auto_https off
    }

    http://${devShareRoute.originHost}:${toString devShareRoute.originPort} {
      bind ${devShareRoute.originHost}
      reverse_proxy {$DEV_SHARE_ORIGIN}
    }
  '';
  devShare = pkgs.writeShellApplication {
    name = "dev-share";
    runtimeInputs = [
      pkgs.caddy
      pkgs.cloudflared
      pkgs.qrencode
      pkgs.util-linux
    ];
    text = ''
      export DEV_SHARE_PUBLIC_URL=https://${devShareRoute.hostname}
      export DEV_SHARE_CADDY_CONFIG=${devShareCaddyConfig}
      export DEV_SHARE_LOCK_FILE="''${XDG_RUNTIME_DIR:?}/dev-share.lock"
      exec ${devShareCore}/bin/dev-share "$@"
    '';
  };
in
{
  assertions = [
    {
      assertion = (import ./manifest.nix).active;
      message = "The shared MCP origin tunnel runtime was imported while its manifest is inactive.";
    }
    {
      assertion = config.nori.lanRoutes ? memory-origin && config.nori.lanRoutes ? projects-origin;
      message = "The shared MCP origin tunnel requires both memory-origin and projects-origin inventory endpoints.";
    }
  ];

  /*
    One connector owns this named tunnel and its complete ingress table. Two
    cloudflared processes with divergent configs would be load-balanced and
    could return nondeterministic 404s for either hostname.
  */
  sops.secrets.mcp-origin-cloudflared-credentials = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "cloudflared-tunnel-credentials";
    owner = "nori";
    mode = "0400";
  };

  nori.backups.mcp-origin-tunnel.skip = "Stateless — tunnel configuration is generated from Nix and credentials are managed by SOPS.";

  nori.harden.mcp-origin-cloudflared = { };

  environment.systemPackages = [ devShare ];

  systemd.services.mcp-origin-cloudflared = {
    description = "Shared Cloudflare Tunnel for authenticated MCP origins";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "herdr-projects-mcp-origin.service"
      "hindsight-mcp-origin.service"
    ];
    requires = [
      "herdr-projects-mcp-origin.service"
      "hindsight-mcp-origin.service"
    ];
    serviceConfig = {
      Type = "simple";
      User = "nori";
      Group = "users";
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --config ${tunnelConfig} run";
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
}
