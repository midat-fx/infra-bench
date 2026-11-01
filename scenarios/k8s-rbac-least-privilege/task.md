# log-shipper is cluster-admin

An audit found that the `log-shipper` ServiceAccount in namespace
`k8s-rbac-least-privilege` is bound to `cluster-admin`. The shipper only tails
the logs of pods in its own namespace: it lists and watches pods there and
reads their logs. It needs nothing else, anywhere.

Rewrite `rbac.yaml` so the ServiceAccount has exactly the access it needs.
The verifier re-applies the manifests from scratch and probes the account's
effective permissions with `kubectl auth can-i`.
