---
name: mcp-server-integration
description: Configure and secure MCP servers with minimal context overhead and predictable tool behavior
compatibility: opencode
metadata:
  domain: tooling
  protocol: mcp
---
## What I do
- Configure local and remote MCP servers for task-specific workflows.
- Set safe defaults for auth, permissions, and tool exposure.
- Reduce token overhead by enabling only high-value servers and tools.
- Troubleshoot MCP auth and connectivity issues systematically.

## Working style
- Start with explicit use-cases and required tools.
- Keep heavy servers disabled by default and enable per agent when needed.
- Use env-based secret injection and avoid plaintext credentials in config.
- Validate auth status and latency before enabling broad usage.

## Output checklist
- MCP servers are scoped to actual workflows.
- Permission boundaries are documented and least-privilege.
- Debug steps provided for auth and connection failures.
- Tool patterns avoid accidental broad context inflation.
