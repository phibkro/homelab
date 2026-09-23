{
  ...
}:
/**
  Pure home-manager module — same shape as every other
  src/users/nori/workstation.nix. The home-manager-as-NixOS-module wrapper
  lives in the sibling default.nix so this file is portable.
*/
{
  imports = [
    ../../profiles/home/pc.nix
    ../../profiles/home/desktop
    ../../profiles/home/development/agentic-workstation.nix
    ./workstation.nix
  ];

  home.stateVersion = "26.05"; # match host's system.stateVersion
  # Stylix supplies the cursor package/name/size; Home Manager now requires
  # generation to be enabled explicitly instead of inferring it from values.
  home.pointerCursor.enable = true;
  programs.home-manager.enable = true;

}
