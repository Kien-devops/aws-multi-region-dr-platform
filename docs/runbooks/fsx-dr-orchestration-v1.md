# FSx ONTAP DR Orchestration V1 Runbook

## Dry run

The state machine accepts a simulation event. It exercises validation, locking, approval, fencing, SnapMirror evidence, writable-storage proof, file verification, and traffic gates without calling destructive APIs:

```json
{
  "eventType": "simulation",
  "eventId": "lab-unique-id",
  "dryRun": true,
  "failureConfirmed": true,
  "failureSignals": ["application", "storage"],
  "primaryFenced": true
}
```

Use a unique `eventId` per run. Preserve the execution ARN, `correlationId`, timestamps, and final notification as evidence.

## Console prerequisites

1. Verify both FSx file systems are `AVAILABLE`, the source volume is `RW`, and Tokyo destination is `DP` until promotion.
2. Verify the existing SnapMirror relationship from `dr-sg-svm:dr-data` to `dr-tokyo-svm:dr-data-dr` with ONTAP CLI/REST. Record state, status, health, lag, and last transfer.
3. Verify Tokyo private routing, security groups, NFS export policy, and ONTAP management access.
4. Configure the ONTAP credential reference in Secrets Manager. Never put the password in Terraform variables, state outputs, SNS, or logs.
5. Configure an authenticated, time-limited operator approval path and a least-privilege GitHub App if live GitOps mutation will later be enabled.
6. Provide Tokyo Lambda egress to Secrets Manager, Step Functions, GitHub, and the Argo CD API through VPC endpoints, private routing, or controlled NAT. Permit HTTPS from the Lambda security group to the Tokyo ONTAP management endpoint.

The ONTAP secret is referenced by ARN and must contain `host`, `username`, and `password`. The host is the Tokyo private management URL. The Lambda uses ONTAP REST relationship inspection, quiesce/break actions, cluster-job polling, and volume RW/online verification only after the feature flags and approval gates permit them.

The GitOps secret must contain `token`, `owner`, `repo`, `path`, `base_branch`, `argocd_server`, `argocd_token`, and `argocd_application`. `path` must identify only the Tokyo file-service storage patch. Prefer a short-lived GitHub App installation token; a static personal token increases rotation and blast-radius risk. The workflow creates an idempotent DR branch and pull request, waits for operator merge, then requires Argo CD `Synced`, `Healthy`, and `Succeeded` before storage verification.

## Live operation boundary

This repository change does not run `snapmirror break`, `terraform apply`, Git push, Kubernetes mutation, Global Accelerator update, or automatic failback. Promotion must remain disabled until fencing, approval, destination writability, synthetic file write/read/checksum, Argo reconciliation, and traffic verification are independently evidenced.

## Evidence

Record failure start, alarm/EventBridge receipt, execution start, approval, fencing, SnapMirror status, promotion completion, Tokyo `/ready`, synthetic file SHA-256, traffic switch, and recovery completion. Calculate RTO from the measured failure timestamp to successful recovery; estimate RPO from actual replicated application/storage markers, not from the configured SnapMirror schedule.
