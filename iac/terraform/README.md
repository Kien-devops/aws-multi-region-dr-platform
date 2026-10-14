# Terraform migration

This stack codifies the infrastructure that was created manually in the AWS Console.
It is import-first: existing resources must be imported into the state before any apply.

## Layout

```text
iac/terraform/
|-- envs/lab/
|   |-- backend.tf
|   |-- providers.tf
|   |-- versions.tf
|   |-- main.tf
|   |-- variables.tf
|   |-- outputs.tf
|   |-- terraform.tfvars.example
|   |-- terraform.tfvars.import.example
|   `-- import.ps1
`-- modules/
    |-- vpc/
    |-- ecr/
    |-- eks/
    `-- lbc/
```

`.terraform/`, `terraform.tfstate*`, and `terraform.tfvars` are local generated/private files and are excluded by `.gitignore`.

## Scope

- Singapore and Tokyo VPC foundations, NAT, routes, peering, and FSx cross-region security groups.
- Primary-region ECR repositories, registry scanning, replication, and Tokyo repository creation template.
- Existing Singapore EKS cluster, managed node group, access entries, and LBC IRSA role.

Tokyo EKS, Aurora, Secrets Manager, FSx ONTAP, ALB, Global Accelerator, Argo CD, and Kubernetes objects are intentionally not managed yet. Their live IDs/configuration need a separate read-only inventory before codification.

## Safety

1. For the existing account, copy `envs/lab/terraform.tfvars.import.example` to `envs/lab/terraform.tfvars`. The plain example keeps all create flags disabled.
2. Run `terraform init`, `terraform fmt -check`, `terraform validate`. The state backend is S3 at `s3://aws-multi-region-dr-platform-620306387033/terraform/lab/terraform.tfstate`; S3 native lockfile locking is enabled.
3. Import existing resources using `envs/lab/import.ps1` or the commands in it. The script is intentionally explicit and stops on unexpected failures.
4. Run `terraform plan`. Do not apply until the plan is reviewed; NAT, EKS, peering, and IAM changes are production-sensitive.

The configuration defaults to the live observed EKS version `1.37`, not the stale table value `1.32`.

The backend bucket is in `ap-southeast-1` and currently uses SSE-S3. AWS inspection found bucket versioning disabled; enable versioning separately before production use if recovery of prior state versions is required. Do not run `terraform init -migrate-state` until the state migration is reviewed and explicitly approved.

`manage_lbc_helm = true` requires a readable kubeconfig and an active cluster context. If the current operator cannot read kubeconfig, keep it false and manage the already-installed Helm release outside this first import pass.
