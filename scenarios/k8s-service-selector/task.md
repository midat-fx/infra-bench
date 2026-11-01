# shop-public has no endpoints after the v2 rollout

In namespace `k8s-service-selector`, the `shop-public` Service stopped serving
traffic right after `web` was rolled out as v2: it has no endpoints. The
namespace also runs `admin`, an internal back-office UI that must never be
reachable through `shop-public`.

Fix `web.yaml` so that `shop-public` routes to all `web` pods, and only to
them, and keeps doing so on the next version bump.

The verifier deletes the namespace, re-applies the manifests from scratch and
checks the Service's endpoints and responses.
