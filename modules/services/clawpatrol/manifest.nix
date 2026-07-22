{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;

  endpoints.clawpatrol = {
    port = 8092;
    exposeOnTailnet = true;
    audience = "operator";
    noAuthReason = "Claw Patrol enforces its own root-password dashboard session";
  };
}
