# Functions

Sample functions deployed on the platform. Each directory contains the user-supplied
`handler.py` and the `service.yaml` that was applied to the cluster. The container image
is assembled from `portal/templates/` (Dockerfile + Flask wrapper) and the handler, so a
function author only ever writes `handler.py`.

| Directory | Deployed as | Harbor repository | What it does |
|-----------|-------------|-------------------|--------------|
| `hello-world/` | `first-func` | `client-demo/first-func` | Returns `{"message": "Hello, World!"}` |
| `text-upper/` | `portal-test-upper` | `client-demo/portal-test-upper` | Upper-cases the request body (first function deployed through the portal) |
| `number-stats/` | `tfunction` | `client-demo/tfunction` | `POST {"numbers": [...]}` → count / sum / average / min / max / sorted |
| `db-query/` | `dbconnection` | `client-demo/dbconnection` | `SELECT id, name, value FROM items` on PostgreSQL via `psycopg2` |
| `hello-client/` | `hello-client` | `client-demo/hello-client` | The original function built with the **OpenFaaS `python3-http` template**; runs unchanged on Knative |

All six services (these five plus `psycopg2-test`, a throwaway dependency check) report `READY True`:

```
$ kubectl get ksvc
NAME                URL                                                  LATESTCREATED             LATESTREADY               READY   REASON
dbconnection        http://dbconnection.default.192.168.1.5.sslip.io        dbconnection-00001        dbconnection-00001        True
first-func          http://first-func.default.192.168.1.5.sslip.io          first-func-00001          first-func-00001          True
hello-client        http://hello-client.default.192.168.1.5.sslip.io        hello-client-00001        hello-client-00001        True
portal-test-upper   http://portal-test-upper.default.192.168.1.5.sslip.io   portal-test-upper-00001   portal-test-upper-00001   True
psycopg2-test       http://psycopg2-test.default.192.168.1.5.sslip.io       psycopg2-test-00001       psycopg2-test-00001       True
tfunction           http://tfunction.default.192.168.1.5.sslip.io           tfunction-00001           tfunction-00001           True
```

## Handler contract

```python
def handle(event, context) -> dict:
    ...
```

### `event`

| Attribute | Type | Description |
|-----------|------|-------------|
| `event.body` | `bytes` | Raw request body (`b''` when empty). Decode with `.decode("utf-8")`. |
| `event.headers` | `dict[str, str]` | Request headers (Flask `request.headers` as a dict). |
| `event.method` | `str` | `GET`, `POST`, `PUT`, `DELETE` or `PATCH`. |
| `event.path` | `str` | Request path (always `/` behind Knative's default route). |

### `context`

| Attribute | Type | Description |
|-----------|------|-------------|
| `context.function_name` | `str` | Value of the `FUNCTION_NAME` environment variable, `"unknown"` when unset. |

### Return value

A `dict` with any of the following keys (all optional):

| Key | Type | Default |
|-----|------|---------|
| `statusCode` | `int` | `200` |
| `body` | `str` or JSON-serialisable object | `""` — strings are returned verbatim, other objects are `jsonify`-ed |
| `headers` | `dict` | `{}` |

Returning anything other than a `dict` serialises the value as JSON with status 200.
Unhandled exceptions are caught by the wrapper and returned as
`{"error": "...", "type": "ExceptionName"}` with status 500.

### Minimal example

```python
import json

def handle(event, context):
    text = event.body.decode("utf-8") if isinstance(event.body, bytes) else event.body
    return {
        "statusCode": 200,
        "body": json.dumps({"echo": text, "fn": context.function_name}),
        "headers": {"Content-Type": "application/json"},
    }
```

## Runtime image

`portal/templates/Dockerfile` — `python:3.12-alpine`, `ca-certificates` + `libpq`, non-root
user `app`, dependencies `flask`, `waitress`, `psycopg2-binary`, listens on `:8080`. The
wrapper `index.py` serves `/` for all HTTP methods and calls `handle()`.

Function-specific Python dependencies are not yet supported by the portal (see the roadmap in
the main README); everything in `portal/templates/requirements.txt` is available.

## Deploying a function from the CLI

```bash
# Build the image from a function directory and push it to Harbor
scripts/build-push.sh functions/number-stats tfunction

# Apply the Knative Service and wait until Ready
scripts/deploy.sh number-stats

# Invoke through the Kourier NodePort
scripts/invoke.sh tfunction '{"numbers": [3, 1, 4, 1, 5, 9]}'
```

## Injecting secrets (db-query)

`functions/db-query/handler.py` reads `DB_HOST` and `DB_PASSWORD` from the environment.
These are provided through a Kubernetes secret referenced by the Knative Service:

```bash
DB_PASSWORD='<DB_PASSWORD>' functions/db-query/db-credentials.example.sh
kubectl apply -f functions/db-query/service.yaml
```

```yaml
      containers:
        - image: 192.168.1.5/client-demo/dbconnection:latest
          env:
            - name: DB_HOST
              valueFrom:
                secretKeyRef: { name: db-credentials, key: host }
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef: { name: db-credentials, key: password }
```

Example response:

```json
{"items": [{"id": 1, "name": "apple", "value": 10}, {"id": 2, "name": "banana", "value": 20}, {"id": 3, "name": "cherry", "value": 30}]}
```

## hello-client — OpenFaaS template on Knative

`hello-client/` keeps the original layout generated by `faas-cli new --lang python3-http`:
`Dockerfile` (multi-stage, pulls `ghcr.io/openfaas/of-watchdog:0.11.6`), `index.py`
(Flask + waitress on `:5000`) and `function/` (handler, requirements, tox). The watchdog
listens on `:8080` and proxies to the WSGI server — exactly the port Knative expects — so
the image built for OpenFaaS was deployed to Knative without a single change. This was the
first function to run on the platform and is the one used for the cold-start measurements.
