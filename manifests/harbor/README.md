# Harbor manifests

| File | Purpose |
|------|---------|
| `harbor.yml.example` | Scrubbed copy of the `harbor.yml` used in the lab. Copy to `/opt/harbor/harbor.yml`, replace the placeholders, then run `./install.sh`. |
| `generate-cert.sh` | Generates the self-signed CA/leaf certificate with `IP:192.168.1.5` in the SAN. Called by `scripts/01-install-harbor.sh`. |

## Runtime layout on the master node

```
/opt/harbor/                 installer, harbor.yml, docker-compose.yml
/etc/harbor/certs/harbor.crt TLS certificate (also distributed as CA to all nodes)
/etc/harbor/certs/harbor.key TLS private key (never leaves the master)
/data/harbor/                registry blobs, PostgreSQL, Redis, job logs
```

Containers started by `docker compose` in `/opt/harbor`:
`harbor-core`, `harbor-db`, `harbor-jobservice`, `harbor-portal`, `harbor-log`,
`registry`, `registryctl`, `redis`, `nginx` (reverse proxy on 80/443).

## Project and robot account

* Project: `client-demo` (private)
* Robot account: `robot$client-demo+client-demo-robot` with `pull` + `push` on the project
* The robot token is created in the Harbor UI (*Project → Robot Accounts*) and only
  stored in the Kubernetes secret `harbor-registry` and the Docker credential store on
  the build host. It is never written to this repository.
