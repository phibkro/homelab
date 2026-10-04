import { Credentials, formatHeaders } from "@distilled.cloud/cloudflare/Credentials";
import { CloudflareEnvironment } from "alchemy/Cloudflare";
import * as Provider from "alchemy/Provider";
import { Resource, type Resource as ResourceType } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Schema from "effect/Schema";
import { FetchHttpClient, HttpClient, HttpClientRequest, HttpClientResponse } from "effect/unstable/http";

/**
 * Compatibility resource: Alchemy beta.45 has an Access authentication client,
 * but no self-hosted application/policy resource. Retire this provider when
 * native Cloudflare Access application resources support these policy modes.
 * Service tokens are externally owned; only their UUID is accepted here.
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
  result_info: Schema.optional(Schema.Struct({ total_pages: Schema.optional(Schema.Int) })),
});
const decodeApplication = Schema.decodeUnknownEffect(Application);
const decodeApplications = Schema.decodeUnknownEffect(Schema.Array(Application));
const decodePolicy = Schema.decodeUnknownEffect(Policy);
const decodePolicies = Schema.decodeUnknownEffect(Schema.Array(Policy));
export const ServiceTokenId = Schema.String.check(Schema.isUUID());
const decodeServiceTokenId = Schema.decodeEffect(ServiceTokenId);

export class AccessRequestError extends Schema.TaggedError<AccessRequestError>()("AccessRequestError", {
  path: Schema.String,
  message: Schema.String,
}) {}
export class UnexpectedAccessPolicies extends Schema.TaggedError<UnexpectedAccessPolicies>()("UnexpectedAccessPolicies", {
  applicationId: Schema.String,
  policyIds: Schema.Array(Schema.String),
}) {}

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

const SelfHostedApplicationProvider = () => Provider.effect(
  SelfHostedApplication,
  Effect.gen(function* () {
    const { accountId } = yield* CloudflareEnvironment;
    const controlCredentials = yield* Credentials;
    const client = yield* HttpClient.HttpClient;
    const request = Effect.fn("Access.request")(function*(
      path: string,
      method: "GET" | "POST" | "PUT" | "DELETE" = "GET",
      body?: unknown,
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
      // Never reason about exclusivity from a truncated policy/application list.
      if ((envelope.result_info?.total_pages ?? 1) > 1) {
        return yield* new AccessRequestError({ path, message: "Paginated Access results require operator review" });
      }
      return envelope.result;
    });
    const listApplications = Effect.fn("Access.listApplications")(function*() {
      return yield* decodeApplications(yield* request("/access/apps?per_page=1000"));
    });
    const findApplication = Effect.fn("Access.findApplication")(function*(id: string | undefined, hostname: string) {
      const applications = yield* listApplications();
      return applications.find((app) => app.type === "self_hosted" && (app.id === id || app.domain === hostname));
    });
    const listPolicies = Effect.fn("Access.listPolicies")(function*(id: string) {
      return yield* decodePolicies(yield* request(`/access/apps/${id}/policies?per_page=1000`));
    });
    const selectPolicy = Effect.fn("Access.selectPolicy")(function*(
      applicationId: string, props: SelfHostedApplicationProps, id?: string,
    ) {
      const policies = yield* listPolicies(applicationId);
      const selected = policies.find((policy) => id ? policy.id === id : policy.name === policyName(props));
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
        if (!output?.applicationId || !output.policyId) return undefined;
        const app = yield* findApplication(output.applicationId, olds.hostname);
        if (!app || app.id !== output.applicationId) return undefined;
        const policy = yield* selectPolicy(app.id, olds, output.policyId);
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
).pipe(Layer.provide(FetchHttpClient.layer));

export const providers = () => SelfHostedApplicationProvider();
