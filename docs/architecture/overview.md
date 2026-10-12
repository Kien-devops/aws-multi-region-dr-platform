# Architecture Overview

## Current Lab Phase

Core labs build database and application infrastructure; storage labs add an independent filesystem DR path:

```text
ECR -> VPC -> EKS -> controllers -> Aurora Global Database
    -> Secrets/ESO prerequisites -> Argo CD platform
    -> temporary validation ALBs -> Global Accelerator -> CloudWatch

EC2 -> NFS 4.1 -> FSx for ONTAP Singapore
    -> asynchronous SnapMirror -> FSx for ONTAP Tokyo
```

`gitops/app2` remains the EKS delivery boundary. `file-service` runs on private EC2 and is not managed by Argo CD.

## Target Architecture

```text
Clients
  -> application AWS Global Accelerator
     -> Singapore public ALB -> dr-sg-eks -> app2
     -> Tokyo public ALB     -> dr-tokyo-eks -> app2 warm standby
  -> file-service AWS Global Accelerator
     -> Singapore public ALB -> private EC2 -> NFS -> FSx ONTAP RW
     -> Tokyo public ALB     -> private EC2 -> NFS -> FSx ONTAP DP/RW

backend-3 -> Aurora PostgreSQL Global Database
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
| Storage EC2 | `dr-sg-storage-ec2` | `dr-tokyo-storage-ec2` |
| Storage ALB | `dr-sg-storage-alb` | `dr-tokyo-storage-alb` |
| FSx/SVM/volume | `dr-sg-fsx-ontap` / `dr-sg-svm` / `dr-data` | `dr-tokyo-fsx-ontap` / `dr-tokyo-svm` / `dr-data-dr` |

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
- The SnapMirror intercluster path in this design does use the peering routes and approved intercluster ports.
- Multi-AZ floating client endpoints have different cross-VPC routing constraints; this lab uses deployment choices documented in LAB 19-20 and must revalidate them before execution.

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
| Storage RPO | `< 5 minutes` target | Measure with storage sequence markers |
| Storage write RTO | `< 15 minutes` target | Measure from declaration to successful Tokyo write |

Targets are not achieved results. See [LAB 17](../labs/17-rto-rpo-test.md).

## Roadmap

1. Phase 1: Console-first infrastructure labs.
2. Phase 2: app2 CI/CD, immutable images, GitOps Applications, ExternalSecret, workload deployment.
3. Phase 3: business transaction DR tests and measured application RTO/RPO.
4. Phase 4: Terraform migration using the validated architecture.
