# Disaster Recovery Flow

## Infrastructure State Machine

```text
NORMAL_SG_PRIMARY
  -> planned: validate -> Aurora switchover -> GA shift -> TOKYO_PRIMARY
  -> incident: fence SG -> Aurora failover -> GA shift -> TOKYO_PRIMARY_DEGRADED

TOKYO_PRIMARY
  -> rebuild/synchronize SG secondary
  -> planned switchover -> GA shift -> NORMAL_SG_PRIMARY
```

## Planned Switchover

1. Confirm both Regions healthy, engine versions compatible, lag stable.
2. Perform `switchover-global-cluster` to the target secondary.
3. Confirm exactly one writer and topology `available`.
4. Change GA traffic dials for new connections.
5. Validate EKS, ALB, secret, endpoint, alarms.

Planned operation aims to avoid data loss. Report measured application RPO only after Phase 3 transaction testing.

## Unplanned Failover

1. Incident Commander declares old primary unsafe.
2. Fence traffic/writes to reduce split-brain risk.
3. Confirm Tokyo standby is healthy enough to promote.
4. Invoke managed Global Database failover with explicit data-loss authorization.
5. Route new GA connections to Tokyo.
6. Validate infrastructure and document possible data loss.

## Failback

1. Rebuild or reattach Singapore as a synchronized secondary.
2. Observe stable lag and validate Singapore platform directly.
3. Managed switchover to Singapore.
4. Restore GA preference.
5. Keep Tokyo healthy as warm standby.

## Split-Brain Controls

- Never create two independent writable clusters and call them one global database.
- Keep recovered former primary fenced until RDS topology is authoritative.
- Use the global writer endpoint for future clients.
- Restrict failover permissions and require one accountable operator.
- Application scaling/state changes must not conflict with Argo CD reconciliation.

## Measurement Boundaries

Infrastructure timeline:

```text
T0 declaration
T1 active endpoint unhealthy
T2 Tokyo validation HTTP success
T3 Tokyo database writer active
T4 platform checklist complete
```

Application first successful business write and transaction loss are deferred to Phase 3.
