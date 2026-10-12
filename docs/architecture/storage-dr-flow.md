# Storage Disaster Recovery Flow

## Separation of State

```text
backend-3 -> Aurora Global Database -> transaction state
file-service -> EC2 -> NFS 4.1 -> FSx ONTAP -> file state
```

File metadata, events and uploaded bytes live together under `/mnt/dr-data`; Aurora is not required to rebuild the file catalog.

## Normal State

```text
Users -> dr-file-global-accelerator
       -> dr-sg-storage-alb -> dr-sg-storage-ec2
          -> /mnt/dr-data -> dr-sg-svm:dr-data (RW)
                              |
                              | asynchronous SnapMirror
                              v
                         dr-tokyo-svm:dr-data-dr (DP/read-only)

       -> dr-tokyo-storage-alb -> dr-tokyo-storage-ec2
          health may be alive, but readiness is false while storage is read-only
```

The storage accelerator is separate from the EKS accelerator. Global Accelerator has no HTTP path routing, and the Kubernetes controller owns the EKS ALB lifecycle.

## Network Boundary

- VPC peering remains unnecessary for Aurora, ECR and Secrets Manager managed replication.
- SnapMirror requires bidirectional reachability between every source and destination intercluster LIF.
- Cross-Region peering rules use CIDRs, not peer security-group IDs.
- Allow only verified intercluster traffic: ICMP and TCP `443`, `10000`, `11104`, `11105` between intercluster LIF CIDRs.
- NFS clients use private SVM endpoints. Start with AWS's documented NFS rule set; reduce to TCP `2049` only after an NFSv4.1-only validation proves all operations and failover behavior.

## Promotion Boundary

```text
fence source writers
  -> final update when source is reachable
  -> verify relationship state and last transfer
  -> quiesce
  -> break destination
  -> mount/verify Tokyo RW
  -> enable Tokyo file-service
  -> shift new traffic
```

For unplanned failover, the final update may be impossible. The latest replicated marker defines observed storage RPO.

## Failback Boundary

Tokyo is authoritative after promotion. Reverse replication Tokyo to Singapore, wait for synchronization, stop Tokyo writes, perform a final update, promote Singapore, then restore Singapore-to-Tokyo protection. `snapmirror resync` can discard divergent destination data; require a snapshot/evidence checkpoint and two-person direction review.

## Evidence

- Relationship state/status and last-transfer timestamp.
- Highest acknowledged and recovered storage sequence.
- Source fencing evidence.
- Promotion timestamps and first successful write.
- Original/recovered SHA-256 values.

Measured results remain empty until the labs run on deployed AWS resources.
