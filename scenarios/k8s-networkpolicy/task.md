# frontend cannot reach api

Namespace `k8s-networkpolicy` runs `api`, `frontend` and `batch`. The security
baseline is default-deny ingress, with explicit allow rules per caller. Since
the policies were rolled out, `frontend` gets timeouts calling
`http://api/` (Service port 80).

Fix the NetworkPolicies so that `frontend` can call `api`. Only `frontend` may
call it: `batch` must still be blocked, and the namespace keeps its
default-deny ingress policy.

Edit `netpol.yaml` (leave `apps.yaml` alone). The verifier deletes the
namespace, re-applies the manifests from scratch and tests real traffic.
