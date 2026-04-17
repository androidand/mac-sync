---
name: sql-performance-tuning
description: Design schemas and optimize SQL queries for correctness, reliability, and performance at scale
compatibility: opencode
metadata:
  domain: data
  stack: sql
---
## What I do
- Review SQL for correctness, index strategy, and execution-plan risks.
- Design safe schema changes and migrations with rollback paths.
- Reduce latency and resource usage through query and indexing improvements.
- Protect data integrity with constraints and transactional correctness.

## Working style
- Validate cardinality assumptions and join selectivity before optimizing.
- Prefer explicit columns over SELECT * for stable contracts.
- Use staged migrations for high-risk changes on large tables.
- Separate online-safe changes from backfill tasks.

## Output checklist
- Query plans analyzed for key hotspots.
- Index recommendations include tradeoffs and write amplification impact.
- Migrations are reversible where possible.
- Operational rollout notes include lock and downtime risk.
