# Request Flow

## Current Phase 1 Flow

```text
Client
  -> Global Accelerator static IP/DNS
  -> regional temporary validation ALB
  -> IP target group
  -> infra-validation NGINX pod
```

This flow proves network, controller, ALB target health, GA routing, and EKS pod reachability. It does not prove app2 routing, authentication, database access, or business correctness.

## Target Phase 2 Flow

```text
Client
  -> Global Accelerator
  -> regional ALB (TLS termination)
  -> Kubernetes Ingress rules
  -> frontend/backend Services
  -> app2 Pods
  -> Aurora Global Database writer endpoint
```

## Hop-by-Hop Responsibilities

1. **Global Accelerator:** exposes static anycast IPs, selects healthy regional endpoint groups, routes new connections.
2. **ALB:** terminates TLS in production, evaluates target health, performs HTTP path/host routing.
3. **AWS Load Balancer Controller:** converts Kubernetes Ingress/Service state into ALB, listener, target group, and security-group state.
4. **Kubernetes Service:** selects ready pods. IP target mode registers pod IPs directly.
5. **Application:** authenticates/validates requests and applies business logic. Deferred.
6. **Aurora:** global writer endpoint follows the current primary; regional readers serve explicitly designed read traffic.

## Health Semantics

- GA considers ALB endpoint health from ALB target groups.
- ALB health path must represent the workload's ability to serve traffic, not merely process liveness.
- Phase 1 uses `/` on disposable NGINX.
- Phase 2 must use app-specific readiness that does not mutate business data.

## Failure Behavior

- Traffic dial changes affect new connections, not existing TCP connections.
- GA can ignore a zero traffic dial during health failover when another endpoint group has a healthy endpoint with positive weight.
- If no healthy endpoints exist, GA can fail open. Monitoring must detect this state.
- Database promotion and network traffic movement are separate control-plane operations; sequence them through a runbook.

## Security

- Phase 1 HTTP carries no sensitive data.
- Phase 2 requires HTTPS, ACM certificate management, restricted origin/security groups, WAF decision, secure headers, and end-to-end secret handling.
- Aurora remains private; only approved EKS/client sources reach TCP 5432.
