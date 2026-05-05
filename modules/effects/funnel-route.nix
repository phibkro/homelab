{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    mkIf
    ;
in
{
  # nori.funnelRoutes — single source of truth for Tailscale Funnel
  # exposure. Each entry contributes a path-mounted handler on the
  # workstation's funnel hostname; the composer below assembles ONE
  # serve config covering all entries and applies it via
  # `tailscale serve set-config`.
  #
  # Why an aggregator (vs each app calling `tailscale serve` itself):
  # `tailscale serve set-config` REPLACES the entire serve config — if
  # two apps each ran their own `set-config`, the second would erase
  # the first. The aggregator collects, the single oneshot applies.
  #
  # Funnel exposure = INTERNET-public, not tailnet-public. The threat
  # model is materially different from `nori.lanRoutes.<n>.audience`:
  #   * lanRoutes audience = "operator|family|public" — all
  #     gated-by-tailnet; tailnet IS the auth perimeter
  #   * funnelRoutes — anyone on the public internet can reach this
  # Keeping them as separate effect surfaces lets call sites surface
  # the choice ("expose to tailnet" vs "expose to internet")
  # explicitly rather than inheriting it from a shared enum.
  #
  # ── Service distinct hostnames? ─────────────────────────────────
  # Tailscale's serve config ties handlers to a `<host>:443` key, and
  # the host is the machine's tailnet name (workstation.<tailnet>.ts.net).
  # `tailscale serve advertise` exists for advertising the machine as
  # a service-name proxy on the tailnet, but Funnel doesn't (yet)
  # honour distinct hostnames per service for public exposure. So:
  # all funnel entries today land at <workstation>.ts.net/<path>/.
  # When Tailscale ships per-service Funnel hostnames or we adopt a
  # custom domain (e.g. `<n>.phibkro.dev` CNAME), the composer
  # adapts; call sites stay unchanged.

  options.nori.funnelRoutes = mkOption {
    default = { };
    description = ''
      Tailscale Funnel exposure for self-deployed apps. Each attribute
      adds one path-mounted handler to the workstation funnel.
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = ''
              URL path on the funnel hostname where this app is
              mounted, e.g. "/filmder/". Trailing slash matters
              for sub-path asset resolution — keep it.
            '';
          };

          target = mkOption {
            type = types.str;
            description = ''
              Where Tailscale forwards requests. `tailscale serve`
              auto-detects the kind from the string shape:
                * `/var/lib/<n>/dist` — static-file directory
                * `http://127.0.0.1:<port>` — local HTTP backend
                * `https://localhost:<port>` (or `https+insecure://`) — local HTTPS backend
                * `unix:/var/run/<n>.sock` — Unix socket
            '';
          };
        };
      }
    );
  };

  config = mkIf (config.nori.funnelRoutes != { }) (
    let
      # ── Funnel port ────────────────────────────────────────────────
      # Funnel only accepts 443, 8443, or 10000 as the local TLS-
      # termination port. We pick 8443: port 443 is already owned by
      # Caddy serving `*.nori.lan` (the LAN reverse-proxy plane), and
      # tailscaled trying to bind 443 on the tailnet interface
      # collides with Caddy's 0.0.0.0:443 listener — symptom:
      # `localListener failed to listen ... bind: address already in use`,
      # then TLS handshakes fail with "internal error".
      #
      # Externally — for visitors on the public internet — the URL
      # IS still `https://<host>.<tailnet>.ts.net/<path>` (port 443
      # implicit). Tailscale's funnel infrastructure maps public
      # :443 → our local :8443 transparently. The :8443 only shows
      # up for inside-tailnet direct access (where there's no
      # funnel-edge to do the mapping).
      funnelPort = 8443;

      # Each route is materialised as one `tailscale serve` invocation.
      # The commands are idempotent — re-running set the same state.
      # `tailscale serve reset` runs first so removed routes are
      # cleaned up (declarative-feeling: state always derived from
      # current nori.funnelRoutes).
      serveCommands = lib.concatMapStringsSep "\n" (cfg: ''
        tailscale serve --bg --https ${toString funnelPort} \
          --set-path ${cfg.path} ${cfg.target}
      '') (lib.attrValues config.nori.funnelRoutes);
    in
    {
      systemd.services.tailscale-funnel-config = {
        description = "Apply Tailscale serve + funnel config (nori.funnelRoutes)";
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];

        path = with pkgs; [
          jq
          tailscale
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -euo pipefail

          # Wait for tailscale to settle — `after = [tailscaled]`
          # only ensures the unit started, not that the daemon has
          # finished login + DNS resolution. Retry up to 60s.
          for _ in $(seq 1 30); do
            if tailscale status --json 2>/dev/null \
                 | jq -e '.Self.DNSName // empty' >/dev/null; then
              break
            fi
            sleep 2
          done

          if ! tailscale status --json 2>/dev/null \
               | jq -e '.Self.DNSName // empty' >/dev/null; then
            echo "tailscale not ready after 60s — aborting" >&2
            exit 1
          fi

          # Reset to a clean slate, then re-apply every route
          # currently declared in nori.funnelRoutes. Removing a route
          # from the Nix config + rebuild = it disappears from
          # tailscaled state on the next activation.
          tailscale serve reset
          ${serveCommands}

          # Enable Funnel for the local serve port. tailscale's
          # public-edge maps internet :443 → our local :8443.
          tailscale funnel --bg ${toString funnelPort}
        '';
      };
    }
  );
}
