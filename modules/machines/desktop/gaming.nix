_:

{
  /*
    Steam + Proton stack for workstation's desktop session — placed in
    modules/machines/desktop/ because each is meaningless headless (pi never wants
    Steam). NVIDIA modesetting + open kernel module live in hardware.nix;
    anti-cheat games may need `WINE_FULLSCREEN_FSR=1` or similar per-game
    launch options.
  */

  programs.steam = {
    enable = true;
    /*
      remotePlay would let other devices stream from this host; keeping
      firewall closed keeps the default-deny posture. Flip true if/when
      SteamLink from another tailnet device is wanted.
    */
    remotePlay.openFirewall = false;
    # Off so Hyprland stays the default session; the gamescope wrapper
    # is still available via programs.gamescope below.
    gamescopeSession.enable = false;
  };

  programs.gamescope.enable = true;
  programs.gamemode.enable = true;

  hardware.graphics.enable32Bit = true;
}
