{
  config,
  lib,
  pkgs,
  ...
}:

/*
  rust-motd renders the stats body (uptime/load/memory/fs/services/
  last-login) into /var/lib/rust-motd/motd. The codename banner is
  rendered by the `motd` wrapper below instead, so it can be
  customised per invocation (font/filter/colour/random/animated).
  Consequence: sshd PrintMotd shows the cached body only; the toilet
  codename renders only when `motd` is run interactively.
*/

let
  self = config.nori.hosts.${config.networking.hostName} or null;
  codename =
    if self != null then (self.codename or config.networking.hostName) else config.networking.hostName;
  role = if self != null then (self.role or "?") else "?";
  hostname = config.networking.hostName;

  # toilet only bundles its own .tlf fonts in share/figlet/. Merge in
  # figlet's .flf set so the curated list (doh, etc.) all resolve.
  fontDir = pkgs.symlinkJoin {
    name = "motd-fontdir";
    paths = [
      "${pkgs.toilet}/share/figlet"
      "${pkgs.figlet}/share/figlet"
    ];
  };
in
{
  programs.rust-motd = {
    enable = true;
    enableMotdInSSHD = true;
    # systemd OnCalendar spec, NOT a duration. "1d" silently breaks
    # the timer with `bad-setting`. Use `daily` (or e.g. `*:0/30`).
    refreshInterval = "daily";
    settings = {
      # No `banner` section — owned by the `motd` wrapper.

      uptime = {
        prefix = "Uptime";
      };

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
        nori = 2;
      };

      service_status = {
        sshd = "sshd";
        tailscaled = "tailscaled";
      };
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "motd";
      runtimeInputs = with pkgs; [
        toilet
        coreutils
        ncurses
      ];
      text = ''
        FONT=""
        FILTER=""
        COLOR=""
        REFRESH_MS=""
        RANDOMISE_FONT=0
        RANDOMISE_FILTER=0
        RANDOMISE_COLOR=0

        FONTS=(mono9 smblock smmono9 future term smbraille doh)
        FILTERS=(border metal gay metal:border border:gay crop)
        COLORS=(red green yellow blue magenta cyan white)

        FONT_DIR='${fontDir}'

        usage() {
          cat <<'EOF'
        Usage: motd [OPTIONS]

          -f, --font FONT       toilet/figlet font (default: doh)
                                curated: mono9 smblock smmono9 future term smbraille doh
          -F, --filter FILTER   toilet filter (default: none)
                                curated: border metal gay metal:border border:gay crop
          -c, --color COLOR     ANSI colour (default: terminal default)
                                curated: red green yellow blue magenta cyan white
          -r, --random[=ATTRS]  randomise the named attributes; ATTRS is a comma-
                                separated subset of {font,filter,color}. Bare
                                --random randomises all three. Explicit -f/-F/-c
                                pins override the roll for that attribute.
              --refresh[=MS]    re-render in-place every MS ms until Ctrl-C
                                (bare --refresh defaults to 1000ms)
          -h, --help

        Examples:
          motd                              # all defaults
          motd --random                     # roll font + filter + color
          motd --random=font                # roll font only
          motd -c cyan --random=font        # color pinned, font random
          motd --random --refresh=500       # animate, full re-roll every 500ms
          motd -f mono9 --refresh           # pinned font, redraw stats every 1s
        EOF
        }

        parse_random() {
          local val="$1"
          if [[ -z "$val" || "$val" == "all" ]]; then
            RANDOMISE_FONT=1
            RANDOMISE_FILTER=1
            RANDOMISE_COLOR=1
            return
          fi
          local IFS=,
          local attr
          for attr in $val; do
            case "$attr" in
              font)         RANDOMISE_FONT=1 ;;
              filter)       RANDOMISE_FILTER=1 ;;
              color|colour) RANDOMISE_COLOR=1 ;;
              *) echo "motd: unknown --random attribute: $attr" >&2; exit 1 ;;
            esac
          done
        }

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -f|--font)     FONT="$2"; shift 2 ;;
            -F|--filter)   FILTER="$2"; shift 2 ;;
            -c|--color)    COLOR="$2"; shift 2 ;;
            -r|--random)   parse_random ""; shift ;;
            --random=*)    parse_random "''${1#--random=}"; shift ;;
            --refresh)     REFRESH_MS=1000; shift ;;
            --refresh=*)   REFRESH_MS="''${1#--refresh=}"; shift ;;
            -h|--help)     usage; exit 0 ;;
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
          local f="$FONT" F="$FILTER" c="$COLOR"
          if [[ -z "$f" && "$RANDOMISE_FONT" == 1 ]]; then
            f=$(shuf -n1 -e "''${FONTS[@]}")
          fi
          if [[ -z "$F" && "$RANDOMISE_FILTER" == 1 ]]; then
            F=$(shuf -n1 -e "''${FILTERS[@]}")
          fi
          if [[ -z "$c" && "$RANDOMISE_COLOR" == 1 ]]; then
            c=$(shuf -n1 -e "''${COLORS[@]}")
          fi
          if [[ -z "$f" ]]; then f=doh; fi

          local args=(-d "$FONT_DIR" -f "$f")
          if [[ -n "$F" ]]; then args+=(-F "$F"); fi

          local code=""
          if [[ -n "$c" ]]; then code=$(color_code "$c"); fi
          if [[ -n "$code" ]]; then tput setaf "$code"; fi
          toilet "''${args[@]}" '${codename}'
          if [[ -n "$code" ]]; then tput sgr0; fi
          echo '(${hostname}) — ${role}'
        }

        refresh_body_cache() {
          sudo systemctl start rust-motd.service
        }

        render_body() {
          cat /var/lib/rust-motd/motd
        }

        if [[ -z "$REFRESH_MS" ]]; then
          refresh_body_cache
          render_banner
          render_body
          exit 0
        fi

        # --- in-place animate ---  # multi-line: ok (bash heredoc)
        # ms → fractional seconds for `sleep`. LC_ALL=C so `.` is the
        # decimal separator regardless of locale.
        sleep_sec=$(LC_ALL=C printf '%d.%03d' $((REFRESH_MS/1000)) $((REFRESH_MS%1000)))

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
          sleep "$sleep_sec"
        done
      '';
    })
  ];
}
