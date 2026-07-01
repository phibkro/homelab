_: {
  /**
    Mako — Wayland notification daemon. Picks up `notify-send` from any
    CLI / app and renders toasts in the corner. home-manager provisions
    a systemd user service that starts at session login.

    Defaults are sensible; the only knob set is corner radius matching
    Hyprland's `decoration.rounding = 4` for visual consistency.
  */
  services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000; # 5s
      border-radius = 4;
      border-size = 2;
      max-visible = 5;
      anchor = "top-right";
      margin = "12";
      padding = "10";

      /*
        Layer OSD ("which special-workspace tag is now showing" —
        modules/machines/workstation/home.nix's layer-toggle/layer-cycle
        scripts send `notify-send -a layer-osd`). Scoped to this one
        app-name so regular notifications keep the corner/5s default;
        only this criteria gets the center/fast-timeout toast treatment.
        Fade in/out is NOT mako's doing — mako has no opacity/transition
        support at all (checked: mako(5) has zero hits for fade/opacity).
        It comes free from Hyprland's `fadeLayersIn`/`fadeLayersOut`
        animation, which applies to any layer-shell surface (mako's
        popups included) and is enabled by default — confirmed via
        `hyprctl animations` 2026-07-01.
      */
      "app-name=layer-osd" = {
        anchor = "center";
        default-timeout = 900;
        width = 220;
        height = 70;
        font = "sans 20";
        border-radius = 16;
      };
    };
  };
}
