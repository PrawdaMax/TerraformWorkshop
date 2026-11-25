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
  # Terraform muss mindestens Version 1.10 verwenden
  # (wird für das State-Locking per "use_lockfile" im S3-Backend benötigt).
  required_version = ">= 1.10"

  # Remote-Backend: AWS S3.
  # Der State wird nicht mehr lokal gespeichert, sondern zentral in
  # einem S3-Bucket. Dadurch können sowohl der eigene PC als auch
  # GitHub Actions (Apply- und Destroy-Workflow) auf denselben State
  # zugreifen.
  backend "s3" {
    # Name des S3-Buckets (Bucket-Namen sind weltweit eindeutig).
    bucket = "tf-state-workshop3-134806263123"

    # Pfad der State-Datei innerhalb des Buckets.
    key = "terraform_03/terraform.tfstate"

    region = "us-east-1"

    # Verschlüsselt die State-Datei im Bucket.
    encrypt = true

    # Sperrt den State während eines Laufs über eine .tflock-Datei,
    # damit nicht zwei Läufe gleichzeitig Änderungen vornehmen.
    use_lockfile = true
  }
}
