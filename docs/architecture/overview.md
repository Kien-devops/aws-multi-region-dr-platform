# Architecture Overview

## Current Lab Phase

Phase 1 builds infrastructure only:

```text
ECR -> VPC -> EKS -> controllers -> Aurora Global Database
    -> Secrets/ESO prerequisites -> Argo CD platform
    -> temporary validation ALBs -> Global Accelerator -> CloudWatch
```

`app2` is not deployed. `gitops/app2` and application DR scripts are retained for later phases.

## Target Architecture

```text
Clients
  -> AWS Global Accelerator
     -> Singapore public ALB -> dr-sg-eks -> app2
     -> Tokyo public ALB     -> dr-tokyo-eks -> app2 warm standby
  -> Aurora PostgreSQL Global Database
     -> app2-sg-db primary writer
     -> app2-tokyo-db read-only secondary
```

## Regional Foundations

| Layer | Singapore | Tokyo |
|---|---|---|
| Region | `ap-southeast-1` | `ap-northeast-1` |
| VPC | `dr-sg-vpc`, `10.10.0.0/16` | `dr-tokyo-vpc`, `10.20.0.0/16` |
| EKS | `dr-sg-eks` | `dr-tokyo-eks` |
| Node group | `dr-sg-ng` | `dr-tokyo-ng` |
| Aurora | `app2-sg-db` writer | `app2-tokyo-db` secondary |
| Validation ALB | `dr-sg-validation-alb` | `dr-tokyo-validation-alb` |

## Warm Standby Model

- Singapore is the normal traffic and database-write Region.
- Tokyo infrastructure stays healthy and has replicated images, database storage, secret, platform controllers, and validation path.
- Phase 2 decides application replica counts and GitOps DR state.
- Global Accelerator uses endpoint health and new-connection routing; ALB health comes from target groups.
- Aurora Global Database managed switchover is for planned role changes; managed failover is for unplanned events and can lose unreplicated data.

## Availability and Failure Boundaries

- Two AZs per Region for subnets, ALB, EKS placement, and DB subnet groups.
- Lab mode uses one NAT per Region, creating an AZ dependency. Production HA uses one NAT per AZ or a validated endpoint/egress design.
- One Aurora instance per Region is cost-saving only. Production primary needs an in-Region reader/failover target and capacity testing.
- Inter-Region VPC peering is optional; managed ECR/Aurora/Secrets replication does not use it.

## Security Boundaries

- EKS nodes and Aurora are private.
- EKS human access uses IAM access entries and temporary credentials.
- Controllers use IRSA with exact ServiceAccount trust subjects.
- Future app pods use a dedicated runtime DB user through Secrets Manager/ESO.
- Database, accelerator, and IAM mutation actions require constrained operator roles and CloudTrail.

## Recovery Objectives

| Objective | Design target | Evidence state |
|---|---:|---|
| Infrastructure traffic recovery | `< 5 minutes` | Measure in LAB 14/15 |
| Aurora lag/RPO signal | `< 30 seconds` | Observe CloudWatch; not transaction proof |
| Application RTO/RPO | Same design targets | Deferred to Phase 3 |

Targets are not achieved results. See [LAB 17](../labs/17-rto-rpo-test.md).

## Roadmap

1. Phase 1: Console-first infrastructure labs.
2. Phase 2: app2 CI/CD, immutable images, GitOps Applications, ExternalSecret, workload deployment.
3. Phase 3: business transaction DR tests and measured application RTO/RPO.
4. Phase 4: Terraform migration using the validated architecture.
