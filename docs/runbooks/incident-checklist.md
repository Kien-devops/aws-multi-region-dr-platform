# Runbook: Incident Checklist

## Roles

- **Incident Commander:** owns decision and blast radius.
- **AWS Operator:** executes approved RDS/GA/EKS changes.
- **DBA:** validates topology, lag, data risk, reconciliation.
- **Verifier:** independently checks health/evidence.
- **Recorder/Communications:** UTC timeline and stakeholder updates.

## Detect and Assess

- [ ] Incident ID and UTC `T0` recorded.
- [ ] Affected Region/components identified.
- [ ] CloudWatch/GA/ALB/EKS/RDS signals reviewed.
- [ ] IAM/network/configuration causes checked before declaring Regional disaster.
- [ ] Tokyo capacity and health verified.
- [ ] Last known Aurora lag/RPO metrics captured.
- [ ] Current writer and GA routing state recorded.

## Decision Gate

- [ ] Incident Commander authorizes planned switchover or unplanned failover.
- [ ] Possible data-loss boundary stated for unplanned failover.
- [ ] Old-primary fencing plan agreed.
- [ ] Rollback/failback owner assigned.
- [ ] Application phase status confirmed: deployed or deferred.

## Execute

- [ ] Fence Singapore traffic/writes.
- [ ] Validate Tokyo EKS, ALB, secret, database secondary.
- [ ] Execute correct Aurora operation: switchover or failover.
- [ ] Confirm exactly one writer.
- [ ] Shift GA new-connection routing.
- [ ] Validate infrastructure and alarms.
- [ ] If app2 exists, apply GitOps-controlled DR state; avoid self-heal conflict.

## Stabilize

- [ ] Error/health/lag metrics stable.
- [ ] Former primary remains isolated until cleared.
- [ ] Secret and global writer endpoint behavior confirmed.
- [ ] Infrastructure recovery timestamp recorded.
- [ ] Application validation explicitly completed or marked deferred.
- [ ] Stakeholder update avoids unverified RTO/RPO claims.

## Prepare Failback

- [ ] Singapore root cause resolved/security-cleared.
- [ ] Singapore restored as synchronized secondary.
- [ ] Observation window and lag threshold satisfied.
- [ ] Planned failback approved using [failback.md](failback.md).

## Close

- [ ] Evidence and CloudTrail/RDS/GA events retained.
- [ ] Design target versus measured result table completed.
- [ ] Application transaction RPO marked deferred unless directly measured.
- [ ] Post-incident actions assigned: monitoring, IAM, capacity, runbook, GameDay, architecture fixes.
