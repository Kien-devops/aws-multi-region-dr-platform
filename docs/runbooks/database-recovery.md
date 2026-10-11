# Runbook: Aurora Global Database Recovery

## Endpoint Strategy

- Future write clients use the Aurora Global Database writer endpoint.
- Regional reader endpoints are explicit read paths.
- Instance endpoints are diagnostic only.
- `/app2/database` stores the global writer endpoint so replicated secret values remain valid after managed role change.

## Scenario 1: Instance Failure Inside Primary Region

This is an Aurora instance/cluster failover, not a cross-Region DR event. Keep GA traffic unchanged unless application health requires otherwise. Verify the regional cluster endpoint moves to the new writer and inspect RDS events.

## Scenario 2: Planned Cross-Region Switchover

Use `switchover-global-cluster` after lag/version/health prechecks. Expected outcome: target secondary becomes primary and replication direction reverses. Validate the global writer endpoint and exactly one `IsWriter=true` member.

## Scenario 3: Unplanned Cross-Region Failover

Use the Global Database failover workflow only with explicit authorization acknowledging possible data loss. Fence the former primary, promote Tokyo, keep the old primary isolated when it returns, then rebuild/rejoin it as a secondary.

## Scenario 4: Broken or Divergent Secondary

1. Stop treating the unhealthy cluster as DR-ready.
2. Preserve required snapshots/evidence.
3. Remove/rebuild the secondary using the current RDS-supported workflow from the authoritative primary.
4. Match engine version, subnet group, SG, KMS, parameter group, backup/log settings.
5. Wait for connected synchronization and stable lag before restoring readiness.

Do not manually copy data between two writable clusters without a documented reconciliation plan.

## Verification Commands

```bash
aws rds describe-global-clusters --region <CURRENT_PRIMARY_REGION> --global-cluster-identifier app2-global-db \
  --query 'GlobalClusters[0].{Status:Status,Endpoint:Endpoint,Members:GlobalClusterMembers[*].{Arn:DBClusterArn,Writer:IsWriter,Sync:SynchronizationStatus}}'

aws rds describe-db-clusters --region ap-southeast-1 --db-cluster-identifier app2-sg-db
aws rds describe-db-clusters --region ap-northeast-1 --db-cluster-identifier app2-tokyo-db
```

Review CloudWatch `AuroraGlobalDBReplicationLag`, `AuroraGlobalDBProgressLag`, `AuroraGlobalDBRPOLag`, RDS events, CPU, memory, connections, and storage capacity.

## Split-Brain Prevention

- One authoritative global topology and one writer.
- Fence traffic before emergency promotion.
- Restrict failover API permissions.
- Do not point secrets/DNS to a standalone divergent cluster.
- Require DBA/Incident Commander approval before reintroducing the former primary.

## Credential Recovery

- Never rotate or expose credentials merely to work around network failures.
- Rotate through Secrets Manager/approved RDS process.
- Verify primary secret replication is `InSync`.
- If a replica is promoted to standalone during an exceptional regional isolation event, document that it no longer receives updates from the original primary and define reconciliation before normal operations resume.

## Application-Dependent Steps

Schema migrations, transaction reconciliation, first successful business write, and transaction RPO are deferred to the application phase.
