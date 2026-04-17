---
name: ralphloop-workflows
description: Integrate ralphloop MCP workflows with secure credentials, scoped tools, and reliable execution patterns
compatibility: opencode
metadata:
  domain: integration
  provider: ralphloop
---
## What I do
- Configure ralphloop server endpoints and environment-based authentication.
- Scope ralphloop tool permissions to specific tasks and agents.
- Establish fallback behavior when ralphloop is unavailable.
- Produce reproducible debug steps for auth, network, and permission failures.

## Working style
- Keep ralphloop disabled by default until credentials and URL are validated.
- Enable only required ralphloop tools for each workflow.
- Verify server auth state before invoking heavy operations.
- Log assumptions about endpoint URLs and token scopes.

## Output checklist
- Connection prechecks are documented.
- Permissions are least-privilege.
- Failure handling path is defined.
- Activation steps are short and repeatable.
