# IaC console inventory

This file records the operator-provided console inventory used to shape the optional Terraform modules. It is not a Terraform state export and does not prove a live resource until the resource is imported and `terraform plan` is clean.

## Confirmed naming contract

| Area | Singapore | Tokyo / global |
|---|---|---|
| Region | `ap-southeast-1` | `ap-northeast-1` |
| VPC | `dr-sg-vpc` / `10.10.0.0/16` | `dr-tokyo-vpc` / `10.20.0.0/16` |
| EKS | `dr-sg-eks` | `dr-tokyo-eks` |
| Node group | `dr-sg-ng` | `dr-tokyo-ng` |
| Aurora | `app2-sg-db` writer | `app2-global-db-cluster-1` reader; global ID `app2-global-db` |
| Secret | `/app2/database` | replicated secret |
| Validation ALB | `dr-sg-validation-alb` | `dr-tokyo-validation-alb` |
| Global Accelerator | primary endpoint, traffic dial 100 | standby endpoint, traffic dial 0 |
| Alerts | SNS `dr-platform-alerts` | cross-region metrics/dashboard |

## Terraform ownership

- Terraform owns the imported VPC, ECR, Singapore EKS, and Singapore LBC resources already present in the S3 backend.
- Optional modules now describe Tokyo EKS, EKS managed add-ons, Aurora Global Database, Secrets Manager replication, Global Accelerator, SNS, and the CloudWatch dashboard.
- ALBs created by Kubernetes Ingress remain Kubernetes/LBC outputs; Terraform must not create duplicate `aws_lb` resources for them.
- Argo CD, External Secrets Operator, validation workloads, CloudWatch alarms, and Kubernetes manifests require a separate cluster-provider inventory before adoption.

## Evidence boundaries

- The current operator inventory says two Spot nodes in each region. The Terraform state was deliberately changed earlier to `dr-sg-ng` `min=0`, `desired=0` for cost control; this is the effective desired state until restored explicitly.
- The repository's imported EKS configuration uses Kubernetes `1.37`; an older console summary mentions `1.32`. Verify the live cluster before enabling Tokyo EKS management.
- The Singapore LBC module now models the observed Pod Identity trust (`pods.eks.amazonaws.com`). The EKS Pod Identity association itself remains a separate importable resource and must be verified before managing it.
- Aurora subnet groups, security-group IDs, Global Accelerator listener/endpoint ARNs, add-on versions, alarm dimensions, and dashboard JSON are not inferred. Fill them from read-only AWS inventory before enabling their management flags.
