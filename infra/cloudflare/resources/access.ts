import { Credentials, formatHeaders } from "@distilled.cloud/cloudflare/Credentials";
import { CloudflareEnvironment } from "alchemy/Cloudflare";
import * as Provider from "alchemy/Provider";
import { Resource, type Resource as ResourceType } from "alchemy/Resource";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

/**
 * Compatibility resource for self-hosted Access applications.
 *
 * Alchemy beta.45 does not expose the current Access application resource, so
 * this provider stays deliberately narrow: one exact hostname, one exact email
 * allow policy, and stable remote IDs. Retire it for Alchemy's native
 * Cloudflare.Access.Application once this stack upgrades.
 */

export interface SelfHostedApplicationProps {
  name: string;
  hostname: string;
  email: string;
  sessionDuration: string;
}

export type SelfHostedApplication = ResourceType<
  "Homelab.Cloudflare.SelfHostedAccessApplication",
  SelfHostedApplicationProps,
  {
    applicationId: string;
    policyId: string;
    hostname: string;
  }
>;

export const SelfHostedApplication = Resource<SelfHostedApplication>(
  "Homelab.Cloudflare.SelfHostedAccessApplication",
);

type AccessApplication = {
  id: string;
  name: string;
  domain: string;
  type: string;
};

type AccessPolicy = {
  id: string;
  name: string;
  decision: string;
  include: unknown[];
};

const SelfHostedApplicationProvider = () =>
  Provider.effect(
    SelfHostedApplication,
    Effect.gen(function* () {
      const { accountId } = yield* CloudflareEnvironment;
      const controlCredentials = yield* Credentials;

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
            catch: (cause) => new Error("Cloudflare Access application request failed", { cause }),
          });
        });

      const listApplications = () => request<AccessApplication[]>("/access/apps");
      const findApplication = (applicationId: string | undefined, hostname: string) =>
        listApplications().pipe(
          Effect.map((applications) =>
            applications.find(
              (application) =>
                application.type === "self_hosted" &&
                (application.id === applicationId || application.domain === hostname),
            ),
          ),
        );
      const listPolicies = (applicationId: string) =>
        request<AccessPolicy[]>(`/access/apps/${applicationId}/policies`);

      const desiredApplication = (news: SelfHostedApplicationProps) => ({
        name: news.name,
        domain: news.hostname,
        type: "self_hosted",
        session_duration: news.sessionDuration,
        app_launcher_visible: false,
        http_only_cookie_attribute: true,
      });
      const desiredPolicy = (news: SelfHostedApplicationProps) => ({
        name: `${news.name}: operator`,
        decision: "allow",
        include: [{ email: { email: news.email } }],
        exclude: [],
        require: [],
        precedence: 1,
        session_duration: news.sessionDuration,
      });

      return {
        stables: ["applicationId", "policyId"],
        read: Effect.fn(function* ({ olds, output }) {
          if (!output?.applicationId || !output.policyId) return undefined;
          const application = yield* findApplication(output.applicationId, olds.hostname);
          if (!application || application.id !== output.applicationId) return undefined;
          const policy = (yield* listPolicies(application.id)).find(
            (candidate) => candidate.id === output.policyId,
          );
          return policy
            ? {
                applicationId: application.id,
                policyId: policy.id,
                hostname: application.domain,
              }
            : undefined;
        }),
        reconcile: Effect.fn(function* ({ news, output }) {
          const observed = yield* findApplication(output?.applicationId, news.hostname);
          const application = observed
            ? yield* request<AccessApplication>(`/access/apps/${observed.id}`, {
                method: "PUT",
                body: JSON.stringify(desiredApplication(news)),
              })
            : yield* request<AccessApplication>("/access/apps", {
                method: "POST",
                body: JSON.stringify(desiredApplication(news)),
              });
          const policies = yield* listPolicies(application.id);
          const policyName = `${news.name}: operator`;
          const observedPolicy = policies.find(
            (candidate) => candidate.id === output?.policyId || candidate.name === policyName,
          );
          const policy = observedPolicy
            ? yield* request<AccessPolicy>(
                `/access/apps/${application.id}/policies/${observedPolicy.id}`,
                { method: "PUT", body: JSON.stringify(desiredPolicy(news)) },
              )
            : yield* request<AccessPolicy>(`/access/apps/${application.id}/policies`, {
                method: "POST",
                body: JSON.stringify(desiredPolicy(news)),
              });
          return {
            applicationId: application.id,
            policyId: policy.id,
            hostname: application.domain,
          };
        }),
        delete: Effect.fn(function* ({ olds, output }) {
          const application = yield* findApplication(output.applicationId, olds.hostname);
          if (application?.id === output.applicationId) {
            yield* request<{ id?: string }>(`/access/apps/${application.id}`, {
              method: "DELETE",
            });
          }
        }),
      };
    }),
  );

export const providers = () => SelfHostedApplicationProvider();
