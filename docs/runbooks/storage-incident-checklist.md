# Runbook: Storage Incident Checklist

## Detect and Assess

- [ ] Record UTC `T0`, incident ID, reporter and affected file APIs.
- [ ] Check storage GA, ALB target, EC2/SSM, `/health`, `/ready`, NFS mount and FSx events.
- [ ] Capture SnapMirror state/status/last transfer and latest recovered sequence.
- [ ] Determine whether failure is app, EC2, NFS, source FSx, network, replication or Region-wide.

## Fence

- [ ] Disable Singapore storage GA endpoint.
- [ ] Stop/deregister Singapore file-service when reachable.
- [ ] Identify every NFS client capable of writing; fence all, not only the demo EC2.
- [ ] Preserve logs/snapshots; do not resync.

## Decision

- [ ] Confirm Tokyo infrastructure healthy.
- [ ] State possible RPO/data loss explicitly.
- [ ] Obtain promotion approval and reviewer confirmation of destination path.

## Recover

- [ ] Planned: final update -> Idle -> quiesce -> Quiesced.
- [ ] Break Tokyo destination.
- [ ] Verify RW mount, storage event, file checksum and `/ready`.
- [ ] Shift new traffic to Tokyo.

## Stabilize

- [ ] Confirm one writer only.
- [ ] Record T3/T4, latest marker, lost records and customer impact.
- [ ] Keep Singapore fenced after return.
- [ ] Hand off to [ONTAP failback](ontap-failback.md).

## Close

- [ ] Store sanitized evidence.
- [ ] Reconcile monitoring/runbooks and access changes.
- [ ] Report Target, Expected and Measured Result separately.
