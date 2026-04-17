---
name: backend-api-engineering
description: Build and harden backend APIs with robust contracts, observability, and safe rollout practices
compatibility: opencode
metadata:
  domain: backend
  stack: api
---
## What I do
- Design and implement API endpoints with clear request/response contracts.
- Add validation, authorization checks, idempotency, and safe error semantics.
- Improve observability: structured logs, correlation IDs, and actionable metrics.
- Add tests across unit, integration, and critical e2e paths where needed.

## Working style
- Start from use cases and failure modes.
- Define explicit status codes and error payloads.
- Guard external calls with timeouts, retries, and circuit-breaking strategy when applicable.
- Keep performance budgets visible and test for N+1 or over-fetching risks.

## Output checklist
- Validation and auth enforced before business logic.
- Error responses are consistent and documented.
- Tests cover happy path plus key failure scenarios.
- Backward compatibility or migration impact is stated.
