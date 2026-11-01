# Same provider pins as the scenarios; only used to fill the plugin cache.
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "5.100.0" }
    random = { source = "hashicorp/random", version = "3.7.2" }
  }
}
