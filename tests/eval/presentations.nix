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
  pi = inputs.self.nixosConfigurations.pi.config;
  aurora = inputs.self.nixosConfigurations.aurora.config;
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
  edgeHostnameCollisionFails =
    let
      changedCatalog = workloadCatalog // {
        gatus = workloadCatalog.gatus // {
          endpoints = workloadCatalog.gatus.endpoints // {
            status = workloadCatalog.gatus.endpoints.uptime;
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
    && portalServices.audio.authentication == "oidc"
    && portalServices.downloads.visibleTo == [ "operator" ]
    &&
      portalServices.filmder.visibleTo == [
        "public"
        "family"
        "operator"
      ];

  deprecatedDomainPolicyWorks =
    pi.services.caddy.virtualHosts ? "http://*.nori.lan"
    && pi.services.blocky.settings.customDNS.mapping."media.nori.lan" == pi.nori.lanIp;
  glanceSettings = builtins.toJSON aurora.services.glance.settings;
  portalUsesCanonicalDomain =
    lib.hasInfix "https://media.home.phibkro.org" glanceSettings
    && !lib.hasInfix ".nori.lan" glanceSettings;
  entryPlaneEndpointsFollowSite =
    lib.all (endpoint: endpoint.runsOn == inventory.site.entryPlaneHost)
      [
        inventory.workloads.authelia.endpoints.auth
        inventory.workloads."beszel-hub".endpoints.metrics
        inventory.workloads.gatus.endpoints.uptime
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
  && edgeHostnameCollisionFails
  && portalPolicyWorks
  && deprecatedDomainPolicyWorks
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
    Edge collision:  ${toString edgeHostnameCollisionFails}
    Legacy aliases:  ${toString deprecatedDomainPolicyWorks}
    Portal domains:  ${toString portalUsesCanonicalDomain}
    Entry plane:     ${toString entryPlaneEndpointsFollowSite}
  ''
