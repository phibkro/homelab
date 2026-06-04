{ config, ... }:

{
  # systemd-journal-upload — ships every host's journald to the
  # VictoriaLogs daemon on pi (modules/server/victorialogs/server.nix).
  # Common-concern: each host running this is what makes VictoriaLogs
  # actually accumulate cross-host log history. Without it, the daemon
  # is up but empty (the state it was in between 2026-05-16 → today).
  #
  # The shipper itself ships with systemd (no extra package). State —
  # the per-host cursor recording how far through the local journal
  # the uploader has read — lives at /var/lib/private/systemd-journal-upload/
  # (DynamicUser). On a pi outage it resumes from the cursor when the
  # daemon comes back, so transient outages don't lose logs.
  #
  # Direct tailnet HTTP to pi:9428/insert/journald, NOT via Caddy's
  # https://logs.nori.lan: the Caddy front is for the human-facing
  # query UI; making the write-path go through Caddy makes Caddy a
  # SPoF for log ingest, which defeats the point of running the
  # daemon on pi for fate-independence. journald-upload doesn't need
  # TLS on the trusted tailnet path either.
  #
  # Pi ships its own journal too (it's the workhorse for the observer-
  # plane; we want pi's own logs queryable). The pi-uploads-to-pi
  # path is fine — VictoriaLogs ingests fine over loopback-via-tailnet
  # and journal-upload only emits status lines occasionally, no log
  # feedback loop.
  services.journald.upload = {
    enable = true;
    settings.Upload = {
      URL = "http://${config.nori.hosts.pi.tailnetIp}:9428/insert/journald";
      # Tight network timeout so a pi outage doesn't pile up retries
      # forever; journal-upload's own RestartSec=3 (from the upstream
      # module) handles reconnect.
      NetworkTimeoutSec = "30s";
    };
  };
}
