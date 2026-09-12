{
  lib,
  pkgs,
  ...
}:
let
  approvedSource = builtins.path {
    path = ../..;
    name = "nori-desktop-approved-source";
    filter =
      path: _type:
      let
        name = builtins.baseNameOf path;
      in
      !(builtins.elem name [ ".git" "dist" "node_modules" "result" ]);
  };
  sourceMarker = builtins.toJSON {
    source = toString approvedSource;
    host = "workstation";
  };
  settingsPreview = pkgs.writeShellApplication {
    name = "nori-desktop-settings-preview";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.nix
    ];
    text = ''
      set -euo pipefail

      profile=""
      profile_hash=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --profile)
            profile="''${2-}"
            shift 2
            ;;
          --profile-hash)
            profile_hash="''${2-}"
            shift 2
            ;;
          *)
            echo "usage: nori-desktop-settings-preview --profile PATH --profile-hash SHA256" >&2
            exit 64
            ;;
        esac
      done
      [ -n "$profile" ] && [ -n "$profile_hash" ]
      [ -f "$profile" ] && [ ! -L "$profile" ]
      max_profile_bytes=1048576
      profile_bytes=$(stat -c %s "$profile")
      [ "$profile_bytes" -le "$max_profile_bytes" ] || {
        echo "profile exceeds the 1 MiB settings-service limit" >&2
        exit 65
      }
      actual_hash=$(sha256sum "$profile" | cut -d ' ' -f 1)
      [ "$actual_hash" = "$profile_hash" ] || {
        echo "profile hash does not match requested immutable preview" >&2
        exit 65
      }
      jq -e '
        type == "object" and
        ((keys | sort) == ["components", "formatVersion", "revision", "savedCommands"]) and
        .formatVersion == 1 and
        (.revision | type == "number" and floor == . and . >= 0) and
        (.components | type == "object") and
        (.savedCommands | type == "array")
      ' "$profile" >/dev/null

      marker=/etc/nori-desktop-settings/approved-source.json
      source=$(jq -er '.source | strings' "$marker")
      host=$(jq -er '.host | strings' "$marker")
      case "$source" in
        /nix/store/*) ;;
        *)
          echo "approved source marker is not a Nix store path" >&2
          exit 65
          ;;
      esac
      [ -d "$source" ] && [ ! -L "$source" ]
      resolved=$(nix-instantiate --eval --strict --json \
        "$source/lib/desktop-settings-eval.nix" \
        -A resolved \
        --argstr source "$source" \
        --argstr profile "$profile" \
        --argstr profileHash "$profile_hash" \
        --argstr host "$host")
      jq -e 'type == "object"' <<<"$resolved" >/dev/null
      jq -cn --argjson resolved "$resolved" '{ resolved: $resolved }'
    '';
  };
  settingsBuilder = pkgs.writeShellApplication {
    name = "nori-desktop-settings-build";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.nix
    ];
    text = ''
      set -euo pipefail

      profile=""
      profile_hash=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --profile)
            profile="''${2-}"
            shift 2
            ;;
          --profile-hash)
            profile_hash="''${2-}"
            shift 2
            ;;
          *)
            echo "usage: nori-desktop-settings-build --profile PATH --profile-hash SHA256" >&2
            exit 64
            ;;
        esac
      done
      [ -n "$profile" ] && [ -n "$profile_hash" ]
      [ -f "$profile" ] && [ ! -L "$profile" ]
      max_profile_bytes=1048576
      profile_bytes=$(stat -c %s "$profile")
      [ "$profile_bytes" -le "$max_profile_bytes" ] || {
        echo "profile exceeds the 1 MiB settings-service limit" >&2
        exit 65
      }

      actual_hash=$(sha256sum "$profile" | cut -d ' ' -f 1)
      [ "$actual_hash" = "$profile_hash" ] || {
        echo "profile hash does not match requested immutable build" >&2
        exit 65
      }
      jq -e '
        type == "object" and
        ((keys | sort) == ["components", "formatVersion", "revision", "savedCommands"]) and
        .formatVersion == 1 and
        (.revision | type == "number" and floor == . and . >= 0) and
        (.components | type == "object") and
        (.savedCommands | type == "array")
      ' "$profile" >/dev/null

      marker=/etc/nori-desktop-settings/approved-source.json
      source=$(jq -er '.source | strings' "$marker")
      host=$(jq -er '.host | strings' "$marker")
      case "$source" in
        /nix/store/*) ;;
        *)
          echo "approved source marker is not a Nix store path" >&2
          exit 65
          ;;
      esac
      [ -d "$source" ] && [ ! -L "$source" ]
      revision=$(jq -er '.revision' "$profile")
      artifact=$(nix-build "$source/lib/desktop-settings-eval.nix" \
        -A toplevel \
        --no-out-link \
        --argstr source "$source" \
        --argstr profile "$profile" \
        --argstr profileHash "$profile_hash" \
        --argstr host "$host")
      metadata="$artifact/etc/nori-desktop-settings/generation.json"
      [ -f "$metadata" ]
      jq -e \
        --arg source "$source" \
        --argjson revision "$revision" \
        --arg hash "$profile_hash" \
        '.source == $source and .profileRevision == $revision and .profileHash == $hash' \
        "$metadata" >/dev/null
      jq -cn --arg artifact "$artifact" --slurpfile metadata "$metadata" \
        '{ artifact: $artifact, metadata: $metadata[0] }'
    '';
  };
  settingsActivator = pkgs.writeShellApplication {
    name = "nori-desktop-settings-activate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.nix
      settingsBuilder
    ];
    text = ''
      set -euo pipefail

      operation=""
      profile=""
      artifact=""
      revision=""
      profile_hash=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --operation)
            operation="''${2-}"
            shift 2
            ;;
          --profile)
            profile="''${2-}"
            shift 2
            ;;
          --artifact)
            artifact="''${2-}"
            shift 2
            ;;
          --revision)
            revision="''${2-}"
            shift 2
            ;;
          --profile-hash)
            profile_hash="''${2-}"
            shift 2
            ;;
          *)
            echo "nori-desktop-settings-activate accepts no arbitrary command or argument" >&2
            exit 64
            ;;
        esac
      done
      [ "$operation" = "org.nori.desktop-settings.activate" ]
      [ -n "$profile" ] && [ -n "$artifact" ] && [ -n "$revision" ] && [ -n "$profile_hash" ]
      [ -n "''${PKEXEC_UID-}" ]
      case "$artifact" in
        /nix/store/*) ;;
        *)
          echo "activation artifact is not a Nix store path" >&2
          exit 65
          ;;
      esac
      [ "$(readlink -f "$artifact")" = "$artifact" ]
      [ -f "$profile" ] && [ ! -L "$profile" ]
      [ "$(stat -c %u "$profile")" = "$PKEXEC_UID" ]
      profile_mode=$((8#$(stat -c %a "$profile")))
      (( (profile_mode & 8#077) == 0 ))
      max_profile_bytes=1048576
      profile_bytes=$(stat -c %s "$profile")
      [ "$profile_bytes" -le "$max_profile_bytes" ] || {
        echo "profile exceeds the 1 MiB settings-service limit" >&2
        exit 65
      }

      custody=/var/lib/nori-desktop-settings
      install -d -m 0700 -o root -g root "$custody"
      temporary=$(mktemp -d "$custody/activation.XXXXXX")
      trap 'rm -rf "$temporary"' EXIT
      copied_profile="$temporary/profile.json"
      install -m 0600 -o root -g root "$profile" "$copied_profile"
      copied_bytes=$(stat -c %s "$copied_profile")
      [ "$copied_bytes" -le "$max_profile_bytes" ] || {
        echo "profile exceeds the 1 MiB settings-service limit after custody copy" >&2
        exit 65
      }
      actual_hash=$(sha256sum "$copied_profile" | cut -d ' ' -f 1)
      [ "$actual_hash" = "$profile_hash" ] || {
        echo "profile bytes changed before privileged activation" >&2
        exit 65
      }
      jq -e \
        --argjson revision "$revision" \
        '
          type == "object" and
          ((keys | sort) == ["components", "formatVersion", "revision", "savedCommands"]) and
          .formatVersion == 1 and
          (.revision | type == "number" and floor == . and . >= 0 and . == $revision) and
          (.components | type == "object") and
          (.savedCommands | type == "array")
        ' "$copied_profile" >/dev/null

      expected=$(${settingsBuilder}/bin/nori-desktop-settings-build \
        --profile "$copied_profile" \
        --profile-hash "$profile_hash")
      expected_artifact=$(printf '%s' "$expected" | jq -er '.artifact | strings')
      [ "$expected_artifact" = "$artifact" ] || {
        echo "requested artifact does not match approved source and profile" >&2
        exit 65
      }
      marker=/etc/nori-desktop-settings/approved-source.json
      source=$(jq -er '.source | strings' "$marker")
      metadata="$artifact/etc/nori-desktop-settings/generation.json"
      [ -f "$metadata" ]
      jq -e \
        --arg source "$source" \
        --argjson revision "$revision" \
        --arg hash "$profile_hash" \
        '.source == $source and .profileRevision == $revision and .profileHash == $hash' \
        "$metadata" >/dev/null

      "$artifact/bin/switch-to-configuration" switch >&2

      active_metadata=/run/current-system/etc/nori-desktop-settings/generation.json
      [ -f "$active_metadata" ]
      jq -e \
        --arg source "$source" \
        --argjson revision "$revision" \
        --arg hash "$profile_hash" \
        '.source == $source and .profileRevision == $revision and .profileHash == $hash' \
        "$active_metadata" >/dev/null
      active_path=$(readlink -f /run/current-system)
      boot_default=false
      if [ "$(readlink -f /nix/var/nix/profiles/system)" = "$active_path" ]; then
        boot_default=true
      fi
      jq -cn \
        --arg path "$active_path" \
        --arg source "$source" \
        --argjson revision "$revision" \
        --arg hash "$profile_hash" \
        --argjson boot_default "$boot_default" \
        '{ activeGeneration: { path: $path, source: $source, profileRevision: $revision, profileHash: $hash, bootDefault: $boot_default } }'
    '';
  };
  polkitPolicy = pkgs.writeTextDir "share/polkit-1/actions/org.nori.desktop-settings.policy" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
    <policyconfig>
      <action id="org.nori.desktop-settings.activate">
        <description>Activate an approved Nori desktop settings generation</description>
        <message>Authentication is required to activate this desktop settings generation</message>
        <defaults>
          <allow_any>no</allow_any>
          <allow_inactive>no</allow_inactive>
          <allow_active>no</allow_active>
        </defaults>
        <annotate key="org.freedesktop.policykit.exec.path">/run/current-system/sw/bin/nori-desktop-settings-activate</annotate>
        <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
      </action>
    </policyconfig>
  '';
in
{
  environment.etc."nori-desktop-settings/approved-source.json" = {
    mode = "0444";
    text = sourceMarker;
  };

  environment.systemPackages = [
    settingsPreview
    settingsBuilder
    settingsActivator
    polkitPolicy
  ];

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.nori.desktop-settings.activate" &&
        subject.user == "nori" &&
        subject.active
      ) {
        return polkit.Result.AUTH_ADMIN;
      }
    });
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/nori-desktop-settings 0700 root root -"
  ];
}
