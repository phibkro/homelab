{
  config,
  lib,
  pkgs,
  ...
}:

# filmder — TMDB-backed movie browser. Operator's old NTNU project
# (uni group work, 2023). Static Vite + React build, public via
# Tailscale Funnel.
#
# ── Build/deploy shape ─────────────────────────────────────────────
# Build is an *activation-time systemd oneshot* rather than a Nix
# flake build, because filmder's TMDB token is read at *build time*
# by Vite and embedded into the JS bundle (`import.meta.env.VITE_*`).
# Nix's hermetic build sandbox can't read /run/secrets/X, so the
# clean `nix build → /nix/store/<hash>-filmder` path doesn't apply
# here. Activation-time build with the secret read via systemd
# `EnvironmentFile`-equivalent (just `cat /run/secrets/...` in the
# script) is the pragmatic compromise.
#
# That said: the TMDB read token in the deployed JS bundle is
# *publicly visible* — anyone who view-sources the page can scrape
# it. Sops here gives git hygiene + rotation ergonomics, not
# deployed-secrecy. Real secrecy would require a server-side proxy
# that holds the token (significant filmder refactor).
#
# ── Trigger ──────────────────────────────────────────────────────
# `filmder-build.service` is a oneshot but NOT in `wantedBy` — every
# nixos-rebuild would otherwise re-run npm-install + vite-build
# (~40-60s), which is wasteful on no-op rebuilds. Operator triggers
# it explicitly via `just deploy-app filmder` (which calls
# `systemctl start filmder-build.service`). The funnel exposure
# (`tailscale-funnel-config.service` from nori.funnelRoutes) starts
# at boot regardless; before first build, it serves 404 until the
# operator runs the deploy script once.

let
  inherit (config.sops) secrets;
  filmderRepo = "https://github.com/phibkro/filmder.git";
in
{
  sops.secrets.tmdb-token = {
    sopsFile = ../../secrets/apps.yaml;
    owner = "filmder";
    mode = "0400";
  };

  users.users.filmder = {
    isSystemUser = true;
    group = "filmder";
    home = "/var/lib/filmder";
    description = "filmder build + serve user";
  };
  users.groups.filmder = { };

  systemd.services.filmder-build = {
    description = "Build filmder static site (manual trigger via `just deploy-app filmder`)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # Tooling on PATH for the script. nodejs ships bundled npm.
    # `bash` is required by some npm postinstall scripts (notably
    # @swc/core, which spawns `sh` to run platform-detection logic).
    # Without it, `npm ci` fails with `spawn sh ENOENT`.
    path = with pkgs; [
      bash
      git
      nodejs_22
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "filmder";
      Group = "filmder";

      # systemd-managed state dir — exposes $STATE_DIRECTORY to the
      # script. Created with mode 0750, owned by filmder:filmder.
      StateDirectory = "filmder";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/filmder";
    };

    script = ''
      set -euo pipefail

      # 1. Pull or clone source.
      if [ ! -d src/.git ]; then
        rm -rf src
        git clone --depth 1 ${filmderRepo} src
      else
        git -C src fetch --depth 1 origin main
        git -C src reset --hard origin/main
      fi

      cd src

      # 2. Skip rebuild if dist already matches the current commit.
      #    Avoids re-running npm-install + vite-build on idempotent
      #    rebuilds (operator can force a fresh build by running
      #    `just deploy-app filmder` after a `git push`).
      CURRENT_COMMIT=$(git rev-parse HEAD)
      SENTINEL="$STATE_DIRECTORY/.last-built-commit"
      if [ -f "$SENTINEL" ] && [ "$(cat "$SENTINEL")" = "$CURRENT_COMMIT" ] && [ -d "$STATE_DIRECTORY/dist" ]; then
        echo "filmder already built for commit $CURRENT_COMMIT — skipping"
        exit 0
      fi

      # 3. Inject the TMDB token (read from the sops-decrypted file).
      #    sops stores the raw v4 read-access JWT; filmder's API
      #    client uses the env var as the full Authorization header
      #    value verbatim, so we prepend the `Bearer ` scheme here.
      #    Other consumers of `tmdb-token` (future apps) get the raw
      #    value and format their own header — the secret stays
      #    convention-free in sops.
      export VITE_API_READ_ACCESS_TOKEN="Bearer $(cat ${secrets.tmdb-token.path})"

      # 4. Path-mount under /filmder/ on the funnel host. Vite reads
      #    PUBLIC_BASE in vite.config.ts → all asset URLs become
      #    /filmder/assets/...; without it the bundle 404s under a
      #    sub-path mount.
      export PUBLIC_BASE=/filmder/

      # 5. Build.
      npm ci
      npm run build

      # 6. Atomic publish: write to staging, swap, clean up.
      rm -rf "$STATE_DIRECTORY/dist.new"
      cp -r dist "$STATE_DIRECTORY/dist.new"
      if [ -d "$STATE_DIRECTORY/dist" ]; then
        mv "$STATE_DIRECTORY/dist" "$STATE_DIRECTORY/dist.old"
      fi
      mv "$STATE_DIRECTORY/dist.new" "$STATE_DIRECTORY/dist"
      rm -rf "$STATE_DIRECTORY/dist.old"

      # 7. Record the built commit.
      echo "$CURRENT_COMMIT" > "$SENTINEL"
    '';
  };

  # Funnel exposure — Tailscale serves /var/lib/filmder/dist/ at
  # https://workstation.saola-matrix.ts.net/filmder/. Public to the
  # internet; no auth gate (portfolio site, intentional).
  nori.funnelRoutes.filmder = {
    path = "/filmder/";
    target = "/var/lib/filmder/dist";
  };

  # FS hardening — tighten both build + (any future serve) units.
  # Build unit is the only one with persistent FS access; the funnel
  # composer's tailscale-funnel-config is oneshot-only, no hardening
  # needed since it just exec's tailscale CLI.
  nori.harden.filmder-build = {
    binds = [ "/var/lib/filmder" ];
  };

  # Backup intent — stateless. The published dist/ is reproducible
  # from public GitHub source + the sops-encrypted token. No local
  # state worth saving.
  nori.backups.filmder.skip = "stateless static site, rebuilt from public GitHub source";
}
