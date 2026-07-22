let
  active = false;
in
{
  inherit active;
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  endpoints =
    if active then
      {
        chat = {
          port = 8080;
          exposeOnTailnet = true;
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
      }
    else
      { };
}
