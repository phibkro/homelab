{ pkgs, ... }:
{
  # Inhibits Wayland's idle-inhibit-unstable-v1 protocol while PipeWire
  # has active media streams. Plugs the gap left when we removed
  # hypridle's ignore_dbus_inhibit setting in this session: long videos
  # / music now keep the machine awake automatically, without re-opening
  # the browser-tab-leak exposure (the 2026-06-08 OOM came from a
  # *generic* dbus inhibit being held by an idle tab, not from PipeWire).
  #
  # min-media-duration filters out short notification beeps / UI feedback
  # so they don't briefly trigger inhibit. 5s is the upstream default
  # and matches what other Wayland-shell users have settled on.
  #
  # Defense against the OOM leak case still belongs at MemoryHigh caps
  # on the browser (tracked in docs/ROADMAP.md § "MemoryHigh caps"), NOT
  # at the idle layer.
  home.packages = [ pkgs.wayland-pipewire-idle-inhibit ];

  systemd.user.services.wayland-pipewire-idle-inhibit = {
    Unit = {
      Description = "Inhibit Wayland idle while PipeWire streams are active";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "pipewire.service" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wayland-pipewire-idle-inhibit}/bin/wayland-pipewire-idle-inhibit";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
