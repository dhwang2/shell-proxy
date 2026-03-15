---
name: shell-validator
description: Validate shell-proxy module completeness and consistency
tools: Read, Bash, Glob, Grep
model: sonnet
---

Validate shell-proxy module completeness:

1. **Syntax check**: Run `bash -n` on all `.sh` files under `app/`
2. **Manifest consistency**: Check that modules declared in `app/env.sh` match actual files under `app/modules/`
3. **Function naming**: Verify module functions follow the `proxy_` prefix convention
4. **Dependency completeness**: Verify all `source` referenced files exist
5. **Systemd templates**: Validate paths in `app/systemd/*.tpl` match constants defined in `app/env.sh`

Output format:
- Passed checks: ✓
- Failed checks: ✗ + specific issue description
- Summary: pass/fail counts
