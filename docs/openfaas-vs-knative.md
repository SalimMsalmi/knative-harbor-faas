# From OpenFaaS CE to Knative Serving

The proof of concept began on OpenFaaS Community Edition and ended on Knative Serving. This
note records why, and what the migration involved.

## Requirements

1. Images must come from a **private, on-premises registry** (Harbor).
2. Idle functions must **scale to zero**.
3. Everything must be **open source and free to run** on our own hardware.
4. Deploying a function should not require Kubernetes knowledge.

## What happened with OpenFaaS CE

OpenFaaS was the first choice: it has an excellent CLI, language templates and a simple
mental model. The first function, `hello-client`, was scaffolded with
`faas-cli new --lang python3-http`, built and pushed to Harbor.

Deployment then failed. The Community Edition rejected the function because its image was
not public — CE only deploys images from public registries. Private registries are a
feature of the commercial editions, as is scale-to-zero. Two of the four requirements
could therefore not be met without a licence.

## Comparison

Assessment as of this proof of concept:

| | OpenFaaS CE | Knative Serving |
|---|---|---|
| Licence | Community Edition licence with usage limits | Apache-2.0 |
| Private registry images | Not in CE | Yes (`imagePullSecrets`) |
| Scale-to-zero | Not in CE | Built in, on by default |
| Function contract | Any container via the watchdog | Any container that serves HTTP on a port |
| Revisions and traffic splitting | No | Built in |
| Developer tooling | `faas-cli`, template store, UI | `kn` CLI; no build tooling in Serving |
| Footprint | Small (gateway + provider) | Moderate (five control-plane pods + ingress) |
| Ingress | Gateway service | Pluggable (Kourier, Istio, Contour) |

Knative met every requirement except the fourth: Serving deliberately does not build images
or provide a deployment UI. That gap is what the [FaaS Portal](portal.md) fills.

## Migration

The migration was smaller than expected, because both platforms ultimately run a container
that speaks HTTP.

1. **Installed Knative Serving 1.16 and Kourier**, and patched three ConfigMaps
   ([setup guide, step 4](setup-guide.md#4-install-knative-serving-and-kourier)).
2. **Reused the existing image unchanged.** The OpenFaaS `python3-http` image runs
   `of-watchdog` on port 8080, which proxies to the Flask handler. Knative only needs a
   port, so `stack.yaml` was replaced by a short Knative `Service`
   ([`functions/hello-client/service.yaml`](../functions/hello-client/service.yaml)) and the
   same image was deployed.
3. **Solved the self-signed registry issue** that Knative introduces: its controller
   resolves tags to digests and does not trust the Harbor CA
   (`registries-skipping-tag-resolving`, see [troubleshooting](troubleshooting.md)).
4. **Replaced the template toolchain** with a simpler runtime template
   ([`portal/templates/`](../portal/templates)) — a plain Flask wrapper without the
   watchdog — and the portal that builds from it. The handler signature
   `handle(event, context)` was kept, so OpenFaaS-style handlers remain source compatible.

## Result

| Requirement | Status |
|---|---|
| Private Harbor registry | Met — robot account pull secret, TLS verified |
| Scale-to-zero | Met — ~1.6–2.0 s cold start, ~7 ms warm |
| Open source only | Met |
| No Kubernetes knowledge to deploy | Met for the PoC through the portal |

## Trade-offs accepted

- Knative has more moving parts and more concepts (Service, Configuration, Revision, Route).
- Without OpenFaaS templates the platform owns its runtime image; today that means Python only.
- Build tooling is our responsibility, and the current host-Docker approach needs hardening.
