# Runbook: Failback to Singapore

## Scope

Return to Singapore through a new planned change after Tokyo has stabilized. This is not an automatic reversal of failover.

## Preconditions

- Tokyo is the sole current writer.
- Singapore is a connected, healthy Global Database secondary.
- Replication lag stable for the approved observation window.
- Engine versions/patches compatible; no blocking maintenance.
- Singapore EKS and validation ALB healthy.
- Change approval and rollback owner assigned.

## Sequence

1. If necessary, rebuild Singapore secondary from the current Tokyo primary. Never reuse divergent standalone data without reconciliation.
2. Validate synchronization and Singapore infrastructure.
3. Record UTC `T0`.
4. Perform managed switchover:

   ```bash
   aws rds switchover-global-cluster \
     --region ap-northeast-1 \
     --global-cluster-identifier app2-global-db \
     --target-db-cluster-identifier <SINGAPORE_DB_CLUSTER_ARN>
   ```

5. Wait for Singapore `IsWriter=true`, Tokyo `IsWriter=false`, global status `available`.
6. Set Singapore GA traffic dial `100`; Tokyo `0`.
7. Validate new connections, EKS, ALB, secret metadata, alarms.
8. Keep Tokyo healthy as warm standby.

## GitOps Rule

When app2 exists, return Tokyo replica/capacity state through a Git commit or an approved suspended-sync procedure. Do not leave live cluster state divergent from Git.

## Rollback

If Singapore fails validation while Tokyo is still healthy, perform a separate approved managed switchover back to Tokyo and restore GA preference. Preserve both event timelines.

## Evidence

Capture lag graph, topology before/after, GA dials, validation requests, approvals, and timestamps. Application business validation remains deferred until Phase 3.
