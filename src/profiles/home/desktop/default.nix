/**
  Full workstation desktop profile. The reusable Hyprland session is combined
  with the workstation application groups below.
*/
{
  imports = [
    ./hyprland-session.nix
    ./productivity.nix
    ./communication.nix
    ./research.nix
    ../creative/audio.nix
    ../creative/video.nix
  ];
}
