{
  config,
  lib,
  pkgs,
  ...
}:

# finnbydel — neighborhood-marketplace T3 stack (Next.js 13 + tRPC +
# Prisma). Operator's old NTNU project. Tailnet-only access at
# https://finnbydel.nori.lan via Caddy.
#
# ── DB choice: sqlite ─────────────────────────────────────────────
# Project's prisma/schema.prisma was originally `provider = "mysql"`
# (with `relationMode = "prisma"` + `@db.VarChar(255)` annotations).
# Operator chose sqlite for the deploy — fewer moving parts,
# self-contained file at /var/lib/finnbydel/db.sqlite. Project-side
# schema patch lives in operator's filmder repo (mysql → sqlite,
# drop relationMode + VarChar). Phase A2 postgres is heim's
# concern; finnbydel doesn't drag it in.
#
# ── Build/serve shape ─────────────────────────────────────────────
# Same skeleton as filmder, but with a long-running serve unit
# (Next.js needs to host its server):
#   * finnbydel-build.service — oneshot, manual trigger via
#     `just deploy-app finnbydel`. git pull → bun install (postinstall
#     runs prisma generate) → prisma db push (sync schema to sqlite,
#     creating the file on first run) → next build. Sentinel-skip if
#     already built for current commit.
#   * finnbydel-serve.service — long-running. `bun run start`
#     (= `next start`) on 127.0.0.1:9093. ExecStartPost on build
#     restarts serve so a fresh deploy auto-takes-effect.
# Caddy reverse-proxies finnbydel.nori.lan → 127.0.0.1:9093.
#
# ── DB migrations ────────────────────────────────────────────────
# `prisma db push` (not `migrate deploy`) — schema-first sync, no
# migration files needed. Right call for personal-project scope:
# we control both schema and DB, no parallel-environment drift to
# worry about. `--accept-data-loss` because for a fresh deploy the
# flag is a no-op; future schema changes that drop columns would
# need explicit operator confirmation (rare for finnbydel).

let
  finnbydelRepo = "https://github.com/phibkro/finnbydel.git";
  servePort = 9093;
  dbUrl = "file:/var/lib/finnbydel/db.sqlite";

  # Prisma on NixOS: the binary engines aren't pre-built for the
  # `linux-nixos` target, so prisma's runtime download fails (404
  # against binaries.prisma.sh). Fix is pointing PRISMA_*_BINARY +
  # PRISMA_QUERY_ENGINE_LIBRARY at nix-built artefacts via
  # pkgs.prisma-engines_6 (engine major version pinned to project's
  # @prisma/client major; v6 covers schema-engine + libquery_engine).
  # Plus openssl on PATH because prisma probes it for libssl version
  # detection.
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
    description = "Build finnbydel (manual trigger via `just deploy-app finnbydel`)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = with pkgs; [
      git
      bun
      openssl
      prisma-engines_6
    ];

    environment = prismaEnv // {
      DATABASE_URL = dbUrl;
      NODE_ENV = "production";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "finnbydel";
      Group = "finnbydel";
      StateDirectory = "finnbydel";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/finnbydel";

      # `+` prefix runs as root regardless of User= — needed because
      # systemctl restart requires privilege the finnbydel user
      # doesn't have. Fires only on successful build, so a failed
      # rebuild won't bounce a known-good serve.
      ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart finnbydel-serve.service";
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

      cd src/finnbydel-app

      # Sentinel: skip rebuild if already built for current commit.
      CURRENT_COMMIT=$(git -C .. rev-parse HEAD)
      SENTINEL="$STATE_DIRECTORY/.last-built-commit"
      if [ -f "$SENTINEL" ] && [ "$(cat "$SENTINEL")" = "$CURRENT_COMMIT" ] && [ -d ".next" ]; then
        echo "finnbydel already built for $CURRENT_COMMIT — skipping"
        exit 0
      fi

      # bun install triggers `postinstall: prisma generate` from
      # package.json. Generated client lands in node_modules/.prisma.
      bun install

      # Sync schema → sqlite. Creates the DB file on first run.
      # --skip-generate avoids re-running prisma generate (already
      # done by postinstall). --accept-data-loss is a no-op on a
      # fresh DB; future destructive schema changes need operator
      # explicit confirmation in source.
      bunx prisma db push --skip-generate --accept-data-loss

      # Run seed if the project has one wired (prisma.seed in
      # package.json + a seed script). No-op if not configured —
      # `prisma db seed` errors with "No seed command provided"
      # which we swallow. Idempotency is the seed script's
      # responsibility (check-existing-then-skip pattern).
      if grep -q '"seed"' package.json 2>/dev/null; then
        bunx prisma db seed || echo "[finnbydel-build] seed step failed; continuing"
      else
        echo "[finnbydel-build] no prisma.seed config in package.json — skipping seed"
      fi

      # Next.js production build → .next/
      bun run build

      echo "$CURRENT_COMMIT" > "$SENTINEL"
    '';
  };

  systemd.services.finnbydel-serve = {
    description = "Serve finnbydel via Next.js";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      bun
      openssl
      prisma-engines_6
    ];

    environment = prismaEnv // {
      DATABASE_URL = dbUrl;
      NODE_ENV = "production";
      PORT = toString servePort;
      HOSTNAME = "127.0.0.1";
    };

    # Skip start until a *complete* Next.js build exists. BUILD_ID
    # is the file Next writes only on successful build — pointing
    # at the .next directory itself would also match a half-failed
    # build that left a corrupt .next/ on disk (then `next start`
    # crashes with "Could not find a production build"). build's
    # ExecStartPost re-evaluates the condition on success, so once
    # BUILD_ID lands, serve activates cleanly.
    unitConfig.ConditionPathExists = "/var/lib/finnbydel/src/finnbydel-app/.next/BUILD_ID";

    serviceConfig = {
      Type = "simple";
      User = "finnbydel";
      Group = "finnbydel";

      # StateDirectory ensures /var/lib/finnbydel exists before the
      # mount-namespace bind-mount setup. Without it, harden.binds
      # fails with "No such file or directory" on cold boot before
      # any build has run.
      StateDirectory = "finnbydel";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/finnbydel/src/finnbydel-app";

      ExecStart = "${pkgs.bun}/bin/bun run start";

      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  nori.lanRoutes.finnbydel = {
    port = servePort;
    audience = "public";
    monitor = { };
    dashboard = {
      title = "Finnbydel";
      icon = "si:nextdotjs";
      group = "Personal";
      description = "Neighborhood marketplace (uni project, 2023)";
    };
  };

  nori.harden.finnbydel-build = {
    binds = [ "/var/lib/finnbydel" ];
  };
  nori.harden.finnbydel-serve = {
    binds = [ "/var/lib/finnbydel" ];
  };

  # Backup intent: paths-based, user tier. The sqlite file holds
  # whatever data accumulates from the (currently unwired) UI
  # interactions; even an empty seeded DB is worth backing up so a
  # restore replays exactly the schema-version + content snapshot
  # rather than re-running prisma db push at restore time.
  nori.backups.finnbydel = {
    paths = [ "/var/lib/finnbydel/db.sqlite" ];
    tier = "user";
  };
}
