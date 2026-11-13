# Troubleshooting

Problems encountered while building and operating this proof of concept, with their cause
and fix. Start with the quick diagnosis, then jump to the matching section.

## Quick diagnosis

```bash
kubectl get ksvc                                   # READY and REASON columns
kubectl describe ksvc <name>                       # conditions of the Service
kubectl get revision -l serving.knative.dev/service=<name>
kubectl describe revision <name>-00001             # why a Revision is not Ready
kubectl get pods -l serving.knative.dev/service=<name>
kubectl describe pod <pod>                         # image pull errors show up in Events
kubectl logs <pod> -c user-container               # the function's own output
curl -k https://192.168.1.5/api/v2.0/health        # Harbor
```

---

## OpenFaaS CE refuses to deploy images from the private registry

**Symptom** — deploying a function whose image is in Harbor is rejected by OpenFaaS
Community Edition with a message that only public images are allowed.

**Cause** — a licensing restriction of the Community Edition, not a configuration error.

**Fix** — none within CE. This is the reason the platform moved to Knative Serving; see
[openfaas-vs-knative.md](openfaas-vs-knative.md).

## Revision fails with an x509 / "certificate signed by unknown authority" error

**Symptom** — `kubectl get ksvc` shows `READY False` with `RevisionMissing` or
`RevisionFailed`, and the Revision status mentions being unable to fetch the image digest
because of an x509 error. No pod is ever created.

**Cause** — before creating a Deployment, the Knative controller resolves the image tag to
a digest by contacting the registry itself. The controller pod does not have the Harbor CA,
even when every node does.

**Fix** — tell Knative not to resolve tags for this registry, then restart the controller:

```bash
kubectl patch configmap/config-deployment -n knative-serving --type merge \
  -p '{"data":{"registries-skipping-tag-resolving":"192.168.1.5"}}'
kubectl rollout restart deployment/controller -n knative-serving
```

## Pod stuck in `ImagePullBackOff` with an x509 error

**Symptom** — the pod exists; its events show `failed to pull image … x509: certificate
signed by unknown authority`.

**Cause** — the node the pod was scheduled on does not trust the Harbor certificate. It is
easy to configure the master and forget the worker.

**Fix** — on **every** node:

```bash
sudo scripts/02-trust-harbor-ca.sh /path/to/harbor.crt
```

Check that `/etc/containerd/certs.d/192.168.1.5/hosts.toml` and `ca.crt` exist and that the
registry `config_path` in `/etc/containerd/config.toml` is not empty:

```bash
grep -n config_path /etc/containerd/config.toml
```

## Pod stuck in `ImagePullBackOff` with `unauthorized` or `401`

**Cause** — the Service has no `imagePullSecrets`, the secret is in another namespace, or
the robot credential is wrong.

**Fix**

```bash
kubectl get secret harbor-registry -n default
kubectl get ksvc <name> -o jsonpath='{.spec.template.spec.imagePullSecrets}'
```

Recreate the secret with [`manifests/image-pull-secret.example.sh`](../manifests/image-pull-secret.example.sh).
A frequent cause is shell expansion of the robot name: `robot$client-demo+client-demo-robot`
contains a `$`, so it must be single-quoted. With double quotes the shell silently turns it
into `robot+client-demo-robot`.

## `docker push` fails with `unauthorized` on the build host

**Cause** — the host is not logged in, or the robot account was recreated and has a new
secret.

**Fix**

```bash
docker login 192.168.1.5 -u 'robot$client-demo+client-demo-robot'
```

## `kourier` Service shows `EXTERNAL-IP <pending>`

**Cause** — the Service is of type `LoadBalancer` and a bare-metal cluster has nothing to
allocate an address.

**Fix** — expected. Use the NodePort and a `Host` header:

```bash
kubectl get svc kourier -n kourier-system      # 80:32491/TCP
curl -H "Host: <name>.default.192.168.1.5.sslip.io" http://192.168.1.5:32491
```

Installing MetalLB would give Kourier a real address; it is on the roadmap.

## Function returns `404` from Envoy

**Cause** — the `Host` header does not match a Knative route. Kourier routes only by host.

**Fix** — the header must be exactly the host part of the URL shown by `kubectl get ksvc`:
`<name>.<namespace>.192.168.1.5.sslip.io`. Calling `http://192.168.1.5:32491` without it
always returns 404.

## Function receives an empty or mangled body

**Symptom** — the handler sees a truncated body when called with `curl -d` and a payload
containing `=` or `&`.

**Cause** — `curl -d` sends `Content-Type: application/x-www-form-urlencoded`, so the
runtime wrapper parses the payload as a form and passes only the first key to the handler.

**Fix** — send an explicit content type for anything that is not a simple string:

```bash
curl -H "Host: …" -H "Content-Type: application/json" --data-raw '{"numbers":[1,2,3]}' http://192.168.1.5:32491
```

## Portal reports "Function deployment timed out"

**Cause** — the Knative Service did not become `Ready` within the portal's 60-second
window. Typical reasons: the first pull of a new image onto a node is slow, the handler
fails at import time, or one of the image-pull problems above.

**Fix** — the deployment is not rolled back, so inspect it directly:

```bash
kubectl get ksvc <name>
kubectl get pods -l serving.knative.dev/service=<name>
kubectl logs -l serving.knative.dev/service=<name> -c user-container
```

A syntax error in the submitted code appears in the container log as a Python traceback.

## Redeployed function still runs the old code

**Cause** — images are tagged `:latest` and the Service template is unchanged, so Knative
does not create a new Revision.

**Fix**

```bash
kubectl delete ksvc <name>      # then deploy again
```

## After a reboot, `kubectl` reports "connection refused" on port 6443

**Symptom** — the API server is down; `systemctl status kubelet` shows it restarting, and
the journal mentions swap.

**Cause** — swap was turned off with `swapoff -a` only. The entry in `/etc/fstab` re-enabled
it at boot, and the kubelet refuses to run with swap on.

**Fix** — on every node:

```bash
sudo swapoff -a
sudo sed -i '/\sswap\s/ s/^/#/' /etc/fstab
sudo systemctl restart kubelet
```

The control plane returns within a minute or two.

## After a reboot, Harbor is down

**Symptom** — `https://192.168.1.5` is unreachable and `docker ps` shows no Harbor
containers; image pulls and portal deploys fail.

**Cause** — Harbor was installed from a temporary directory (`/tmp/harbor`), which was
cleared at boot along with its `docker-compose.yml` and generated configuration. The data
in `/data/harbor` is untouched.

**Fix** — reinstall the *same version* from a persistent directory, pointing at the existing
data volume and certificates; projects, images and robot accounts are preserved:

```bash
cd /opt/harbor            # harbor.yml: same hostname, data_volume and database password as before
sudo ./install.sh
curl -k https://192.168.1.5/api/v2.0/health
```

Do not try to run the `goharbor/prepare` container by hand with custom mounts; use
`install.sh` (or `./prepare` followed by `docker compose up -d`), which mounts the paths the
tool expects.

## Functions are slow on the first request

**Cause** — that is the cold start: the function was at zero replicas.

**Fix** — for latency-sensitive functions keep one replica warm:

```yaml
metadata:
  annotations:
    autoscaling.knative.dev/min-scale: "1"
```
