{ pkgs, ... }:
{
  home.packages = [
    pkgs.obsidian
    # pkgs.zotero is removed until nixpkgs fixes it: 10.0.2 (nixos-unstable
    # c59305b) and 10.0.4 (master bae6f80) both abort in buildPhase with
    # "AboutTranslations ... not found in modules/ActorManagerParent.sys.mjs"
    # against firefox-esr-153-unwrapped 153.4.0esr (observed 2026-10-02).
    # Restore `pkgs.zotero` once a nixpkgs bump builds it.
  ];
}
