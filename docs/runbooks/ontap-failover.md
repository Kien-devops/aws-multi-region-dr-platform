# Runbook: FSx ONTAP Failover to Tokyo

## Scope

Storage path only. Aurora/EKS use their own runbooks.

## Preconditions

- Incident/change ID, Incident Commander, ONTAP operator and approver.
- Tokyo FSx/SVM/EC2/ALB available.
- Last acknowledged storage sequence and relationship timestamp recorded when possible.

## Decision Gates

1. Is Singapore still writable or reachable by any client? If yes, fence it first.
2. Is this planned? Run final update/quiesce. If no, document why final update is impossible.
3. Is potential data loss authorized? If no, do not break.
4. Has a reviewer confirmed exact destination `dr-tokyo-svm:dr-data-dr`?

## Actions

1. Storage GA Singapore dial `0`; stop/deregister Singapore file-service; revoke other writer mounts.
2. Capture `snapmirror show -fields state,status,last-transfer-end-timestamp`.
3. Planned only: update, verify Idle, quiesce, verify Quiesced.
4. Break Tokyo destination.
5. Mount/verify Tokyo RW; start service; `/ready` writable.
6. Write a storage event and verify file checksum.
7. Storage GA Tokyo dial `100`; verify new client requests.

## Expected State

Tokyo is the only writer. Singapore remains fenced. Relationship is broken until failback work begins.

## Failure Handling

- Break not executed: restore Singapore if safe.
- Break executed, Tokyo validation fails: keep both traffic paths fenced; repair Tokyo or restore from backup.
- Singapore returns: do not route or resync automatically.

## Evidence

Fencing, relationship status/timestamps, approval, first Tokyo write, recovered sequence/checksum, traffic result.
