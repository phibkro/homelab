{ pkgs, ... }:

/**
  General development tools shared by every operator shell.

  Language compilers and project-specific CLIs belong in project dev shells.
  These tools stay global because they operate on the Nix configuration or
  provide the repository-independent edit/test loop on every homelab node.
*/
{
  home.packages = with pkgs; [
    just
    ripgrep
    nixd
    nil
    devenv
    nodejs
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "Philip B. Krogh";
      user.email = "71797726+phibkro@users.noreply.github.com";
      user.useConfigOnly = true;
      init.defaultBranch = "main";
      safe.directory = "*";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
