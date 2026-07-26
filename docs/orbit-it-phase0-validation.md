# Interactive Tools — Phase 0 validation runbook (item 6)

Validates the on-cluster IT infrastructure end-to-end with a **stock IT (Jupyter)**
before Orbit is introduced. Run against an instance deployed from the
`interactive-tools` branch with Interactive Tools enabled.

Example instance below is **gemini** (`galaxy_hostname = gemini.galaxy.useanvil.org`,
zone `us-east4-c`). Substitute for other instances.

Derived values (gemini):

| Thing | Value |
| --- | --- |
| IT proxy host | `interactivetool.gemini.galaxy.useanvil.org` |
| Wildcard | `*.ep.its.interactivetool.gemini.galaxy.useanvil.org` |
| Cloud DNS zone name | `it-gemini-galaxy-useanvil-org` |
| Wildcard TLS secret | `galaxy-it-tls` (namespace `galaxy`) |

## 0. Prerequisites

| Check | State |
| --- | --- |
| VM service account has `roles/dns.admin` | one-time, done for the default compute SA |
| Cloud DNS API (`dns.googleapis.com`) enabled | done |
| VM OAuth scope `cloud-platform` | default (launch_vm.sh) |
| Deploy passes `enable_interactive_tools=true` | via `--interactive-tools` (launch_vm.sh) or `ENABLE_INTERACTIVE_TOOLS=true` in the launcher script; requires `--hostname` |

## 1. During deploy — capture the delegation nameservers

`interactive_tools.yml` creates the per-instance Cloud DNS zone and prints its
nameservers. Grab them from the VM deploy log or Cloud DNS directly:

```bash
gcloud compute ssh ks-gemini-test --zone=us-east4-c \
  --command='sudo grep -A2 "DELEGATION REQUIRED" /var/log/cloud-init-output.log'
# or:
gcloud dns managed-zones describe it-gemini-galaxy-useanvil-org \
  --format='value(nameServers)'
```

## 2. One-time Route 53 delegation

In the **`galaxy.useanvil.org`** Route 53 hosted zone add an `NS` record:

- Name: `interactivetool.gemini.galaxy.useanvil.org`
- Type: `NS` · Value: the 4 Cloud DNS nameservers from step 1

Confirm the chain resolves once propagated:

```bash
dig +short NS interactivetool.gemini.galaxy.useanvil.org          # the 4 Cloud DNS NS
dig +short A  x.ep.its.interactivetool.gemini.galaxy.useanvil.org # the gemini VM IP (wildcard)
```

## 3. Verify the DNS + cert layer

```bash
export KUBECONFIG=~/.kube/configs/gemini   # re-fetch from the VM if clobbered
kubectl get clusterissuer letsencrypt-dns01                  # Ready=True
kubectl get certificate galaxy-it-wildcard -n galaxy         # READY=True
kubectl get secret galaxy-it-tls -n galaxy                   # exists (kubernetes.io/tls)
```

The **Certificate going Ready is the decisive check**: cert-manager solved the
DNS-01 challenge keyless (ADC + `dns.admin`) and the delegation is live. It stays
`Pending` until step 2 propagates — expected.

## 4. Verify routing (never GCP Batch)

```bash
CM='kubectl get cm galaxy-configs -n galaxy -o jsonpath={.data.job_conf\.yml}'
$CM | grep -B1 'interactive_tool'                            # environment: k8s
$CM | grep -E 'interactivetools_proxy_host|k8s_interactivetools_tls_secret'
# expect: interactivetool.gemini.galaxy.useanvil.org  and  galaxy-it-tls
```

## 5. Launch a stock IT (Jupyter)

Ensure a stock IT tool is installed (e.g. `interactive_tool_jupyter_notebook`).
Launch it from the Galaxy UI, then:

```bash
# IT runs as a pod ON THIS CLUSTER (not a Batch job):
kubectl get pods -n galaxy | grep -i interactive
# Service + Ingress created with the wildcard secret:
kubectl get ingress -n galaxy \
  -o custom-columns=NAME:.metadata.name,HOST:.spec.rules[0].host,TLS:.spec.tls[0].secretName
#   HOST = <id>-<token>.ep.its.interactivetool.gemini...   TLS = galaxy-it-tls
```

Browser: open the IT link from Galaxy — it loads over **HTTPS with a valid cert**
(no warning) and the **WebSocket connects** (live kernel/terminal).

Confirm it did NOT go to Batch:

```bash
kubectl exec -n galaxy galaxy-postgres-1 -c postgres -- \
  psql -U postgres -d galaxy -c \
  "select id, state, job_runner_name from job where tool_id like '%interactive_tool%' order by id desc limit 3;"
# job_runner_name = k8s   (never gcp_batch)
```

## 6. Success criteria (Phase 0 complete)

- Certificate `galaxy-it-wildcard` Ready; `galaxy-it-tls` populated.
- IT runs as a k8s pod on the instance, `job_runner_name=k8s`, no Batch job.
- IT reachable over HTTPS at the wildcard host, valid cert, WebSocket connected.

## Troubleshooting

- **Cert stuck `Pending`** — delegation not propagated (recheck step 2 `dig`) or
  ADC/`dns.admin`. `kubectl describe certificate galaxy-it-wildcard -n galaxy`,
  then follow the Order/Challenge; check cert-manager logs for `cloudDNS`/permission
  errors.
- **IT pod `Pending`** — node CPU/memory pressure (small instances). `kubectl
  describe pod` for `Insufficient cpu`.
- **404 / WS fails** — ingress host or annotations; confirm
  `interactivetools_proxy_host` and that the IT ingress carries the websocket
  annotations and the `galaxy-it-tls` secret from step 4.

## Do not tear down the Cloud DNS zone

The zone persists across redeploys; deleting/recreating it reshuffles its
nameservers and breaks the Route 53 delegation. Treat it like the reserved static IP.
