{ inputs, ... }:
{
  # home-manager as a NixOS module (per DESIGN.md L355-358) — config flows
  # from this Nix attrset into ~/.config/hypr/hyprland.conf etc. at
  # activation time.
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true; # use system nixpkgs, don't fork a per-user one
    useUserPackages = true; # install user pkgs to /etc/profiles/per-user
    extraSpecialArgs = { inherit inputs; };

    users.nori = {
      home.stateVersion = "25.11"; # match host's system.stateVersion
      programs.home-manager.enable = true;

      wayland.windowManager.hyprland = {
        enable = true;

        # Use the system Hyprland (programs.hyprland.enable = true above).
        # Without this home-manager would also install a user-scope copy
        # and the two could drift across rebuilds.
        package = null;
        portalPackage = null;

        settings = {
          # Samsung S34J552 — 34" ultrawide, native 3440x1440 @ 75Hz on DP-3.
          # Position 0x0, scale 1.0 (panel is large enough that 1440p reads
          # well at 1:1; bump to 1.25 if text feels small).
          monitor = [ "DP-3,3440x1440@75,0x0,1" ];

          # Norwegian keymap to mirror modules/common/base.nix (console.keyMap).
          input = {
            kb_layout = "no";
            follow_mouse = 1;
            sensitivity = 0;
          };

          general = {
            gaps_in = 4;
            gaps_out = 8;
            border_size = 2;
            layout = "dwindle";
          };

          decoration = {
            rounding = 4;
          };

          dwindle = {
            pseudotile = true;
            preserve_split = true;
          };

          # Mod key — SUPER (Windows / Cmd-equivalent).
          "$mod" = "SUPER";

          bind = [
            # Apps
            "$mod, RETURN, exec, ghostty"
            "$mod, SPACE,  exec, fuzzel"
            "$mod, B,      exec, zen"

            # Window
            "$mod, Q, killactive,"
            "$mod SHIFT, E, exit,"
            "$mod, V, togglefloating,"
            "$mod, F, fullscreen,"

            # Focus (vim-style + arrows)
            "$mod, h, movefocus, l"
            "$mod, j, movefocus, d"
            "$mod, k, movefocus, u"
            "$mod, l, movefocus, r"
            "$mod, left,  movefocus, l"
            "$mod, down,  movefocus, d"
            "$mod, up,    movefocus, u"
            "$mod, right, movefocus, r"

            # Workspaces 1-9
            "$mod, 1, workspace, 1"
            "$mod, 2, workspace, 2"
            "$mod, 3, workspace, 3"
            "$mod, 4, workspace, 4"
            "$mod, 5, workspace, 5"
            "$mod, 6, workspace, 6"
            "$mod, 7, workspace, 7"
            "$mod, 8, workspace, 8"
            "$mod, 9, workspace, 9"

            "$mod SHIFT, 1, movetoworkspace, 1"
            "$mod SHIFT, 2, movetoworkspace, 2"
            "$mod SHIFT, 3, movetoworkspace, 3"
            "$mod SHIFT, 4, movetoworkspace, 4"
            "$mod SHIFT, 5, movetoworkspace, 5"
            "$mod SHIFT, 6, movetoworkspace, 6"
            "$mod SHIFT, 7, movetoworkspace, 7"
            "$mod SHIFT, 8, movetoworkspace, 8"
            "$mod SHIFT, 9, movetoworkspace, 9"

            # Screenshot region → clipboard (shell-script-y; replace later
            # with a wrapper if it grows beyond one line).
            ", PRINT, exec, grim -g \"$(slurp)\" - | wl-copy -t image/png"
          ];

          bindm = [
            # Mouse drag move/resize
            "$mod, mouse:272, movewindow"
            "$mod, mouse:273, resizewindow"
          ];

          # Autostart — polkit agent for elevation prompts.
          # Wallpaper / status bar / notification daemon are deferred to
          # follow-up commits (waybar, mako, hyprpaper config).
          exec-once = [
            "systemctl --user start hyprpolkitagent"
          ];
        };
      };
    };
  };
}
