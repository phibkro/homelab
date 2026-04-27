{
  config,
  lib,
  pkgs,
  ...
}:

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
      # OIDC env vars that don't contain secrets. The secret-bearing
      # OAUTH_CLIENT_SECRET is loaded from the sops-rendered env file
      # at /run/secrets/rendered/oidc-chat-env via EnvironmentFile
      # below — auto-declared by the lan-route abstraction (see
      # `nori.lanRoutes.chat.oidc` at the bottom of this file).
      OPENID_PROVIDER_URL = "https://auth.nori.lan/.well-known/openid-configuration";
      OAUTH_CLIENT_ID = "chat";
      OAUTH_PROVIDER_NAME = "Authelia";
      ENABLE_OAUTH_SIGNUP = "True";
      # Link OAuth identities to existing accounts by email match
      # instead of creating a duplicate. Default is false because in
      # multi-IdP setups a malicious provider could spoof emails to
      # take over accounts; here Authelia is the only OIDC issuer
      # and we trust its email claims, so the safety vs. UX
      # tradeoff falls on the merge side. Without this, an Authelia
      # email change creates an orphan account (we hit this once
      # already during the proton-vs-gmail mismatch).
      OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "True";
      # Python's httpx/requests/urllib3 use certifi's bundled trust
      # store by default — they don't see /etc/ssl/certs and so don't
      # trust Caddy's local CA. SSL_CERT_FILE overrides certifi to use
      # the system bundle (which has the local CA via
      # security.pki.certificateFiles in modules/services/caddy.nix).
      SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
      REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
    };
  };

  # Default-deny filesystem access beyond Open WebUI's own state dir
  # (DynamicUser StateDirectory at /var/lib/open-webui handles itself).
  # User-uploaded files land inside that state dir; no need for /mnt
  # or /srv access. If a future need arises (e.g. importing media into
  # Open WebUI's RAG knowledge base), add the path here.
  systemd.services.open-webui.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];

    # DynamicUser needs supplementary group `keys` to read the
    # sops-rendered env file (mode 0440 root:keys).
    SupplementaryGroups = [ "keys" ];
    EnvironmentFile = config.sops.templates."oidc-chat-env".path;
  };

  # Exposed at https://chat.nori.lan via Caddy. Auto-monitored by
  # Gatus. OIDC client + sops secret + env-file template auto-
  # generated from the `oidc = { ... }` block — see
  # modules/lib/lan-route.nix for the schema and
  # modules/services/authelia.nix for the clients-list assembly.
  nori.lanRoutes.chat = {
    port = 8080;
    monitor = { };
    oidc = {
      clientName = "Open WebUI";
      redirectPath = "/oauth/oidc/callback";
    };
  };
}
