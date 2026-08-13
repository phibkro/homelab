import * as Dns from "@distilled.cloud/cloudflare/dns";
import { Credentials, formatHeaders } from "@distilled.cloud/cloudflare/Credentials";
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
import * as Stream from "effect/Stream";

/*
 * Small Alchemy v2 resources for Cloudflare's 2026 MCP Portal API.
 *
 * Alchemy beta.45 does not yet expose MCP Portal or DNS Record resources, but
 * its Apache-2.0 @distilled.cloud/cloudflare dependency already ships the
 * generated, typed API operations. These providers deliberately stay thin:
 * observe the exact stable ID, create or update it, and delete only the ID
 * recorded in Alchemy state. Retire them when upstream Alchemy grows native
 * resources rather than letting this compatibility seam define new semantics.
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

const McpServerProvider = () =>
  Provider.effect(
    McpServer,
    Effect.gen(function* () {
      const { accountId } = yield* CloudflareEnvironment;
      const controlCredentials = yield* Credentials;
      const authenticated = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
        effect.pipe(Effect.provideService(Credentials, controlCredentials));
      const create = yield* ZeroTrust.createAccessAiControlMcpServer;
      const update = yield* ZeroTrust.updateAccessAiControlMcpServer;
      const remove = yield* ZeroTrust.deleteAccessAiControlMcpServer;
      const sync = yield* ZeroTrust.syncAccessAiControlMcpServer;

      const find = (serverId: string) =>
        ZeroTrust.listAccessAiControlMcpServers.items({ accountId, search: serverId }).pipe(
          Stream.filter((server) => server.id === serverId),
          Stream.runHead,
          Effect.map(Option.getOrUndefined),
          authenticated,
        );

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
          const observed = yield* find(output?.serverId ?? olds.id);
          return observed ? attributes(observed) : undefined;
        }),
        reconcile: Effect.fn(function* ({ news, output }) {
          const observed = yield* find(output?.serverId ?? news.id);
          let reconciled: {
            id: string;
            name: string;
            hostname: string;
            status?: string | null;
          };
          if (!observed) {
            reconciled = yield* authenticated(
              create({
                accountId,
                id: news.id,
                name: news.name,
                hostname: news.url,
                authType: "bearer",
                authCredentials: Redacted.value(news.bearerToken),
                description: news.description,
              }),
            );
          } else if (observed.hostname !== news.url) {
            return yield* Effect.fail(
              new Error(
                `MCP server ${news.id} URL is immutable (${observed.hostname} != ${news.url}); replace the resource intentionally`,
              ),
            );
          } else {
            reconciled = yield* authenticated(
              update({
                accountId,
                id: observed.id,
                name: news.name,
                description: news.description,
                authCredentials: Redacted.value(news.bearerToken),
              }),
            );
          }
          const synchronized = yield* authenticated(sync({ accountId, id: reconciled.id }));
          if (synchronized.status === "error" || synchronized.error) {
            return yield* Effect.fail(
              new Error(
                `MCP server ${reconciled.id} capability sync failed: ${synchronized.error ?? "unknown error"}`,
              ),
            );
          }
          return attributes(reconciled);
        }),
        delete: Effect.fn(function* ({ output }) {
          const observed = yield* find(output.serverId);
          if (observed) {
            yield* authenticated(remove({ accountId, id: output.serverId }));
          }
        }),
      };
    }),
  );

const McpPortalProvider = () =>
  Provider.effect(
    McpPortal,
    Effect.gen(function* () {
      const { accountId } = yield* CloudflareEnvironment;
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
      const { accountId } = yield* CloudflareEnvironment;
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

type AccessApplication = {
  id?: string | null;
  domain: string;
  type: string;
  destinations?: ({ type?: string | null; mcpServerId?: string | null } | unknown)[] | null;
};

type AccessPolicy = {
  id: string;
  name: string;
  decision: string;
  include: unknown[];
};

const McpAccessPolicyProvider = () =>
  Provider.effect(
    McpAccessPolicy,
    Effect.gen(function* () {
      const { accountId } = yield* CloudflareEnvironment;
      const controlCredentials = yield* Credentials;
      const applications = ZeroTrust.listAccessApplicationsForAccount;

      const request = <A>(path: string, init?: RequestInit) =>
        Effect.gen(function* () {
          const credentials = yield* controlCredentials;
          return yield* Effect.tryPromise({
            try: async () => {
              const response = await fetch(
                `${credentials.apiBaseUrl}/accounts/${accountId}${path}`,
                {
                  ...init,
                  headers: {
                    ...formatHeaders(credentials),
                    "content-type": "application/json",
                    ...init?.headers,
                  },
                },
              );
              const body = (await response.json()) as {
                success: boolean;
                errors?: { message?: string }[];
                result: A;
              };
              if (!response.ok || !body.success) {
                throw new Error(
                  body.errors?.map((error) => error.message).join(", ") ||
                    `Cloudflare Access API returned ${response.status}`,
                );
              }
              return body.result;
            },
            catch: (cause) => new Error(`Cloudflare Access policy request failed`, { cause }),
          });
        });

      const findApplication = (application: McpAccessPolicyProps["application"]) =>
        Effect.gen(function* () {
          const all = (yield* runItems(applications.items({ accountId })).pipe(
            Effect.provideService(Credentials, controlCredentials),
          )) as readonly AccessApplication[];
          const match = all.find((candidate) => {
            if (candidate.type !== application.type || !candidate.id) return false;
            if (application.type === "mcp_portal") {
              return candidate.domain === application.hostname;
            }
            return candidate.destinations?.some(
              (destination) =>
                typeof destination === "object" &&
                destination !== null &&
                "mcpServerId" in destination &&
                destination.mcpServerId === application.serverId,
            );
          });
          return match?.id
            ? match.id
            : yield* Effect.fail(
                new Error(
                  `Cloudflare has not created the ${application.type} Access application yet`,
                ),
              );
        }).pipe(
          // MCP server and portal creation asynchronously materialize their
          // Access applications. Keep the dependency explicit in Alchemy and
          // tolerate the small provider-side propagation window as well.
          Effect.retry({ schedule: Schedule.exponential("250 millis"), times: 8 }),
        );

      const listPolicies = (applicationId: string) =>
        request<AccessPolicy[]>(`/access/apps/${applicationId}/policies`);

      const desired = (news: McpAccessPolicyProps) => ({
        name: news.name,
        decision: "allow",
        include: [{ email: { email: news.email } }],
        exclude: [],
        require: [],
        precedence: 1,
        session_duration: "24h",
      });

      return {
        stables: ["applicationId", "policyId"],
        read: Effect.fn(function* ({ olds, output }) {
          // A prior failed deploy can leave a "creating" state entry without
          // attributes. There is no remote policy to observe in that case;
          // do not spend the full Access-application propagation retry window
          // trying to reconstruct an ID from unresolved dependency props.
          if (!output?.applicationId || !output.policyId) return undefined;
          const policy = (yield* listPolicies(output.applicationId)).find(
            (candidate) => candidate.id === output?.policyId || candidate.name === olds.name,
          );
          return policy ? { applicationId: output.applicationId, policyId: policy.id } : undefined;
        }),
        reconcile: Effect.fn(function* ({ news, output }) {
          const applicationId = yield* findApplication(news.application);
          const policies = yield* listPolicies(applicationId);
          const observed = policies.find(
            (candidate) => candidate.id === output?.policyId || candidate.name === news.name,
          );
          const policy = observed
            ? yield* request<AccessPolicy>(
                `/access/apps/${applicationId}/policies/${observed.id}`,
                { method: "PUT", body: JSON.stringify(desired(news)) },
              )
            : yield* request<AccessPolicy>(`/access/apps/${applicationId}/policies`, {
                method: "POST",
                body: JSON.stringify(desired(news)),
              });
          return { applicationId, policyId: policy.id };
        }),
        delete: Effect.fn(function* ({ output }) {
          const policies = yield* listPolicies(output.applicationId);
          if (policies.some((policy) => policy.id === output.policyId)) {
            yield* request<{ id?: string }>(
              `/access/apps/${output.applicationId}/policies/${output.policyId}`,
              { method: "DELETE" },
            );
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
