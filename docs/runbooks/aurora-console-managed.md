# Aurora console-managed runbook

Aurora Global Database is intentionally outside Terraform ownership. Terraform still owns the VPC, private subnets, Aurora security-group data lookups, EKS, IAM, Pod Identity, Secrets Manager, and networking prerequisites.

## Create or restore the database

1. In the Singapore AWS Console, create an Aurora PostgreSQL primary cluster in the existing VPC.
2. Select the existing private DB subnet group and security group `app2-sg-db-sg`.
3. Create the primary DB instance with the required class and monitoring settings.
4. Add the Singapore cluster to the existing Aurora Global Database `app2-global-db`.
5. Add a Tokyo secondary cluster in the existing Tokyo VPC using its private DB subnet group and `app2-tokyo-db-sg`.
6. Wait until global replication reports connected/available before enabling application traffic.

Do not create a second global cluster. Confirm identifiers, engine version, encryption, private access, backup policy, and deletion protection in the Console before proceeding.

## Update application secret

Update Secrets Manager secret `/app2/database` without exposing values in Git, logs, or chat. Set the current writer endpoint and database settings:

- `DB_HOST`
- `DB_PORT` (`5432`)
- `DB_USER`
- `DB_PASSWORD`
- `DB_NAME`
- `DB_SSL`

External Secrets Operator syncs the secret to `app2-db-secret` in namespace `app2`. Verify only metadata and readiness. Restart `backend-3` if the pod does not reload the updated secret.

## Verification

```powershell
kubectl -n app2 get secretstore,externalsecret,secret app2-db-secret
kubectl -n app2 rollout status deployment/app2-backend-3
```

Validate `backend-3` health and the orders API using a harmless test record. Never print or decode `DB_PASSWORD`.

Terraform plans must not contain `aws_rds_global_cluster`, `aws_rds_cluster`, or `aws_rds_cluster_instance` actions. Recreating or modifying Aurora is a Console change followed by a Secrets Manager update, not `terraform apply`.
