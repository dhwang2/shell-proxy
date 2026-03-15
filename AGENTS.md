# shell-proxy AGENTS.md

AI-facing maintenance rules for the `shell-proxy` repository.

Last Updated: 2026-03-14

## Scope

- Current Bash production line for VPS proxy management.
- Formal release line: `v0.x`.
- Current formal baseline: `v0.0.0`.
- Runtime root: `/etc/shell-proxy`.

## Security

- This is a public repository. Never commit secrets, tokens, or credentials.
- Do not commit `.DS_Store`, `.idea/`, `.vscode/`.

## Directory Structure

```text
shell-proxy/
├── .claude/
│   ├── rules/
│   │   ├── archive.md
│   │   ├── shell-scripts.md
│   │   └── verification.md
│   ├── agents/
│   │   ├── security-reviewer.md
│   │   └── shell-validator.md
│   ├── skills/
│   │   └── shell-proxy-verify/
│   │       ├── SKILL.md
│   │       └── references/
│   │           ├── file-module-map.md
│   │           └── dependency-graph.md
│   └── settings.json
├── app/                               ← Application source
│   ├── bootstrap.sh                   ← Install entry
│   ├── env.sh                         ← Single source of truth (module manifest)
│   ├── install.sh
│   ├── management.sh
│   ├── self_update.sh
│   ├── watchdog.sh
│   ├── systemd/                       ← Service templates
│   │   ├── sing-box.service.tpl
│   │   ├── snell-v5.service.tpl
│   │   ├── shadow-tls.service.tpl
│   │   ├── caddy-sub.service.tpl
│   │   └── proxy-watchdog.service.tpl
│   └── modules/                       ← Domain-grouped modules
│       ├── core/
│       ├── protocol/
│       ├── routing/
│       ├── subscription/
│       ├── user/
│       ├── network/
│       ├── runtime/
│       └── service/
├── docs/
│   ├── dev/
│   │   ├── checklist.md           ← Task state tracking
│   │   └── workflow.md            ← Execution records
│   └── plans/
└── AGENTS.md
```

## Main Services

- `sing-box.service`
- `snell-v5.service`
- `shadow-tls.service` and `shadow-tls-*.service`
- `proxy-watchdog.service`
- `caddy-sub.service`

## Documentation

- Use [docs/dev/checklist.md](docs/dev/checklist.md) for task state and [docs/dev/workflow.md](docs/dev/workflow.md) for execution records.

## Linkage Rules

- If install paths, service names, or log paths change, review:
  - `app/bootstrap.sh`, `app/env.sh`, `app/install.sh`, `app/management.sh`, `app/self_update.sh`, `app/systemd/*.tpl`
- If module paths, module groups, bundle groups, or menu loading changes, review:
  - `app/env.sh`, `app/management.sh`, `app/install.sh`, `app/self_update.sh`
- If `share` or `routing` hot paths change, also review:
  - cache TTLs, fallback paths, bundle paths
  - `docs/plans/refactor-architecture_shell-proxy.md`

## Validation

- `bash -n app/env.sh`
- `bash -n app/install.sh`
- `bash -n app/management.sh`
- `bash -n app/self_update.sh`
- `find app/modules -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n`
- `git diff --check`

## Verification Workflow

Full specifications in [.claude/rules/verification.md](.claude/rules/verification.md). Summary:

| Tier | When | What |
|---|---|---|
| **Tier 1 — Syntax** | Every change | `bash -n` on modified files + `git diff --check` |
| **Tier 2 — Minimum Real-World** | Single-module bug fixes, localized changes | Tier 1 + invoke `shell-proxy-verify` skill (tier=2): affected modules + direct dependents |
| **Tier 3 — Regression** | Features, cross-module refactors, manifest changes | Tier 1 + invoke `shell-proxy-verify` skill (tier=3): full topological traversal of all modules |

**Adaptive selection rule**: Agent evaluates the number of modified files, whether changes cross module boundaries, and whether `app/env.sh` or entry scripts are touched — then applies the matching tier.

## Coding Rules

- Use `#!/bin/bash` shebang.
- Quote all variable expansions: `"${VAR}"` not `$VAR`.
- Use `[[ ]]` for conditionals.
- Functions must use `proxy_` prefix.
- Use `local` for function-scoped variables.
- Use `printf` over `echo` for portability in output functions.
- Respect module group boundaries defined in `app/env.sh`.

## Claude Code Workflow

- Hooks auto-validate `bash -n` after shell script edits.
- Use shell-validator agent for comprehensive module integrity checks.
- Use plan mode for cross-module refactors touching `app/env.sh` manifest.
