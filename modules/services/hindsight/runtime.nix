{
  config,
  inputs,
  pkgs,
  ...
}:

let
  version = "0.9.0";
  apiPort = 9077;
  originPort = 9078;
  uiProxyPort = 9998;
  controlPlanePort = 9999;
  originTailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;

  /*
    Upstream publishes the Control Plane as a self-contained Next.js npm
    tarball (ISC). Package that artifact directly instead of running npx at
    every boot. Source and integrity are the registry metadata for
    @vectorize-io/hindsight-control-plane@0.9.0.
  */
  controlPlane = pkgs.stdenvNoCC.mkDerivation {
    pname = "hindsight-control-plane";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@vectorize-io/hindsight-control-plane/-/hindsight-control-plane-${version}.tgz";
      hash = "sha512-zIYnV9VOZKh+D2g6kyBCsfTi1Dc0KAjE60Hu2l38LEYlMJ66jrbeuEfAcBW8Gy3wV4LYpzaXsWBxce18dr/JQA==";
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];
    unpackPhase = ''
      runHook preUnpack
      mkdir source
      tar -xzf "$src" --strip-components=1 -C source
      cd source
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/libexec/hindsight-control-plane" "$out/bin"
      cp -R bin package.json public standalone "$out/libexec/hindsight-control-plane/"
      makeWrapper "$out/libexec/hindsight-control-plane/bin/cli.js" \
        "$out/bin/hindsight-control-plane" \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs_24 ]}
      runHook postInstall
    '';

    meta = {
      description = "Web control plane for Hindsight agent memory";
      homepage = "https://github.com/vectorize-io/hindsight";
      license = pkgs.lib.licenses.isc;
      mainProgram = "hindsight-control-plane";
    };
  };

  originCaddyfile = pkgs.writeText "hindsight-mcp-origin.Caddyfile" ''
    {
      admin off
      auto_https off
    }

    # The socket is reachable only on loopback and the workstation's tailnet
    # address. The shared cloudflared service is its sole public projection.
    http://:${toString originPort} {
      bind 127.0.0.1 ${originTailnetIp}
      log

      @authorized {
        path /mcp/chatlog-insights-v1 /mcp/chatlog-insights-v1/*
        header Authorization "Bearer {$HINDSIGHT_MCP_BEARER_TOKEN}"
      }

      handle @authorized {
        reverse_proxy http://127.0.0.1:${toString apiPort}
      }

      respond 404
    }

    http://127.0.0.1:${toString uiProxyPort} {
      bind 127.0.0.1

      reverse_proxy http://127.0.0.1:${toString controlPlanePort} {
        header_up Host localhost:${toString controlPlanePort}
        header_up X-Forwarded-Host localhost:${toString controlPlanePort}
        header_up X-Forwarded-Proto http
      }
    }
  '';

in
{
  assertions = [
    {
      assertion = (import ./manifest.nix).active;
      message = "The Hindsight runtime was imported while its manifest is inactive.";
    }
  ];

  sops.secrets.hindsight-mcp-bearer-token = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "hindsight_mcp_bearer_token";
    owner = "nori";
    mode = "0400";
  };

  sops.templates."hindsight-mcp-origin-env" = {
    owner = "nori";
    mode = "0400";
    content = ''
      HINDSIGHT_MCP_BEARER_TOKEN=${config.sops.placeholder.hindsight-mcp-bearer-token}
    '';
  };

  /*
    The API remains loopback-only. Cloudflare receives only the stateless MCP
    projection through the bearer-checking origin proxy; the REST API and
    mutating retain endpoint are never routed to the tunnel.
  */
  systemd.services.chatlog-hindsight = {
    description = "Hindsight memory API for Chatlog";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      HOME = "/home/nori";
      UV_CACHE_DIR = "/home/nori/.cache/hindsight-uv";
      XDG_CACHE_HOME = "/home/nori/.cache/hindsight-xdg";
      HINDSIGHT_API_DATABASE_URL = "pg0://hindsight-embed-chatlog-pilot";
      HINDSIGHT_API_LLM_PROVIDER = "openai-codex";
      HINDSIGHT_API_ENABLE_OBSERVATIONS = "true";
      HINDSIGHT_API_MCP_ENABLED_TOOLS = "recall,reflect";
      HINDSIGHT_API_MCP_STATELESS = "true";
      HINDSIGHT_API_STORE_DOCUMENT_TEXT = "true";
      HINDSIGHT_API_WORKERS = "1";
    };
    serviceConfig = {
      Type = "simple";
      User = "nori";
      Group = "users";
      ExecStart = "${pkgs.steam-run}/bin/steam-run ${pkgs.uv}/bin/uvx hindsight-api@${version} --host 127.0.0.1 --port ${toString apiPort} --no-access-log";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "5min";
      TimeoutStopSec = "90s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      ProtectKernelTunables = true;
      RestrictSUIDSGID = true;
    };
  };

  systemd.services.hindsight-control-plane = {
    description = "Tailnet-only Hindsight Control Plane";
    wantedBy = [ "multi-user.target" ];
    after = [ "chatlog-hindsight.service" ];
    requires = [ "chatlog-hindsight.service" ];
    environment = {
      HOME = "/home/nori";
      NEXT_TELEMETRY_DISABLED = "1";
    };
    serviceConfig = {
      Type = "simple";
      User = "nori";
      Group = "users";
      ExecStart = "${pkgs.steam-run}/bin/steam-run ${controlPlane}/bin/hindsight-control-plane --hostname 127.0.0.1 --port ${toString controlPlanePort} --api-url http://127.0.0.1:${toString apiPort}";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      ProtectKernelTunables = true;
      RestrictSUIDSGID = true;
    };
  };

  systemd.services.hindsight-mcp-origin = {
    description = "Bearer-authenticated Hindsight MCP origin";
    wantedBy = [ "multi-user.target" ];
    after = [ "chatlog-hindsight.service" ];
    requires = [ "chatlog-hindsight.service" ];
    serviceConfig = {
      Type = "simple";
      User = "nori";
      Group = "users";
      EnvironmentFile = config.sops.templates."hindsight-mcp-origin-env".path;
      ExecStart = "${pkgs.caddy}/bin/caddy run --config ${originCaddyfile} --adapter caddyfile";
      Restart = "on-failure";
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

  # The API and UI currently keep writable caches below the operator's home.
  # Make that existing authority explicit while applying the shared baseline.
  nori.harden.chatlog-hindsight.protectHome = false;
  nori.harden.hindsight-control-plane.protectHome = false;
  nori.harden.hindsight-mcp-origin = { };

  nori.backups.hindsight.skip = ''
    Derived pilot index: canonical sessions remain in Chatlog and can be
    re-ingested. A live filesystem copy of embedded PostgreSQL would not be a
    valid backup; add pg_dump-based preparation before treating this bank as
    irreplaceable state.
  '';
}
