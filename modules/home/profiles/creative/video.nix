{ inputs, pkgs, ... }:

let
  resolve-remux = pkgs.writeShellApplication {
    name = "resolve-remux";
    runtimeInputs = [ pkgs.ffmpeg ];
    text = builtins.readFile ../../desktop/resolve-remux.sh;
  };
in
/**
  Video creation and validation. FLAC/music processing is deliberately not
  coupled here; that belongs to the music dataset pipeline.
*/
{
  home.packages = [
    pkgs.davinci-resolve
    inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.handbrake
    pkgs.vlc
    pkgs.mpv
    resolve-remux
  ];
}
