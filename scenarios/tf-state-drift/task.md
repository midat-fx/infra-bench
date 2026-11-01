# Terraform plan wants to undo the incident fix

During incident INC-2291 the on-call engineer changed the `jobs` SQS queue by
hand in the console: visibility timeout 30 s -> 300 s (workers need ~4 minutes
per job), and tagged it `oncall=INC-2291`. The queue is defined in `main.tf`;
the state for it is `terraform.tfstate` in this directory.

`terraform plan` now proposes to put the timeout back to 30 s. Make the code
match what is running, so that `terraform plan` reports no changes. The live
queue must keep its 300 s timeout and its tags, it must stay managed by this
Terraform state, and drift on it must stay visible in future plans.

The verifier runs `terraform plan -detailed-exitcode` on this directory and
inspects the live queue in LocalStack.
