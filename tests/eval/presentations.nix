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
  pi = inputs.self.nixosConfigurations.pi.config;
  aurora = inputs.self.nixosConfigurations.aurora.config;
  statusServices = inventory.status.services;
  portalServices = inventory.portal.services;

  presentationKeys = [
    "audience"
    "authentication"
    "description"
    "registrationRequired"
    "title"
    "url"
    "visibleTo"
  ];

  shapeIsMinimal =
    catalog: lib.all (service: lib.attrNames service == presentationKeys) (lib.attrValues catalog);
  statusIsInternetSafe = lib.all (
    service:
    service.audience != "operator"
    && lib.hasPrefix "https://" service.url
    && lib.hasSuffix ".home.phibkro.org" service.url
  ) (lib.attrValues statusServices);

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
in
if
  inventory.site == {
    domain = "home.phibkro.org";
    deprecatedDomains = [ "nori.lan" ];
  }
  && shapeIsMinimal statusServices
  && shapeIsMinimal portalServices
  && statusIsInternetSafe
  && portalPolicyWorks
  && deprecatedDomainPolicyWorks
  && portalUsesCanonicalDomain
then
  "ok — presentation catalogs, portal links, and deprecated redirects derive from the canonical site"
else
  throw ''
    Presentation projection mismatch.
    Status services: ${builtins.toJSON statusServices}
    Portal policy:   ${toString portalPolicyWorks}
    Status safe:     ${toString statusIsInternetSafe}
    Legacy aliases:  ${toString deprecatedDomainPolicyWorks}
    Portal domains:  ${toString portalUsesCanonicalDomain}
  ''
