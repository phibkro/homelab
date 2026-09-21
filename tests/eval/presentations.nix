{
  inputs,
  lib,
  ...
}:

/**
  Future status and onboarding projection test.

  Internet-facing status data excludes operator-only endpoints and all
  topology. The richer portal catalog carries explicit visibility tiers for a
  future authenticated frontend, without ports, hosts, or secret material.
*/
let
  inventory = inputs.self.lib.noriInventory;
  compiler = import ../../inventory;
  workloadCatalog = import ../../inventory/workloads.nix { inherit lib; };
  statusServices = inventory.status.services;
  portalServices = inventory.portal.services;

  portalPresentationKeys = [
    "audience"
    "authentication"
    "description"
    "registrationRequired"
    "title"
    "url"
    "visibleTo"
  ];
  statusPresentationKeys = [
    "description"
    "title"
    "url"
  ];

  shapeIsMinimal =
    keys: catalog: lib.all (service: lib.attrNames service == keys) (lib.attrValues catalog);
  statusIsInternetSafe = lib.all (
    service: lib.hasPrefix "https://" service.url && lib.hasSuffix ".home.phibkro.org" service.url
  ) (lib.attrValues statusServices);
  expectedStatusServices = [
    "audio"
    "media"
    "requests"
  ];
  invalidPublicationFails =
    endpointChange:
    let
      changedCatalog = workloadCatalog // {
        jellyfin = workloadCatalog.jellyfin // {
          endpoints = workloadCatalog.jellyfin.endpoints // {
            media = workloadCatalog.jellyfin.endpoints.media // endpointChange;
          };
        };
      };
      evaluated = builtins.tryEval (
        builtins.deepSeq
          (compiler {
            inherit lib;
            workloadCatalog = changedCatalog;
          }).public.status
          true
      );
    in
    !evaluated.success;

  portalPolicyWorks =
    portalServices.media.audience == "family"
    &&
      portalServices.media.visibleTo == [
        "family"
        "operator"
      ]
    /*
      Navidrome moved off Authelia OIDC to native accounts in 70398f9
      ("expose family media through native accounts"). Assert the pair, not
      just the enum: a native-account service is only correct for a family
      audience if the portal also tells them registration is required.
    */
    && portalServices.audio.authentication == "service-native-or-exception"
    && portalServices.audio.registrationRequired
    && portalServices.downloads.audience == "operator"
    && portalServices.downloads.authentication == "forward-auth"
    && portalServices.downloads.registrationRequired
    && portalServices.downloads.visibleTo == [ "operator" ]
    && portalServices.filmder.audience == "family"
    && portalServices.filmder.authentication == "forward-auth"
    && portalServices.filmder.registrationRequired
    &&
      portalServices.filmder.visibleTo == [
        "family"
        "operator"
      ];

  entryPlaneOwnershipIsExplicit =
    inventory.hosts.${inventory.site.entryPlaneHost}.kind == "ansible"
    && !(builtins.hasAttr inventory.site.entryPlaneHost inputs.self.nixosConfigurations);
  portalUsesCanonicalDomain = lib.all (
    service: lib.hasSuffix ".home.phibkro.org" service.url && !lib.hasInfix ".nori.lan" service.url
  ) (lib.attrValues portalServices);
  entryPlaneEndpointsFollowSite =
    lib.all (endpoint: endpoint.runsOn == inventory.site.entryPlaneHost)
      [
        inventory.workloads.authelia.endpoints.auth
        inventory.workloads."beszel-hub".endpoints.metrics
        inventory.workloads.gatus.endpoints.status
        inventory.workloads.gatus.endpoints.uptime
        inventory.workloads.glance.endpoints.home
        inventory.workloads."ntfy-server".endpoints.alert
        inventory.workloads.victoriametrics.endpoints.tsdb
        inventory.workloads."victorialogs-server".endpoints.logs
      ];
in
if
  inventory.site == {
    domain = "home.phibkro.org";
    deprecatedDomains = [ "nori.lan" ];
    entryPlaneHost = "pi";
  }
  && lib.attrNames statusServices == expectedStatusServices
  && shapeIsMinimal statusPresentationKeys statusServices
  && shapeIsMinimal portalPresentationKeys portalServices
  && statusIsInternetSafe
  && invalidPublicationFails { monitor = null; }
  && invalidPublicationFails { audience = "operator"; }
  && portalPolicyWorks
  && entryPlaneOwnershipIsExplicit
  && portalUsesCanonicalDomain
  && entryPlaneEndpointsFollowSite
then
  "ok — presentation catalogs, portal links, and deprecated redirects derive from the canonical site"
else
  throw ''
    Presentation projection mismatch.
    Status services: ${builtins.toJSON statusServices}
    Portal policy:   ${toString portalPolicyWorks}
    Status safe:     ${toString statusIsInternetSafe}
    Entry ownership: ${toString entryPlaneOwnershipIsExplicit}
    Portal domains:  ${toString portalUsesCanonicalDomain}
    Entry plane:     ${toString entryPlaneEndpointsFollowSite}
  ''
