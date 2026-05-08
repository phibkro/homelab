{
  lib,
  pkgs,
  ...
}:

# finnbydel — bydel-lookup tool. Operator's old NTNU project (2023).
# Tailnet at https://finnbydel.nori.lan; public at
# https://finnbydel.phibkro.org + https://finnbydel-api.phibkro.org.
#
# ── Stack (post-Astro+Hono migration) ────────────────────────────
# - app/    Astro static SPA-ish frontend with React island for the
#           autocomplete form. Built to dist/ and served by darkhttpd.
# - server/ Hono on Bun + Prisma + zod for the REST API. Long-running
#           bun process. SQLite at /var/lib/finnbydel/db.sqlite.
#
# Two cloudflared subdomains because Vite-built frontends bake the
# API origin at build time, and putting the API on a separate
# hostname keeps the tunnel ingress single-port-per-route — same
# pattern as drinks.
#
# ── Build/serve shape ─────────────────────────────────────────────
# Three units:
#   * finnbydel-build.service — oneshot, manual via `just deploy-app
#     finnbydel`. git pull → server: bun install + prisma generate +
#     prisma db push + idempotent seed → app: bun install + bun run
#     build (with PUBLIC_API_URL injected) → atomic dist publish to
#     /var/lib/finnbydel/dist. Sentinel-skip on idempotent rebuilds.
#     ExecStartPost bounces both serve units.
#   * finnbydel-server.service — long-running Hono on 127.0.0.1:9093
#     (the API).
#   * finnbydel-static.service — long-running darkhttpd serving the
#     SPA on 127.0.0.1:9098.
#
# ── DB migrations ────────────────────────────────────────────────
# Schema-first sync via `prisma db push` — no migration files. Right
# call for personal-project scope: we own both schema + DB, no
# parallel-environment drift. `--accept-data-loss` is a no-op on a
# fresh DB; destructive schema changes would need explicit operator
# confirmation in source.

let
  finnbydelRepo = "https://github.com/phibkro/finnbydel.git";
  serverPort = 9093;
  staticPort = 9098;
  dbPath = "/var/lib/finnbydel/db.sqlite";
  apiUrl = "https://finnbydel-api.phibkro.org";

  prismaEnv = {
    PRISMA_QUERY_ENGINE_LIBRARY = "${pkgs.prisma-engines_6}/lib/libquery_engine.node";
    PRISMA_QUERY_ENGINE_BINARY = "${pkgs.prisma-engines_6}/bin/query-engine";
    PRISMA_SCHEMA_ENGINE_BINARY = "${pkgs.prisma-engines_6}/bin/schema-engine";
  };
in
{
  users.users.finnbydel = {
    isSystemUser = true;
    group = "finnbydel";
    home = "/var/lib/finnbydel";
    description = "finnbydel build + serve user";
  };
  users.groups.finnbydel = { };

  systemd.services.finnbydel-build = {
    description = "Build finnbydel server + SPA (manual trigger via `just deploy-app finnbydel`)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = with pkgs; [
      git
      bun
      openssl
      prisma-engines_6
      sqlite
    ];

    environment = prismaEnv // {
      DATABASE_URL = "file:${dbPath}";
      PUBLIC_API_URL = apiUrl;
      NODE_ENV = "production";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "finnbydel";
      Group = "finnbydel";
      StateDirectory = "finnbydel";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/finnbydel";

      # Bounce both long-running units on successful build. `+`
      # prefix runs as root so finnbydel user doesn't need
      # sudo/systemctl privileges.
      ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart finnbydel-server.service finnbydel-static.service";
    };

    script = ''
      set -euo pipefail

      if [ ! -d src/.git ]; then
        rm -rf src
        git clone --depth 1 ${finnbydelRepo} src
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
         && [ -d server/node_modules/@prisma/client ]; then
        echo "finnbydel already built for $CURRENT_COMMIT — skipping"
        exit 0
      fi

      # ── Server ───────────────────────────────────────────────
      pushd server >/dev/null
      bun install
      bunx prisma generate
      bunx prisma db push --skip-generate --accept-data-loss

      # Idempotent seed: only run when the City table is empty.
      # Prisma's `db seed` doesn't have built-in idempotency; the
      # repo's seed.ts is upsert-shaped but still fast-paths on
      # empty.
      CITY_COUNT=$(sqlite3 ${dbPath} "SELECT COUNT(*) FROM City;" 2>/dev/null || echo 0)
      if [ "$CITY_COUNT" = "0" ]; then
        echo "[finnbydel-build] empty DB — running seed"
        bun run prisma/seed.ts || echo "[finnbydel-build] seed step failed; continuing"
      else
        echo "[finnbydel-build] DB has $CITY_COUNT cities — skipping seed"
      fi
      popd >/dev/null

      # ── App ──────────────────────────────────────────────────
      pushd app >/dev/null
      bun install
      # PUBLIC_API_URL is read at build time and embedded in the
      # client bundle. Set in this unit's `environment` above.
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

  systemd.services.finnbydel-server = {
    description = "finnbydel REST API (Hono on Bun)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      bun
      openssl
      prisma-engines_6
    ];

    environment = prismaEnv // {
      DATABASE_URL = "file:${dbPath}";
      NODE_ENV = "production";
      PORT = toString serverPort;
      HOST = "127.0.0.1";
    };

    # Skip start until DB + generated Prisma client both exist. The
    # build's ExecStartPost re-evaluates this on success, so the
    # unit picks up cleanly on first deploy.
    unitConfig.ConditionPathExists = [
      dbPath
      "/var/lib/finnbydel/src/server/node_modules/@prisma/client"
    ];

    serviceConfig = {
      Type = "simple";
      User = "finnbydel";
      Group = "finnbydel";
      StateDirectory = "finnbydel";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/finnbydel/src/server";

      ExecStart = "${pkgs.bun}/bin/bun run src/index.ts";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.finnbydel-static = {
    description = "finnbydel SPA static files (darkhttpd) for Caddy/cloudflared";
    wantedBy = [ "multi-user.target" ];
    # No `After=finnbydel-build`: same deadlock pattern as heim —
    # `ExecStartPost = systemctl restart` from finnbydel-build would
    # wait for build to be `active`, but build can't reach `active`
    # until start-post returns. ConditionPathExists handles the
    # cold-boot ordering instead.
    unitConfig.ConditionPathExists = "/var/lib/finnbydel/dist";

    serviceConfig = {
      Type = "simple";
      User = "finnbydel";
      Group = "finnbydel";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.darkhttpd}/bin/darkhttpd"
        "/var/lib/finnbydel/dist"
        "--addr 127.0.0.1"
        "--port ${toString staticPort}"
        "--no-listing"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # SPA at finnbydel.{nori.lan,phibkro.org}
  nori.lanRoutes.finnbydel = {
    port = staticPort;
    audience = "public";
    monitor = { };
    dashboard = {
      title = "Finnbydel";
      icon = "si:astro";
      group = "Projects";
      description = "Bydel lookup (uni project, 2023; Astro+Hono refactor 2026)";
    };
  };
  nori.publicRoutes.finnbydel = {
    host = "finnbydel";
    port = staticPort;
    sitemap = {
      title = "Finnbydel";
      description = "Find your bydel — Norwegian neighbourhood lookup. Uni project, 2023.";
    };
  };

  # API at finnbydel-api.{nori.lan,phibkro.org}. No dashboard entry
  # — backend for the SPA. Hono root handler returns a small JSON
  # health blob, so the default `/` monitor passes.
  nori.lanRoutes.finnbydel-api = {
    port = serverPort;
    audience = "public";
    monitor = { };
  };
  nori.publicRoutes.finnbydel-api = {
    host = "finnbydel-api";
    port = serverPort;
  };

  nori.harden.finnbydel-build = {
    binds = [ "/var/lib/finnbydel" ];
  };
  nori.harden.finnbydel-server = {
    binds = [ "/var/lib/finnbydel" ];
  };
  nori.harden.finnbydel-static = {
    readOnlyBinds = [ "/var/lib/finnbydel" ];
  };

  # Backup intent: the sqlite file holds the seeded bydel polygons +
  # whatever data accumulates from UI interactions (currently
  # nothing, but worth a snapshot so a restore replays exactly the
  # schema + seeded data without re-fetching from upstream sources).
  nori.backups.finnbydel = {
    paths = [ dbPath ];
    tier = "user";
  };
}
