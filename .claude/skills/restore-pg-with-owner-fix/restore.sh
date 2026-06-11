#!/usr/bin/env bash
# restore-pg-with-owner-fix — see SKILL.md for the full rationale.
#
# Usage: sudo restore.sh <db> <role> <dump.sql.gz>
#
# Drop + recreate <db> owned by <role>, restore the gzipped dump, then
# ALTER OWNER all tables + sequences + the public schema back to <role>.
# Fixes the "psql as postgres restores everything postgres-owned"
# trap that breaks services reading their own schema_version sentinel.

set -euo pipefail

if [ "$#" -ne 3 ]; then
  cat >&2 <<EOF
usage: $0 <db> <role> <dump.sql.gz>

  <db>           destination database name (will be dropped + recreated)
  <role>         postgres role that should own everything
                 (must already exist; the service's NixOS module
                 typically declares this via services.<svc>.user
                 or ensureUsers)
  <dump.sql.gz>  gzipped pg_dump output; readable by root

run as root (the script invokes \`sudo -u postgres ...\` internally).
EOF
  exit 2
fi

DB="$1"
ROLE="$2"
DUMP="$3"

if [ "$(id -u)" -ne 0 ]; then
  echo "✗ must run as root (script invokes sudo -u postgres internally)" >&2
  exit 1
fi

if [ ! -r "$DUMP" ]; then
  echo "✗ dump file not readable: $DUMP" >&2
  exit 1
fi

if ! sudo -u postgres psql -lqtAF: \
   | awk -F: '{print $1}' | grep -qx "$ROLE"; then
  # `psql -l` lists databases; role check is a separate query
  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ROLE'" \
     | grep -qx 1; then
    echo "✗ postgres role '$ROLE' does not exist." >&2
    echo "   declare it via the service's NixOS module first" >&2
    echo "   (services.<svc>.user or postgresql.ensureUsers)" >&2
    exit 1
  fi
fi

echo "── dropping + recreating database $DB owned by $ROLE ──"
sudo -u postgres dropdb --if-exists "$DB"
sudo -u postgres createdb -O "$ROLE" "$DB"

echo "── restoring from $DUMP ──"
# psql exit isn't fatal here — partial errors (e.g. extension already
# present from the createdb template) are expected; the ownership
# fix below + verify step are what tells you the restore actually
# took.
sudo -u postgres bash -c "gunzip -c '$DUMP' | psql '$DB'" 2>&1 \
  | tail -5

echo "── ALTER OWNER → $ROLE on every table + sequence + public schema ──"
sudo -u postgres psql "$DB" <<EOF
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' OWNER TO $ROLE';
  END LOOP;
  FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public' LOOP
    EXECUTE 'ALTER SEQUENCE ' || quote_ident(r.sequence_name) || ' OWNER TO $ROLE';
  END LOOP;
END\$\$;
ALTER SCHEMA public OWNER TO $ROLE;
EOF

echo
echo "── verify (first table owners) ──"
sudo -u postgres psql "$DB" -c "\dt" | head -10

echo
echo "✓ restore + ownership fix complete; start the service to resume."
