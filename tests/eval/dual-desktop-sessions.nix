{
  inputs,
  lib,
  pkgs,
}:

/**
  The two graphical hosts expose the same local and remote desktop choices
  while keeping workstation-only gaming and virtualization isolated.
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
  hasSystemPackage =
    host: packageName:
    lib.any (package: lib.getName package == packageName) host.environment.systemPackages;

  desktopContract = host: {
    hyprland = host.programs.hyprland.enable;
    plasma = host.services.desktopManager.plasma6.enable;
    bigscreen =
      hasSystemPackage host "plasma-bigscreen"
      && hasSystemPackage host "plasma-nm"
      && hasSystemPackage host "kdeconnect-kde";
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
  remoteTcpPorts = [
    21118
    47984
    47989
    47990
    48010
  ];
  remoteUdpPorts = [
    47998
    47999
    48000
    48002
    48010
  ];
  remoteDesktopContract =
    host:
    let
      firewall = host.networking.firewall;
      tailnetFirewall = firewall.interfaces."tailscale0";
    in
    host.services.sunshine.enable
    && host.services.sunshine.package.version == "2026.914.233613"
    && host.services.sunshine.autoStart
    && host.services.sunshine.capSysAdmin
    && lib.elem "uinput" host.users.users.nori.extraGroups
    && !host.services.sunshine.openFirewall
    && !host.services.sunshine.settings.system_tray
    &&
      host.services.sunshine.settings.csrf_allowed_origins
      == "https://${host.networking.hostName}.saola-matrix.ts.net:47990"
    && !host.services.avahi.enable
    && !(host.services.rustdesk-server.enable or false)
    && host.systemd.user.services.sunshine.wantedBy == [ "graphical-session.target" ]
    && hasHomePackage host "moonlight-qt"
    && hasHomePackage host "rustdesk"
    && lib.all (port: lib.elem port tailnetFirewall.allowedTCPPorts) remoteTcpPorts
    && lib.all (port: lib.elem port tailnetFirewall.allowedUDPPorts) remoteUdpPorts
    && lib.all (port: !lib.elem port firewall.allowedTCPPorts) remoteTcpPorts
    && lib.all (port: !lib.elem port firewall.allowedUDPPorts) remoteUdpPorts;

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
    workstation.programs.steam.enable && workstation.virtualisation.libvirtd.enable;
  adelieIsolation =
    !(adelie.programs.steam.enable or false)
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
    && adelie.hardware.nvidia.videoAcceleration
    && adelie.hardware.nvidia.package == adelie.boot.kernelPackages.nvidiaPackages.production
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
    && contract.bigscreen
    && contract.greetd
    && !contract.competingManagers
    && contract.keyrings
  ) (lib.attrValues desktopContracts))
  "both graphical hosts must expose Plasma, Bigscreen, and UWSM Hyprland through greetd with PAM keyring unlock";
assert lib.assertMsg (
  (home workstation).nori.hyprRice.enable && (home adelie).nori.hyprRice.enable
) "both graphical homes must enable the shared Hyprland rice";
assert lib.assertMsg (lib.all lifecycleContract (
  lib.attrValues graphicalHosts
)) "Hyprland resource monitoring must start and stop with hyprland-session.target";
assert lib.assertMsg (lib.all remoteDesktopContract (
  lib.attrValues graphicalHosts
)) "both graphical hosts must provide tailnet-only RustDesk, Sunshine, and Moonlight peer access";
assert lib.assertMsg (
  (home workstation).home.sessionVariables.QT_STYLE_OVERRIDE == ""
  && (home adelie).home.sessionVariables.QT_STYLE_OVERRIDE == ""
) "both graphical homes must keep the invalid Plasma-wide Kvantum override disabled";
assert lib.assertMsg (
  workstationIsolation && adelieIsolation
) "Adelie must not inherit workstation gaming, virtualization, or application bundles";
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
    printf '%s\n' hyprland-uwsm.desktop plasma-bigscreen-wayland.desktop plasma.desktop > expected
    for session in ${chooserDirectory}/*.desktop; do
      basename "$session"
    done | sort > actual
    diff -u expected actual
    test -e ${chooserDirectory}/hyprland-uwsm.desktop
    test -e ${chooserDirectory}/plasma.desktop
    test -e ${chooserDirectory}/plasma-bigscreen-wayland.desktop
    test -z "$(find ${xSessionDirectory} -mindepth 1 -print -quit)"
    touch "$out"
  ''
