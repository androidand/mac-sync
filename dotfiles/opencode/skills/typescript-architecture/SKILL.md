---
name: typescript-architecture
description: Design and refactor TypeScript codebases with strict typing, clear boundaries, and testable modules
compatibility: opencode
metadata:
  domain: engineering
  stack: typescript
---
## What I do
- Enforce strict and explicit typing at module boundaries.
- Improve architecture with cohesive modules, low coupling, and predictable interfaces.
- Replace implicit behavior with narrow domain types and explicit error handling.
- Keep refactors behavior-preserving and backed by tests.

## Working style
- Model domain first: entities, value objects, input/output contracts.
- Push side effects to edges, keep core logic deterministic.
- Use discriminated unions for state and result handling where helpful.
- Prefer small pure functions and composition over monolithic classes.

## Output checklist
- Public APIs are typed and documented by signatures.
- Runtime validation exists at untrusted boundaries.
- Lint/typecheck/tests pass with no new warnings.
- Migration notes included if interfaces changed.
