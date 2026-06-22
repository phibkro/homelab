{
  config,
  lib,
  pkgs,
  ...
}:

/*
  heim — operator's portfolio site. Astro static site, markdown-
  authored content, no DB. Same deploy-app shape as filmder.nix:
  manual `just deploy-app heim` triggers the oneshot, kept out of
  `wantedBy` so nixos-rebuild stays fast.

  ── Migration history ────────────────────────────────────────────
  Earlier attempt was Next.js + Payload CMS + Postgres + Turborepo;
  blocked on Payload-CLI + bun + tsx ESM-resolution incompat. Pivoted
  to Astro because (a) operator likes writing markdown, (b) static
  output drops the entire runtime + DB dependency tree, (c) the
  bun-build-then-darkhttpd-serve pattern is the proven shape on this
  homelab. The Postgres `heim` DB + role from the prior attempt are
  orphaned and should be dropped manually:
    sudo -u postgres dropdb heim && sudo -u postgres dropuser heim

  ── sharp + LD_LIBRARY_PATH ──────────────────────────────────────
  Astro's <Image> component uses sharp for build-time image
  optimization. Sharp's native binary loads libstdc++.so.6 at runtime
  via dlopen; NixOS systemd's minimal env doesn't have libstdc++ on
  the dynamic-linker path. LD_LIBRARY_PATH at pkgs.stdenv.cc.cc.lib
  resolves the dlopen during build. (Serve-side: pure static files,
  no sharp at runtime.)
*/

let
  heimRepo = "https://github.com/phibkro/heim.git";
  servePort = 9094;

  ldLibraryPath = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
in
lib.mkMerge [
  {
    nori.services.heim.tags = [
      "personal-app"
      "stateless"
    ];

    nori.lanRoutes.heim = {
      port = servePort;
      runsOn = "aurora";
      audience = "public";
      monitor = { };
      dashboard = {
        title = "Heim";
        icon = "si:astro";
        group = "Projects";
        description = "Operator's portfolio (Astro, markdown-authored)";
      };
    };
  }
  (lib.mkIf config.nori.services.heim.enabled {
    users.users.heim = {
      isSystemUser = true;
      group = "heim";
      home = "/var/lib/heim";
      description = "heim build + serve user";
    };
    users.groups.heim = { };

    systemd.services.heim-build = {
      description = "Build heim Astro site (manual trigger via `just deploy-app heim`)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = with pkgs; [
        git
        bun
      ];

      environment = {
        LD_LIBRARY_PATH = ldLibraryPath;
      };

      serviceConfig = {
        Type = "oneshot";
        User = "heim";
        Group = "heim";
        StateDirectory = "heim";
        StateDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/heim";
        ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart heim-serve.service";
      };

      script = ''
        set -euo pipefail

        if [ ! -d src/.git ]; then
          rm -rf src
          git clone --depth 1 ${heimRepo} src
        else
          git -C src fetch --depth 1 origin main
          git -C src reset --hard origin/main
        fi

        cd src

        CURRENT_COMMIT=$(git rev-parse HEAD)
        SENTINEL="$STATE_DIRECTORY/.last-built-commit"
        if [ -f "$SENTINEL" ] \
           && [ "$(cat "$SENTINEL")" = "$CURRENT_COMMIT" ] \
           && [ -d "$STATE_DIRECTORY/dist" ]; then
          echo "heim already built for $CURRENT_COMMIT — skipping"
          exit 0
        fi

        bun install
        bun run build

        # Atomic publish — write to staging, swap, clean up.
        rm -rf "$STATE_DIRECTORY/dist.new"
        cp -r dist "$STATE_DIRECTORY/dist.new"
        if [ -d "$STATE_DIRECTORY/dist" ]; then
          mv "$STATE_DIRECTORY/dist" "$STATE_DIRECTORY/dist.old"
        fi
        mv "$STATE_DIRECTORY/dist.new" "$STATE_DIRECTORY/dist"
        rm -rf "$STATE_DIRECTORY/dist.old"

        echo "$CURRENT_COMMIT" > "$SENTINEL"
      '';
    };

    systemd.services.heim-serve = {
      description = "Serve heim static files for Caddy reverse-proxy";
      wantedBy = [ "multi-user.target" ];

      /*
        No `After=heim-build`. heim-build is a manually-triggered oneshot,
        not a boot dependency — and `After=` plus `ExecStartPost=systemctl
        restart heim-serve` deadlocks: heim-build's start-post fires the
        restart, the restart's start-job waits for heim-build to be
        `active`, heim-build can't reach `active` until start-post returns.
        ConditionPathExists guards cold-boot ordering instead (skip cleanly
        before the first deploy populates dist; build's ExecStartPost
        bounces this unit on subsequent deploys).
      */
      unitConfig.ConditionPathExists = "/var/lib/heim/dist";

      serviceConfig = {
        Type = "simple";
        User = "heim";
        Group = "heim";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.darkhttpd}/bin/darkhttpd"
          "/var/lib/heim/dist"
          "--addr 0.0.0.0"
          "--port ${toString servePort}"
          "--no-listing"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    nori.harden.heim-build = {
      binds = [ "/var/lib/heim" ];
    };
    nori.harden.heim-serve = {
      readOnlyBinds = [ "/var/lib/heim" ];
    };

    nori.backups.heim.skip = "stateless static site, rebuilt from public GitHub source";
  })
]
