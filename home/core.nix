{ pkgs, ... }:

# Cross-platform home-manager core, imported by every machine's
# `home.nix`. The operator's interactive baseline: shell prompt, git
# config, sops/age, common CLI on PATH.
#
# Pi imports this too. Heavy packages (claude-code → Node, anything
# pulling large Rust/C++ toolchains) live per-machine in
# `machines/<machine>/home.nix` rather than here — pi's anti-write
# USB SSD shouldn't carry packages it can't use.

{
  home.packages = with pkgs; [
    comma # `, <pkg>` runs nix packages ad-hoc
    just
    ripgrep
    tmux
    age
    sops
    nixd
    nil
    devenv
  ];

  programs.git = {
    enable = true;
    # GitHub-provided noreply address — keeps the real email out of
    # public commit history. ID prefix is GitHub's per-account stable
    # identifier; required so GitHub can attribute commits to the
    # account when matched against an associated email.
    settings = {
      user.name = "phibkro";
      user.email = "71797726+phibkro@users.noreply.github.com";
      init.defaultBranch = "main";
    };
  };

  # Per-project dev shells without a manual `nix develop`: direnv reads a
  # repo's `.envrc` (`use flake`) on `cd` and loads its pinned toolchain;
  # nix-direnv caches the built shell so re-entry is instant and GC-pins the
  # closure. Pairs with the self-contained project flakes (pagu, bang-lang,
  # occupational-health). Opt in per repo with `direnv allow`.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
