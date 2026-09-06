_: {
  /*
    hyprlock only — the manual lock screen UI (Super+L). hypridle is
    deliberately not enabled. Workstation is the converged desktop/server;
    this module provides manual locking without an idle suspend policy.
  */
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 2; # ignore input for 2s after wake to avoid accidental unlock
        ignore_empty_input = true;
      };

      background = [
        {
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
        }
      ];

      label = [
        {
          text = "$TIME";
          color = "rgba(220, 220, 220, 1.0)";
          font_size = 96;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, 220";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          size = "320, 56";
          position = "0, -120";
          halign = "center";
          valign = "center";
          outline_thickness = 2;
          dots_size = 0.3;
          dots_spacing = 0.3;
          fade_on_empty = true;
          placeholder_text = "Password";
          check_color = "rgba(204, 153, 255, 1.0)";
        }
      ];
    };
  };

}
