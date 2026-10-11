# Runbook: Failover to Tokyo

> Production-sensitive. Requires Incident Commander authorization. Aurora Global Database failover can lose unreplicated data.

## Scope

Phase 1 runbook validates infrastructure only. app2 scaling, business writes, and transaction RPO are deferred.

## Activation Criteria

- Singapore is unavailable or declared unsafe for writes.
- Tokyo EKS, ALB, database secondary, secret replica, and operator access are healthy.
- Incident roles assigned: approver, operator, verifier, recorder.
- Last known Aurora lag captured.

## Sequence

1. Record incident ID and UTC `T0`.
2. Fence Singapore:
   - Set Singapore GA endpoint weight/dial to zero if reachable.
   - Prevent application writes to the old primary.
   - If Phase 2 Argo CD Applications exist, change Git desired state or suspend automated sync under change control before manual scaling.
3. Verify Tokyo:

   ```bash
   kubectl --context tokyo get nodes
   kubectl --context tokyo -n infra-validation get pods,ingress
   aws secretsmanager describe-secret --region ap-northeast-1 --secret-id /app2/database
   ```

4. Promote Tokyo through the RDS Global Database **Failover** action. Approved CLI:

   ```bash
   aws rds failover-global-cluster \
     --region ap-southeast-1 \
     --global-cluster-identifier app2-global-db \
     --target-db-cluster-identifier <TOKYO_DB_CLUSTER_ARN> \
     --allow-data-loss
   ```

5. Wait for Tokyo `IsWriter=true` and global status `available`.
6. Set Tokyo GA traffic dial `100`; keep Singapore `0`.
7. Validate new connections:

   ```bash
   curl -sS -H 'Connection: close' http://<ACCELERATOR_DNS_NAME>/
   aws rds describe-global-clusters --region ap-northeast-1 --global-cluster-identifier app2-global-db
   ```

8. Confirm alarms, log all timestamps, announce infrastructure recovery state.

## Do Not

- Do not promote Tokyo before validating its health.
- Do not declare zero data loss without transaction evidence.
- Do not reconnect a recovered Singapore writer independently.
- Do not run `kubectl scale` against a self-healing Argo CD Application without controlling reconciliation.
- Do not publish secret values in incident channels.

## Application Phase Addendum

Deferred until app2 is deployed:

- Scale/promote Tokyo application desired state through GitOps.
- Validate frontend/backends and first successful business write.
- Run `scripts/dr/rpo-check.sh` against recorded sequence markers.

## Recovery Handoff

Tokyo remains primary until Singapore is rebuilt as a synchronized secondary. Use [failback.md](failback.md); do not immediately reverse traffic.
