{
  config,
  lib,
  pkgs,
  ...
}:

let
  /**
    Flip to `false` to pause the chat front-end without dropping its
    state at /var/lib/private/open-webui (DynamicUser symlink). The
    single boolean toggles:
      * the systemd unit
      * the https://chat.nori.lan Caddy route + Authelia OIDC client
      * Gatus monitor + Glance dashboard entry
      * the daily sqlite3-dump-then-restic backup
    Paused 2026-06-06 — open-webui's Python process held a steady
    multi-GB RSS contributing to the workstation memory-pressure
    freeze. Re-flip to `true` when chat is wanted; sqlite + restic
    state at /var/lib/private/open-webui survives the toggle.
  */
  enabled = false;
in
lib.mkMerge [
  {
    nori.services.open-webui.tags = [
      "family-tier"
      "stateful"
    ];

    nori.lanRoutes = lib.mkIf enabled {
      chat = {
        port = 8080;
        runsOn = "workstation";
        exposeOnTailnet = true; # pi's Caddy proxies cross-host over tailnet
        monitor = { };
        audience = "family";
        oidc = {
          clientName = "Open WebUI";
          redirectPath = "/oauth/oidc/callback";
        };
        dashboard = {
          title = "Open WebUI";
          icon = "sh:open-webui";
          group = "Consume";
          description = "Local LLM chat (Ollama-backed)";
        };
      };
    };
  }
  (lib.mkIf config.nori.services.open-webui.enabled {
    /**
      Open WebUI: chat front-end on top of local Ollama. First registered
      user becomes admin and invites family from the UI.

      Second backend (OpenRouter, OpenAI-compatible) can be wired later
      via OPENAI_API_BASE_URL + OPENAI_API_KEY (latter from sops).

      Restore previous chats from the Ubuntu One Touch backup: stop
      open-webui, copy
        docker-services/open-webui/data/webui.db
      → /var/lib/open-webui/webui.db (chown to open-webui:open-webui),
      start service. Schema migrations run on boot.
    */

    services.open-webui = {
      enable = enabled;
      host = "0.0.0.0";
      port = 8080;
      openFirewall = false;

      environment = {
        OLLAMA_BASE_URL = "http://127.0.0.1:11434";
        WEBUI_AUTH = "True";
        ENABLE_SIGNUP = "False";
        DEFAULT_MODELS = "";
        # OAUTH_CLIENT_SECRET is injected via EnvironmentFile below
        # (sops template auto-declared by `nori.lanRoutes.chat.oidc`).
        OPENID_PROVIDER_URL = "https://auth.${config.nori.domain}/.well-known/openid-configuration";
        OAUTH_CLIENT_ID = "chat";
        OAUTH_PROVIDER_NAME = "Authelia";
        ENABLE_OAUTH_SIGNUP = "True";
        /*
          Link OAuth identities to existing accounts by email match
          instead of creating a duplicate. Default is false because in
          multi-IdP setups a malicious provider could spoof emails to
          take over accounts; here Authelia is the only OIDC issuer
          and we trust its email claims, so the safety vs. UX
          tradeoff falls on the merge side. Without this, an Authelia
          email change creates an orphan account (we hit this once
          already during the proton-vs-gmail mismatch).
        */
        OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "True";
        /*
          Python's httpx/requests/urllib3 use certifi's bundled trust
          store; LE roots ship with Mozilla's bundle so certifi trusts
          `*.home.phibkro.org` natively. Pointing at the system bundle
          is harmless and survives any future internal-CA reintroduction.
        */
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
      };
    };

    /**
      Default-deny filesystem access beyond Open WebUI's own state dir
      (DynamicUser StateDirectory at /var/lib/open-webui handles itself).
      User-uploaded files land inside that state dir; no need for /mnt
      or /srv access. If a future need arises (e.g. importing media into
      Open WebUI's RAG knowledge base), add the path under
      nori.harden.open-webui.binds.

      mkIf-gated: when `enabled = false`, services.open-webui itself is
      off (no ExecStart) but nori.harden + other systemd.services.open-webui
      additions would still fire, producing a stub unit with `bad-setting`.
    */
    nori.harden = lib.mkIf enabled { open-webui = { }; };

    /**
      DynamicUser needs supplementary group `keys` to read the sops-
      rendered env file (mode 0440 root:keys). Wrapped in mkIf because
      when `enabled = false`, the lanRoute is unregistered → no OIDC
      block → no sops.templates."oidc-chat-env" generated, and referencing
      the missing template would 400 at eval.
    */
    systemd.services.open-webui.serviceConfig = lib.mkIf enabled {
      SupplementaryGroups = [ "keys" ];
      EnvironmentFile = config.sops.templates."oidc-chat-env".path;
    };

    /**
      Pattern C2 backup — sqlite3 .backup before restic. The path
      /var/lib/open-webui is a symlink to /var/lib/private/open-webui
      (DynamicUser StateDirectory mechanism); restic stores symlinks AS
      symlinks and would otherwise back up just the symlink record. So
      paths target /var/lib/private/open-webui directly. The
      prepareCommand can use either path — bash file ops follow symlinks.

      When disabled, the backup is skipped — the state isn't changing,
      the existing restic snapshots remain on /mnt/backup/open-webui as
      the recovery surface. Resume the daily job by flipping `enabled`.
    */
    nori.backups.open-webui =
      if enabled then
        {
          include = [
            "/var/lib/private/open-webui"
            "/var/backup/open-webui"
          ];
          prepareCommand = ''
            if [ -f /var/lib/open-webui/data/webui.db ]; then
              mkdir -p /var/backup/open-webui
              # VACUUM INTO + PRAGMA busy_timeout — see the long-form # multi-line: ok
              # rationale in navidrome.nix. The sqlite3 CLI's `.backup`
              # ignores busy_timeout (hard-coded ~2.5s retry), so the
              # previous `.timeout 30000` was a no-op. Open WebUI's
              # scheduler-worker polls every 10s + chat completions
              # write constantly, so the lock is held more often than
              # for navidrome — but the same fix applies.
              # Serialize concurrent prep — onetouch + mp510 race fix.
              # See navidrome.nix for the long form.
              (
                ${pkgs.util-linux}/bin/flock -x 9
                rm -f /var/backup/open-webui/webui.db.tmp
                ${pkgs.sqlite}/bin/sqlite3 /var/lib/open-webui/data/webui.db \
                  "PRAGMA busy_timeout = 30000;" \
                  "VACUUM INTO '/var/backup/open-webui/webui.db.tmp';"
                mv /var/backup/open-webui/webui.db.tmp /var/backup/open-webui/webui.db
              ) 9>/var/backup/open-webui/.prep.lock
            fi
          '';
          timer = "*-*-* 04:00:00";
        }
      else
        {
          skip = "Service disabled — see `enabled` at top of file. Existing snapshots in /mnt/backup/open-webui retained.";
        };

  })
]
