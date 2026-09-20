{ lib, ... }:

/**
  Typed, read-only projection of the pure pre-evaluation inventory.

  Values are injected by `lib/machines.nix`; modules consume this
  interface but cannot use it to select imports. Compiler-private module paths
  and future artifact handles never enter the projection.
*/

let
  inherit (lib) mkOption types;
  hostRoles = import ../../../inventory/host-roles.nix;
  audienceKeys = (import ../../../roles/audiences.nix).keys;

  identityOptions = {
    tailnetIp = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    lanIp = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    role = mkOption {
      type = types.enum hostRoles;
    };
    roleOneLiner = mkOption { type = types.str; };
    codename = mkOption { type = types.str; };
    hardware = mkOption { type = types.str; };
    primaryJob = mkOption { type = types.str; };
  };

  remoteBackupSourceOptions = {
    user = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; };
    directory = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; };
    hostKey = mkOption { type = types.str; };
    authorizedKey = mkOption { type = types.str; };
  };

  hostType = types.submodule {
    options = identityOptions // {
      kind = mkOption {
        type = types.enum [
          "ansible"
          "nixos"
        ];
      };
      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      profiles = mkOption { type = types.listOf types.str; };
      workloads = mkOption { type = types.listOf types.str; };
    };
  };

  profileType = types.submodule {
    options.description = mkOption { type = types.str; };
  };

  realizationType = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      host = mkOption { type = types.str; };
      instance = mkOption { type = types.str; };
    };
  };
  forwardAuthType = types.submodule {
    options.exemptPaths = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
  };

  oidcType = types.submodule {
    options = {
      clientName = mkOption { type = types.str; };
      redirectPath = mkOption { type = types.str; };
      tokenEndpointAuthMethod = mkOption {
        type = types.enum [
          "client_secret_basic"
          "client_secret_post"
        ];
      };
      scopes = mkOption {
        type = types.listOf types.str;
        default = [
          "openid"
          "profile"
          "email"
          "groups"
        ];
      };
      authorizationPolicy = mkOption {
        type = types.str;
        default = "one_factor";
      };
      secretEnvName = mkOption {
        type = types.str;
        default = "OAUTH_CLIENT_SECRET";
      };
    };
  };

  monitorType = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        default = "/";
      };
      interval = mkOption {
        type = types.str;
        default = "60s";
      };
      headers = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      conditions = mkOption {
        type = types.listOf types.str;
        default = [ "[STATUS] == 200" ];
      };
      failureThreshold = mkOption {
        type = types.ints.positive;
        default = 3;
      };
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  dashboardType = types.submodule {
    options = {
      title = mkOption { type = types.str; };
      icon = mkOption { type = types.str; };
      group = mkOption {
        type = types.enum [
          "Consume"
          "Acquire"
          "Personal"
          "Projects"
          "Admin"
        ];
      };
      description = mkOption { type = types.str; };
      allowInsecure = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  routeType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      workload = mkOption { type = types.str; };
      endpoint = mkOption { type = types.str; };
      host = mkOption { type = types.str; };
      hostname = mkOption { type = types.str; };
      port = mkOption { type = types.port; };
      scheme = mkOption {
        type = types.enum [
          "http"
          "https"
        ];
      };
      reachability = mkOption {
        type = types.enum [
          "internal"
          "internet"
        ];
      };
      audience = mkOption { type = types.enum audienceKeys; };
      authentication = mkOption {
        type = types.enum [
          "oidc"
          "forward-auth"
          "service-native-or-exception"
          "none"
        ];
      };
      auth = mkOption {
        type = types.enum [
          "none"
          "oidc"
          "forward-auth"
        ];
      };
      exposeOnTailnet = mkOption { type = types.bool; };
      forwardAuth = mkOption {
        type = types.nullOr forwardAuthType;
        default = null;
      };
      oidc = mkOption {
        type = types.nullOr oidcType;
        default = null;
      };
      monitor = mkOption {
        type = types.nullOr monitorType;
        default = null;
      };
      dashboard = mkOption {
        type = types.nullOr dashboardType;
        default = null;
      };
      publicStatus = mkOption {
        type = types.bool;
        default = false;
      };
      upstreamHostHeader = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      upstreamOriginHeader = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };


  piRouteType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      hostname = mkOption { type = types.str; };
      upstream_address = mkOption { type = types.str; };
      upstream_port = mkOption { type = types.port; };
      scheme = mkOption { type = types.enum [ "http" "https" ]; };
      reachability = mkOption { type = types.enum [ "internal" "internet" ]; };
      audience = mkOption { type = types.enum audienceKeys; };
      auth = mkOption { type = types.enum [ "none" "oidc" "forward-auth" ]; };
      forward_auth_exempt_paths = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      forward_auth_upstream = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      oidc_redirect_path = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      upstream_host_header = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      upstream_origin_header = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  piProbeType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      url = mkOption { type = types.str; };
      interval = mkOption { type = types.str; };
      headers = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      client = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
      conditions = mkOption { type = types.listOf types.str; };
      failure_threshold = mkOption { type = types.ints.positive; };
      send_on_resolved = mkOption { type = types.bool; };
    };
  };

  piBookmarkType = types.submodule {
    options = {
      title = mkOption { type = types.str; };
      icon = mkOption { type = types.str; };
      description = mkOption { type = types.str; };
      url = mkOption { type = types.str; };
    };
  };

  piScrapeTargetType = types.submodule {
    options = {
      targets = mkOption { type = types.listOf types.str; };
      labels = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };
  };

  piProjectionType = types.submodule {
    options = {
      pi_lan_address = mkOption { type = types.str; };
      pi_service_bind_address = mkOption { type = types.str; };
      pihole_lan_address = mkOption { type = types.str; };
      pihole_tailnet_address = mkOption { type = types.str; };
      pi_domain = mkOption { type = types.str; };
      pi_deprecated_domains = mkOption { type = types.listOf types.str; };
      pi_routes = mkOption { type = types.listOf piRouteType; };
      pi_tailnet_workload_ports = mkOption { type = types.listOf types.port; };
      glance_enabled = mkOption { type = types.bool; };
      glance_bookmark_groups = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              title = mkOption { type = types.str; };
              links = mkOption { type = types.listOf piBookmarkType; };
            };
          }
        );
      };
      authelia_oidc_clients = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              client_id = mkOption { type = types.str; };
              client_name = mkOption { type = types.str; };
              authorization_policy = mkOption { type = types.str; };
              token_endpoint_auth_method = mkOption { type = types.str; };
              redirect_uris = mkOption { type = types.listOf types.str; };
              scopes = mkOption { type = types.listOf types.str; };
            };
          }
        );
      };
      gatus_endpoints = mkOption { type = types.listOf piProbeType; };
      victoriametrics_scrape_jobs = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              job_name = mkOption { type = types.str; };
              static_configs = mkOption { type = types.listOf piScrapeTargetType; };
            };
          }
        );
      };
      beszel_agent_listen_port = mkOption { type = types.port; };
      beszel_systems = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              host = mkOption { type = types.str; };
              port = mkOption { type = types.port; };
            };
          }
        );
      };
      ddns_hostnames = mkOption { type = types.listOf types.str; };
      pihole_local_dns_records = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              address = mkOption { type = types.str; };
              names = mkOption { type = types.listOf types.str; };
            };
          }
        );
      };
      pi_backup_enabled = mkOption { type = types.bool; };
      pi_backup_target_address = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      pi_backup_target_host = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      pi_backup_target_user = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      pi_backup_repository_prefix = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      pi_backup_target_known_host = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      pi_backup_jobs = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              paths = mkOption { type = types.listOf types.str; };
            };
          }
        );
        default = [ ];
      };
    };
  };

  workloadType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "service"
          "job"
        ];
      };
      active = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the placed workload currently realizes its user-facing runtime and endpoints.";
      };
      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      hostRoles = mkOption {
        type = types.listOf (types.enum hostRoles);
        description = "Host roles on which this workload may be placed.";
      };
      placement = mkOption {
        type = types.attrs;
        description = "Compiler-validated ordered placement selectors and cardinality.";
      };
      endpoints = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Resolved, secret-free endpoint metadata; validated by the networking route schema when projected.";
      };
      listenPort = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host-local listener shared by every realization of a replicated workload.";
      };
      hosts = mkOption { type = types.listOf types.str; };
      realizations = mkOption { type = types.listOf realizationType; };
      artifact = mkOption {
        type = types.nullOr artifactType;
        default = null;
      };
    };
  };

  artifactType = types.submodule {
    options = {
      kind = mkOption { type = types.enum [ "static-web" ]; };
      immutable = mkOption { type = types.bool; };
      source = mkOption {
        type = types.submodule {
          options = {
            repository = mkOption { type = types.str; };
            ref = mkOption { type = types.str; };
          };
        };
      };
      consumer = mkOption {
        type = types.submodule {
          options = {
            kind = mkOption {
              type = types.enum [
                "nix-package"
                "release-archive"
                "oci-image"
                "legacy-host-build"
              ];
            };
            unit = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          };
        };
      };
      legacyException = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              owner = mkOption { type = types.str; };
              reason = mkOption { type = types.str; };
              removalTrigger = mkOption { type = types.str; };
              verification = mkOption { type = types.str; };
            };
          }
        );
        default = null;
      };
    };
  };

  datasetType = types.submodule {
    options = {
      description = mkOption { type = types.str; };
      valueTier = mkOption {
        type = types.enum [
          "replaceable"
          "curated"
          "irreplaceable"
        ];
      };
      canonicalFormat = mkOption { type = types.str; };
      storage = mkOption {
        type = types.submodule {
          options = {
            filesystem = mkOption { type = types.str; };
            relativePath = mkOption { type = types.str; };
          };
        };
      };
      producers = mkOption { type = types.listOf types.str; };
      consumers = mkOption { type = types.listOf types.str; };
      derivedFormats = mkOption { type = types.listOf types.str; };
      delivery = mkOption {
        type = types.submodule {
          options = {
            protocol = mkOption { type = types.str; };
            transcodeOnDemand = mkOption { type = types.listOf types.str; };
          };
        };
      };
    };
  };

  diskType = types.submodule {
    options = {
      role = mkOption {
        type = types.enum [
          "backup"
          "cold-primary"
        ];
      };
      attachedHost = mkOption { type = types.str; };
      mountPoint = mkOption { type = types.str; };
      identity = mkOption {
        type = types.submodule {
          options = {
            byId = mkOption { type = types.str; };
            model = mkOption { type = types.str; };
            serial = mkOption { type = types.str; };
            capacityBytes = mkOption { type = types.ints.unsigned; };
            transport = mkOption {
              type = types.enum [
                "sata"
                "usb"
              ];
            };
          };
        };
      };
      filesystem = mkOption {
        type = types.submodule {
          options = {
            device = mkOption { type = types.str; };
            type = mkOption { type = types.str; };
            label = mkOption { type = types.str; };
          };
        };
      };
    };
  };

  deploymentTargetType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "ansible"
          "nixos"
        ];
      };
      profiles = mkOption { type = types.listOf types.str; };
      workloads = mkOption { type = types.listOf types.str; };
      buildAttribute = mkOption { type = types.nullOr types.str; };
      planCommand = mkOption { type = types.nullOr types.str; };
      applyCommand = mkOption { type = types.nullOr types.str; };
      verifyCommand = mkOption { type = types.nullOr types.str; };
    };
  };

  deploymentType = types.submodule {
    options = {
      targets = mkOption { type = types.attrsOf deploymentTargetType; };
      buildOrder = mkOption { type = types.listOf types.str; };
      activationOrder = mkOption { type = types.listOf types.str; };
    };
  };

  topologyNodeType = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      kind = mkOption {
        type = types.enum [
          "machine"
          "device"
          "workload"
          "realization"
          "endpoint"
          "dataset"
        ];
      };
      properties = mkOption { type = types.attrs; };
      capabilities = mkOption { type = types.attrsOf types.attrs; };
    };
  };

  topologyRequirementType = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      owner = mkOption { type = types.str; };
      name = mkOption { type = types.str; };
      capability = mkOption { type = types.str; };
      relationship = mkOption { type = types.str; };
      target = mkOption { type = types.str; };
      constraints = mkOption { type = types.attrsOf types.attrs; };
    };
  };

  topologyRelationshipType = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      type = mkOption { type = types.str; };
      source = mkOption { type = types.str; };
      target = mkOption { type = types.str; };
      properties = mkOption { type = types.attrs; };
    };
  };

  topologyType = types.submodule {
    options = {
      schemaVersion = mkOption { type = types.ints.positive; };
      nodes = mkOption { type = types.listOf topologyNodeType; };
      requirements = mkOption { type = types.listOf topologyRequirementType; };
      relationships = mkOption { type = types.listOf topologyRelationshipType; };
    };
  };

  presentationType = types.submodule {
    options = {
      title = mkOption { type = types.str; };
      description = mkOption { type = types.str; };
      url = mkOption { type = types.str; };
      audience = mkOption {
        type = types.enum audienceKeys;
      };
      authentication = mkOption {
        type = types.enum [
          "oidc"
          "forward-auth"
          "service-native-or-exception"
          "none"
        ];
      };
      registrationRequired = mkOption { type = types.bool; };
      visibleTo = mkOption {
        type = types.listOf (types.enum audienceKeys);
      };
    };
  };
in
{
  options.nori.inventory = {
    currentHost = mkOption {
      type = types.str;
      readOnly = true;
      description = "Host whose NixOS configuration is currently evaluating.";
    };
    currentWorkloads = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = "Workload identifiers resolved from service-owned ordered placement selectors.";
    };
    hosts = mkOption {
      type = types.attrsOf hostType;
      readOnly = true;
      description = "Public-safe host identity, profile, and resolved workload inventory.";
    };
    profiles = mkOption {
      type = types.attrsOf profileType;
      readOnly = true;
      description = "Explicit reusable profile descriptions.";
    };
    workloads = mkOption {
      type = types.attrsOf workloadType;
      readOnly = true;
      description = "Public-safe workload identity and resolved placement.";
    };
    routes = mkOption {
      type = types.attrsOf routeType;
      default = { };
      readOnly = true;
      description = "Compiler-owned active HTTP route projection shared by NixOS and Pi adapters.";
    };
    pi = mkOption {
      type = piProjectionType;
      default = { };
      readOnly = true;
      description = "Secret-free Pi Ansible projection; transport credentials remain adapter inputs.";
    };
    topology = mkOption {
      type = topologyType;
      readOnly = true;
      description = "Validated intended topology graph derived from the public inventory.";
    };
    disks = mkOption {
      type = types.attrsOf diskType;
      readOnly = true;
      description = "Public-safe external disk registry; host-local NVMe layouts are intentionally excluded.";
    };
    backup = mkOption {
      readOnly = true;
      description = "Public backup destination, pinned SSH keys, and explicit remote repository manifests.";
      type = types.submodule {
        options = {
          enabled = mkOption { type = types.bool; };
          targetName = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; };
          device = mkOption { type = types.str; };
          fsType = mkOption { type = types.str; };
          targetHost = mkOption { type = types.str; };
          hostname = mkOption { type = types.str; };
          mountPoint = mkOption { type = types.str; };
          retention = mkOption {
            type = types.submodule {
              options.coldMedia = mkOption {
                type = types.submodule {
                  options = {
                    localSnapshotPreserve = mkOption { type = types.str; };
                    resticPruneOpts = mkOption { type = types.listOf types.str; };
                  };
                };
              };
            };
          };
          pi = mkOption {
            type = types.submodule {
              options = remoteBackupSourceOptions // {
                repositoryPrefix = mkOption { type = types.enum [ "" ]; };
                jobs = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        name = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; };
                        paths = mkOption { type = types.listOf types.str; };
                      };
                    }
                  );
                };
              };
            };
          };
          adelie = mkOption {
            type = types.submodule {
              options = remoteBackupSourceOptions // {
                repositoryPrefix = mkOption { type = types.enum [ "repos" ]; };
              };
            };
          };
        };
      };
    };
    datasets = mkOption {
      type = types.attrsOf datasetType;
      readOnly = true;
      description = "Public-safe canonical dataset ownership, storage, producer, consumer, and delivery contracts.";
    };
    deployment = mkOption {
      type = deploymentType;
      readOnly = true;
      description = "Public-safe build targets and backend-before-entry-plane activation order derived from host inventory.";
    };
    site = mkOption {
      type = types.submodule {
        options = {
          domain = mkOption { type = types.str; };
          deprecatedDomains = mkOption { type = types.listOf types.str; };
          entryPlaneHost = mkOption { type = types.str; };
        };
      };
      readOnly = true;
      description = "Canonical public service namespace and deprecated aliases.";
    };
    status = mkOption {
      type = types.submodule {
        options.services = mkOption { type = types.attrsOf presentationType; };
      };
      readOnly = true;
      description = "Internet-safe monitored family/public service catalog without topology details.";
    };
    portal = mkOption {
      type = types.submodule {
        options = {
          accessTiers = mkOption { type = types.attrsOf types.str; };
          services = mkOption { type = types.attrsOf presentationType; };
        };
      };
      readOnly = true;
      description = "Access-tiered portal/onboarding catalog for an authenticated future frontend.";
    };
  };
}
