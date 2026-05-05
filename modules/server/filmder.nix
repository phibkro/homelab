{
  config,
  lib,
  pkgs,
  ...
}:

# filmder — TMDB-backed movie browser. Operator's old NTNU project
# (uni group work, 2023). Static Vite + React build; tailnet-only
# access at https://filmder.nori.lan via Caddy.
#
# Internet-public exposure was prototyped via Tailscale Funnel (filmder
# Phase A1) and reverted — the portfolio isn't ready to receive public
# traffic yet, and the LAN-only shape keeps tailnet-IS-the-perimeter
# uncomplicated. To re-enable public exposure later, see
# `memory/reference/tailscale_funnel_implementation.md` for the
# `nori.funnelRoutes` effect to recreate (~30 lines, well-understood).
#
# ── Build/deploy shape ─────────────────────────────────────────────
# Build is an *activation-time systemd oneshot* rather than a Nix
# flake build, because filmder's TMDB token is read at *build time*
# by Vite and embedded into the JS bundle (`import.meta.env.VITE_*`).
# Nix's hermetic build sandbox can't read /run/secrets/X, so the
# clean `nix build → /nix/store/<hash>-filmder` path doesn't apply
# here. Activation-time build with the secret read directly in the
# script is the pragmatic compromise.
#
# ── Trigger ──────────────────────────────────────────────────────
# `filmder-build.service` is a oneshot but NOT in `wantedBy` — every
# nixos-rebuild would otherwise re-run install + build (~10s with bun,
# previously ~40-60s with npm), wasteful on no-op rebuilds. Operator
# triggers via `just deploy-app filmder`. The serve unit
# (`filmder-serve.service`) auto-starts; before first build it serves
# 404s until the operator runs the deploy script once.
#
# ── Tooling: bun, not npm ────────────────────────────────────────
# Drop-in replacement for `npm ci && npm run build`. Bonus side-effect:
# bun handles native-module postinstall internally (no shelling to
# `sh`), so the `bash`-on-systemd-path workaround that npm needed
# (@swc/core spawns `sh` for platform detection) goes away.

let
  inherit (config.sops) secrets;
  filmderRepo = "https://github.com/phibkro/filmder.git";
  servePort = 9092;
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

    path = with pkgs; [
      git
      bun
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
      #    Force a fresh build via:
      #      sudo rm /var/lib/filmder/.last-built-commit && just deploy-app filmder
      #    Or just push a new commit to filmder's repo (HEAD bump
      #    invalidates the sentinel).
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

      # 4. Build with bun (~10s end-to-end on this hardware).
      bun install
      bun run build

      # 5. Atomic publish: write to staging, swap, clean up.
      rm -rf "$STATE_DIRECTORY/dist.new"
      cp -r dist "$STATE_DIRECTORY/dist.new"
      if [ -d "$STATE_DIRECTORY/dist" ]; then
        mv "$STATE_DIRECTORY/dist" "$STATE_DIRECTORY/dist.old"
      fi
      mv "$STATE_DIRECTORY/dist.new" "$STATE_DIRECTORY/dist"
      rm -rf "$STATE_DIRECTORY/dist.old"

      # 6. Record the built commit.
      echo "$CURRENT_COMMIT" > "$SENTINEL"
    '';
  };

  # Static-file server fronting /var/lib/filmder/dist on a local port.
  # Caddy reverse-proxies `https://filmder.nori.lan` → here.
  # darkhttpd: tiny single-process C webserver, perfect for this
  # role (no config files, sane MIME types, ~40KB binary).
  systemd.services.filmder-serve = {
    description = "Serve filmder static files for Caddy reverse-proxy";
    after = [ "filmder-build.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "filmder";
      Group = "filmder";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.darkhttpd}/bin/darkhttpd"
        "/var/lib/filmder/dist"
        "--addr 127.0.0.1"
        "--port ${toString servePort}"
        "--no-listing"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Tailnet exposure — `filmder.nori.lan` via Caddy reverse-proxy.
  # `audience = "public"` here means tailnet-public (anyone on the
  # tailnet can reach it without an auth prompt). Distinct from
  # internet-public, which would re-add `nori.funnelRoutes.filmder`
  # — see this file's header comment for the future-toggle pointer.
  nori.lanRoutes.filmder = {
    port = servePort;
    audience = "public";
    monitor = { };
    dashboard = {
      title = "Filmder";
      icon = "si:themoviedatabase";
      group = "Personal";
      description = "TMDB-backed movie browser (uni project, 2023)";
    };
  };

  nori.harden.filmder-build = {
    binds = [ "/var/lib/filmder" ];
  };
  nori.harden.filmder-serve = {
    readOnlyBinds = [ "/var/lib/filmder" ];
  };

  # Backup intent — stateless. The published dist/ is reproducible
  # from public GitHub source + the sops-encrypted token. No local
  # state worth saving.
  nori.backups.filmder.skip = "stateless static site, rebuilt from public GitHub source";
}
