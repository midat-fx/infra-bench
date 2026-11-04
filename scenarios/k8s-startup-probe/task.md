# ledger restarts forever

The `ledger` Deployment in namespace `k8s-startup-probe` never stays up. Its
container is killed and restarted every few seconds, and the pod never turns
Ready. The app is not broken: it spends about 20 seconds loading its data
(`sleep 20` stands in for that), then serves `/healthz` over HTTP on port 8080.

Fix `app.yaml` so the pod starts, becomes Ready and stays up without
restarts. Constraints from the platform team:

- keep the start-up as it is; the 20 seconds are real work, not a bug;
- keep an HTTP liveness probe on `/healthz`. Once the app is up, a hung server
  must be restarted within 10 seconds (initial delay plus period times failure
  threshold).

The verifier deletes the namespace and re-applies the manifests in this
directory from scratch, then watches the pod for 40 seconds, so the files are
the deliverable.
