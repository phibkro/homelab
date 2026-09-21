{ config, lib, ... }:

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
  localTailnetRoutePorts = lib.sort builtins.lessThan (
    lib.unique (
      map (route: route.port) (
        lib.filter (route: route.host == config.nori.inventory.currentHost && route.exposeOnTailnet) (
          lib.attrValues config.nori.inventory.routes
        )
      )
    )
  );

  identityOptions = {
    tailnetIp = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Stable Tailscale IPv4 address, or null when the host is not enrolled.";
    };
    lanIp = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Stable LAN IPv4 address, or null when the host is tailnet-only.";
    };
    role = mkOption {
      type = types.enum hostRoles;
      description = "Host role used by workload placement constraints.";
    };
    roleOneLiner = mkOption {
      type = types.str;
      description = "Short operator-facing summary of the host role.";
    };
    codename = mkOption {
      type = types.str;
      description = "Human-readable host codename.";
    };
    hardware = mkOption {
      type = types.str;
      description = "Human-readable hardware summary.";
    };
    primaryJob = mkOption {
      type = types.str;
      description = "Primary responsibility of the host.";
    };
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
        description = "Deployment backend selected for the host.";
      };
      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Stable placement capabilities declared by the host.";
      };
      profiles = mkOption {
        type = types.listOf types.str;
        description = "Resolved reusable profiles selected for the host.";
      };
      workloads = mkOption {
        type = types.listOf types.str;
        description = "Resolved workloads selected for the host.";
      };
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
      secretHashEnvName = mkOption { type = types.str; };
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
      monitorProbeName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Canonical Gatus series key selected as this route's health outcome.";
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
  listenerType = types.submodule {
    options.port = mkOption {
      type = types.port;
      description = "Private host-local listener port projected from a workload manifest.";
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
      listeners = mkOption {
        type = types.attrsOf listenerType;
        default = { };
        description = "Private listener metadata projected unchanged from the workload manifest.";
      };
      probeNames = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Canonical names of workload-level monitoring probes.";
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
            persistentDerivative = mkOption { type = types.bool; };
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
      readOnly = true;
      description = "Compiler-owned active HTTP route projection shared by NixOS and Pi adapters.";
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
                        workload = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; };
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
  };

  config.networking.firewall.interfaces."tailscale0".allowedTCPPorts = localTailnetRoutePorts;
}
