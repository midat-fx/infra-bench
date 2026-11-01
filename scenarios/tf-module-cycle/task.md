# terraform plan fails with "Cycle"

This configuration wires two modules: `app` (the application's security group)
and `db` (the database's). The app may talk to Postgres (tcp/5432) on the
database, and the database accepts 5432 only from the app's security group.
Each module needs the other's group ID, and `terraform plan` stops with
`Error: Cycle`.

Restructure the Terraform so it plans and applies, while keeping exactly that
network intent: app egress tcp/5432 to the db group, db ingress tcp/5432 from
the app group, both by security-group reference (no CIDR rules for 5432).
Keep the two modules.

The verifier applies against LocalStack from fresh state and evaluates policy
over `terraform show -json`.
