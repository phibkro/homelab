import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as State from "alchemy/State";
import * as Effect from "effect/Effect";

const DAY = 24 * 60 * 60;

/**
 * Cloudflare infrastructure for the homelab.
 *
 * Provisions the binary cache that replaced cache.garnix.io. The CI pi-build
 * job is the fleet's only native aarch64 builder, so it signs and uploads the
 * Pi system closure here; the workstation substitutes it instead of
 * recompiling linux-rpi under binfmt emulation.
 *
 * The bucket is deliberately PRIVATE — no `domains` entry, so no custom
 * domain and no public hostname. A published Nix cache discloses the exact
 * package set and versions a host runs, and this bucket holds closures for a
 * machine that also serves the entry plane. Readers authenticate with the S3
 * API instead. Omitting public access also avoids the managed bucket-policy
 * step that failed during the occupational-health deploy.
 *
 * Nothing here is bound to a Worker: `nix copy` speaks S3 directly, so the
 * bucket is the whole surface.
 *
 * Operator: `bun alchemy deploy` (needs `alchemy login` once — Cloudflare auth
 * is operator-owned and cannot run headlessly).
 */
export default Alchemy.Stack(
  "Homelab",
  { providers: Cloudflare.providers(), state: State.localState() },
  Effect.gen(function* () {
    const cache = yield* Cloudflare.R2Bucket("NixCache", {
      name: "homelab-nix-cache",

      // Norway. Jurisdiction is left at "default" on purpose: the objects are
      // builds of public open-source packages, and an "eu" jurisdiction moves
      // the S3 endpoint to a different hostname for every client.
      locationHint: "weur",

      lifecycleRules: [
        {
          // Without this the bucket grows without bound: every closure ever
          // built is retained, and nothing else prunes it. Ninety days keeps
          // the kernels a rollback would need while staying inside the free
          // tier. Objects still referenced are simply re-uploaded on the next
          // CI run, so expiry costs a rebuild at worst, never correctness.
          id: "expire-closures",
          enabled: true,
          deleteObjectsTransition: {
            condition: { type: "Age", maxAge: 90 * DAY },
          },
        },
        {
          // An interrupted `nix copy` leaves multipart parts that are billed
          // as storage but are invisible to a bucket listing.
          id: "abort-stale-multipart-uploads",
          enabled: true,
          abortMultipartUploadsTransition: {
            condition: { type: "Age", maxAge: 7 * DAY },
          },
        },
      ],
    });

    // Consumed as GitHub repository variables by .github/workflows/check.yml.
    return {
      bucket: cache.bucketName,
      endpoint: `${cache.accountId}.r2.cloudflarestorage.com`,
    };
  }),
);
