{ config, lib, pkgs, ... }:

# rust-motd renders the system-stats body (uptime, load, memory,
# filesystems, services, last-login) into /var/lib/rust-motd/motd.
# It does NOT render the codename banner anymore — banner rendering
# moved into the `motd` wrapper below so it can be customised per
# invocation (font, filter, colour, randomised, in-place animated).
#
# sshd PrintMotd shows the cached file at login, so login banner is
# now just the stats body — the toilet codename only renders when you
# run `motd` interactively. Tradeoff accepted.

let
  self = config.nori.hosts.${config.networking.hostName} or null;
  codename = if self != null then (self.codename or config.networking.hostName) else config.networking.hostName;
  role = if self != null then (self.role or "?") else "?";
  hostname = config.networking.hostName;
in
{
  programs.rust-motd = {
    enable = true;
    enableMotdInSSHD = true;
    refreshInterval = "1d";
    settings = {
      # No `banner` section — owned by the `motd` wrapper.

      uptime = {
        prefix = "Uptime";
      };

      # CPU load — 1/5/15-minute averages. rust-motd's only CPU-side
      # component (no direct % utilisation widget). `:.2` precision is
      # Rust's format syntax — caps the long floats at two decimal places.
      load_avg = {
        format = "Load    1m  {one:.2}   ·   5m  {five:.2}   ·   15m  {fifteen:.2}";
      };

      memory = {
        swap_pos = "beside";
      };

      filesystems = {
        root = "/";
      };

      last_login = {
        # Operator-level access only — root logins are noise (root is
        # ssh-key for nixos-anywhere deploys, hits twice on every
        # rebuild, no auth-anomaly value).
        nori = 2;
      };

      service_status = {
        # Universal core — present on every NixOS host in the lab.
        sshd = "sshd";
        tailscaled = "tailscaled";
      };
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "motd";
      runtimeInputs = with pkgs; [ toilet coreutils ncurses ];
      text = ''
        FONT=""
        FILTER=""
        COLOR=""
        RANDOM_MODE=0
        REFRESH=""

        FONTS=(mono9 smblock smmono9 future term smbraille doh)
        FILTERS=(border metal gay metal:border border:gay crop)

        usage() {
          cat <<'EOF'
        Usage: motd [OPTIONS]

          -f, --font FONT       toilet font (default: doh)
                                curated: mono9 smblock smmono9 future term smbraille doh
          -F, --filter FILTER   toilet filter (default: none)
                                curated: border metal gay metal:border border:gay crop
          -c, --color COLOR     ANSI colour: red green yellow blue magenta cyan white
                                default: terminal default (neutral)
          -r, --random          re-roll any unset font/filter from the curated lists
              --refresh=SEC     re-render in-place every SEC (e.g. 1s, 500ms) until Ctrl-C
          -h, --help

        Examples:
          motd
          motd --random
          motd --random --refresh=1s
          motd -f mono9 -c cyan
        EOF
        }

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -f|--font)    FONT="$2"; shift 2 ;;
            -F|--filter)  FILTER="$2"; shift 2 ;;
            -c|--color)   COLOR="$2"; shift 2 ;;
            -r|--random)  RANDOM_MODE=1; shift ;;
            --refresh=*)  REFRESH="''${1#--refresh=}"; shift ;;
            --refresh)    REFRESH="$2"; shift 2 ;;
            -h|--help)    usage; exit 0 ;;
            *) echo "motd: unknown option: $1" >&2; usage >&2; exit 1 ;;
          esac
        done

        color_code() {
          case "$1" in
            red) echo 1 ;; green) echo 2 ;; yellow) echo 3 ;;
            blue) echo 4 ;; magenta) echo 5 ;; cyan) echo 6 ;;
            white) echo 7 ;; *) echo "" ;;
          esac
        }

        render_banner() {
          local f="$FONT" F="$FILTER"
          if [[ "$RANDOM_MODE" == 1 ]]; then
            if [[ -z "$f" ]]; then f=$(shuf -n1 -e "''${FONTS[@]}"); fi
            if [[ -z "$F" ]]; then F=$(shuf -n1 -e "''${FILTERS[@]}"); fi
          fi
          if [[ -z "$f" ]]; then f=doh; fi

          local args=(-f "$f")
          if [[ -n "$F" ]]; then args+=(-F "$F"); fi

          local code=""
          if [[ -n "$COLOR" ]]; then
            code=$(color_code "$COLOR")
          fi
          if [[ -n "$code" ]]; then tput setaf "$code"; fi
          toilet "''${args[@]}" '${codename}'
          if [[ -n "$code" ]]; then tput sgr0; fi
          echo '(${hostname}) — ${role}'
        }

        refresh_body_cache() {
          # Triggers rust-motd to re-render /var/lib/rust-motd/motd.
          # Skipped in --refresh animate mode: body stats don't move
          # at sub-second granularity and per-tick sudo is noisy.
          sudo systemctl start rust-motd.service
        }

        render_body() {
          cat /var/lib/rust-motd/motd
        }

        if [[ -z "$REFRESH" ]]; then
          refresh_body_cache
          render_banner
          render_body
          exit 0
        fi

        # --- in-place animate ---
        # Position at top-left + clear-to-end each tick so a shorter
        # banner doesn't leave stale lines below it. Hide cursor for
        # cleaner redraw; restore on any exit path.
        cleanup() { tput cnorm; printf '\n'; }
        trap cleanup EXIT INT TERM

        refresh_body_cache
        tput civis
        clear
        while true; do
          tput cup 0 0
          tput ed
          render_banner
          render_body
          sleep "$REFRESH"
        done
      '';
    })
  ];
}
