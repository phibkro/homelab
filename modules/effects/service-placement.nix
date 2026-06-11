{ config, lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  # nori.services — per-service host-placement registry.
  #
  # Decouples "what is this service" (the module body) from "is it
  # active on this host" (a flag the host owns). The activation flag
  # lets a service module live in `modules/services/` while being
  # silent on hosts that don't enable it — which is what P2 of the
  # aurora migration relies on to move family-tier services from
  # workstation to aurora by flipping a flag rather than moving
  # imports.
  #
  # Shape — read by service modules:
  #
  #   { lib, config, ... }: lib.mkMerge [
  #     (lib.mkIf config.nori.services.<name>.enabled {
  #       # service config goes here
  #     })
  #   ];
  #
  # Service modules check `enabled` (not `enable`) — that's the
  # combined value that honours both per-service flips and the
  # tag-based bulk opt-in below.
  #
  # Tag-based opt-in — hosts that want a coherent bundle of services:
  #
  #   nori.enableServicesByTag = [ "family-tier" "observability" ];
  #
  # Any service whose `tags` list intersects that list gets enabled.
  # Combined with explicit per-service flags via OR (either route to
  # enabled = true is sufficient).
  #
  # Why a separate effect rather than reusing `services.<svc>.enable`
  # — keeping host-placement metadata in `nori.<X>` co-locates it with
  # the rest of the Reader+Writer effect family (lanRoutes, fs, backups,
  # harden) so the per-host wiring story is uniform. ADR-0002 / aurora
  # migration plan P1.

  options.nori.services = mkOption {
    default = { };
    description = ''
      Per-service host-placement registry. Service modules under
      modules/services/ declare themselves here with `tags` describing
      what kind of service they are; hosts opt in via
      `nori.services.<name>.enable = true` or by tag via
      `nori.enableServicesByTag`.
    '';
    example = lib.literalExpression ''
      {
        vault   = { enable = true; tags = [ "family-tier" "stateful" ]; };
        jellyfin = { tags = [ "media-server" "gpu-bound" ]; };
      }
    '';
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Per-host explicit opt-in. Combined with the tag-based
                bulk opt-in via OR; read the combined value through
                `enabled`, not this raw flag.
              '';
            };
            tags = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = ''
                Labels describing what category this service is in.
                Hosts can enable whole categories at once via
                `nori.enableServicesByTag`. Conventional tags as of
                the aurora migration: `family-tier`, `media-server`,
                `media-reader`, `observability`, `network-appliance`,
                `gpu-bound`, `stateful`, `stateless`. Tags are
                informational — no enum gate — so new categories can
                be introduced without a schema change. See ADR-0002.
              '';
            };
            enabled = mkOption {
              type = types.bool;
              readOnly = true;
              internal = true;
              default =
                config.nori.services.${name}.enable
                || lib.any (t: lib.elem t config.nori.enableServicesByTag) config.nori.services.${name}.tags;
              description = ''
                Effective activation flag: true iff the service is
                explicitly enabled OR any of its tags matches the
                host's `nori.enableServicesByTag` list. Service
                modules gate themselves on this.
              '';
            };
          };
        }
      )
    );
  };

  options.nori.enableServicesByTag = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = ''
      Host-level bulk opt-in. Any service whose `tags` list intersects
      this list gets `enabled = true`. Combines with per-service
      `enable` via OR.
    '';
    example = lib.literalExpression ''[ "family-tier" "observability" ]'';
  };

  # No `config` block — service-placement is a pure Reader at this
  # layer. The `enabled` derivation lives in the submodule default
  # above so service modules read it through the per-service path.
  # Consumers: every modules/services/<name>.nix (post-P2 sweep).
}
