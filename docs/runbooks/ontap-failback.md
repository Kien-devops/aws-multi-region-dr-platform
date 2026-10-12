# Runbook: FSx ONTAP Failback to Singapore

## Scope

Return authoritative Tokyo storage state to Singapore, then restore Singapore -> Tokyo protection.

## Preconditions

- Tokyo stable and authoritative; Singapore repaired and fenced.
- Snapshots/backups retained; peer routes healthy.
- Two people verify source/destination direction.

## Decision Gates

1. Can Singapore destination data be discarded back to the newest common snapshot? If unclear, stop.
2. Is there a common snapshot? If no, use backup/new-volume migration.
3. Can Tokyo writes be paused for final synchronization?

## Actions

1. Snapshot both sides.
2. Reverse resync Tokyo -> Singapore; wait `Snapmirrored`/`Idle`.
3. Validate Singapore copy without serving writes.
4. Stop Tokyo writers; final update; quiesce; break Singapore destination.
5. Verify Singapore RW, checksum, sequence and `/ready`.
6. Shift storage GA to Singapore.
7. Delete/release reverse relationship.
8. Recreate/resync Singapore -> Tokyo; confirm Tokyo DP/read-only.

## Rollback

Before Singapore promotion, remain on Tokyo. After promotion, treat Singapore as authoritative and use another controlled switchover.

## Warning

`snapmirror resync` can delete destination snapshots newer than the common snapshot and discard divergent data. Never infer direction from Region names.

## Evidence

Snapshots, peer/relationship status, direction approval, final sequence, first Singapore write, restored normal protection.
