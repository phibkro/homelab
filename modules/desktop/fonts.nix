{ pkgs, ... }:
{
  /*
    System-level font set for the Linux desktop session. fontconfig
    picks these up via /run/current-system/sw/share/fonts/, so every
    rendering process — Ghostty, fuzzel, waybar, mako, Hyprlock,
    Zen, Electron apps, even system services that emit text — sees
    the same font baseline.

    Minimal by intent: enough so apps don't render tofu boxes (squares
    for missing glyphs) without pulling tens of MB of unused families.
    JetBrainsMono Nerd Font is the terminal / launcher / hyprlock font
    (see home/desktop/hypr-lock.nix `font_family`); plain JetBrainsMono
    for documents that don't need Nerd Font icons; noto-fonts +
    noto-fonts-color-emoji + dejavu_fonts cover broad Unicode + emoji.

    System scope (vs home-manager) because fontconfig system path is the
    path GUI apps + system processes both honor; pi (no GUI) doesn't
    import modules/desktop/ so it stays font-free. Mac handles fonts at
    user scope (~/Library/Fonts) in machines/macbook/home.nix because
    macOS has no system layer here.
  */
  fonts.packages = [
    # Sans-serif primary — Roboto is Google's Material Design body font;
    # pairs with Material Symbols below for a coherent UI.
    pkgs.roboto
    # Mono — JetBrainsMono + the Nerd Font variant (programming ligatures
    # + powerline / device / brand glyphs for prompts, lazygit, btop).
    pkgs.jetbrains-mono
    pkgs.nerd-fonts.jetbrains-mono
    # Fallback chain — Noto covers ~all of Unicode, color-emoji handles
    # 🌍 + flags etc., dejavu fills gaps where Noto's coverage is patchy.
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    pkgs.dejavu_fonts
    /*
      Material Symbols — Google's Material Design icon font. Used by the
      waybar blue-light toggle (light_mode / dark_mode glyphs); install
      system-wide so any future Material-Symbols-using widget just works.
    */
    pkgs.material-symbols
  ];
}
