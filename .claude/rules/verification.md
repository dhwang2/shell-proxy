# shell-proxy Verification Specifications

## Verification Tiers

Agent must select the appropriate tier based on the complexity and scope of fix points.

### Tier 1 — Syntax Validation (every change)

Mandatory for all code modifications, no exceptions.

- `bash -n` on every modified `.sh` file.
- `git diff --check` for whitespace issues.

### Tier 2 — Minimum Real-World Verification (targeted fixes)

When: single-module bug fixes, localized logic changes, style adjustments.

1. **Fix-point verification**: Execute the specific code path affected by the change and confirm correct behavior.
2. **Adjacent-path smoke test**: For functionalities strongly coupled to the fix point, run a single-pass verification of their core operations (e.g., if a protocol install function changed, also verify protocol list/status still works).

Scope boundary: only the modified module and its direct callers.

### Tier 3 — Real-World Regression Verification (feature enhancements, cross-module changes)

When: new features, module refactors, changes touching `app/env.sh` manifest, cross-module dependency changes, or any change spanning 3+ files.

Based on Script Functionality Enhancement Specification — traverse all core functionalities:

1. **Installation flow**: Use actual installation commands for a genuine installation process.
2. **Menu interaction simulation**: Walk through the interactive menu to verify navigation and option rendering.
3. **User management**: Add user → verify user appears in listings and config.
4. **Protocol operations**: Add protocol → verify service starts → verify runtime status → uninstall protocol → verify clean removal.
5. **Routing rules**: Add traffic routing rules → verify rules apply → verify config reflects changes.
6. **Subscription verification**: View subscription links → verify config file content matches expectations.
7. **Self-update**: Trigger script update flow → verify version and file integrity post-update.

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

1. Deploy modified files to the target server (SCP + copy to `/etc/shell-proxy/modules/`).
2. Rebuild bundles (`proxy_rebuild_menu_bundles_impl`).
3. Enter the affected menu flow(s) and interact with them — confirm prompts render correctly, inputs work, and no display artifacts appear.
4. Document the verification result in the workflow entry's **Verification** section.

### What counts as verification

- Navigating into the modified menu and confirming the prompt/display renders correctly.
- Completing at least one full interaction cycle (select option → see result → return).
- If the change affects multiple menus, verify each affected menu.

### What does NOT count

- Only running `bash -n` (syntax check ≠ runtime behavior).
- Only rebuilding bundles without entering the menu.
- Assuming the change works based on code reading alone.
