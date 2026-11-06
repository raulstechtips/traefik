# traefik

Helm chart that installs Traefik and the shared routing resources used by the cluster.

## Purpose

The chart wraps the upstream `traefik` chart `35.2.0` as a dependency. We use it only through values and never fork its templates.
The dependency comes directly from `https://traefik.github.io/charts`.

The wrapper owns:

- The secured `traefik-dashboard` IngressRoute.
- The shared `default-headers`, `strict-referrer`, `oauth-verify`, `oauth-signin`, and `oauth-chain` Middlewares.
- External endpoint definitions. Each `externalServices` entry creates a Service, an optional Endpoints object, optional extra Middlewares, and one IngressRoute.

Everything else (Deployment, Service, ServiceAccount, RBAC, and IngressClass) comes from the upstream chart.
`charts/values.yaml` lists only upstream values that differ from the `35.2.0` defaults and that are not environment-specific.

The chart is published to GHCR. Argo CD installs it with values from `cluster-config` (`apps/dev/traefik.yaml`).

## Before first install

These must already exist:

- The Traefik CRDs, only when the Argo CD Application sets `helm.skipCrds: true`. The dev Application sets it because the dev cluster had the CRDs before Argo CD managed Traefik. On a new cluster, leave `skipCrds` unset so that Argo CD installs the CRDs from the chart.
- The TLS Secrets named by `dashboard.tlsSecretName` and each `externalServices[].tlsSecretName`.

Runtime dependency (not an install prerequisite): `oauth-signin` and `oauth-verify` call the `oauth2-proxy` Service in `middlewares.oauth.signIn.serviceNamespace`. Without it, Traefik installs and runs, but the routes that use `oauth-chain` (the dashboard and Longhorn) do not work until oauth2-proxy is ready. Traefik picks up the Service automatically when it appears.

## Values reference

| Key | Default | Meaning |
| --- | --- | --- |
| `dashboard.enabled` | `false` | `true` renders `traefik-dashboard`. |
| `dashboard.host` | `""` | Dashboard host. Required when enabled. |
| `dashboard.tlsSecretName` | `""` | Dashboard TLS Secret. Required when enabled. |
| `dashboard.middlewares` | `[]` | Middleware references used by the dashboard route. |
| `middlewares.enabled` | `false` | `true` manages the five shared Middlewares. |
| `middlewares.namespace` | `default` | Namespace for all shared Middlewares. |
| `middlewares.defaultHeaders.contentSecurityPolicy` | `""` | CSP copied from the live middleware used by cluster routes. |
| `externalServices` | `[]` | External Service, Endpoints, middleware, and route definitions. |
| `externalServices[].endpointIP` | omitted | When set, creates an Endpoints object. When omitted, only the Service and route are created. |
| `externalServices[].middlewares` | required | The ordered Middleware list of the route. An item with only `name` (and optional `namespace`) is a reference. An item with `spec` also creates that Middleware in the entry namespace (`namespace` must then be unset or the same). |

Any `traefik.*` key goes straight to the upstream chart.

## Weekly Cloudflare IP ranges

Traefik trusts the `X-Forwarded-*` headers on `websecure` only from the Cloudflare edge (`traefik.ports.websecure.forwardedHeaders.trustedIPs`). This is an entrypoint setting, so a Middleware cannot hold it.

The `cloudflare-ips` GitHub Actions workflow (`.github/workflows/cloudflare-ips.yaml`, script `scripts/cloudflare-ips.sh`) runs each Monday:

1. It reads `https://api.cloudflare.com/client/v4/ips`.
2. If the response has no valid IPv4 or IPv6 list, the job fails and changes nothing.
3. If the list is the same as `trustedIPs`, the job stops.
4. If the list is different, the job replaces only the list lines, pushes a `bugfix/DEVSECOPS-60-cloudflare-ip-ranges-<date>` branch and opens a PR. Jenkins builds the branch from the push webhook.

A new list changes the Traefik container arguments. After you merge and sync, the Traefik pods restart one at a time.

To test without changes, start the workflow manually with `dry_run` set. Offline test: `IPS_FILE=<json> DRY_RUN=1 scripts/cloudflare-ips.sh`.

One-time repository setting: **Settings > Actions > General > Workflow permissions > Allow GitHub Actions to create and approve pull requests**.

## Upgrades

1. Set the new dependency version in `charts/Chart.yaml`.
2. Run `/opt/homebrew/bin/helm dependency update charts`.
3. Compare the new defaults with `charts/values.yaml`.
4. Read the upstream release notes for CRD changes. With `helm.skipCrds: true` (dev), Argo CD does not upgrade the CRDs, so apply the new CRDs from the official Traefik instructions before you sync.
5. Run the local wrapper checks and render-versus-live parity report.
6. Merge, then sync the Application when ready.

## Adoption notes

- The live Argo Application tracks 13 resources and no CRDs. The new Application keeps CRDs outside Argo ownership with `helm.skipCrds: true`.
- Cluster routes normally reference `default/default-headers`, `default/strict-referrer`, and `default/oauth-*`. The wrapper therefore manages the shared set in `default`, not `traefik`.
- The `default/default-headers` live CSP matches the operator's current working copy. The older `traefik/default-headers` CSP does not. Adoption keeps the live `default` policy.
- The live `default/oauth-verify` uses `/oauth2/auth`. The `traefik/oauth-verify` copy and the old manifest omit that path. Adoption keeps the live object used by routes.
- The old Application tracks six `traefik/*` Middleware copies (`default-headers`, `strict-referrer`, `oauth-verify`, `oauth-signin`, `oauth-chain`, `vpn-ip-acl`). No route uses them (checked 2026-11-06), so the wrapper does not render them. On the first sync, Argo CD shows these six objects as requiring pruning. Prune them.
- The chart has no `vpn-ip-acl`. oauth2-proxy replaced it. A route that needs an IP limit gets its own `ipAllowList` (inline in `externalServices[].middlewares`, or in the app chart).
- The external resources are currently hand-applied and untracked. Adoption adds them to this chart because the operator's working copy already shows that intent.
- The hand-applied `default/llm-ingress-prod` IngressRoute and `default/llm-service` Service are not in this chart (no longer used). Delete them by hand after the move.
- Kubernetes `1.30` renders the live-compatible `v1/Endpoints` objects. Kubernetes `1.33` and later render `discovery.k8s.io/v1` EndpointSlices because Endpoints is deprecated there.
- Wrapper-owned objects gain standard Helm labels. Their functional specifications remain equal to the live objects unless a namespace move is listed above.
- The old values used unsupported keys for the log level, access-log default modes, web redirect, and HTTP/3 advertised port. Those settings are absent from the live Deployment, so the wrapper does not carry them forward.
