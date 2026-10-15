# Terraform migration

This stack codifies infrastructure created manually in the AWS Console.
It is import-first: existing resources must be imported before any apply.

`envs/lab` is the only root module and the only Terraform state.

```text
terraform.tfvars
      |
      v
variables.tf -> locals.tf -> data.tf
      |
      v
network.tf / eks.tf / database.tf / identity.tf / ...
      |
      v
modules/* -> AWS
```

## Layout

```text
iac/terraform/
|-- envs/lab/
|   |-- backend.tf
|   |-- providers.tf
|   |-- versions.tf
|   |-- locals.tf
|   |-- data.tf
|   |-- network.tf
|   |-- ecr.tf
|   |-- eks.tf
|   |-- eks-addons.tf
|   |-- database.tf
|   |-- secrets.tf
|   |-- identity.tf
|   |-- load-balancer-controller.tf
|   |-- observability.tf
|   |-- global-accelerator.tf
|   |-- moved.tf
|   |-- variables.tf
|   |-- outputs.tf
|   |-- terraform.tfvars.example
|   |-- terraform.tfvars.import.example
|   `-- import.ps1
`-- modules/
    |-- vpc/
    |-- vpc_peering/
    |-- ecr/
    |-- eks/
    |-- iam_role/
    `-- lbc/
    |-- eks_addons/
    |-- aurora_global/
    |-- secrets_replica/
    |-- global_accelerator/
    `-- observability/
```

`.terraform/`, `terraform.tfstate*`, and `terraform.tfvars` are local generated/private files and are excluded by `.gitignore`.

## Scope

- Singapore and Tokyo VPC foundations, NAT, routes, peering, and FSx cross-region security groups.
- Primary-region ECR repositories, registry scanning, replication, and Tokyo repository creation template.
- Existing Singapore and Tokyo EKS clusters, managed node groups, access entries, Pod Identity roles/associations, and EKS add-ons.
- Optional import-first resources for Tokyo EKS, EKS managed add-ons, Aurora Global Database, Secrets Manager replication, Global Accelerator, SNS, and CloudWatch dashboard.

FSx ONTAP, ALB endpoint objects, Argo CD, External Secrets Operator, validation workloads, CloudWatch alarms, and Kubernetes objects remain outside this Terraform stack. Their live IDs/configuration and Helm/Kubernetes ownership need a separate read-only inventory before codification. The optional modules do not prove that the console-reported resources exist until their import IDs are added to the S3-backed state.

The optional modules are disabled by default in `terraform.tfvars.example`. Enable one only after importing the existing resource and reviewing `terraform plan`; otherwise Terraform will attempt to create a duplicate resource.

## Safety

1. For the existing account, copy `envs/lab/terraform.tfvars.import.example` to `envs/lab/terraform.tfvars`. The plain example keeps all create flags disabled.
2. Run `terraform init`, `terraform fmt -check`, `terraform validate`. The state backend is S3 at `s3://aws-multi-region-dr-platform-620306387033/terraform/lab/terraform.tfstate`; S3 native lockfile locking is enabled.
3. Import existing resources using `envs/lab/import.ps1` or the commands in it. The script is intentionally explicit and stops on unexpected failures.
4. Run `terraform plan`. Do not apply until the plan is reviewed; NAT, EKS, peering, and IAM changes are production-sensitive.

The configuration defaults to the live observed EKS version `1.37`. Current lab values use Singapore node scaling `2/2/4` and EKS Pod Identity for LBC, ESO, and CloudWatch Agent in both regions.

The backend bucket is in `ap-southeast-1` and currently uses SSE-S3. AWS inspection found bucket versioning disabled; enable versioning separately before production use if recovery of prior state versions is required. Do not run `terraform init -migrate-state` until the state migration is reviewed and explicitly approved.

`manage_lbc_helm = true` requires a readable kubeconfig and an active cluster context. If the current operator cannot read kubeconfig, keep it false and manage the already-installed Helm release outside this first import pass.

`manage_observability = true` models the SNS topic/dashboard/alarms. Keep `manage_alert_email_subscription = false` until the existing topic is imported; enabling it creates an email subscription that requires confirmation.
