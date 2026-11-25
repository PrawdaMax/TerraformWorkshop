terraform {
  # Definition der benötigten Provider für Terraform.
  required_providers {
    aws = {
      # Verwendet den offiziellen AWS-Provider von HashiCorp.
      source = "hashicorp/aws"

      # Legt den zulässigen Versionsbereich des AWS-Providers fest.
      # "~> 5.92" erlaubt Versionen ab 5.92,
      # jedoch keine Version 6.0 oder höher.
      version = "~> 5.92"
    }
  }

  # Definiert die erforderliche Terraform-Version.
  # Terraform muss mindestens Version 1.2 verwenden.
  required_version = ">= 1.2"
}
