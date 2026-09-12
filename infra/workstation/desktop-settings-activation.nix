{
  config,
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
      !(builtins.elem name [
        ".git"
        "dist"
        "node_modules"
        "result"
      ]);
  };
  sourceMarker = builtins.toJSON {
    source = toString approvedSource;
    host = "workstation";
  };
  settingsServicePackage = config.home-manager.users.nori.nori.desktop.settingsService.package;
  settingsIngress = config.home-manager.users.nori.nori.desktop.settingsService.ingress;
  settingsProfileValidator =
    config.home-manager.users.nori.nori.desktop.settingsService.profileValidator;
  settingsPreview = pkgs.writeShellApplication {
    name = "nori-desktop-settings-preview";
    runtimeInputs = [
      pkgs.coreutils
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
      revision=$(jq -er '.revision' "$profile")
      jq -cn \
        --argjson resolved "$resolved" \
        --arg source "$source" \
        --argjson revision "$revision" \
        --arg hash "$profile_hash" \
        '{ resolved: $resolved, metadata: { source: $source, profileRevision: $revision, profileHash: $hash } }'
    '';
  };
  settingsBuilder = pkgs.writeShellApplication {
    name = "nori-desktop-settings-build";
    runtimeInputs = [
      pkgs.coreutils
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
      resolved=$(nix-instantiate --eval --strict --json \
        "$source/lib/desktop-settings-eval.nix" \
        -A resolved \
        --argstr source "$source" \
        --argstr profile "$profile" \
        --argstr profileHash "$profile_hash" \
        --argstr host "$host")
      jq -e 'type == "object"' <<<"$resolved" >/dev/null
      jq -cn --arg artifact "$artifact" --slurpfile metadata "$metadata" --argjson resolved "$resolved" \
        '{ artifact: $artifact, metadata: $metadata[0], resolved: $resolved }'
    '';
  };
  settingsActivator = pkgs.writeShellApplication {
    name = "nori-desktop-settings-activate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.util-linux
      settingsProfileValidator
      settingsBuilder
    ];
    text = ''
      set -euo pipefail

      operation=""
      apply_id=""
      revision=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --operation) operation="''${2-}"; shift 2 ;;
          --apply-id) apply_id="''${2-}"; shift 2 ;;
          --expected-revision) revision="''${2-}"; shift 2 ;;
          *)
            echo "usage: nori-desktop-settings-activate --operation ID --apply-id UUID --expected-revision N" >&2
            exit 64
            ;;
        esac
      done
      [ "$operation" = "org.nori.desktop-settings.activate" ]
      authority_uid=$(id -u nori-desktop-settings)
      caller_uid=$(id -u nori)
      [ -n "''${PKEXEC_UID-}" ] && [ "$PKEXEC_UID" = "$caller_uid" ]
      [ -n "$apply_id" ] && [ -n "$revision" ]
      [[ "$apply_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
      [[ "$revision" =~ ^(0|[1-9][0-9]*)$ ]]

      state=/var/lib/nori-desktop-settings
      job="$state/jobs/$apply_id.json"
      lock="$state/activation.lock"
      [ -f "$job" ] && [ ! -L "$job" ]
      [ "$(stat -c %u "$job")" = "$authority_uid" ]
      job_mode=$((8#$(stat -c %a "$job")))
      (( (job_mode & 8#077) == 0 ))

      exec 9>"$lock"
      flock -n 9 || {
        echo "another desktop settings activation is already in progress" >&2
        exit 75
      }

      jq -e \
        --arg id "$apply_id" \
        --argjson revision "$revision" \
        '
          type == "object" and
          .id == $id and
          .status == "awaiting_authorization" and
          .revision == $revision and
          (.profileHash | strings) and
          (.source | strings | startswith("/nix/store/")) and
          (.previewArtifact | strings | startswith("/nix/store/"))
        ' "$job" >/dev/null
      profile_hash=$(jq -er '.profileHash' "$job")
      [[ "$profile_hash" =~ ^[0-9a-f]{64}$ ]]
      source=$(jq -er '.source' "$job")
      preview_artifact=$(jq -er '.previewArtifact' "$job")
      profile="$state/revisions/$revision-$profile_hash.json"
      [ -f "$profile" ] && [ ! -L "$profile" ]
      [ "$(stat -c %u "$profile")" = "$authority_uid" ]
      profile_mode=$((8#$(stat -c %a "$profile")))
      (( (profile_mode & 8#077) == 0 ))
      actual_hash=$(sha256sum "$profile" | cut -d ' ' -f 1)
      [ "$actual_hash" = "$profile_hash" ] || {
        echo "profile bytes changed before privileged activation" >&2
        exit 65
      }

      update_job() {
        status="$1"
        message="$2"
        temporary=$(mktemp "$state/jobs/.''${apply_id}.XXXXXX")
        jq --arg status "$status" --arg message "$message" --arg now "$(date --iso-8601=seconds)" \
          '
            .status = $status
            | .updatedAt = $now
            | .log = ((.log + [$message]) | .[-64:])
            | if $status == "failed"
              then .error = {
                code: "activation_rejected",
                message: "Root activation failed before the generation switch completed"
              }
              else del(.error)
              end
          ' \
          "$job" >"$temporary"
        chmod 0600 "$temporary"
        chown nori-desktop-settings:nori-desktop-settings "$temporary"
        mv -f "$temporary" "$job"
        sync -f "$job"
        sync -f "$state/jobs"
      }

      claimed=false
      switch_complete=false
      on_error() {
        exit_status=$?
        trap - ERR
        if [ "$claimed" = true ]; then
          if [ "$switch_complete" = true ]; then
            update_job reconciling "Activation may have completed; waiting for user runtime reconciliation" || true
          else
            update_job failed "Root activation failed before the generation switch completed" || true
          fi
        fi
        exit "$exit_status"
      }
      trap on_error ERR
      update_job activating "Root activation claimed the committed service apply"
      claimed=true

      custody=$(mktemp -d "$state/root-activation.XXXXXX")
      trap 'rm -rf "$custody"' EXIT
      copied_profile="$custody/profile.json"
      install -m 0600 -o root -g root "$profile" "$copied_profile"
      ${settingsProfileValidator}/bin/nori-desktop-settings-validate-profile --profile "$copied_profile"
      marker=/etc/nori-desktop-settings/approved-source.json
      approved_source=$(jq -er '.source | strings' "$marker")
      [ "$source" = "$approved_source" ]
      expected=$(${settingsBuilder}/bin/nori-desktop-settings-build \
        --profile "$copied_profile" \
        --profile-hash "$profile_hash")
      artifact=$(printf '%s' "$expected" | jq -er '.artifact | strings')
      [ "$artifact" = "$preview_artifact" ]
      metadata="$artifact/etc/nori-desktop-settings/generation.json"
      jq -e \
        --arg source "$source" \
        --argjson revision "$revision" \
        --arg hash "$profile_hash" \
        '.source == $source and .profileRevision == $revision and .profileHash == $hash' \
        "$metadata" >/dev/null
      "$artifact/bin/switch-to-configuration" switch >&2
      switch_complete=true
      update_job reconciling "Generation activated; waiting for the user runtime agent to reconcile Waybar"
      trap - ERR
      jq -cn --arg id "$apply_id" --arg artifact "$artifact" \
        '{ applyId: $id, artifact: $artifact, status: "reconciling" }'
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
  environment.etc."polkit-1/actions/org.nori.desktop-settings.policy".source =
    "${polkitPolicy}/share/polkit-1/actions/org.nori.desktop-settings.policy";
  environment.etc."nori-desktop-settings/activate".source =
    "${settingsActivator}/bin/nori-desktop-settings-activate";
  users.groups.nori-desktop-settings = { };
  users.users.nori-desktop-settings = {
    isSystemUser = true;
    group = "nori-desktop-settings";
  };
  users.users.nori.extraGroups = lib.mkAfter [ "nori-desktop-settings" ];

  systemd.services.nori-desktop-config = {
    description = "Nori desktop settings authority";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nori-desktop-settings";
      Group = "nori-desktop-settings";
      StateDirectory = "nori-desktop-settings";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "nori-desktop-settings";
      RuntimeDirectoryMode = "0710";
      ExecStart = "${settingsServicePackage}/bin/nori-desktop-settings daemon";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "NORI_DESKTOP_SETTINGS_CONFIG_HOME=/var/lib/nori-desktop-settings"
        "NORI_DESKTOP_SETTINGS_STATE_HOME=/var/lib/nori-desktop-settings"
        "NORI_DESKTOP_SETTINGS_DATA_DIR=/etc/nori-desktop-settings"
        "NORI_DESKTOP_SETTINGS_APPROVED_SOURCE=/etc/nori-desktop-settings/approved-source.json"
        "NORI_DESKTOP_SETTINGS_ACTIVE_METADATA=/etc/nori-desktop-settings/generation.json"
        "NORI_DESKTOP_SETTINGS_EVALUATOR=/run/current-system/sw/bin/nori-desktop-settings-preview"
        "NORI_DESKTOP_SETTINGS_BUILDER=/run/current-system/sw/bin/nori-desktop-settings-build"
        "NORI_DESKTOP_SETTINGS_RICE_COMMAND=${settingsServicePackage}/bin/rice-saved-command"
        "NORI_DESKTOP_SETTINGS_SHELL=${lib.getExe pkgs.bash}"
        "NORI_DESKTOP_SETTINGS_SOCKET=/run/nori-desktop-settings/settings-backend.sock"
      ];
    };
  };
  systemd.services.nori-desktop-config-ingress = {
    description = "Nori desktop settings credential-checked public ingress";
    wantedBy = [ "multi-user.target" ];
    requires = [ "nori-desktop-config.service" ];
    after = [ "nori-desktop-config.service" ];
    serviceConfig = {
      Type = "simple";
      User = "nori-desktop-settings";
      Group = "nori-desktop-settings";
      ExecStart =
        "${settingsIngress}/bin/nori-desktop-settings-ingress "
        + "/run/nori-desktop-settings/settings.sock "
        + "/run/nori-desktop-settings/settings-backend.sock "
        + (toString config.users.users.nori.uid);
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  environment.etc."nori-desktop-settings/settings-input.schema.json".source =
    config.home-manager.users.nori.nori.desktop.generated.inputSchema;
  environment.etc."nori-desktop-settings/settings-output.schema.json".source =
    config.home-manager.users.nori.nori.desktop.generated.outputSchema;
  environment.etc."nori-desktop-settings/components.json".source =
    config.home-manager.users.nori.nori.desktop.generated.presentation;
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

}
