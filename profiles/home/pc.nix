{ pkgs, ... }:

/**
  Operator-attached computer profile. This is the public composition
  boundary for a trusted interactive PC; machine realizations add only
  hardware-, OS-, or role-specific deviations.
*/
{
  imports = [
    ./core.nix
    ./development/agentic-tools.nix
  ];

  home.packages = [ pkgs.gh ];
}
