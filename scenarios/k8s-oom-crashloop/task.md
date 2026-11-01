# report-api is crash-looping

After the last release the `report-api` pods in namespace `k8s-oom-crashloop`
restart over and over (`CrashLoopBackOff`). The service loads a 48 MiB report
cache into memory at start-up (`CACHE_MB`); that is expected and must stay.

Fix `deployment.yaml` so both replicas start and stay up.

Constraints from the platform team:
- every container keeps a memory limit, and no limit may exceed 256Mi;
- do not change the application command or `CACHE_MB`.

The verifier deletes the namespace and re-applies the manifests in this
directory from scratch, so the files are the deliverable.
