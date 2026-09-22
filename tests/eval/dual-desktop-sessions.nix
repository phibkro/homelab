{
  inputs,
  lib,
  pkgs,
}:

/**
  The two graphical hosts expose the same local session choices while keeping
  workstation-only authority and Hyprland-only services isolated.
*/
let
  hosts = inputs.self.nixosConfigurations;
  inventory = inputs.self.lib.noriInventory;
  workstation = hosts.workstation.config;
  adelie = hosts.adelie.config;
  graphicalHosts = {
    inherit workstation adelie;
  };

  home = host: host.home-manager.users.nori;
  markerHost =
    host:
    (builtins.fromJSON (
      builtins.unsafeDiscardStringContext
        host.environment.etc."nori-desktop-settings/approved-source.json".text
    )).host;
  hasHomePackage =
    host: packageName: lib.any (package: lib.getName package == packageName) (home host).home.packages;

  desktopContract = host: {
    hyprland = host.programs.hyprland.enable;
    plasma = host.services.desktopManager.plasma6.enable;
    greetd = host.services.greetd.enable && host.services.greetd.useTextGreeter;
    competingManagers =
      host.services.displayManager.sddm.enable
      || host.services.displayManager.plasma-login-manager.enable;
    keyrings =
      host.security.pam.services.greetd.enableGnomeKeyring
      && host.security.pam.services.greetd.kwallet.enable
      && host.security.pam.services.greetd.kwallet.forceRun;
  };
  desktopContracts = lib.mapAttrs (_: desktopContract) graphicalHosts;

  lifecycleContract =
    host:
    let
      sessionHome = home host;
      target = sessionHome.wayland.systemd.target;
      service = sessionHome.systemd.user.services.steady-state-resource-alert;
      timer = sessionHome.systemd.user.timers.steady-state-resource-alert;
    in
    target == "hyprland-session.target"
    && service.Unit.PartOf == [ target ]
    && service.Unit.After == [ target ]
    && timer.Unit.PartOf == [ target ]
    && timer.Unit.After == [ target ]
    && timer.Install.WantedBy == [ target ];

  workstationIsolation =
    workstation.programs.steam.enable
    && workstation.services.sunshine.enable
    && workstation.virtualisation.libvirtd.enable;
  adelieIsolation =
    !(adelie.programs.steam.enable or false)
    && !(adelie.services.sunshine.enable or false)
    && !(adelie.virtualisation.libvirtd.enable or false)
    && lib.all (packageName: !hasHomePackage adelie packageName) [
      "audacity"
      "davinci-resolve"
      "discord"
      "zotero"
    ];

  inventoryComposition =
    lib.all (hostName: lib.elem "graphical-desktop" inventory.hosts.${hostName}.profiles)
      [
        "adelie"
        "workstation"
      ];
  sourceMarkers = markerHost workstation == "workstation" && markerHost adelie == "adelie";
  nvidiaDisplay =
    adelie.services.xserver.videoDrivers == [ "nvidia" ]
    && adelie.hardware.graphics.enable
    && adelie.hardware.nvidia.open
    && adelie.hardware.nvidia.modesetting.enable
    && adelie.nori.gpu.nvidiaDevices == [ ];

  chooserDirectory = workstation.environment.etc."greetd/sessions".source;
  xSessionDirectory = workstation.environment.etc."greetd/xsessions".source;
  chooserContract =
    workstation.services.greetd.settings.default_session.command
    == adelie.services.greetd.settings.default_session.command
    &&
      workstation.services.greetd.settings.default_session.command
      == "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --asterisks --sessions /etc/greetd/sessions --xsessions /etc/greetd/xsessions --cmd 'uwsm start hyprland-uwsm.desktop'"
    && adelie.environment.etc."greetd/sessions".source == chooserDirectory
    && adelie.environment.etc."greetd/xsessions".source == xSessionDirectory;
in
assert lib.assertMsg
  (lib.all (
    contract:
    contract.hyprland
    && contract.plasma
    && contract.greetd
    && !contract.competingManagers
    && contract.keyrings
  ) (lib.attrValues desktopContracts))
  "both graphical hosts must expose Plasma and UWSM Hyprland through greetd with PAM keyring unlock";
assert lib.assertMsg (
  (home workstation).nori.hyprRice.enable && (home adelie).nori.hyprRice.enable
) "both graphical homes must enable the shared Hyprland rice";
assert lib.assertMsg (lib.all lifecycleContract (
  lib.attrValues graphicalHosts
)) "Hyprland resource monitoring must start and stop with hyprland-session.target";
assert lib.assertMsg (
  workstationIsolation && adelieIsolation
) "Adelie must not inherit workstation gaming, remote-play, virtualization, or application bundles";
assert lib.assertMsg inventoryComposition
  "both graphical hosts must select the shared profile explicitly";
assert lib.assertMsg sourceMarkers
  "desktop-settings authority markers must name their evaluated host";
assert lib.assertMsg nvidiaDisplay
  "Adelie must use the production NVIDIA display stack without granting service devices";
assert lib.assertMsg chooserContract
  "both greetd instances must use the same filtered chooser and Hyprland fallback";
pkgs.runCommandLocal "eval-dual-desktop-sessions"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
    ];
  }
  ''
    set -eu
    printf '%s\n' hyprland-uwsm.desktop plasma.desktop > expected
    for session in ${chooserDirectory}/*.desktop; do
      basename "$session"
    done | sort > actual
    diff -u expected actual
    test -e ${chooserDirectory}/hyprland-uwsm.desktop
    test -e ${chooserDirectory}/plasma.desktop
    test -z "$(find ${xSessionDirectory} -mindepth 1 -print -quit)"
    touch "$out"
  ''
