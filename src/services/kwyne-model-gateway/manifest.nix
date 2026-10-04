let
  route = builtins.fromJSON (
    builtins.readFile ../../infra/cloudflare/routes/kwyne-model-gateway.json
  );
in
{
  active = true;
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
    "operator-tier"
    "stateful"
  ];
  # Private listeners reserve ports without projecting Pi/LAN/tailnet endpoints.
  listeners.broker.port = route.brokerPort;
  listeners.gateway.port = route.originPort;
}
