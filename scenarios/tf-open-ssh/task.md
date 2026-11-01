# SSH open to the internet on the web tier

The `web` security group in `main.tf` accepts SSH (tcp/22) from anywhere, over
IPv4 and IPv6. Policy: SSH only from the office network `198.51.100.0/24`
(IPv4; the office has no IPv6). HTTPS (tcp/443) stays open to the world on
both IPv4 and IPv6; egress is unchanged.

Fix the Terraform. The verifier applies against LocalStack from fresh state
and evaluates policy over `terraform show -json`, checking every ingress rule
on the group whose port range includes 22.
