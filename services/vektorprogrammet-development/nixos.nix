{
  config,
  lib,
  pkgs,
  ...
}:

let
  databaseName = "vektorprogrammet_development";
  databaseUser = databaseName;
  originHostname = "vektor-db-origin.phibkro.org";
  stateDirectory = "${config.services.postgresql.dataDir}/vektorprogrammet-development";
  passwordFile = "${stateDirectory}/database-password";
  certificateFile = "${stateDirectory}/server.crt";
  certificateKeyFile = "${stateDirectory}/server.key";
in
{
  services.postgresql = {
    enable = true;
    ensureDatabases = [ databaseName ];
    ensureUsers = [
      {
        name = databaseUser;
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
    settings = {
      listen_addresses = "localhost";
      password_encryption = "scram-sha-256";
      ssl = true;
      ssl_cert_file = certificateFile;
      ssl_key_file = certificateKeyFile;
      ssl_min_protocol_version = "TLSv1.3";
    };
    authentication = lib.mkBefore ''
      # Hyperdrive reaches this role through the local Cloudflare Tunnel only.
      hostssl ${databaseName} ${databaseUser} 127.0.0.1/32 scram-sha-256
      hostssl ${databaseName} ${databaseUser} ::1/128 scram-sha-256
      hostnossl ${databaseName} ${databaseUser} 127.0.0.1/32 reject
      hostnossl ${databaseName} ${databaseUser} ::1/128 reject
    '';
  };

  /*
    PostgreSQL must read its certificate before startup. The certificate is
    local development trust material. Hyperdrive still authenticates with the
    dedicated SCRAM role and reaches the listener only through Cloudflare.
  */
  systemd.services.postgresql.preStart = lib.mkBefore ''
    install -d -m 0700 ${stateDirectory}
    if ! test -s ${certificateFile} \
      || ! test -s ${certificateKeyFile} \
      || ! ${pkgs.openssl}/bin/openssl x509 -in ${certificateFile} -checkend 2592000 -noout \
      || ! ${pkgs.openssl}/bin/openssl x509 -in ${certificateFile} -checkhost ${originHostname} -noout; then
      umask 077
      ${pkgs.openssl}/bin/openssl req \
        -new -newkey rsa:3072 -nodes -x509 -days 825 \
        -subj /CN=${originHostname} \
        -addext subjectAltName=DNS:${originHostname} \
        -keyout ${certificateKeyFile}.new \
        -out ${certificateFile}.new
      mv ${certificateKeyFile}.new ${certificateKeyFile}
      mv ${certificateFile}.new ${certificateFile}
    fi
  '';

  /*
    Generate the database password once on the host. The value never enters
    the Nix store or repository. PostgreSQL reads it from its private data path.
  */
  systemd.services.vektorprogrammet-development-database-ready = {
    description = "Provision the Vektorprogrammet development database credential";
    wantedBy = [ "multi-user.target" ];
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      RemainAfterExit = true;
      UMask = "0077";
    };
    script = ''
      set -euo pipefail
      install -d -m 0700 ${stateDirectory}
      if ! test -s ${passwordFile}; then
        ${pkgs.openssl}/bin/openssl rand -base64 48 > ${passwordFile}.new
        chmod 0600 ${passwordFile}.new
        mv ${passwordFile}.new ${passwordFile}
      fi
      ${config.services.postgresql.package}/bin/psql \
        --dbname=postgres \
        --no-psqlrc \
        --set=ON_ERROR_STOP=1 <<'SQL'
      SELECT format(
        'ALTER ROLE ${databaseUser} PASSWORD %L',
        rtrim(pg_read_file('${passwordFile}'))
      ) \gexec
      SQL
    '';
  };

  nori.harden.vektorprogrammet-development-database-ready = { };

  services.postgresqlBackup = {
    enable = true;
    databases = [ databaseName ];
    startAt = "*-*-* 03:30:00";
    pgdumpOptions = "--no-owner";
  };

  nori.backups.vektorprogrammet-development = {
    include = [
      "/var/backup/postgresql/${databaseName}.sql.gz"
      passwordFile
    ];
    timer = "*-*-* 04:30:00";
  };
}
