import { Credentials, formatHeaders } from "@distilled.cloud/cloudflare/Credentials";
import { CloudflareEnvironment } from "alchemy/Cloudflare";
import * as Provider from "alchemy/Provider";
import { Resource, type Resource as ResourceType } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Schema from "effect/Schema";
import { FetchHttpClient, HttpClient, HttpClientRequest, HttpClientResponse } from "effect/http";

/**
 * Alchemy beta.80 has native Access resources, but their type/attributes differ
 * from this established state owner. Keep the compatibility identity until an
 * explicit state migration can preserve application and policy IDs without
 * replacement or deletion. Service tokens remain externally owned.
 */
export type SelfHostedApplicationProps = {
  name: string;
  hostname: string;
  sessionDuration: string;
} & (
  | { mode: "email"; email: string; serviceTokenId?: never }
  | { mode: "service-auth"; serviceTokenId: string; email?: never }
);

export type SelfHostedApplication = ResourceType<
  "Homelab.Cloudflare.SelfHostedAccessApplication",
  SelfHostedApplicationProps,
  { applicationId: string; policyId: string; hostname: string }
>;
export const SelfHostedApplication = Resource<SelfHostedApplication>(
  "Homelab.Cloudflare.SelfHostedAccessApplication",
);

const Application = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  domain: Schema.String,
  type: Schema.String,
});
const Policy = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  decision: Schema.String,
  include: Schema.Array(Schema.Unknown),
  exclude: Schema.optional(Schema.Array(Schema.Unknown)),
  require: Schema.optional(Schema.Array(Schema.Unknown)),
});
const Envelope = Schema.Struct({
  success: Schema.Boolean,
  result: Schema.Unknown,
  result_info: Schema.optional(Schema.Unknown),
});
const decodeApplication = Schema.decodeUnknownEffect(Application);
const decodeApplications = Schema.decodeUnknownEffect(Schema.Array(Application));
const decodePolicy = Schema.decodeUnknownEffect(Policy);
const decodePolicies = Schema.decodeUnknownEffect(Schema.Array(Policy));
export const ServiceTokenId = Schema.String.check(Schema.isUUID());
const decodeServiceTokenId = Schema.decodeEffect(ServiceTokenId);
const hasApplicationLocator = Schema.is(Schema.Struct({ hostname: Schema.NonEmptyString, name: Schema.NonEmptyString }));

export class AccessRequestError extends Schema.TaggedError<AccessRequestError>()("AccessRequestError", {
  path: Schema.String,
  message: Schema.String,
}) {}
export class UnexpectedAccessPolicies extends Schema.TaggedError<UnexpectedAccessPolicies>()("UnexpectedAccessPolicies", {
  applicationId: Schema.String,
  policyIds: Schema.Array(Schema.String),
}) {}
export class AmbiguousAccessIdentity extends Schema.TaggedError<AmbiguousAccessIdentity>()("AmbiguousAccessIdentity", {
  kind: Schema.Literals(["application", "policy"]),
  ids: Schema.Array(Schema.String),
}) {}

const decodeListEnvelope = Schema.decodeUnknownEffect(Schema.Struct({
  result: Schema.Array(Schema.Unknown),
  result_info: Schema.Struct({
    count: Schema.Int,
    page: Schema.Literal(1),
    total_count: Schema.Int,
  }),
}));

/** A partial or unverifiable list cannot establish application/policy ownership. */
export const decodeCompleteAccessList = Effect.fn("Access.decodeCompleteAccessList")(function*(
  input: unknown, path: string,
) {
  const envelope = yield* decodeListEnvelope(input).pipe(
    Effect.mapError(() => new AccessRequestError({
      path, message: "Access list completeness metadata is missing or invalid",
    })),
  );
  if (envelope.result_info.count !== envelope.result.length ||
      envelope.result_info.total_count !== envelope.result.length) {
    return yield* new AccessRequestError({ path, message: "Access list is incomplete; operator review required" });
  }
  return envelope.result;
});

const policyName = (props: SelfHostedApplicationProps) =>
  `${props.name}: ${props.mode === "service-auth" ? "service auth" : "operator"}`;
const desiredPolicy = (props: SelfHostedApplicationProps) => ({
  name: policyName(props),
  decision: props.mode === "service-auth" ? "non_identity" : "allow",
  include: props.mode === "service-auth"
    ? [{ service_token: { token_id: props.serviceTokenId } }]
    : [{ email: { email: props.email } }],
  exclude: [],
  require: [],
  precedence: 1,
  session_duration: props.sessionDuration,
});

const matchesServicePolicy = (policy: typeof Policy.Type, props: SelfHostedApplicationProps) => {
  const desired = desiredPolicy(props);
  return policy.decision === desired.decision &&
    JSON.stringify(policy.include) === JSON.stringify(desired.include) &&
    (policy.exclude?.length ?? 0) === 0 && (policy.require?.length ?? 0) === 0;
};

export const SelfHostedApplicationProvider = () => Provider.effect(
  SelfHostedApplication,
  Effect.gen(function* () {
    const { accountId } = yield* (yield* CloudflareEnvironment);
    const controlCredentials = yield* Credentials;
    const client = yield* HttpClient.HttpClient;
    const request = Effect.fn("Access.request")(function*(
      path: string,
      method: "GET" | "POST" | "PUT" | "DELETE" = "GET",
      body?: unknown,
      completeList = false,
    ) {
      const credentials = yield* controlCredentials;
      const base = HttpClientRequest.make(method)(`${credentials.apiBaseUrl}/accounts/${accountId}${path}`, {
        headers: formatHeaders(credentials),
      });
      const req = body === undefined ? base : yield* HttpClientRequest.bodyJson(base, body);
      const response = yield* client.execute(req);
      const envelope = yield* HttpClientResponse.schemaBodyJson(Envelope)(response);
      if (response.status < 200 || response.status >= 300 || !envelope.success) {
        return yield* new AccessRequestError({ path, message: `Cloudflare Access API returned ${response.status}` });
      }
      // List metadata is required only for list responses, never mutations.
      return completeList ? yield* decodeCompleteAccessList(envelope, path) : envelope.result;
    });
    const listApplications = Effect.fn("Access.listApplications")(function*() {
      return yield* decodeApplications(yield* request("/access/apps", "GET", undefined, true));
    });
    const findApplication = Effect.fn("Access.findApplication")(function*(id: string | undefined, hostname: string) {
      const applications = yield* listApplications();
      const identified = id === undefined ? [] : applications.filter((app) => app.type === "self_hosted" && app.id === id);
      const matches = identified.length === 0
        ? applications.filter((app) => app.type === "self_hosted" && app.domain === hostname)
        : identified;
      if (matches.length > 1) {
        return yield* new AmbiguousAccessIdentity({ kind: "application", ids: matches.map((app) => app.id) });
      }
      return matches[0];
    });
    const listPolicies = Effect.fn("Access.listPolicies")(function*(id: string) {
      return yield* decodePolicies(yield* request(`/access/apps/${id}/policies`, "GET", undefined, true));
    });
    const selectPolicy = Effect.fn("Access.selectPolicy")(function*(
      applicationId: string, props: SelfHostedApplicationProps, id?: string,
    ) {
      const policies = yield* listPolicies(applicationId);
      const identified = id === undefined ? [] : policies.filter((policy) => policy.id === id);
      const matches = identified.length === 0
        ? policies.filter((policy) => policy.name === policyName(props) && policy.decision === desiredPolicy(props).decision)
        : identified;
      if (matches.length > 1) {
        return yield* new AmbiguousAccessIdentity({ kind: "policy", ids: matches.map((policy) => policy.id) });
      }
      const selected = matches[0];
      if (props.mode === "service-auth" && policies.some((policy) => policy.id !== selected?.id)) {
        return yield* new UnexpectedAccessPolicies({ applicationId, policyIds: policies.map((policy) => policy.id) });
      }
      return selected;
    });
    const applicationBody = (props: SelfHostedApplicationProps) => ({
      name: props.name, domain: props.hostname, type: "self_hosted",
      session_duration: props.sessionDuration, app_launcher_visible: false,
      http_only_cookie_attribute: true,
    });
    return {
      stables: ["applicationId", "policyId"],
      read: Effect.fn(function*({ olds, output }) {
        if (!output && !hasApplicationLocator(olds)) return undefined;
        const app = yield* findApplication(output?.applicationId, olds.hostname);
        if (!app) return undefined;
        const policy = yield* selectPolicy(app.id, olds, output?.policyId);
        if (policy && olds.mode === "service-auth" && !matchesServicePolicy(policy, olds)) return undefined;
        return policy ? { applicationId: app.id, policyId: policy.id, hostname: app.domain } : undefined;
      }),
      reconcile: Effect.fn(function*({ news, output }) {
        if (news.mode === "service-auth") yield* decodeServiceTokenId(news.serviceTokenId);
        const observed = yield* findApplication(output?.applicationId, news.hostname);
        // Reject unmanaged policies before changing an existing application.
        const observedPolicy = observed ? yield* selectPolicy(observed.id, news, output?.policyId) : undefined;
        const app = yield* decodeApplication(yield* request(
          observed ? `/access/apps/${observed.id}` : "/access/apps",
          observed ? "PUT" : "POST", applicationBody(news),
        ));
        if (!observed) yield* selectPolicy(app.id, news);
        const policy = yield* decodePolicy(yield* request(
          `/access/apps/${app.id}/policies${observedPolicy ? `/${observedPolicy.id}` : ""}`,
          observedPolicy ? "PUT" : "POST", desiredPolicy(news),
        ));
        // Recheck exclusivity before releasing DNS's dependency on this resource.
        const confirmed = yield* selectPolicy(app.id, news, policy.id);
        if (news.mode === "service-auth" && (!confirmed || !matchesServicePolicy(confirmed, news))) {
          return yield* new AccessRequestError({
            path: `/access/apps/${app.id}/policies`,
            message: "Gateway must have exactly one matching service-auth policy",
          });
        }
        return { applicationId: app.id, policyId: policy.id, hostname: app.domain };
      }),
      delete: Effect.fn(function*({ olds, output }) {
        const app = yield* findApplication(output.applicationId, olds.hostname);
        if (app?.id === output.applicationId) {
          // Do not delete an application containing operator-added policies.
          yield* selectPolicy(app.id, olds, output.policyId);
          yield* request(`/access/apps/${app.id}`, "DELETE");
        }
      }),
    };
  }),
);

export const providers = () => SelfHostedApplicationProvider().pipe(Layer.provide(FetchHttpClient.layer));
