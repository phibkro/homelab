{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Gaming-related programs + system tweaks for workstation's desktop
  # session. Lives in modules/desktop/ because each is meaningless on a
  # headless host — pi never wants Steam.
  #
  # Components:
  #   programs.steam            Steam runtime, udev rules for
  #                             controllers, multi-arch (32-bit) for
  #                             Wine/Proton-based Windows games.
  #   programs.gamescope        Gamescope compositor (used by Steam's
  #                             Big Picture / SteamOS-like sessions).
  #                             enabling makes the binary available;
  #                             gamescopeSession.enable would also
  #                             register a session entry — left off so
  #                             Hyprland stays the default session.
  #   programs.gamemode         CPU/GPU governor + scheduler tweaks
  #                             during games. opt-in per game via
  #                             `gamemoderun %command%` in Steam launch
  #                             options; harmless if never used.
  #   hardware.graphics.enable32Bit  32-bit GL libs for Wine/Proton
  #                                  (most Windows games are 32-bit
  #                                  even when run on 64-bit Wine).
  #
  # NVIDIA-specific: hardware.nvidia.modesetting + open kernel module
  # are already on (hardware.nix). Proton on NVIDIA Wayland works in
  # current driver 595; minor games with anti-cheat may need explicit
  # `WINE_FULLSCREEN_FSR=1` or similar (per-game launch option).

  programs.steam = {
    enable = true;
    # remotePlay would let other devices stream from this host; keeping
    # firewall closed keeps the default-deny posture. Flip true if/when
    # SteamLink from another tailnet device is wanted.
    remotePlay.openFirewall = false;
    # Bundled gamescope wrapper available; full Big Picture session
    # gated separately if/when wanted.
    gamescopeSession.enable = false;
  };

  programs.gamescope.enable = true;
  programs.gamemode.enable = true;

  hardware.graphics.enable32Bit = true;
}
