---
name: agentic-swarm-orchestration
description: Coordinate multi-agent execution plans with bounded concurrency, clear handoffs, and mergeable outputs
compatibility: opencode
metadata:
  domain: orchestration
  mode: multi-agent
---
## What I do
- Break complex work into parallelizable sub-tasks across specialized agents.
- Define ownership boundaries, contracts, and merge criteria between agents.
- Control fan-out to avoid wasted context and token burn.
- Consolidate outputs into a single implementation plan or integrated patch set.

## Working style
- Start with dependency graph: what can run in parallel and what must be sequential.
- Use small, testable deliverables per agent.
- Require each agent to return assumptions, risks, and verification results.
- Perform final integration pass for consistency and regressions.

## Output checklist
- Parallel plan with bounded concurrency is explicit.
- Handoffs include exact inputs/outputs.
- Integration conflicts and overlap are resolved.
- Final result includes verification summary.
