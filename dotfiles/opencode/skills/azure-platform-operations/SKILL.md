---
name: azure-platform-operations
description: Plan and operate Azure workloads with secure defaults, clear IaC patterns, and production readiness
compatibility: opencode
metadata:
  domain: cloud
  provider: azure
---
## What I do
- Design Azure resource architecture aligned with workload and compliance constraints.
- Improve deployment reliability with IaC and environment promotion strategy.
- Strengthen security posture: least privilege, secret handling, network boundaries.
- Tune runtime reliability with monitoring, alerting, and incident response hooks.

## Working style
- Identify critical resources and blast radius first.
- Prefer managed identity and key vault integration over static secrets.
- Make environment differences explicit and version-controlled.
- Capture operational runbooks for deploy and rollback.

## Output checklist
- Security controls are explicit and auditable.
- Deployment plan includes verification and rollback steps.
- Monitoring dashboards and alerts map to SLO-impacting failures.
- Cost and performance tradeoffs are called out.
