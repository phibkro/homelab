{
  lib,
  pkgs,
  ...
}:

# drinks — cocktail recipe browser. Operator's old NTNU project (uni
# group work, 2023). Tailnet at https://drinks.nori.lan + public at
# https://drinks.phibkro.org; GraphQL backend at the matching `-api`
# subdomains.
#
# ── Why two subdomains ───────────────────────────────────────────
# Vite SPA + Apollo standalone GraphQL = two artefacts, two ports.
# `nori.lanRoutes`/`nori.publicRoutes` are single-port-per-route by
# design; the frontend bakes VITE_API_URL at build time so the API
# origin must be known when drinks-build runs.
#
# ── Build/serve shape ─────────────────────────────────────────────
# Three units:
#   * drinks-build.service — oneshot, manual via `just deploy-app
#     drinks`. git pull → server: bun install + migrate + idempotent
#     seed → app: bun install + bun run build (with VITE_API_URL
#     injected) → atomic dist publish. Sentinel-skip on idempotent
#     rebuilds.
#   * drinks-server.service — long-running. Apollo standalone +
#     Drizzle ORM over bun:sqlite, on 127.0.0.1:9095.
#   * drinks-static.service — long-running darkhttpd on
#     127.0.0.1:9096 serving /var/lib/drinks/dist.
#
# ── Data layer (post-Drizzle migration) ──────────────────────────
# Server uses Drizzle + `bun:sqlite` directly — no engine binary,
# no PRISMA_*_BINARY env vars, no openssl prerequisite. Migrations
# are CREATE TABLE IF NOT EXISTS via src/migrate.ts (idempotent
# against the existing /var/lib/drinks/db.sqlite which was first
# populated under Prisma's schema).
#
# ── Backend history ───────────────────────────────────────────────
# Originally Cloudflare Workers + D1. Rewritten to Apollo standalone
# + Prisma sqlite for homelab; then migrated to Drizzle to drop the
# prisma-engines_6 NixOS-binary maintenance surface.

let
  drinksRepo = "https://github.com/phibkro/drinks.git";
  serverPort = 9095;
  staticPort = 9096;
  dbPath = "/var/lib/drinks/db.sqlite";
  apiUrl = "https://drinks-api.phibkro.org";
in
{
  users.users.drinks = {
    isSystemUser = true;
    group = "drinks";
    home = "/var/lib/drinks";
    description = "drinks build + serve user";
  };
  users.groups.drinks = { };

  systemd.services.drinks-build = {
    description = "Build drinks server + SPA (manual trigger via `just deploy-app drinks`)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = with pkgs; [
      git
      bun
      sqlite
    ];

    environment = {
      DATABASE_URL = "file:${dbPath}";
      VITE_API_URL = apiUrl;
      NODE_ENV = "production";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "drinks";
      Group = "drinks";
      StateDirectory = "drinks";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/drinks";
      ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart drinks-server.service drinks-static.service";
    };

    script = ''
      set -euo pipefail

      if [ ! -d src/.git ]; then
        rm -rf src
        git clone --depth 1 ${drinksRepo} src
      else
        git -C src fetch --depth 1 origin main
        git -C src reset --hard origin/main
      fi

      cd src

      # Sentinel: skip rebuild if already built for current commit.
      CURRENT_COMMIT=$(git rev-parse HEAD)
      SENTINEL="$STATE_DIRECTORY/.last-built-commit"
      if [ -f "$SENTINEL" ] \
         && [ "$(cat "$SENTINEL")" = "$CURRENT_COMMIT" ] \
         && [ -d "$STATE_DIRECTORY/dist" ] \
         && [ -d server/node_modules/drizzle-orm ]; then
        echo "drinks already built for $CURRENT_COMMIT — skipping"
        exit 0
      fi

      # ── Server ───────────────────────────────────────────────
      pushd server >/dev/null
      bun install

      # Idempotent CREATE TABLE IF NOT EXISTS via bun:sqlite.
      bun run src/migrate.ts

      # Idempotent seed: only run when the table is empty (the
      # seed uses plain insert and would dupe on repeat).
      DRINK_COUNT=$(sqlite3 ${dbPath} "SELECT COUNT(*) FROM Drink;" 2>/dev/null || echo 0)
      if [ "$DRINK_COUNT" = "0" ]; then
        echo "[drinks-build] empty DB — running seed"
        bun run src/seed.ts
      else
        echo "[drinks-build] DB has $DRINK_COUNT drinks — skipping seed"
      fi
      popd >/dev/null

      # ── App ──────────────────────────────────────────────────
      pushd app >/dev/null
      bun install
      bun run build
      popd >/dev/null

      # Atomic publish of the SPA dist.
      rm -rf "$STATE_DIRECTORY/dist.new"
      cp -r app/dist "$STATE_DIRECTORY/dist.new"
      if [ -d "$STATE_DIRECTORY/dist" ]; then
        mv "$STATE_DIRECTORY/dist" "$STATE_DIRECTORY/dist.old"
      fi
      mv "$STATE_DIRECTORY/dist.new" "$STATE_DIRECTORY/dist"
      rm -rf "$STATE_DIRECTORY/dist.old"

      echo "$CURRENT_COMMIT" > "$SENTINEL"
    '';
  };

  systemd.services.drinks-server = {
    description = "drinks GraphQL server (Apollo standalone + Drizzle/bun:sqlite)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ bun ];

    environment = {
      DATABASE_URL = "file:${dbPath}";
      NODE_ENV = "production";
      PORT = toString serverPort;
      HOST = "127.0.0.1";
    };

    # Skip start until built tree + DB exist. Build's ExecStartPost
    # restarts on success, so once these conditions land, serve
    # activates cleanly.
    unitConfig.ConditionPathExists = [
      dbPath
      "/var/lib/drinks/src/server/node_modules/drizzle-orm"
    ];

    serviceConfig = {
      Type = "simple";
      User = "drinks";
      Group = "drinks";
      StateDirectory = "drinks";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/drinks/src/server";

      ExecStart = "${pkgs.bun}/bin/bun run src/index.ts";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.drinks-static = {
    description = "drinks SPA static files (darkhttpd) for Caddy reverse-proxy";
    wantedBy = [ "multi-user.target" ];
    # No `After=drinks-build`: build's `ExecStartPost = systemctl
    # restart drinks-static` would deadlock against this — restart's
    # start-job waits for build to be `active`, build can't reach
    # `active` until start-post returns. ConditionPathExists handles
    # cold-boot ordering instead. See memory/feedback.
    unitConfig.ConditionPathExists = "/var/lib/drinks/dist";

    serviceConfig = {
      Type = "simple";
      User = "drinks";
      Group = "drinks";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.darkhttpd}/bin/darkhttpd"
        "/var/lib/drinks/dist"
        "--addr 127.0.0.1"
        "--port ${toString staticPort}"
        "--no-listing"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # SPA at drinks.{nori.lan,phibkro.org}
  nori.lanRoutes.drinks = {
    port = staticPort;
    audience = "public";
    monitor = { };
    dashboard = {
      title = "Drinks";
      icon = "si:graphql";
      group = "Projects";
      description = "Cocktail recipe browser (uni project, 2023)";
    };
  };
  nori.publicRoutes.drinks = {
    host = "drinks";
    port = staticPort;
    sitemap = {
      title = "Drinks";
      description = "Cocktail recipe browser, GraphQL backed. Uni project, 2023.";
    };
  };

  # API at drinks-api.{nori.lan,phibkro.org}. Apollo standalone
  # serves Apollo Sandbox HTML at GET / so the default monitor 200s.
  nori.lanRoutes.drinks-api = {
    port = serverPort;
    audience = "public";
    monitor = { };
  };
  nori.publicRoutes.drinks-api = {
    host = "drinks-api";
    port = serverPort;
  };

  nori.harden.drinks-build = {
    binds = [ "/var/lib/drinks" ];
  };
  nori.harden.drinks-server = {
    binds = [ "/var/lib/drinks" ];
  };
  nori.harden.drinks-static = {
    readOnlyBinds = [ "/var/lib/drinks" ];
  };

  # Backup intent: the sqlite file holds reviews submitted via the
  # mutation surface. Source + seed data are reproducible from public
  # GitHub — only user-generated rows are worth saving.
  nori.backups.drinks = {
    paths = [ dbPath ];
    tier = "user";
  };
}
