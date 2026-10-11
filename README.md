# AWS Multi-Region Disaster Recovery Platform

Bộ lab **Console-first** xây dựng và kiểm chứng hạ tầng Warm Standby trên AWS trước khi đưa ứng dụng `app2` vào.

> **Current state:** `INFRASTRUCTURE LABS READY` / `APPLICATION NOT YET DEPLOYED`.
>
> Repository chứa GitOps manifests và scripts cho các phase sau, nhưng LAB 00-18 hiện không deploy app2, không chạy business test, không tuyên bố RTO/RPO ứng dụng đã đạt.

## 1. Project Phases

| Phase | Scope | Status |
|---|---|---|
| **1 - Infrastructure Labs** | ECR, VPC, EKS, controllers, Aurora Global Database, Secrets, Argo CD platform, temporary validation ALBs, Global Accelerator, observability, infrastructure DR, cleanup | Documented; requires manual AWS execution |
| **2 - Application CI/CD + GitOps** | app2 build/test/scan, immutable SHA images, ECR publish, Argo CD Applications, ExternalSecret, Kubernetes workloads | Deferred |
| **3 - Application DR Benchmark** | Business health, `/api/v1/orders`, continuous writer, measured application RTO/RPO | Deferred |
| **4 - Terraform Migration** | Reusable IaC modules and environment configuration after Console understanding | Deferred |

## 2. Target Architecture

```text
                         INTERNET
                            |
                    AWS Global Accelerator
                      /             \
                     /               \
                    v                 v
       SINGAPORE PRIMARY          TOKYO DR
       ap-southeast-1             ap-northeast-1
             |                         |
            ALB                       ALB
             |                         |
         dr-sg-eks               dr-tokyo-eks
             |                         |
             +-----------+-------------+
                         |
               Aurora PostgreSQL
                 Global Database
             SG writer / Tokyo secondary
```

Phase 1 uses `infra-validation` NGINX workloads only to create real ALB endpoints and test Global Accelerator. These workloads are not app2.

Detailed architecture:

- [Architecture overview](docs/architecture/overview.md)
- [Request flow](docs/architecture/request-flow.md)
- [Deployment flow](docs/architecture/deployment-flow.md)
- [DR flow](docs/architecture/dr-flow.md)

## 3. Canonical Resource Naming

| Layer | Singapore | Tokyo / Global |
|---|---|---|
| VPC | `dr-sg-vpc` | `dr-tokyo-vpc` |
| Public subnets | `dr-sg-public-a/b` | `dr-tokyo-public-a/b` |
| Private subnets | `dr-sg-private-a/b` | `dr-tokyo-private-a/b` |
| NAT | `dr-sg-nat` | `dr-tokyo-nat` |
| Route tables | `dr-sg-public-rt`, `dr-sg-private-rt` | `dr-tokyo-public-rt`, `dr-tokyo-private-rt` |
| EKS | `dr-sg-eks` | `dr-tokyo-eks` |
| Node group | `dr-sg-ng` | `dr-tokyo-ng` |
| Aurora cluster | `app2-sg-db` | `app2-tokyo-db` |
| Global DB | - | `app2-global-db` |
| Secret | `/app2/database` | replica with same name |
| Validation ALB | `dr-sg-validation-alb` | `dr-tokyo-validation-alb` |
| Global Accelerator | - | `dr-global-accelerator` |

Network plan:

| Region | VPC | Public A/B | Private A/B |
|---|---|---|---|
| Singapore | `10.10.0.0/16` | `10.10.1.0/24`, `10.10.2.0/24` | `10.10.11.0/24`, `10.10.12.0/24` |
| Tokyo | `10.20.0.0/16` | `10.20.1.0/24`, `10.20.2.0/24` | `10.20.11.0/24`, `10.20.12.0/24` |

## 4. Architecture Decisions

- **Warm Standby:** Tokyo infrastructure stays deployable/healthy; application capacity is introduced in Phase 2.
- **Private compute/data:** EKS nodes and Aurora instances use private subnets; public subnets host internet-facing ALBs and NAT.
- **NAT modes:** labs default to one NAT per Region for cost; production uses one NAT per AZ or VPC endpoints plus validated egress design.
- **Managed replication:** ECR, Aurora, and Secrets Manager replication do not depend on VPC peering.
- **Optional peering:** retained only for approved cross-Region private flows.
- **Immutable delivery:** Phase 2 must use commit-SHA image tags, not `latest`.
- **Global writer endpoint:** future database clients should use Aurora Global Database writer endpoint where supported, avoiding regional-hostname changes after managed role changes.
- **GitOps control:** Argo CD is installed in Phase 1 with zero Applications. Phase 2 must prevent manual DR changes from being immediately self-healed away.

## 5. Lab Roadmap

| Lab | Outcome |
|---:|---|
| [00](docs/labs/00-prerequisites.md) | Account, SSO/MFA, tools, quotas, cost guardrails |
| [01](docs/labs/01-ecr-multi-region.md) | Four immutable ECR repos and verified Tokyo replication path |
| [02](docs/labs/02-networking-singapore.md) | Singapore VPC |
| [03](docs/labs/03-networking-tokyo.md) | Tokyo VPC |
| [04](docs/labs/04-cross-region-networking.md) | Optional inter-Region VPC peering |
| [05](docs/labs/05-eks-singapore.md) | Singapore EKS and private node group |
| [06](docs/labs/06-eks-tokyo.md) | Tokyo EKS and warm-standby node group |
| [07](docs/labs/07-aws-load-balancer-controller.md) | Controller IRSA and Helm installs |
| [08](docs/labs/08-aurora-global-database.md) | Aurora PostgreSQL Global Database |
| [09](docs/labs/09-secrets-manager.md) | Replicated DB secret and ESO prerequisites |
| [10](docs/labs/10-argocd-gitops.md) | Argo CD platform, zero app Applications |
| [11](docs/labs/11-infrastructure-readiness.md) | Temporary workloads/ALBs and infrastructure readiness proof |
| [12](docs/labs/12-global-accelerator.md) | Global Accelerator and real health failover proof |
| [13](docs/labs/13-observability.md) | CloudWatch alarms/dashboard/Container Insights |
| [14](docs/labs/14-planned-switchover.md) | Planned infrastructure role change |
| [15](docs/labs/15-unplanned-failover.md) | Authorized unplanned infrastructure failover |
| [16](docs/labs/16-failback.md) | Controlled return to Singapore |
| [17](docs/labs/17-rto-rpo-test.md) | Evidence-backed infrastructure measurements |
| [18](docs/labs/18-cleanup.md) | Dependency-ordered teardown and cost audit |

Every lab includes goal, architecture context, prerequisites, naming, click-by-click implementation, verification, troubleshooting, security, cost, rollback, evidence, and next step.

Command convention: blocks using `\` line continuation are Bash/Git Bash commands. PowerShell-specific blocks are labeled `powershell`. AWS Console remains the primary implementation path; CLI commands are mainly verification and approved operational actions.

## 6. Current vs Target Flows

### Current Phase 1 flow

```text
Temporary NGINX validation pod
  -> ClusterIP Service
  -> AWS Load Balancer Controller
  -> regional ALB
  -> Global Accelerator
```

### Target Phase 2 flow

```text
app2 source
  -> CI test + security scan
  -> immutable ECR SHA image
  -> Git desired-state update
  -> Argo CD sync
  -> EKS workloads
  -> Aurora Global Database
```

Files under [`gitops/app2/`](gitops/app2/) and [`scripts/`](scripts/) are retained as future-phase artifacts. They are not applied by Phase 1 labs.

## 7. DR Targets and Evidence Rules

| Metric | Design target | Current measured result |
|---|---:|---|
| Infrastructure traffic recovery | `< 5 minutes` | Not tested until LAB 14/15 execution |
| Aurora lag/RPO design target | `< 30 seconds` | Not tested; observe real metrics |
| Application write RTO | `< 5 minutes` | Deferred to Phase 3 |
| Application transaction RPO | `< 30 seconds` | Deferred to Phase 3 |

No document may convert a target into an achieved result without timestamped runtime evidence. Planned switchover aims to minimize/avoid data loss but is not reported as measured application `RPO = 0` without transaction proof.

## 8. Security Baseline

- Root MFA, no root keys, short-lived SSO/role credentials.
- Service IAM roles least privilege; no `AdministratorAccess` for controllers/workloads.
- Private EKS nodes and Aurora instances.
- Restricted EKS public endpoint CIDRs; private-only preferred for production.
- Secrets Manager, encryption at rest, TLS, CloudTrail, controlled DR permissions.
- No passwords, kubeconfig, tokens, or secret values in Git/evidence.
- Database uses a runtime user instead of the master user before application onboarding.

## 9. Cost Boundary

This architecture is expensive. Major hourly/usage charges include:

- Two EKS control planes and EC2 node groups.
- Two NAT Gateways in lab mode; more in production HA mode.
- Aurora instances, storage, I/O, backups, cross-Region replication.
- Two validation ALBs and Global Accelerator.
- Public IPv4, CloudWatch logs/metrics/alarms, Secrets Manager, ECR storage/scanning.

Do not rely on fixed dollar estimates in this repo. Use the current AWS Pricing Calculator for the selected Regions/classes, configure LAB 00 budgets, and execute [LAB 18](docs/labs/18-cleanup.md) when pausing.

## 10. Operational Runbooks

- [Failover to Tokyo](docs/runbooks/failover.md)
- [Failback to Singapore](docs/runbooks/failback.md)
- [Aurora database recovery](docs/runbooks/database-recovery.md)
- [Incident checklist](docs/runbooks/incident-checklist.md)

Runbooks distinguish executable Phase 1 infrastructure steps from deferred Phase 2/3 application operations.

## 11. Before LAB 00

- [ ] Confirm this is the intended AWS account.
- [ ] Obtain authority for billable multi-Region resources.
- [ ] Choose monthly budget/alert recipients.
- [ ] Record operator public CIDR.
- [ ] Ensure no conflicting `10.10.0.0/16` or `10.20.0.0/16` networks must connect later.
- [ ] Confirm teardown/snapshot retention policy.
- [ ] Reserve a multi-hour execution window; EKS/Aurora creation is not instant.
- [ ] Understand that repository completion is documentation readiness, not live AWS deployment evidence.

## 12. AWS Documentation Baseline

Service behavior was reviewed against official AWS documentation on `2026-10-12`. Re-check before execution because Console labels, supported versions, and feature prerequisites change:

- [EKS Kubernetes version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [AWS Load Balancer Controller with Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [Aurora Global Database connectivity/endpoints](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-connecting.html)
- [Aurora Global Database switchover/failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html)
- [Secrets Manager multi-Region replication](https://docs.aws.amazon.com/secretsmanager/latest/userguide/replicate-secrets.html)
- [Global Accelerator endpoint health](https://docs.aws.amazon.com/global-accelerator/latest/dg/about-endpoint-groups-health-check-options.html)
- [Global Accelerator CloudWatch metrics](https://docs.aws.amazon.com/global-accelerator/latest/dg/cloudwatch-monitoring.html)
