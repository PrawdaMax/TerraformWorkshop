# Terraform Workshops

| Folder | Content |
|---|---|
| `terraform_01` | Workshop 1 – single EC2 instance in the default VPC |
| `terraform_02` | Workshop 2 – own VPC, subnet, internet gateway, Elastic IP |
| `terraform_03` | Workshop 3 – multiple instances behind a load balancer, deployed via GitHub Actions |

---

## Workshop 3 – Load Balancer & CI/CD

### Architecture

```
                 Internet
                    │
                    ▼
     ┌──────────────────────────────┐
     │ Application Load Balancer    │  ← output: load_balancer_dns
     │ (SG: HTTP 80 from 0.0.0.0/0) │
     └──────────────┬───────────────┘
                    │ Listener :80 → Target Group (health check "/")
        ┌───────────┴───────────┐
        ▼                       ▼
 ┌─────────────┐         ┌─────────────┐
 │ EC2 #1      │         │ EC2 #2      │   SG: HTTP 80 only from the LB
 │ us-east-1a  │         │ us-east-1b  │
 │ 10.0.1.0/24 │         │ 10.0.2.0/24 │
 └─────────────┘         └─────────────┘
        └──────── VPC 10.0.0.0/16 ──────┘
```

Building on the setup of workshop 2 (own VPC, internet gateway, route table):

- **Two subnets** in two Availability Zones (an ALB requires at least two AZs).
- **Multiple EC2 instances** created with `count` (`instance_count`, default `2`), distributed across the subnets. Each serves a page showing which server answered.
- **Application Load Balancer** with a listener on port 80 that forwards to a **target group** containing all instances.
- **Security groups**: the LB is reachable from the internet, the instances only from the LB.
- **Output** `load_balancer_dns`: the DNS address of the load balancer.
- **Backend**: the state is stored remotely in an **S3 bucket** (`terraform.tf`), encrypted and locked during runs (`use_lockfile`).
  Terraform Cloud was not used because it currently refuses to create new free-tier organizations ("Free tier organizations created by user limit reached"), so S3 is used as the "other backend".

### Workflows (GitHub Actions)

Both workflows are started manually (`workflow_dispatch`) under **Actions → Run workflow**.

| Workflow | File | What it does |
|---|---|---|
| Terraform Apply | `.github/workflows/terraform-apply.yml` | `init` → `validate` → `plan` → `apply`, prints the LB DNS |
| Terraform Destroy | `.github/workflows/terraform-destroy.yml` | `init` → `destroy` (must type `destroy` to confirm) |

Required repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_SESSION_TOKEN` | only for temporary credentials (e.g. AWS Academy) |

### Usage

0. One-time setup: create the state bucket and enter its name in `terraform_03/terraform.tf`:
   ```
   aws s3api create-bucket --bucket <unique-name> --region us-east-1
   aws s3api put-bucket-versioning --bucket <unique-name> --versioning-configuration Status=Enabled
   ```
1. Start the **Terraform Apply** workflow.
2. Copy the `load_balancer_dns` value from the log and open `http://<dns>` in a browser (wait 1–3 minutes until the health checks pass).
3. Reload the page several times – the response alternates between *server 1* and *server 2*, which proves that the load balancer distributes requests.
4. Start the **Terraform Destroy** workflow and enter `destroy` to delete all resources.

---

## Why do we need Terraform Cloud (or another backend) when we use CI/CD?

Terraform stores what it has created in a **state file** (`terraform.tfstate`). It uses this file to know which real resources belong to the configuration, so it can update or destroy them later.

Without a remote backend, the state is saved **locally** – and in CI/CD "locally" means on the GitHub Actions runner. Each runner is a **fresh, temporary virtual machine** that is deleted after the job finishes. That causes these problems:

1. **The state is lost after every run.** The apply workflow creates the resources, but the state file disappears together with the runner.
2. **Destroy would not work.** The destroy workflow runs on a new runner with an empty state. Terraform thinks nothing exists, destroys nothing, and the resources keep running (and cost money).
3. **A second apply would create duplicates** (or fail because names like the load balancer already exist), since Terraform does not know about the existing resources.
4. **No locking.** If two workflow runs (or a colleague and the pipeline) run at the same time, they could both change the infrastructure and corrupt the state. A remote backend (Terraform Cloud, or S3 with `use_lockfile`) locks the state during a run.
5. **No shared source of truth.** The local PC, the apply workflow and the destroy workflow must all see the **same** state. A remote backend gives every participant access to it.
6. **Security.** The state can contain sensitive data. It should not be committed to Git; a backend stores it securely (encrypted, with access control and version history).

**In short:** CI/CD runners are stateless and short-lived, but Terraform needs a persistent, shared and locked state. A remote backend such as Terraform Cloud (or alternatively an S3 bucket with locking) provides exactly that.
