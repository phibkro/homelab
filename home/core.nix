{ pkgs, ... }:

# Cross-platform home-manager core. Imported by:
#   * modules/desktop/home.nix (Linux desktop, via home-manager NixOS module)
#   * modules/home/macbook.nix (Mac standalone, via flake homeConfigurations)
#
# What lives here: cross-platform CLI tooling and identity that the
# operator wants on every interactive machine — same shell prompt,
# same git config, same `,` for ad-hoc nix packages.
#
# What does NOT live here:
#   * Linux-desktop-specific bits (Hyprland, GTK/Qt themes, Wayland
#     cursor, X11/Wayland-only programs) → modules/desktop/home.nix
#   * Mac-specific bits (~/Library/Fonts symlink, NODE_EXTRA_CA_CERTS,
#     home.username/homeDirectory) → modules/home/macbook.nix
#   * Hardware-tied tooling (nvtop = NVIDIA, compsize = btrfs)
#
# Rule-of-three threshold note: extracted at 2 instances (Mac + Linux
# desktop) because the operator explicitly named the share. Third
# instance (laptop NixOS) is expected to widen the shared set —
# anticipate moving more cross-platform CLI here at that point.

{
  home.packages = with pkgs; [
    comma # `, <pkg>` runs nix packages ad-hoc; companion to `nix shell`

    # Operator tools — interactive use, not system services. Previously
    # split between modules/desktop/apps.nix systemPackages (workstation)
    # and modules/home/macbook.nix home.packages (Mac); centralized here.
    age # ad-hoc encryption (host SSH keys handle sops-nix activation)
    sops # interactive secrets editing
    claude-code # Anthropic CLI; runs as the operator, not as a service
  ];

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    # JetPack preset — https://starship.rs/presets/jetpack/
    # Minimal `$character` left, everything else right_format. Nerd
    # Font glyphs in module formats; pair with any Nerd Font in the
    # terminal (Hack Nerd Font on Mac via home.file, on workstation
    # via system-level fonts.packages in modules/desktop/apps.nix).
    settings = {
      add_newline = false;
      format = "$character";
      right_format = "$all";
      continuation_prompt = "▶▶ ";

      character = {
        success_symbol = "[◎](bold green)";
        error_symbol = "[●](bold red)";
        vimcmd_symbol = "[■](bold green)";
      };

      git_branch.format = "[$symbol$branch(:$remote_branch)]($style) ";

      nodejs = {
        format = "[$symbol($version )]($style)";
        symbol = " ";
      };

      python = {
        format = "[$symbol$pyenv_prefix($version )(\\($virtualenv\\) )]($style)";
        symbol = " ";
      };
    };
  };

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
}
