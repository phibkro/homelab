{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "all-matches";
    selectors = [
      { host = "workstation"; }
      { host = "adelie"; }
    ];
    cardinality = {
      min = 2;
      max = 2;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "cache"
    "publisher"
  ];
}
