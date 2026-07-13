{
  lib,
  pkgs,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  proxy = pkgs.callPackage ./cliproxyapi.nix { };
  port = 8317;
  baseUrl = "http://127.0.0.1:${toString port}";

  /*
    Runtime state cannot live in the Nix store: it contains the downstream
    API key and Codex OAuth refresh token. Regenerate the declarative config
    on every start while preserving the randomly-created key.

    Upstream's Codex token writer uses os.Create (mode follows umask), so the
    explicit 0077 umask and repair chmod are load-bearing.
  */
  init = pkgs.writeShellApplication {
    name = "claudex-init";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
            umask 077

            config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/claudex"
            data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/claudex"
            state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/claudex"
            config="$config_dir/config.yaml"
            key_file="$state_dir/api-key"

            install -d -m 0700 "$config_dir" "$data_dir/auth" "$state_dir"

            if [ ! -s "$key_file" ]; then
              key=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
              printf '%s\n' "$key" > "$key_file"
            fi
            chmod 0600 "$key_file"
            key=$(tr -d '\n' < "$key_file")

            case "$key" in
              (*[!0-9a-f]*|"")
                echo "claudex-init: invalid API key in $key_file" >&2
                exit 1
                ;;
            esac

            tmp=$(mktemp "$config_dir/config.yaml.XXXXXX")
            trap 'rm -f "$tmp"' EXIT
            cat > "$tmp" <<EOF
      host: "127.0.0.1"
      port: ${toString port}
      tls:
        enable: false
      remote-management:
        allow-remote: false
        secret-key: ""
        disable-control-panel: true
        disable-auto-update-panel: true
      auth-dir: "$data_dir/auth"
      api-keys:
        - "$key"
      debug: false
      pprof:
        enable: false
      plugins:
        enabled: false
      logging-to-file: false
      request-log: false
      usage-statistics-enabled: false
      ws-auth: true
      request-retry: 2
      routing:
        strategy: "fill-first"
        session-affinity: true
      EOF
            chmod 0600 "$tmp"
            mv -f "$tmp" "$config"
            trap - EXIT

            # Repair credentials created by older/manual runs with a permissive umask.
            find "$data_dir/auth" -type d -exec chmod 0700 {} +
            find "$data_dir/auth" -type f -exec chmod 0600 {} +
    '';
  };

  login = pkgs.writeShellApplication {
    name = "claudex-login";
    runtimeInputs = [
      init
      proxy
    ];
    text = ''
      umask 077
      claudex-init
      exec cliproxyapi \
        -config "''${XDG_CONFIG_HOME:-$HOME/.config}/claudex/config.yaml" \
        -local-model \
        -codex-login "$@"
    '';
  };

  status = pkgs.writeShellApplication {
    name = "claudex-status";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.systemd
    ];
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/claudex"
      key_file="$state_dir/api-key"

      systemctl --user --no-pager status claudex.service || true
      if [ -s "$key_file" ]; then
        curl --fail --silent --show-error \
          -H "Authorization: Bearer $(tr -d '\n' < "$key_file")" \
          ${baseUrl}/v1/models | ${pkgs.jq}/bin/jq -r '.data[]?.id' || true
      else
        echo "claudex-status: not initialized; run claudex-login" >&2
      fi
    '';
  };

  modelAudit = pkgs.writeShellApplication {
    name = "claudex-model-audit";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.systemd
    ];
    text = ''
      since="''${1:-15 minutes ago}"
      journalctl --user -u claudex.service --since "$since" --no-pager \
        | sed -nE 's/.*auth=codex-[^ ]+ provider=[^ ]+ model=([^ ]+).*/auth=codex-oauth model=\1/p' \
        | sort -u
    '';
  };

  launcher = pkgs.writeShellApplication {
    name = "claudex";
    runtimeInputs = [
      init
      pkgs.coreutils
      pkgs.curl
      pkgs.systemd
    ];
    text = ''
      claudex-init
      systemctl --user start claudex.service

      ready=false
      for _ in $(seq 1 50); do
        if curl --fail --silent ${baseUrl}/healthz >/dev/null; then
          ready=true
          break
        fi
        sleep 0.1
      done
      if [ "$ready" != true ]; then
        echo "claudex: proxy failed to become ready" >&2
        systemctl --user --no-pager status claudex.service >&2 || true
        exit 1
      fi

      key=$(tr -d '\n' < "''${XDG_STATE_HOME:-$HOME/.local/state}/claudex/api-key")
      opus="''${CLAUDEX_OPUS_MODEL:-gpt-5.6-sol}"
      sonnet="''${CLAUDEX_SONNET_MODEL:-gpt-5.6-terra}"
      haiku="''${CLAUDEX_HAIKU_MODEL:-gpt-5.6-luna}"
      model="''${CLAUDEX_MODEL:-$opus}"
      capabilities="effort,xhigh_effort,max_effort,thinking,adaptive_thinking,interleaved_thinking"

      # The gateway token must win over any API credential inherited from a
      # shell used for ordinary Claude API work.
      unset ANTHROPIC_API_KEY
      export ANTHROPIC_BASE_URL=${baseUrl}
      export ANTHROPIC_AUTH_TOKEN="$key"
      export ANTHROPIC_MODEL="$model"

      export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus"
      export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="GPT-5.6 Sol"
      export ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION="Frontier OpenAI agentic coding model (Opus tier)"
      export ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES="$capabilities"

      export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
      export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="GPT-5.6 Terra"
      export ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION="Balanced OpenAI agentic coding model (Sonnet tier)"
      export ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES="$capabilities"

      export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="GPT-5.6 Luna"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION="Fast OpenAI agentic coding model (Haiku tier)"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES="$capabilities"
      export ANTHROPIC_SMALL_FAST_MODEL="$haiku"

      exec claude "$@"
    '';
  };
in
{
  config = lib.mkIf isLinux {
    home.packages = [
      proxy
      init
      login
      status
      modelAudit
      launcher
    ];

    home.file.".claude/CLAUDEX_ACCEPTANCE.md".source = ./CLAUDEX_ACCEPTANCE.md;

    systemd.user.services.claudex = {
      Unit = {
        Description = "ClaudeX loopback Codex-to-Anthropic protocol proxy";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${init}/bin/claudex-init";
        ExecStart = "${proxy}/bin/cliproxyapi -config %h/.config/claudex/config.yaml -local-model";
        Restart = "on-failure";
        RestartSec = "2s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [
          "%h/.config/claudex"
          "%h/.local/share/claudex"
          "%h/.local/state/claudex"
        ];
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
