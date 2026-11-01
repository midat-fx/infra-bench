# storefront never becomes Ready

The `storefront` Deployment in namespace `k8s-readiness-port` runs, but its
pods never turn Ready, so the `storefront` Service has no endpoints and every
request through it fails. The app itself is healthy: it serves `/healthz` and
`/` over HTTP.

Fix `web.yaml` so the pods become Ready and `http://storefront/` answers
through the Service. Keep an HTTP readiness probe on `/healthz`: the platform
relies on it to pull broken pods out of rotation.

The verifier deletes the namespace and re-applies the manifests in this
directory from scratch, so the files are the deliverable.
