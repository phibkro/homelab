let
  active = true;
in
{
  inherit active;
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "gpu-bound"
    "stateful"
  ];

  endpoints =
    if active then
      {
        ai = {
          port = 11434;
          exposeOnTailnet = true;
          monitor.path = "/api/tags";
        };
      }
    else
      { };
}
