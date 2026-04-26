{ config, lib, pkgs, ... }:

{
  # Open WebUI: chat front-end, primarily for local Ollama. Optional
  # second backend (OpenRouter, OpenAI-compatible) can be added later
  # via OPENAI_API_BASE_URL + OPENAI_API_KEY env vars (the latter from
  # sops). Defer until needed.
  #
  # Auth required (no open signup); first user to register becomes
  # admin and can invite family members from inside the UI.
  #
  # State (SQLite + per-user uploads + conversation history) lives at
  # /var/lib/open-webui. Backed up via Pattern C2 in
  # backup-restic.nix — sqlite3 .backup before restic so the dump is
  # consistent.
  #
  # To restore the previous installation's chats from the Ubuntu One
  # Touch backup: stop open-webui, copy
  #   docker-services/open-webui/data/webui.db
  # → /var/lib/open-webui/webui.db (chown to open-webui:open-webui),
  # start service. Open WebUI runs schema migrations on boot.

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = 8080;
    openFirewall = false;

    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH = "True";
      ENABLE_SIGNUP = "False";
      DEFAULT_MODELS = "";
      # OIDC env vars that don't contain secrets go here. The secret-
      # bearing env var (OAUTH_CLIENT_SECRET) is loaded from
      # /run/secrets/rendered/open-webui-oauth-env via systemd
      # EnvironmentFile below — sops template renders the value at
      # activation, file is mode 0440 root:keys, service runs with
      # SupplementaryGroups=keys so it can read.
      OPENID_PROVIDER_URL = "https://auth.nori.lan/.well-known/openid-configuration";
      OAUTH_CLIENT_ID = "chat";
      OAUTH_PROVIDER_NAME = "Authelia";
      ENABLE_OAUTH_SIGNUP = "True";
      # Python's httpx/requests/urllib3 use certifi's bundled trust
      # store by default — they don't see /etc/ssl/certs and so don't
      # trust Caddy's local CA. SSL_CERT_FILE overrides certifi to use
      # the system bundle (which has the local CA via
      # security.pki.certificateFiles in modules/services/caddy.nix).
      SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
      REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
    };
  };

  sops.secrets.oidc-chat-client-secret = {
    mode = "0440";
    group = "keys";
  };

  sops.templates."open-webui-oauth-env" = {
    mode = "0440";
    group = "keys";
    content = ''
      OAUTH_CLIENT_SECRET=${config.sops.placeholder.oidc-chat-client-secret}
    '';
  };

  # Default-deny filesystem access beyond Open WebUI's own state dir
  # (DynamicUser StateDirectory at /var/lib/open-webui handles itself).
  # User-uploaded files land inside that state dir; no need for /mnt
  # or /srv access. If a future need arises (e.g. importing media into
  # Open WebUI's RAG knowledge base), add the path here.
  systemd.services.open-webui.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
    BindReadOnlyPaths = [ ];

    # DynamicUser needs supplementary group `keys` to read the
    # sops-rendered env file (mode 0440 root:keys).
    SupplementaryGroups = [ "keys" ];
    EnvironmentFile = config.sops.templates."open-webui-oauth-env".path;
  };

  # Exposed at https://chat.nori.lan via Caddy. Auto-monitored by Gatus.
  nori.lanRoutes.chat = {
    port = 8080;
    monitor = { };
  };
}
