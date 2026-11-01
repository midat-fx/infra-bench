# thumbnailer pods are never created

Namespace `k8s-pod-security` enforces the Pod Security Standard `restricted`.
The `thumbnailer` Deployment was copied from an older cluster and no pods
appear: the ReplicaSet reports `FailedCreate`.

Make `thumbnailer` run in this namespace. The namespace must keep enforcing
`restricted`; fix the workload, not the guard rail. The image runs as root by
default, and that is not allowed here.

The verifier deletes the namespace and re-applies every manifest in this
directory from scratch.
