{
  config,
  lib,
  pkgs,
  ...
}:

/*
  filmder — TMDB-backed movie browser. Static Vite + React build.

  Internet-public exposure was prototyped via Tailscale Funnel (Phase
  A1) and reverted — the LAN-only shape keeps tailnet-IS-the-perimeter
  uncomplicated. To re-enable, see
  `memory/reference/tailscale_funnel_implementation.md`.

  ── Build/deploy shape ─────────────────────────────────────────────
  The upstream Vite app expects a build-time TMDB bearer. The host build
  rewrites its two API calls to the local `/tmdb` proxy instead. Three UIDs
  isolate the mutable build, credentialless static server, and credential-
  bearing proxy, so neither the build nor a served symlink can read the bearer.

  ── Trigger ──────────────────────────────────────────────────────
  `filmder-build.service` is a oneshot but NOT in `wantedBy` — every
  nixos-rebuild would otherwise re-run install + build, wasteful on
  no-op rebuilds. Operator triggers via `just deploy-app filmder`.
  The serve unit auto-starts; before first build it serves 404s until
  the operator runs the deploy script once.

  ── Tooling: bun, not npm ────────────────────────────────────────
  Drop-in replacement for `npm ci && npm run build`. Bonus side-effect:
  bun handles native-module postinstall internally (no shelling to
  `sh`), so the `bash`-on-systemd-path workaround that npm needed
  (@swc/core spawns `sh` for platform detection) goes away.
*/

let
  artifact = config.nori.inventory.workloads.filmder.artifact;
  filmderRepo = artifact.source.repository;
  filmderRef = artifact.source.ref;
  servePort = 9092;
  filmderCaddyfile = pkgs.writeText "filmder-Caddyfile" ''
    {
      admin off
      auto_https off
    }

    :${toString servePort} {
      @tmdb path /tmdb/movie/*
      handle @tmdb {
        uri strip_prefix /tmdb
        rewrite * /3{uri}
        reverse_proxy https://api.themoviedb.org {
          header_up Host api.themoviedb.org
          header_up Authorization "{env.TMDB_TOKEN}"
        }
      }

      handle {
        reverse_proxy http://127.0.0.1:9093
      }
    }
  '';
in
{
  sops.secrets.tmdb-token = {
    owner = "filmder-proxy";
    mode = "0400";
  };

  sops.templates.filmder-env = {
    owner = "filmder-proxy";
    group = "filmder-proxy";
    mode = "0400";
    content = ''
      TMDB_TOKEN=Bearer ${config.sops.placeholder.tmdb-token}
    '';
  };

  users.users = {
    filmder-builder = {
      isSystemUser = true;
      group = "filmder-static";
      home = "/var/lib/filmder";
      description = "Unprivileged Filmder source build user";
    };
    filmder-static = {
      isSystemUser = true;
      group = "filmder-static";
      description = "Credentialless Filmder static-file user";
    };
    filmder-proxy = {
      isSystemUser = true;
      group = "filmder-proxy";
      description = "Filmder TMDB proxy user";
    };
  };
  users.groups = {
    filmder-static = { };
    filmder-proxy = { };
  };

  # Keep the credentialless listener alive before the first manual build.
  systemd.tmpfiles.rules = [
    "d /var/lib/filmder 0750 filmder-builder filmder-static -"
    "d /var/lib/filmder/dist 0750 filmder-builder filmder-static -"
  ];

  systemd.services.${artifact.consumer.unit} = {
    description = "Build filmder static site (manual trigger via `just deploy-app filmder`)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = with pkgs; [
      git
      bun
      gnugrep
      gnused
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "filmder-builder";
      Group = "filmder-static";
      ExecStartPost = [ "+${pkgs.systemd}/bin/systemctl restart filmder-static.service" ];

      # systemd-managed state dir — exposes $STATE_DIRECTORY to the script.
      # The builder owns writes; the credential-bearing server reads the group.
      StateDirectory = "filmder";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/filmder";
    };

    script = ''
      set -euo pipefail

      # 1. Pull or clone source.
      if [ ! -d src/.git ]; then
        rm -rf src
        git clone --depth 1 --branch ${filmderRef} ${filmderRepo} src
      else
        git -C src fetch --depth 1 origin ${filmderRef}
        git -C src reset --hard FETCH_HEAD
      fi

      cd src

      # 2. Skip rebuild if dist already matches HEAD. Force a fresh # multi-line: ok
      #    build via:
      #      sudo rm /var/lib/filmder/.last-built-commit && just deploy-app filmder
      CURRENT_COMMIT=$(git rev-parse HEAD)
      SENTINEL="$STATE_DIRECTORY/.last-built-commit"
      if [ -f "$SENTINEL" ] && [ "$(cat "$SENTINEL")" = "$CURRENT_COMMIT" ] && [ -d "$STATE_DIRECTORY/dist" ]; then
        echo "filmder already built for commit $CURRENT_COMMIT — skipping"
        exit 0
      fi

      # 3. Replace the build-time bearer with the narrow local proxy. Fail if
      #    upstream changed either security-sensitive call site.
      grep -Fq 'https://api.themoviedb.org/3' src/server/api.ts
      grep -Fq 'Authorization: import.meta.env.VITE_API_READ_ACCESS_TOKEN,' src/server/api.ts
      sed -i \
        -e 's#https://api.themoviedb.org/3#/tmdb#g' \
        -e '/Authorization: import\.meta\.env\.VITE_API_READ_ACCESS_TOKEN,/d' \
        src/server/api.ts
      if grep -Eq 'VITE_API_READ_ACCESS_TOKEN|api\.themoviedb\.org' src/server/api.ts; then
        echo "filmder credential rewrite incomplete" >&2
        exit 1
      fi

      # 4. Build without production credentials.
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
  # A credentialless process reads builder output. The credential-bearing
  # Caddy process only proxies bytes and the narrow TMDB API path.
  systemd.services.filmder-static = {
    description = "Serve credentialless Filmder static files";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "filmder-static";
      Group = "filmder-static";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.darkhttpd}/bin/darkhttpd"
        "/var/lib/filmder/dist"
        "--addr 127.0.0.1"
        "--port 9093"
        "--no-listing"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.filmder-serve = {
    description = "Proxy Filmder and its narrow TMDB API";
    requires = [ "filmder-static.service" ];
    after = [ "filmder-static.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "filmder-proxy";
      Group = "filmder-proxy";
      EnvironmentFile = config.sops.templates.filmder-env.path;
      ExecStart = "${lib.getExe pkgs.caddy} run --config ${filmderCaddyfile} --adapter caddyfile";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  nori.harden.filmder-build = {
    binds = [ "/var/lib/filmder" ];
  };
  nori.harden.filmder-static = {
    readOnlyBinds = [ "/var/lib/filmder" ];
  };
  nori.harden.filmder-serve = { };

  nori.backups.filmder.skip = "Stateless static site rebuilt from public GitHub source; the TMDB bearer stays in the runtime proxy.";
}
