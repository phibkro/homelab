_: {
  # Desktop integration for the operator-owned compatibility project. Keep its
  # pinned runtime and Steam ID in that project; do not duplicate them here.
  systemd.user.services.hdt-proton-autostart = {
    Unit = {
      Description = "Start HDT compatibility launcher when Hearthstone opens";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
      ConditionPathExists = "/srv/share/projects/reverse-engineering/hdt-proton/hdt.local.json";
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "/srv/share/projects/reverse-engineering/hdt-proton";
      ExecStart = "/etc/profiles/per-user/nori/bin/devenv shell -- bash /srv/share/projects/reverse-engineering/hdt-proton/autostart.sh";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };
  # Adopt the generated project-owned link used before the next full rebuild.
  # Scoped to this unit only; no other operator unit is replaced.
  xdg.configFile."systemd/user/hdt-proton-autostart.service".force = true;
}
