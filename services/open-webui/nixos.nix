{
  config,
  pkgs,
  ...
}:

let
  chat = config.nori.inventory.routes.chat;
  auth = config.nori.inventory.routes.auth;
  ai = config.nori.inventory.routes.ai;
in
{
  /*
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
    enable = true;
    host = "0.0.0.0";
    port = chat.port;
    openFirewall = false;

    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:${toString ai.port}";
      WEBUI_AUTH = "True";
      ENABLE_SIGNUP = "False";
      DEFAULT_MODELS = "";
      # OAUTH_CLIENT_SECRET is injected through the host-local template
      # derived from this workload's manifest OIDC declaration.
      OPENID_PROVIDER_URL = "https://${auth.hostname}/.well-known/openid-configuration";
      OAUTH_CLIENT_ID = chat.name;
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

  /*
    Default-deny filesystem access beyond Open WebUI's own state directory.
    The inventory compiler imports this module only while the workload is
    active, so no second activation gate is needed here.
  */
  nori.harden.open-webui = { };

  /*
    DynamicUser needs supplementary group `keys` to read the host-local OIDC
    environment template.
  */
  systemd.services.open-webui.serviceConfig = {
    SupplementaryGroups = [ "keys" ];
    EnvironmentFile = config.sops.templates."oidc-${chat.name}-env".path;
  };

  /*
    Pattern C2 backup — sqlite3 .backup before restic. The path
    /var/lib/open-webui is a symlink to /var/lib/private/open-webui
    (DynamicUser StateDirectory mechanism); restic stores symlinks AS
    symlinks and would otherwise back up just the symlink record. So
    paths target /var/lib/private/open-webui directly. The
    prepareCommand can use either path — bash file ops follow symlinks.
  */
  nori.backups.open-webui = {
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
  };
}
