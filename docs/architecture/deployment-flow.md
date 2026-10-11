# Deployment Flow

## Current Phase 1

There is no app2 deployment flow yet.

- Argo CD is installed with zero Applications.
- ECR repositories/replication are ready.
- `gitops/app2` manifests and `scripts/update-image-tag.sh` are retained but not applied.
- Temporary `gitops/infra-validation` manifests are applied manually for infrastructure proof only.

## Target Phase 2 Flow

```text
app2 source commit
  -> CI change detection
  -> unit/integration tests
  -> image build
  -> vulnerability/SBOM/signing policy
  -> push immutable commit-SHA image to ECR Singapore
  -> ECR replication to Tokyo
  -> update GitOps desired image digest/tag
  -> review/merge
  -> Argo CD sync to EKS
  -> rollout validation and monitoring
  -> Git revert/previous immutable image for rollback
```

## Artifact Boundaries

- **Source artifact:** checked-out application source at an immutable commit.
- **Build artifact:** container image identified by digest and commit SHA.
- **Deployment artifact:** reviewed Kubernetes/Kustomize desired state referencing the immutable image.

Do not use `latest`. Do not let CI run `kubectl apply` directly against production clusters.

## GitOps and DR State

Phase 2 must encode normal and DR modes declaratively. Valid patterns:

- Commit desired replica/traffic state for the active Region.
- Maintain reviewed DR overlays and promote them through Git.
- Suspend automated sync during a controlled emergency, perform authorized changes, then reconcile Git immediately.

Invalid pattern: `kubectl scale` while Argo CD `selfHeal=true`; reconciliation can undo the operation.

## Rollback

1. Detect failed rollout through Kubernetes/ALB/application health.
2. Stop promotion or revert Git desired state.
3. Argo CD reconciles to the previous immutable artifact.
4. Validate ALB targets, pods, logs, metrics, and business health.
5. Preserve incident evidence.

## Deferred Decisions

- Exact app2 CI workflows and GitHub OIDC role.
- Image signing/admission enforcement.
- Argo CD Application sync policy.
- ExternalSecret resources and database schema migrations.
- Progressive deployment strategy.
