{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  atticClientConfig = pkgs.writeTextDir "attic/config.toml" ''
    default-server = "nori"

    [servers.nori]
    endpoint = "https://cache.${config.nori.domain}/"
    token-file = "${config.sops.secrets.attic-push-token.path}"
  '';
  atticPush = pkgs.writeShellApplication {
    name = "nori-cache-push";
    text = ''
      export XDG_CONFIG_HOME=${atticClientConfig}
      exec ${lib.getExe pkgs.attic-client} push nori "$@"
    '';
  };
in
{
  # --- nix ---------------------------------------------------------------

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];

      /*
        Binary cache substituters. cache.nixos.org is the default
        upstream cache (NixOS module sets it implicitly).

        Nothing here covers aarch64-linux Pi-specific builds, so the
        linux-rpi kernel is compiled from source whenever it changes.
        That compile lands on this machine under binfmt emulation,
        because pi closures are built on the workstation and pushed;
        the CI pi-build job proves the same closure on a native ARM
        runner but keeps nothing.
      */
      extra-substituters = [
        /*
          nixpkgs-cuda-ci builds nixpkgs with cudaSupport=true and
          publishes here. Without it, every CUDA-touching derivation
          (cudatoolkit, cudnn, onnxruntime+cuda, …) compiles from
          source — hours to many hours per rebuild. Migrated from
          cuda-maintainers.cachix.org to cache.nixos-cuda.org Nov 2025.
        */
        "https://cache.nixos-cuda.org"
        /*
          The homelab Attic cache is populated by successful builds on every
          host. Its signing key is declarative, so a cache response is accepted
          only when it matches this trust root.
        */
        "https://cache.${config.nori.domain}/nori"
      ];
      extra-trusted-public-keys = [
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "attic.nori.lan-1:3zt/aS8K1bSEjNvZQB9ga9OeZTxcRkvbb7aYRI/vobo="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;
  sops.secrets.attic-push-token = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "attic_push_token";
    owner = "root";
    mode = "0400";
    restartUnits = [
      "attic-cache-seed.service"
      "attic-cache-watch.service"
    ];
  };

  /*
    Seed the complete active system at boot, then watch individual store
    additions continuously. The seed closes the watcher's intentional gap:
    watch-store only sees paths completed while it is running.
    Attic filters paths already signed by configured upstream caches.
  */
  systemd.services.attic-cache-seed = {
    description = "Publish the active system closure to the homelab Attic cache";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment.XDG_CONFIG_HOME = atticClientConfig;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.attic-client} push nori --jobs 2 /run/current-system";
      Restart = "on-failure";
      RestartSec = "60s";
    };
  };

  systemd.services.attic-cache-watch = {
    description = "Publish new Nix store paths to the homelab Attic cache";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment.XDG_CONFIG_HOME = atticClientConfig;
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.attic-client} watch-store nori --jobs 2";
      Restart = "on-failure";
      RestartSec = "60s";
    };
  };

  nori.harden.attic-cache-seed = { };
  nori.harden.attic-cache-watch = { };

  /*
    Known-insecure packages we accept. Each entry is a deliberate
    trade-off, not a blanket allow. Promote to removal as soon as
    nixpkgs ships a non-EOL bump.

    electron-39.8.10 — bundled by bitwarden-desktop in nixos-26.05.
      Verified still required on stable 2026-06-03 (a removal attempt
      failed the build). Accepted because the electron renderer here
      only displays the vault UI (sandboxed, no broad attack surface
      in this app's usage). Remove when `bitwarden-desktop` in nixpkgs
      bumps electron.
  */
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];

  # --- locale / time -----------------------------------------------------

  time.timeZone = "Europe/Oslo";
  /*
    Locale stays en_US for English error messages / man pages / web
    search continuity. Switch to nb_NO.UTF-8 if you want Norwegian
    date/sort formats too.
  */
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "no";

  # --- packages (minimal baseline shared by all hosts) ------------------

  /*
    System-scope only what root + system services + emergency operations
    genuinely need. Operator-interactive CLI (just, ripgrep, tmux,
    starship, etc.) lives in modules/home/profiles/core.nix — every host
    (incl. pi) imports a modules/home/<host>.nix that pulls in core, so nori on
    any machine has the same baseline.
  */
  environment.systemPackages = with pkgs; [
    bat
    curl
    delta # syntax-highlighted git diff pager — used by `just show-pending-diff`
    dig
    fd
    git # nh + Nix flake operations need git on system PATH
    htop
    tree
    vim
    wget
    atticPush
  ];

  /*
    Default editor — sops uses $EDITOR to launch the secrets editor
    session, git uses it for commit messages, crontab + visudo follow
    the same convention. Setting both EDITOR and VISUAL covers tools
    that distinguish (notably `sudo -e` follows VISUAL first).
  */
  environment.variables = {
    EDITOR = "vim";
    VISUAL = "vim";
  };

  /**
    nh wraps `nixos-rebuild` with internal sudo elevation (don't prefix
    `nh` with sudo) and `--target-host` for SSH-based remote deployment.
    The Justfile + `just remote` wrap the common invocations.
  */
  programs.nh.enable = true;

  /*
    nix-ld provides the dynamic loader + a curated LD_LIBRARY_PATH for
    prebuilt non-NixOS Linux binaries. Required for Zed's remote-server
    (auto-installed under ~/.zed-server/ when Zed connects via SSH) and
    other dev tools that ship Linux binaries.

    Library set is iterative: extend when a binary errors with
    "error while loading shared libraries: <name>" — find it via
    `nix-locate <name>`.
  */
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc # libstdc++, libgcc_s
      zlib
      openssl
      curl
      glibc
    ];
  };

  # --- swap (zram) -------------------------------------------------------

  /*
    Compressed in-memory swap. No disk required; kernel compresses evicted
    pages with zstd before they land in the zram device. At 50% of RAM
    (default) this machine gets ~16 GiB of swap backed by ~8 GiB of
    physical RAM at ~2x compression.

    Primary motivation: CUDA compilation (nvcc, onnxruntime) is extremely
    memory-hungry and caused an OOM + unresponsive system when attempted
    with no swap. zram gives the kernel somewhere to shed pressure instead
    of killing processes. Low overhead when idle.
  */
  zramSwap.enable = true;

  # --- firewall ----------------------------------------------------------

  networking.firewall.enable = true;

  # --- versioning --------------------------------------------------------

  /*
    stateVersion is a *migration* marker, not the nixpkgs version.
    Do not bump this casually. It captures the defaults in effect when the
    system was first installed so stateful services don't silently reshape.
  */
  system.stateVersion = "25.11";

  # --- MOTD --------------------------------------------------------------

  /*
    Codename + role banner on login. Written directly to /etc/motd
    (via environment.etc rather than users.motd) so sshd's
    PrintMotd picks it up — users.motd goes through pam_motd which
    isn't enabled for sshd by default and would silently not show.

    Hostnames stay as identifiers (SSH / known_hosts / Tailscale /
    nix flake refs); codenames are aesthetic. Theme: polar / penguin.
    See modules/infra/hosts.nix for the full mapping.

    Gated on rust-motd not being enabled — pavilion + aurora opt in
    to rust-motd for live battery/cpu/memory/service data; this
    static banner is the fallback for hosts that don't (pi,
    workstation).
  */
  environment.etc.motd =
    let
      self = config.nori.hosts.${config.networking.hostName} or null;
      useRust = config.programs.rust-motd.enable or false;
    in
    lib.mkIf (self != null && !useRust) {
      text = ''

        ${self.codename or config.networking.hostName} (${config.networking.hostName}) — ${self.role}

      '';
    };

  services.openssh.settings.PrintMotd = lib.mkDefault true;
}
