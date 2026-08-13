{
  config,
  inputs,
  pkgs,
  ...
}:

let
  tunnelId = "9fc33815-3e6c-41dc-9858-8e01fe79ecda";
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
      - service: http_status:404
  '';
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
