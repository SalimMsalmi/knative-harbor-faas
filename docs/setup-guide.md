# Setup guide

This guide rebuilds the platform from an empty `kubeadm` cluster. Commands assume the lab
addressing used throughout the repository; override the environment variables shown if
yours differs.

| Variable | Default | Meaning |
|---|---|---|
| `HARBOR_HOST` | `192.168.1.5` | IP of the node running Harbor (also the Kourier entry point) |
| `HARBOR_PROJECT` | `client-demo` | Harbor project holding function images |
| `KNATIVE_VERSION` | `1.16.0` | Knative Serving and net-kourier release |

## 0. Prerequisites

- Two Ubuntu 22.04 machines (4 vCPU / 4 GB each is enough) that can reach each other.
- A working Kubernetes 1.28 cluster created with `kubeadm`, with a CNI (Flannel here) and
  containerd.
- Docker Engine and the Compose plugin on the master node (Harbor and image builds).
- `kubectl` configured for cluster-admin on the master node.
- **Swap disabled permanently** on every node. `swapoff -a` alone does not survive a reboot;
  comment the swap line in `/etc/fstab` too, or the kubelet will refuse to start after the
  next restart:

  ```bash
  sudo swapoff -a
  sudo sed -i '/\sswap\s/ s/^/#/' /etc/fstab
  ```

## 1. Install Harbor

On the master node:

```bash
HARBOR_ADMIN_PASSWORD='<choose>' HARBOR_DB_PASSWORD='<choose>' \
  sudo -E scripts/01-install-harbor.sh
```

The script:

1. generates a self-signed certificate with `IP:192.168.1.5` in the SAN
   ([`manifests/harbor/generate-cert.sh`](../manifests/harbor/generate-cert.sh));
2. downloads the Harbor 2.12.1 online installer into `/opt/harbor`;
3. renders `/opt/harbor/harbor.yml` from
   [`harbor.yml.example`](../manifests/harbor/harbor.yml.example);
4. runs `install.sh`, which starts Harbor with Docker Compose.

Verify:

```bash
curl -k https://192.168.1.5/api/v2.0/health      # every component "healthy"
```

> Install into a persistent directory such as `/opt/harbor`, never `/tmp`. The Compose
> project and generated configuration are needed to restart Harbor after a reboot.

## 2. Trust the Harbor certificate on every node

Copy `/etc/harbor/certs/harbor.crt` to each node and run, **on every node including the
master**:

```bash
sudo scripts/02-trust-harbor-ca.sh /etc/harbor/certs/harbor.crt
```

This installs the certificate for containerd (`/etc/containerd/certs.d/192.168.1.5/`), for
Docker if present (`/etc/docker/certs.d/192.168.1.5/`) and into the system trust store, and
makes sure containerd's registry `config_path` points at `certs.d`.

Verify from a worker:

```bash
sudo ctr -n k8s.io images pull --hosts-dir /etc/containerd/certs.d 192.168.1.5/library/does-not-exist:latest
# expected: "not found" or "unauthorized" — NOT an x509 error
```

## 3. Create the project, robot account and pull secret

In the Harbor UI (`https://192.168.1.5`, user `admin`):

1. **Projects → New Project** → `client-demo`, access level private.
2. **client-demo → Robot Accounts → New Robot Account** → name `client-demo-robot`,
   permissions *Repository: Push* and *Pull*. Copy the generated secret; it is shown once.

Log the build host in, and give the cluster the same credential:

```bash
# Single quotes matter: the robot name contains a "$"
docker login 192.168.1.5 -u 'robot$client-demo+client-demo-robot'

ROBOT_TOKEN='<robot secret>' manifests/image-pull-secret.example.sh
```

## 4. Install Knative Serving and Kourier

```bash
scripts/03-install-knative.sh
```

The script applies the upstream release manifests and then three ConfigMap patches:

```bash
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-core.yaml
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.16.0/kourier.yaml

# Kourier as the ingress
kubectl patch configmap/config-network -n knative-serving --type merge \
  -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

# Magic DNS
kubectl patch configmap/config-domain -n knative-serving --type merge \
  -p '{"data":{"192.168.1.5.sslip.io":""}}'

# Do not resolve tags against the self-signed registry from the controller
kubectl patch configmap/config-deployment -n knative-serving --type merge \
  -p '{"data":{"registries-skipping-tag-resolving":"192.168.1.5"}}'
```

Verify, and note the NodePort mapped to port 80:

```bash
kubectl get pods -n knative-serving          # activator, autoscaler, controller, net-kourier-controller, webhook
kubectl get svc kourier -n kourier-system    # 80:<NODEPORT>/TCP
```

The rest of the repository assumes NodePort `32491`; export `KOURIER_NODEPORT` if yours is
different.

## 5. Deploy the first function

```bash
scripts/build-push.sh functions/hello-world first-func
scripts/deploy.sh hello-world
scripts/invoke.sh first-func
```

```json
{"message": "Hello, World!"}
```

Watch it scale to zero and back:

```bash
kubectl get pods -n default -w
# ~90 s after the last request the pod terminates; the next request recreates it
scripts/cold-start-bench.sh first-func 3
```

## 6. Install the portal

```bash
sudo scripts/install-portal.sh
```

This copies `portal/` to `/opt/faas-portal`, installs Flask, and enables the
[`faas-portal`](../manifests/faas-portal.service) systemd unit. Open
`http://192.168.1.5:5000`, paste a handler, and deploy. See [portal.md](portal.md).

## 7. After a reboot

| Component | Comes back automatically? | If not |
|---|---|---|
| kubelet, control plane, Knative | Yes, provided swap is off | `swapon --show` must be empty; `systemctl restart kubelet` |
| Harbor | Yes, containers use a restart policy | `cd /opt/harbor && docker compose up -d` |
| Portal | Yes (systemd) | `systemctl status faas-portal` |
| Functions | Yes — they are at zero anyway | First request triggers a cold start |

Problems are catalogued in [troubleshooting.md](troubleshooting.md).
