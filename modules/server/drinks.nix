{
  lib,
  pkgs,
  ...
}:

# drinks — cocktail recipe browser. Operator's old NTNU project (uni
# group work, 2023). Tailnet-only at https://drinks.nori.lan; GraphQL
# backend reverse-proxied at https://drinks-api.nori.lan.
#
# ── Why two subdomains ───────────────────────────────────────────
# Vite SPA + Apollo standalone GraphQL = two artefacts, two ports.
# `nori.lanRoutes` is single-port-reverse-proxy by design, so we use
# it twice (peer of the filmder + finnbydel pattern but with both
# halves at once). The frontend bakes `VITE_API_URL` at *build time*,
# so the API origin must be known when drinks-build runs — hence the
# `drinks-api.nori.lan` constant in this module rather than runtime
# discovery.
#
# ── Build/serve shape ─────────────────────────────────────────────
# Three units:
#   * drinks-build.service — oneshot, manual trigger via
#     `just deploy-app drinks`. git pull → server: bun install +
#     prisma generate + migrate deploy + (idempotent) seed → app:
#     bun install + bun run build (with VITE_API_URL injected) →
#     atomic publish to /var/lib/drinks/dist. Sentinel-skip if
#     already built for current commit. ExecStartPost restarts
#     drinks-server so a fresh deploy auto-takes-effect.
#   * drinks-server.service — long-running. `bun run src/index.ts`
#     (Apollo standalone) on 127.0.0.1:9095. Reads sqlite at
#     /var/lib/drinks/db.sqlite.
#   * drinks-static.service — long-running. darkhttpd on
#     127.0.0.1:9096 serving /var/lib/drinks/dist.
#
# ── Prisma on NixOS ───────────────────────────────────────────────
# Same engine-binary plumbing as finnbydel: nix-built prisma-engines_6
# pointed at via PRISMA_*_BINARY + PRISMA_QUERY_ENGINE_LIBRARY because
# prisma's runtime download fails 404 on the `linux-nixos` target.
# Engine major must match @prisma/client major in drinks's package.json
# (currently v6).
#
# ── Backend history ───────────────────────────────────────────────
# Originally Cloudflare Workers + D1 — not homelab-shaped without a
# backend rewrite. Repo now ships an Apollo standalone server +
# plain Prisma sqlite (commit history on the drinks repo).

let
  drinksRepo = "https://github.com/phibkro/drinks.git";
  serverPort = 9095;
  staticPort = 9096;
  dbPath = "/var/lib/drinks/db.sqlite";
  apiUrl = "https://drinks-api.nori.lan";

  prismaEnv = {
    PRISMA_QUERY_ENGINE_LIBRARY = "${pkgs.prisma-engines_6}/lib/libquery_engine.node";
    PRISMA_QUERY_ENGINE_BINARY = "${pkgs.prisma-engines_6}/bin/query-engine";
    PRISMA_SCHEMA_ENGINE_BINARY = "${pkgs.prisma-engines_6}/bin/schema-engine";
  };
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
      openssl
      prisma-engines_6
      sqlite
    ];

    environment = prismaEnv // {
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

      # `+` prefix runs as root regardless of User= — needed because
      # systemctl restart requires privilege the drinks user doesn't
      # have. Fires only on successful build, so a failed rebuild
      # won't bounce a known-good serve.
      ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart drinks-server.service";
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
         && [ -d server/node_modules/@prisma/client ]; then
        echo "drinks already built for $CURRENT_COMMIT — skipping"
        exit 0
      fi

      # ── Server side ───────────────────────────────────────────
      pushd server >/dev/null
      bun install

      # Generate Prisma client (postinstall isn't wired in this
      # repo's package.json, so explicit step).
      bunx prisma generate

      # Apply migrations. Schema-first sync would also work, but
      # this repo committed prisma/migrations/ so deploy them.
      bunx prisma migrate deploy

      # Idempotent seed: only run when the table is empty. The seed
      # script uses createMany without onConflict and would dupe on
      # repeat. sqlite3 query returns 0 if table doesn't exist (with
      # a stderr error swallowed) or the row count otherwise.
      DRINK_COUNT=$(sqlite3 ${dbPath} "SELECT COUNT(*) FROM Drink;" 2>/dev/null || echo 0)
      if [ "$DRINK_COUNT" = "0" ]; then
        echo "[drinks-build] empty DB — running seed"
        bun run src/seed.ts
      else
        echo "[drinks-build] DB has $DRINK_COUNT drinks — skipping seed"
      fi
      popd >/dev/null

      # ── App side ──────────────────────────────────────────────
      pushd app >/dev/null
      bun install
      # VITE_API_URL is read at build time and embedded in the JS
      # bundle. Set in this unit's `environment` above.
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
    description = "drinks GraphQL server (Apollo standalone)";
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

    # Skip start until a built tree + DB exist. db.sqlite is created
    # by `prisma migrate deploy` during drinks-build; node_modules
    # holds the generated Prisma client. Build's ExecStartPost
    # restarts this unit on success, so once the conditions land
    # serve activates cleanly.
    unitConfig.ConditionPathExists = [
      dbPath
      "/var/lib/drinks/src/server/node_modules/@prisma/client"
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
    after = [ "drinks-build.service" ];
    wantedBy = [ "multi-user.target" ];
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

  # SPA at https://drinks.nori.lan
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

  # GraphQL backend at https://drinks-api.nori.lan. No dashboard entry
  # — it's the SPA's data plane, not a user-facing destination. Apollo
  # standalone serves the Apollo Sandbox HTML at GET /, which gives
  # the default `/` monitor a 200.
  nori.lanRoutes.drinks-api = {
    port = serverPort;
    audience = "public";
    monitor = { };
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
