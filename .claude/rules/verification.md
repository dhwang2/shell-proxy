# shell-proxy Verification Specifications

## Verification Tiers

Agent must select the appropriate tier based on the complexity and scope of fix points.

### Tier 1 — Syntax Validation (every change)

Mandatory for all code modifications, no exceptions.

- `bash -n` on every modified `.sh` file.
- `git diff --check` for whitespace issues.

### Tier 2 — Minimum Real-World Verification (targeted fixes)

When: single-module bug fixes, localized logic changes, style adjustments.

Invoke the `shell-proxy-verify` skill with `tier=2` and the list of changed files. The skill resolves affected verification modules + their direct dependents, then executes structured procedures in dependency order.

See: `.claude/skills/shell-proxy-verify/SKILL.md`

### Tier 3 — Real-World Regression Verification (feature enhancements, cross-module changes)

When: new features, module refactors, changes touching `app/env.sh` manifest, cross-module dependency changes, or any change spanning 3+ files.

Invoke the `shell-proxy-verify` skill with `tier=3`. The skill executes all verification modules in topological order (VM-03 → VM-01 → VM-05 → VM-04 → VM-06 → VM-07 → VM-08 → VM-02 → VM-09 → VM-10 → VM-11), skipping VM-12 unless explicitly requested.

See: `.claude/skills/shell-proxy-verify/SKILL.md`

### Tier Selection Guide

| Change Scope | Tier |
|---|---|
| Typo, comment, formatting | Tier 1 only |
| Single function bug fix | Tier 1 + Tier 2 |
| Multi-function fix in one module | Tier 1 + Tier 2 (expanded adjacent paths) |
| New feature or feature enhancement | Tier 1 + Tier 3 |
| Cross-module refactor | Tier 1 + Tier 3 |
| Manifest (`env.sh`) or entry script changes | Tier 1 + Tier 3 |

## Real-World Verification Constraint

After modifying `app/` code, **real-world menu interaction verification on the target server is mandatory** before archiving. This is not optional.

### When to verify

- **Always**: Any change to menu flows, prompts, display output, or user-facing text.
- **Adaptive**: Pure internal logic changes (e.g., variable renaming, comment edits) may skip interactive verification if the change has zero UI impact — but still require `bash -n` validation and bundle rebuild.

### How to verify

Use the `shell-proxy-verify` skill, which handles:
1. Pre-flight: deploy files, rebuild bundles, validate JSON configs
2. Module resolution: map changed files to verification modules via the file-module map
3. Execution: run structured procedures with expected state checks

See: `.claude/skills/shell-proxy-verify/SKILL.md`

### What counts as verification

- Completing the skill's procedures for all resolved modules.
- Each module's expected state checks pass.
- If the change affects multiple menus, all affected modules are verified.

### What does NOT count

- Only running `bash -n` (syntax check ≠ runtime behavior).
- Only rebuilding bundles without entering the menu.
- Assuming the change works based on code reading alone.
