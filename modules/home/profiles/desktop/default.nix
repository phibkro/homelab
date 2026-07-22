/**
  Complete operator desktop profile. The session implementation is private;
  app groups are independently selectable capabilities for future roles.
*/
{
  imports = [
    ../../desktop
    ./wayland-session.nix
    ./productivity.nix
    ./communication.nix
    ./research.nix
    ../creative/audio.nix
    ../creative/video.nix
  ];
}
