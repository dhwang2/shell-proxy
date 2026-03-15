# Shell Script Rules

- Use `#!/bin/bash` shebang.
- Quote all variable expansions: `"${VAR}"` not `$VAR`.
- Use `[[ ]]` for conditionals, not `[ ]`.
- Functions must use `proxy_` prefix.
- After editing any `.sh` file, validate with `bash -n <file>`.
- Use `local` for function-scoped variables.
- Use `printf` over `echo` for portability in output functions.
- Respect module group boundaries defined in `app/env.sh`.
