import * as Dns from "@distilled.cloud/cloudflare/dns";
import { Credentials } from "@distilled.cloud/cloudflare/Credentials";
import { ResponseValidation } from "@distilled.cloud/core/response-validation";
import * as ZeroTrust from "@distilled.cloud/cloudflare/zero-trust";
import * as Zones from "@distilled.cloud/cloudflare/zones";
import { CloudflareEnvironment } from "alchemy/Cloudflare";
import * as Provider from "alchemy/Provider";
import { Resource, type Resource as ResourceType } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Option from "effect/Option";
import * as Redacted from "effect/Redacted";
import * as Schedule from "effect/Schedule";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

/*
 * Small Alchemy v2 resources for Cloudflare's 2026 MCP Portal API.
 *
 * Keep these established resource types and stable IDs across Alchemy upgrades.
 * Alchemy beta.80 has native counterparts, but switching resource types would
 * change state ownership. Retire this seam only through an explicit,
 * identity-preserving migration, not by replacing live resources. The
 * Apache-2.0 @distilled.cloud/cloudflare operations remain the API boundary.
 */

export interface McpServerProps {
  id: string;
  name: string;
  url: string;
  bearerToken: Redacted.Redacted<string>;
  dependency?: string;
  description?: string;
}

export type McpServer = ResourceType<
  "Homelab.Cloudflare.McpServer",
  McpServerProps,
  {
    serverId: string;
    name: string;
    url: string;
    status: string | undefined;
  }
>;

export const McpServer = Resource<McpServer>("Homelab.Cloudflare.McpServer");

export interface McpPortalProps {
  id: string;
  name: string;
  hostname: string;
  description?: string;
  serverIds: string[];
  allowCodeMode?: boolean;
  secureWebGateway?: boolean;
}

export type McpPortal = ResourceType<
  "Homelab.Cloudflare.McpPortal",
  McpPortalProps,
  {
    portalId: string;
    name: string;
    hostname: string;
  }
>;

export const McpPortal = Resource<McpPortal>("Homelab.Cloudflare.McpPortal");

export interface DnsRecordProps {
  hostname: string;
  content: string;
  proxied?: boolean;
  comment?: string;
  dependency?: string;
}

export type DnsRecord = ResourceType<
  "Homelab.Cloudflare.DnsRecord",
  DnsRecordProps,
  {
    recordId: string;
    zoneId: string;
    hostname: string;
    content: string;
    proxied: boolean;
  }
>;

export const DnsRecord = Resource<DnsRecord>("Homelab.Cloudflare.DnsRecord");

export interface McpAccessPolicyProps {
  name: string;
  email: string;
  dependency?: string;
  application: { type: "mcp"; serverId: string } | { type: "mcp_portal"; hostname: string };
}

export type McpAccessPolicy = ResourceType<
  "Homelab.Cloudflare.McpAccessPolicy",
  McpAccessPolicyProps,
  {
    applicationId: string;
    policyId: string;
  }
>;

export const McpAccessPolicy = Resource<McpAccessPolicy>("Homelab.Cloudflare.McpAccessPolicy");

const runItems = <A, E, R>(stream: Stream.Stream<A, E, R>) => stream.pipe(Stream.runCollect);

export class McpIdentityAmbiguous extends Schema.TaggedError<McpIdentityAmbiguous>()("McpIdentityAmbiguous", {
  resource: Schema.Literals(["server", "application", "policy"]),
  name: Schema.String,
  count: Schema.Int,
}) {}

export class McpServerUrlImmutable extends Schema.TaggedError<McpServerUrlImmutable>()("McpServerUrlImmutable", {
  serverId: Schema.String,
  expected: Schema.String,
  observed: Schema.String,
}) {}

export class McpServerSyncFailed extends Schema.TaggedError<McpServerSyncFailed>()("McpServerSyncFailed", {
  serverId: Schema.String,
  message: Schema.String,
}) {}

export class McpApplicationNotReady extends Schema.TaggedError<McpApplicationNotReady>()("McpApplicationNotReady", {
  applicationType: Schema.String,
}) {}

export class McpApplicationIdentityChanged extends Schema.TaggedError<McpApplicationIdentityChanged>()("McpApplicationIdentityChanged", {
  applicationId: Schema.String,
  resolvedApplicationId: Schema.String,
}) {}

const decodePolicyIdentity = Schema.decodeUnknownEffect(Schema.Struct({ id: Schema.NonEmptyString }));
const isIdentity = Schema.is(Schema.NonEmptyString);
const isApplicationSelector = Schema.is(Schema.Union([
  Schema.Struct({ type: Schema.Literal("mcp"), serverId: Schema.NonEmptyString }),
  Schema.Struct({ type: Schema.Literal("mcp_portal"), hostname: Schema.NonEmptyString }),
]));

export const McpServerProvider = () =>
  Provider.effect(
    McpServer,
    Effect.gen(function* () {
      const { accountId } = yield* (yield* CloudflareEnvironment);
      const controlCredentials = yield* Credentials;
      const authenticated = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
        effect.pipe(
          Effect.provideService(Credentials, controlCredentials),
          Effect.provideService(ResponseValidation, "strict"),
        );
      const create = yield* ZeroTrust.createAccessAiControlMcpServer;
      const update = yield* ZeroTrust.updateAccessAiControlMcpServer;
      const remove = yield* ZeroTrust.deleteAccessAiControlMcpServer;
      const sync = yield* ZeroTrust.syncAccessAiControlMcpServer;

      const find = (serverId: string) =>
        ZeroTrust.readAccessAiControlMcpServer({ accountId, id: serverId }).pipe(
          Effect.catchTag("McpServerNotFound", () => Effect.succeed(undefined)),
          authenticated,
        );

      const findByName = Effect.fn("McpServer.findByName")(function* (name: string) {
        const named = (yield* runItems(ZeroTrust.listAccessAiControlMcpServers.items({ accountId })).pipe(authenticated))
          .filter((server) => server.name === name);
        if (named.length > 1) {
          return yield* new McpIdentityAmbiguous({ resource: "server", name, count: named.length });
        }
        return named[0];
      });

      const findServer = Effect.fn("McpServer.findServer")(function* (name: string, serverId?: string) {
        const recorded = serverId ? yield* find(serverId) : undefined;
        if (recorded) return recorded;
        // A lost recorded ID does not establish absence under the stable
        // name. Check the approved adoption selector before any creation.
        return isIdentity(name) ? yield* findByName(name) : undefined;
      });


      const attributes = (server: {
        id: string;
        name: string;
        hostname: string;
        status?: string | null;
      }): McpServer["Attributes"] => ({
        serverId: server.id,
        name: server.name,
        url: server.hostname,
        status: server.status ?? undefined,
      });

      return {
        stables: ["serverId"],
        read: Effect.fn(function* ({ olds, output }) {
          if (!output && !isIdentity(olds?.name)) return undefined;
          const observed = yield* findServer(olds?.name, output?.serverId);
          return observed ? attributes(observed) : undefined;
        }),
        reconcile: Effect.fn(function* ({ news, output }) {
          // External creation can precede a failed state commit or capability
          // sync. Exact-name adoption is operator-approved for this resource;
          // recorded output IDs always remain authoritative. This is
          // at-least-once reconciliation, not an exactly-once create receipt.
          const observed = yield* findServer(news.name, output?.serverId);
          let reconciled: { id: string; name: string; hostname: string; status?: string | null };
          if (!observed) {
            reconciled = yield* authenticated(create({
              accountId,
              id: output?.serverId ?? news.id,
              name: news.name,
              hostname: news.url,
              authType: "bearer",
              authCredentials: Redacted.value(news.bearerToken),
              description: news.description,
            }));
          } else if (observed.hostname !== news.url) {
            return yield* new McpServerUrlImmutable({
              serverId: observed.id, expected: news.url, observed: observed.hostname,
            });
          } else {
            reconciled = yield* authenticated(update({
              accountId,
              id: observed.id,
              name: news.name,
              description: news.description,
              authCredentials: Redacted.value(news.bearerToken),
            }));
          }
          const synchronized = yield* authenticated(sync({ accountId, id: reconciled.id }));
          if (synchronized.status === "error" || synchronized.error) {
            return yield* new McpServerSyncFailed({
              serverId: reconciled.id, message: synchronized.error ?? "unknown error",
            });
          }
          return attributes(reconciled);
        }),
        delete: Effect.fn(function* ({ output }) {
          const observed = yield* find(output.serverId);
          if (observed) yield* authenticated(remove({ accountId, id: output.serverId }));
        }),
      };
    }),
  );

const McpPortalProvider = () =>
  Provider.effect(
    McpPortal,
    Effect.gen(function* () {
      const { accountId } = yield* (yield* CloudflareEnvironment);
      const controlCredentials = yield* Credentials;
      const authenticated = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
        effect.pipe(Effect.provideService(Credentials, controlCredentials));
      const create = yield* ZeroTrust.createAccessAiControlMcpPortal;
      const update = yield* ZeroTrust.updateAccessAiControlMcpPortal;
      const remove = yield* ZeroTrust.deleteAccessAiControlMcpPortal;

      const find = (portalId: string) =>
        ZeroTrust.listAccessAiControlMcpPortals.items({ accountId, search: portalId }).pipe(
          Stream.filter((portal) => portal.id === portalId),
          Stream.runHead,
          Effect.map(Option.getOrUndefined),
          authenticated,
        );

      const attributes = (portal: {
        id: string;
        name: string;
        hostname: string;
      }): McpPortal["Attributes"] => ({
        portalId: portal.id,
        name: portal.name,
        hostname: portal.hostname,
      });

      const desired = (news: McpPortalProps) => ({
        name: news.name,
        hostname: news.hostname,
        description: news.description,
        allowCodeMode: news.allowCodeMode ?? false,
        secureWebGateway: news.secureWebGateway ?? false,
        servers: news.serverIds.map((serverId) => ({
          serverId,
          defaultDisabled: false,
          onBehalf: false,
        })),
      });

      return {
        stables: ["portalId"],
        read: Effect.fn(function* ({ olds, output }) {
          const observed = yield* find(output?.portalId ?? olds.id);
          return observed ? attributes(observed) : undefined;
        }),
        reconcile: Effect.fn(function* ({ news, output }) {
          const observed = yield* find(output?.portalId ?? news.id);
          return attributes(
            observed
              ? yield* authenticated(update({
                  accountId,
                  id: observed.id,
                  ...desired(news),
                }))
              : yield* authenticated(create({
                  accountId,
                  id: news.id,
                  ...desired(news),
                })),
          );
        }),
        delete: Effect.fn(function* ({ output }) {
          const observed = yield* find(output.portalId);
          if (observed) {
            yield* authenticated(remove({ accountId, id: output.portalId }));
          }
        }),
      };
    }),
  );

const DnsRecordProvider = () =>
  Provider.effect(
    DnsRecord,
    Effect.gen(function* () {
      const { accountId } = yield* (yield* CloudflareEnvironment);
      const get = yield* Dns.getRecord;
      const create = yield* Dns.createRecord;
      const update = yield* Dns.updateRecord;
      const remove = yield* Dns.deleteRecord;

      const resolveZoneId = (hostname: string) =>
        Effect.gen(function* () {
          const all = yield* runItems(Zones.listZones.items({}));
          const zone = all
            .filter((candidate) => candidate.account.id === accountId)
            .filter(
              (candidate) => hostname === candidate.name || hostname.endsWith(`.${candidate.name}`),
            )
            .sort((left, right) => right.name.length - left.name.length)[0];
          return zone
            ? zone.id
            : yield* Effect.fail(new Error(`Cloudflare zone not found for ${hostname}`));
        });

      const find = (zoneId: string, hostname: string) =>
        Dns.listRecords
          .items({
            zoneId,
            name: { exact: hostname },
            type: "CNAME",
          })
          .pipe(
            Stream.filter((record) => record.name === hostname),
            Stream.runHead,
            Effect.map(Option.getOrUndefined),
          );

      return {
        stables: ["recordId", "zoneId"],
        read: Effect.fn(function* ({ olds, output }) {
          const zoneId = output?.zoneId ?? (yield* resolveZoneId(olds.hostname));
          const observed = output
            ? yield* get({ zoneId, dnsRecordId: output.recordId })
            : yield* find(zoneId, olds.hostname);
          return observed
            ? {
                recordId: observed.id,
                zoneId,
                hostname: observed.name,
                content: observed.content ?? "",
                proxied: observed.proxied ?? false,
              }
            : undefined;
        }),
        reconcile: Effect.fn(function* ({ news, output }) {
          const zoneId = yield* resolveZoneId(news.hostname);
          if (output && output.zoneId !== zoneId) {
            return yield* Effect.fail(
              new Error(
                `DNS record ${output.recordId} cannot move between zones (${output.zoneId} != ${zoneId}); replace it intentionally`,
              ),
            );
          }
          const observed = output
            ? yield* get({ zoneId, dnsRecordId: output.recordId })
            : yield* find(zoneId, news.hostname);
          const record = observed
            ? yield* update({
                zoneId,
                dnsRecordId: observed.id,
                name: news.hostname,
                type: "CNAME",
                ttl: 1,
                content: news.content,
                proxied: news.proxied ?? true,
                comment: news.comment,
              })
            : yield* create({
                zoneId,
                name: news.hostname,
                type: "CNAME",
                ttl: 1,
                content: news.content,
                proxied: news.proxied ?? true,
                comment: news.comment,
              });
          return {
            recordId: record.id,
            zoneId,
            hostname: record.name,
            content: record.content ?? "",
            proxied: record.proxied ?? false,
          };
        }),
        delete: Effect.fn(function* ({ output }) {
          const observed = yield* find(output.zoneId, output.hostname);
          if (observed?.id === output.recordId) {
            yield* remove({
              zoneId: output.zoneId,
              dnsRecordId: output.recordId,
            });
          }
        }),
      };
    }),
  );

export const McpAccessPolicyProvider = () =>
  Provider.effect(
    McpAccessPolicy,
    Effect.gen(function* () {
      const { accountId } = yield* (yield* CloudflareEnvironment);
      const controlCredentials = yield* Credentials;
      const authenticated = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
        effect.pipe(
          Effect.provideService(Credentials, controlCredentials),
          Effect.provideService(ResponseValidation, "strict"),
        );
      const create = yield* ZeroTrust.createAccessApplicationPolicyForAccount;
      const update = yield* ZeroTrust.updateAccessApplicationPolicyForAccount;
      const remove = yield* ZeroTrust.deleteAccessApplicationPolicyForAccount;

      const findApplication = Effect.fn("McpAccessPolicy.findApplication")(function* (
        application: McpAccessPolicyProps["application"],
      ) {
        const all = yield* runItems(ZeroTrust.listAccessApplicationsForAccount.items({ accountId })).pipe(authenticated);
        const matches = all.filter((candidate) => {
          if (candidate.type !== application.type || !candidate.id) return false;
          if (application.type === "mcp_portal") {
            return "domain" in candidate && candidate.domain === application.hostname;
          }
          return "destinations" in candidate && candidate.destinations?.some(
            (destination) => "mcpServerId" in destination && destination.mcpServerId === application.serverId,
          );
        });
        if (matches.length > 1) {
          return yield* new McpIdentityAmbiguous({ resource: "application", name: application.type, count: matches.length });
        }
        const applicationId = matches[0]?.id;
        if (!applicationId) return yield* new McpApplicationNotReady({ applicationType: application.type });
        return applicationId;
      });

      const listPolicies = (applicationId: string) =>
        runItems(ZeroTrust.listAccessApplicationPoliciesForAccount.items({ accountId, appId: applicationId })).pipe(authenticated);

      const findPolicy = Effect.fn("McpAccessPolicy.findPolicy")(function* (
        applicationId: string, name: string, policyId?: string,
      ) {
        const policies = yield* listPolicies(applicationId);
        const recorded = policyId ? policies.filter((candidate) => candidate.id === policyId) : [];
        const matches = recorded.length > 0 ? recorded : policies.filter(
          (candidate) => candidate.name === name && candidate.decision === "allow",
        );
        if (matches.length > 1) {
          return yield* new McpIdentityAmbiguous({ resource: "policy", name, count: matches.length });
        }
        return matches[0] ? yield* decodePolicyIdentity(matches[0]) : undefined;
      });


      const desired = (news: McpAccessPolicyProps) => ({
        name: news.name,
        decision: "allow" as const,
        include: [{ email: { email: news.email } }],
        exclude: [],
        require: [],
        precedence: 1,
        sessionDuration: "24h",
      });

      return {
        stables: ["applicationId", "policyId"],
        read: Effect.fn(function* ({ olds, output }) {
          // Missing attributes mean unknown identity, not remote absence. Only
          // concrete selectors can be probed; stripped historical parent
          // selectors remain unknown until Apply resolves desired inputs.
          if (!output && (!isIdentity(olds?.name) || !isApplicationSelector(olds?.application))) return undefined;
          const applicationId = output?.applicationId ?? (yield* findApplication(olds.application).pipe(
            Effect.catchTag("McpApplicationNotReady", () => Effect.succeed(undefined)),
          ));
          if (!applicationId) return undefined;
          const policy = yield* findPolicy(applicationId, olds.name, output?.policyId);
          return policy ? { applicationId, policyId: policy.id } : undefined;
        }),
        reconcile: Effect.fn(function* ({ news, output }) {
          // Only application materialization is eventually consistent. Other
          // API errors and cancellation must propagate, not become absence.
          const applicationId = yield* findApplication(news.application).pipe(
            Effect.retry({
              schedule: Schedule.exponential("250 millis"), times: 8,
              while: (error) => error._tag === "McpApplicationNotReady",
            }),
          );
          if (output && output.applicationId !== applicationId) {
            return yield* new McpApplicationIdentityChanged({
              applicationId: output.applicationId, resolvedApplicationId: applicationId,
            });
          }
          // Saved IDs are authoritative. Without one, discovery is confined
          // to exact name AND decision in the resolved application.
          const observedIdentity = yield* findPolicy(applicationId, news.name, output?.policyId);
          const policy = observedIdentity
            ? yield* authenticated(update({ accountId, appId: applicationId, policyId: observedIdentity.id, ...desired(news) }))
            : yield* authenticated(create({ accountId, appId: applicationId, ...desired(news) }));
          const identity = yield* decodePolicyIdentity(policy);
          return { applicationId, policyId: identity.id };
        }),
        delete: Effect.fn(function* ({ output }) {
          const policies = yield* listPolicies(output.applicationId);
          if (policies.some((policy) => policy.id === output.policyId)) {
            yield* authenticated(remove({ accountId, appId: output.applicationId, policyId: output.policyId }));
          }
        }),
      };
    }),
  );

/** DNS remains on the stack's ordinary Cloudflare OAuth credentials. */
export const dnsProviders = () => DnsRecordProvider();

/**
 * The MCP AI-controls endpoints currently require an API token even when the
 * surrounding Alchemy stack is authenticated with OAuth. Keeping these
 * providers separate lets the composition root inject that narrower token
 * without granting it authority over DNS or the existing R2 cache.
 */
export const controlProviders = () =>
  Layer.mergeAll(McpServerProvider(), McpPortalProvider(), McpAccessPolicyProvider());
