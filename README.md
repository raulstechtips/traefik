# traefik

Helm chart that installs Traefik and the shared routing resources used by the cluster.

## Purpose

The chart wraps the upstream `traefik` chart `35.2.0` as a dependency. We use it only through values and never fork its templates.
The dependency comes directly from `https://traefik.github.io/charts`.

The wrapper owns:

- The secured `traefik-dashboard` IngressRoute.
- The shared `default-headers`, `strict-referrer`, `oauth-verify`, `oauth-signin`, and `oauth-chain` Middlewares, plus `vpn-ip-acl` when ranges are configured.
- Exact namespace-specific Middleware objects supplied through `additionalMiddlewares`.
- External endpoint definitions. Each `externalServices` entry creates a Service, an optional Endpoints object, optional extra Middlewares, and one IngressRoute.

Everything else (Deployment, Service, ServiceAccount, RBAC, and IngressClass) comes from the upstream chart.
`charts/values.yaml` lists only upstream values that differ from the `35.2.0` defaults and that are not environment-specific.

The chart is published to GHCR. Argo CD installs it with values from `cluster-config` (`apps/dev/traefik.yaml`).

## Before first install

These must already exist:

- The TLS Secrets named by `dashboard.tlsSecretName` and each `externalServices[].tlsSecretName`.
- The `oauth2-proxy` Service in the namespace configured by `middlewares.oauth.signIn.serviceNamespace`.
- The Traefik CRDs. The live Application does not track them, so the replacement Application uses `helm.skipCrds: true`.

## Values reference

| Key | Default | Meaning |
| --- | --- | --- |
| `dashboard.enabled` | `false` | `true` renders `traefik-dashboard`. |
| `dashboard.host` | `""` | Dashboard host. Required when enabled. |
| `dashboard.tlsSecretName` | `""` | Dashboard TLS Secret. Required when enabled. |
| `dashboard.middlewares` | `[]` | Middleware references used by the dashboard route. |
| `middlewares.enabled` | `false` | `true` manages the five shared Middlewares and an optional `vpn-ip-acl`. |
| `middlewares.namespace` | `default` | Namespace for all shared Middlewares. |
| `middlewares.defaultHeaders.contentSecurityPolicy` | `""` | CSP copied from the live middleware used by cluster routes. |
| `middlewares.vpnIpAcl.sourceRange` | `[]` | VPN and internal network CIDRs. An empty list renders no shared `vpn-ip-acl`. |
| `additionalMiddlewares` | `[]` | Exact Middleware objects as `{name, namespace, spec}` entries. |
| `externalServices` | `[]` | External Service, Endpoints, middleware, and route definitions. |
| `externalServices[].endpointIP` | omitted | When set, creates an Endpoints object. When omitted, only the Service and route are created. |
| `externalServices[].extraMiddlewares` | `[]` | Additional Middleware objects owned with that external service. |

Any `traefik.*` key goes straight to the upstream chart.

## Upgrades

1. Set the new dependency version in `charts/Chart.yaml`.
2. Run `/opt/homebrew/bin/helm dependency update charts`.
3. Compare the new defaults with `charts/values.yaml`.
4. Run the local wrapper checks and render-versus-live parity report.
5. Merge, then sync the Application when ready.

## Adoption notes

- The live Argo Application tracks 13 resources and no CRDs. The new Application keeps CRDs outside Argo ownership with `helm.skipCrds: true`.
- Cluster routes normally reference `default/default-headers`, `default/strict-referrer`, and `default/oauth-*`. The wrapper therefore manages the shared set in `default`, not `traefik`.
- The `default/default-headers` live CSP matches the operator's current working copy. The older `traefik/default-headers` CSP does not. Adoption keeps the live `default` policy.
- The live `default/oauth-verify` uses `/oauth2/auth`. The `traefik/oauth-verify` copy and the old manifest omit that path. Adoption keeps the live object used by routes.
- The six Argo-tracked `traefik/*` Middleware objects remain rendered through `additionalMiddlewares` with their exact live specifications. Adoption therefore has no Middleware prune.
- `monitoring/alertmanager-ingress-prod` and `monitoring/prometheus-ingress-prod` still reference `traefik/oauth-chain`. Move both routes to `default/oauth-chain`, verify them, and then delete the six legacy `additionalMiddlewares` entries from `apps/dev/traefik.yaml`.
- `vpn-ip-acl` remains only in `traefik`. The shared `default` set has an empty `middlewares.vpnIpAcl.sourceRange`, so adoption does not create an unused `default/vpn-ip-acl`.
- The external resources are currently hand-applied and untracked. Adoption adds them to this chart because the operator's working copy already shows that intent.
- `llm-service` has no live Endpoints object. Its entry deliberately omits `endpointIP`, so adoption does not create one.
- Kubernetes `1.30` renders the live-compatible `v1/Endpoints` objects. Kubernetes `1.33` and later render `discovery.k8s.io/v1` EndpointSlices because Endpoints is deprecated there.
- Wrapper-owned objects gain standard Helm labels. Their functional specifications remain equal to the live objects unless a namespace move is listed above.
- The old values used unsupported keys for the log level, access-log default modes, web redirect, and HTTP/3 advertised port. Those settings are absent from the live Deployment, so the wrapper does not carry them forward.
