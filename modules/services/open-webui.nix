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
    };
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
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 ];
}
