{
  config,
  lib,
  inputs,
  ...
}:

{
  /**
    workstation is a server + a desktop. Each concern import below declares
    one role this machine plays; the host is the sum of those concerns plus
    its physical hardware.
  */
  imports = [
    inputs.disko.nixosModules.disko

    ./waydroid.nix
    ./music-ingest.nix
    ./media-storage.nix
    ./resource-policy.nix
    ./hardware.nix
    ./backup-storage.nix
    ./disko.nix
    ./disko-media.nix
    ./disko-mp510.nix
    ./firecracker-environment.nix
  ];
  nori.selfHostedFirecracker.enable = true;

  # networking.hostName injected from the registry key in flake.nix.
  networking.useDHCP = lib.mkDefault true;

  /*
    DHCP still advertises the Genexis router as DNS, but it cannot resolve the
    inventory-derived home.phibkro.org records served by Pi-hole. Prefer the
    appliance explicitly on the workstation so builds and service checks do
    not depend on the pending router-wide DHCP DNS cutover. Keep one public
    resolver as degraded-mode fallback for internet names while Pi is down;
    internal names intentionally remain unavailable in that state.
  */
  networking.nameservers = [
    config.nori.inventory.hosts.pi.lanIp
    "1.1.1.1"
  ];

  /*
    Add the operator user to the `media` group so shell access and
    services running as `nori` can write to the media and family-library
    trees, which are owned root:media 02775 by the shared media setup.
    The group itself and this membership are declared elsewhere in the
    workstation profile; keep this host-specific prerequisite focused on
    the tmpfiles paths below.
  */
  users.users.nori.extraGroups = [ "media" ];

  /*
    Exa web-search credential for interactive OMP processes. SOPS decrypts the
    raw value for nori; the Home Manager OMP wrapper reads it only at launch
    and exports EXA_API_KEY to OMP without copying it into generated config.
  */
  sops.secrets.exa-api-key = {
    owner = "nori";
    mode = "0400";
  };

  /*
    ntfy topic for agent-attention pushes (home-manager: nori.agentNotify).
    Separate secret from the infra `ntfy-channel` so "an agent halted and
    needs you" is its own phone subscription + priority, not mixed with
    "a service is down". owner nori + mode 0400: only the operator's
    interactive agents read it (agent-notify runs as nori), unlike the
    world-readable infra channel that system alert units share.
  */
  sops.secrets.ntfy-agents-channel = {
    owner = "nori";
    mode = "0400";
  };

  /*
    2026-07-23: agents channel moved off ntfy.sh onto the self-hosted pi
    hub. FLEET/AGENT volume (every turn-end/permission/question ping from
    however many agents are running) was tripping ntfy.sh's public rate
    limit (429s, reproduced with a bare nori-alert call) — and it shares
    that quota with every OTHER alert on ntfy.sh, so a noisy fleet could
    silently starve a real infra alert of delivery.

    CRITICAL INFRA alerts (nori.alerts.channels.infra, wired in
    ntfy/notify.nix) deliberately STAY on ntfy.sh: they need to survive
    the homelab itself being down, so pointing them at a service the
    homelab hosts would be self-defeating. Fleet/agent alerts carry no
    such requirement — if pi is down, the phone will also see pi's other
    outage alerts (still on ntfy.sh) and losing agent chatter is a nonissue.

    The pi hub denies anonymous publish (auth-default-access = deny, see
    ntfy/server.nix + docs/runbooks/ntfy-auth-bootstrap.md) — reuse the
    same shared publisher token already provisioned there. It's read by
    home-manager's agent-notify, which runs as nori: same owner/mode as
    the topic secret above.
  */
  sops.secrets.ntfy-publisher-token = {
    owner = "nori";
    group = "keys";
    mode = "0440";
  };

  # The agents channel + route: agent-notify emits `--audience agents`,
  # this maps it to the dedicated topic. Defined here (not in the shared
  # home module) because the secret + nori-alert live at the system layer
  # on the host that runs the fleet.
  nori.alerts.channels.agents = {
    topicSecret = config.sops.secrets.ntfy-agents-channel.path;
    baseUrl = "https://alert.${config.nori.inventory.site.domain}";
    authTokenSecret = config.sops.secrets.ntfy-publisher-token.path;
  };
  nori.alerts.routes.agents = [ "agents" ];

  # Disabled after simultaneous backup failures fanned out into concurrent
  # agent/Nix checks and exhausted workstation memory on 2026-08-30.
  nori.agentFix.enable = false;
  nori.agentFix.units = map (name: "btrbk-${name}") (lib.attrNames config.services.btrbk.instances);

  # Tailnet service discovery uses MagicDNS. Keep this explicit on
  # the existing enrolled node; extraUpFlags only apply during first login.
  services.tailscale.extraSetFlags = [ "--accept-dns=true" ];

  /*
    /tmp is a btrfs subvolume inside @ on the system NVMe, not a tmpfs, so
    agent evidence and scratch worktrees there persist across reboots.
    systemd's tmp.conf already ages it at 10d; agent work on 2026-09-26 left
    ~21 GB younger than that. This line wins over tmp.conf because
    00-nixos.conf sorts first. Aging judges each file by its newest of
    atime/mtime/ctime (atime is frozen by noatime), deletes old files inside
    trees that are still in use, and skips only trees a process holds a BSD
    flock on. Work that must outlive a week belongs outside /tmp.
  */
  systemd.tmpfiles.rules = [ "q /tmp 1777 root root 7d" ];

  /*
    Blackmagic replaced the bytes served for the Resolve 21.1 Linux download
    without changing the version/API selector. Keep nixpkgs' package
    implementation, but correct its fixed-output hash until the nixpkgs pin
    carries the same upstream refresh. This is deliberately an override of
    the package argument rather than a copied package expression, so the
    source of truth for the build remains nixpkgs.
  */
  nixpkgs.overlays = [
    (_final: prev: {
      davinci-resolve = prev.davinci-resolve.override {
        runCommandLocal =
          name: attrs: script:
          prev.runCommandLocal name (
            attrs
            // lib.optionalAttrs (name == "davinci-resolve-src.zip") {
              outputHash = "sha256-+3SB32EHpH9/0hM3h8CrO6f7V4ZAmxUFh3P8m6QDeO0=";
            }
          ) script;
      };
    })
  ]
  ++ lib.optionals (builtins.getEnv "HOMELAB_CI" == "1") [
    /*
      CI-only stub for davinci-resolve. It's unfree → not on cache.nixos.org →
      every `nix flake check` in CI rebuilds a multi-GB binary repackage
      (fetch + autoPatchelf over GBs, ~40 min), right at the GitHub runner's
      disk/time limit — the 2026-07-18 SIGTERM (143) that killed a PR run.

      Pure eval sees getEnv "" → the real package, so local `just rebuild` and
      local `nix flake check` are UNAFFECTED. Only CI opts in, via
      `HOMELAB_CI=1 nix flake check --impure` (see .github/workflows/check.yml):
      then davinci-resolve becomes a no-op shim, the workstation toplevel builds
      in minutes, and CI keeps build-coverage of everything except this one
      proprietary blob. Tradeoff: the impurity is contained to the CI flag; the
      only lost coverage is "does davinci's binary repackage build", which is a
      stable upstream concern local rebuild catches before deploy.
    */
    (_final: prev: {
      davinci-resolve = prev.writeShellScriptBin "davinci-resolve" "exit 0";
    })
  ];

}
