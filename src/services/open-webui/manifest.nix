{
  active = false;
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  endpoints.chat = {
    port = 8080;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    oidc = {
      clientName = "Open WebUI";
      redirectPath = "/oauth/oidc/callback";
      tokenEndpointAuthMethod = "client_secret_basic";
      secretHashEnvName = "OIDC_CHAT_CLIENT_SECRET_HASH";
    };
    dashboard = {
      title = "Open WebUI";
      icon = "sh:open-webui";
      group = "Consume";
      description = "Local LLM chat (Ollama-backed)";
    };
  };
}
