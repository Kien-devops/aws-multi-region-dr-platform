# FSx ONTAP DR Orchestration V1

## Scope

V1 adds a Tokyo-hosted, semi-automated control plane. It does not create FSx, SVM, volumes, SnapMirror relationships, EKS resources, or Global Accelerator resources.

```text
CloudWatch alarm
      |
  EventBridge (disabled by default)
      |
Step Functions Standard
      |-- DynamoDB execution lock + approval record
      |-- Lambda: failure evidence, fencing gate, ONTAP read-only inspection
      |-- Lambda: promotion/GitOps/traffic gates (fail closed in V1)
      `-- SNS audit notifications
```

The actual current workload is `file-service` in EKS. Tokyo uses an NFS mount to the Tokyo SVM and remains read-only until an explicitly approved storage promotion and a separate GitOps change are completed.

## Safety model

- All four feature flags default to `false`.
- Alarm events require raw evidence plus two independent failure signals.
- A conditional DynamoDB lock prevents concurrent executions; TTL bounds stale locks.
- Approval uses a Step Functions callback token stored in a short-lived DynamoDB record. The token is never placed in SNS or logs; a conditional state transition makes the decision single-use.
- Fencing evidence is mandatory. Timeout or unreachable Singapore is never treated as fencing proof.
- Promotion and traffic handlers fail closed unless enabled and all prerequisites are present. V1 contains those API integrations, but this implementation task does not invoke them.
- Every execution carries `correlationId`, event time, and outcome notification.

## Enablement boundary

Keep these values `false` during development:

```hcl
enable_fsx_dr_orchestration   = false
enable_fsx_dr_event_trigger   = false
enable_fsx_dr_promotion       = false
enable_fsx_dr_traffic_switch  = false
```

Before enabling any mutation, configure private ONTAP connectivity, a Secrets Manager secret containing only the ONTAP endpoint and credential, an authenticated approval channel, a dedicated GitHub App/bot, and the exact application traffic endpoint group. Obtain a reviewed change record and test in a non-production account.
