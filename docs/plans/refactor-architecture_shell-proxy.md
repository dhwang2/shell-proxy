# Refactoring Design Plan: Menu and Architecture

Last Updated: 2026-03-10

## 1. Current Status Analysis and Bottleneck Identification

### 1.1 Current Loading Chain

```
management.sh  ──source──>  env.sh (824 lines, path + manifest + cache tools)
       │
       └──source──>  base modules (4 files):
                       common_ops.sh
                       service_base_ops.sh
                       config_ops.sh          (837 lines, heavyweight)
                       runtime_status_ops.sh  (576 lines, heavyweight)
       │
       └──on-demand──>  menu bundles (pre-built) or individual modules (fallback)
```

**Total**: 59 module files, 17431 lines of code, 11 bundle groups.

### 1.2 Core Bottlenecks

| Bottleneck | Root Cause | Severity |
|------------|------------|----------|
| **Temp file storm during config rendering** | `render_singbox_json_with_compact_rule_lines()` creates 4+ temp files + multiple full `jq` serializations each time | **P0** |
| **Dashboard blocking** | 2 `systemctl is-active` calls + IP stack detection + shadowtls binding enumeration per render | **P0** |
| **Cascading cache invalidation** | Single user action → invalidates 7+ cache variables → triggers 5-10 full `jq` parsings | **P0** |
| **Redundant protocol inventory scanning** | `protocol_menu_cache_rebuild_sync()` calls 3 refreshes consecutively, each scanning independently | **P1** |
| **No incremental compilation for user routes** | `sync_user_template_route_rules()` compiles all rules every time, lacking single-user caching | **P1** |
| **Synchronous blocking on service restart** | Every config modification → config normalize + sanitize + systemctl restart all synchronous | **P1** |
| **Overhead of loading fragmented files** | 59 individual files, sourced one by one in fallback mode | **P2** |

### 1.3 User Experience Pain Points

- **Main menu first screen**: systemctl + IP detection → 200-500ms blank wait time.
- **After adding/deleting users**: config rebuild + service restart → 2-5s freeze.
- **Multi-protocol multi-user scenarios**: Cascading refreshes O(N×M) → 10s+ noticeable lag.

---

## 2. New Loading Boundary Design

### 2.1 Three-Layer Loading Model

```
Layer 0 — Bootstrap (≤50ms)
  env.sh (simplified to pure constants + manifest, stripping cache tool functions)
  core/bootstrap_ops.sh (merging 20 high-frequency functions from common_ops + service_base_ops)

Layer 1 — Dashboard (≤100ms)
  core/dashboard_ops.sh (merging display logic from runtime_status_ops)
  When cache hits, only `cat` the cache file, zero computation

Layer 2 — Menu Action (On-demand loading, after user selection)
  Each menu item maintains an independent bundle
  But the number of bundles is reduced from 11 to 8 (merged protocol + protocol_service; merged log + config_view)
```

### 2.2 File Merging Plan

Current 59 → Target **38** module files (36% reduction):

| Merge Group | Current Files | Merged Into | Lines Saved |
|-------------|---------------|-------------|-------------|
| core base | common_ops.sh + service_base_ops.sh | `core/bootstrap_ops.sh` | ~230 lines → ~200 lines |
| config rendering | config_ops.sh + singbox_render_ops.sh | `core/config_ops.sh` | ~1000 lines → ~800 lines |
| protocol install | protocol_install_ops + install_support + install_singbox_build | `protocol/protocol_install_ops.sh` | ~960 lines → ~750 lines |
| protocol support | protocol_support_ops + protocol_inventory_ops + protocol_runtime_ops | `protocol/protocol_runtime_ops.sh` | ~780 lines → ~600 lines |
| routing storage | routing_res_socks_ops + res_socks_query + res_socks_store | `routing/routing_res_socks_ops.sh` | ~860 lines → ~700 lines |
| routing config | routing_base_config + routing_render_ops | `routing/routing_config_ops.sh` | ~260 lines → ~200 lines |
| subscription system | subscription_ops + subscription_cache + subscription_target + subscription_surge + subscription_link | `subscription/subscription_ops.sh` | ~1200 lines → ~900 lines |
| sharing system | share_ops + share_link_ops + share_support_ops | `subscription/share_ops.sh` | ~580 lines → ~450 lines |
| service status | service_ops + service_status_ops + protocol_service_overview | `service/service_ops.sh` | ~690 lines → ~550 lines |
| log+config view | log_ops + config_view_ops | `runtime/log_ops.sh` | ~460 lines → ~380 lines |
| user batch | user_batch_ops + user_selector_ops + user_menu_support_ops | `user/user_ops.sh` | ~500 lines → ~400 lines |

### 2.3 Bundle Group Streamlining

Current 11 groups → Target **8 groups**:

```
base            — bootstrap_ops + config_ops + dashboard_ops
protocol        — protocol_install_ops + protocol_runtime_ops + protocol_*_ops
service         — service_ops (merged with former protocol_service)
user            — user_ops + user_meta + user_template + user_route + user_membership + user_data
routing         — all routing_*
share           — share_ops + subscription_ops
log_config      — log_ops (merged with former config_view)
system          — network_ops + core_ops + network_firewall_ops (merged with former core + network + uninstall)
```

---

## 3. New Cache Boundary Design

### 3.1 Cache Stratification

```
┌─────────────────────────────────────┐
│  L1 — In-memory cache (bash variables)│  Lifecycle: Intra-process
│  fingerprint, parsed results, status  │  Invalidation: Action triggered or TTL
├─────────────────────────────────────┤
│  L2 — Disk snapshot cache             │  Lifecycle: Cross-process
│  dashboard render, sub links, menu UI │  Invalidation: fingerprint change
├─────────────────────────────────────┤
│  L3 — Remote cache                    │  Lifecycle: TTL
│  GitHub release tag, branch commit    │  Invalidation: TTL expiration
└─────────────────────────────────────┘
```

### 3.2 Key Cache Improvements

#### 3.2.1 Dashboard Status Snapshot (New)

```bash
# Directory: $CACHE_DIR/snapshot/
# Files:
#   service-state.json    — One-time query of all service states
#   ip-stack.txt          — IP stack detection results
#   protocol-summary.txt  — Protocol summary
# 
# Refresh strategy:
# - service-state: Refreshed once per menu entry, reused within the menu loop
# - ip-stack: TTL 3600s (NIC changes are extremely rare)
# - protocol-summary: Refreshed when fingerprint($CONF_FILE) changes
```

**Implementation focal points**: When rendering Dashboard, strictly read snapshot files, zero `systemctl` calls.

#### 3.2.2 Unified Fingerprint Aggregation (New)

```bash
# Current problem: calc_file_fingerprint() is independently called 20+ times
# New plan: Perform a "fingerprint sweep" once before entering the menu loop

proxy_refresh_fingerprint_sweep() {
    # For critical files like conf_file, user_meta_db, route_rules
    # Calculate once and cache into PROXY_FILE_FP_CACHE
    # All subsequent functions read from cache
}
```

#### 3.2.3 Incremental Compilation for User Routes (New)

```bash
# Current: sync_user_template_route_rules() compiles all rules
# New plan: Cache compiled results per user

# $CACHE_DIR/user-routes/<user_id>.compiled.json
# fingerprint = hash(user_template + user_route_rules + global_routing)
# Recompile this user only when the fingerprint changes
```

#### 3.2.4 Config Render Pipelining (Replace Temp Files)

```bash
# Current: 4 mktemp + step-by-step processing
# New plan: Single-pipeline jq stream

render_singbox_config_pipeline() {
    jq --from-file "$RENDER_FILTER" "$conf_file" \
        | compact_rule_lines_awk
    # Zero temp files, single jq call
}
```

### 3.3 Unified Cache Invalidation Entry

```bash
# Current problem: 7+ refresh functions each act independently, triggering each other
# New plan: Trigger once cohesively after operations are done

proxy_invalidate_after_mutation() {
    local scope="$1"   # user | protocol | routing | config
    case "$scope" in
        user)
            PROXY_USER_META_FP=""
            PROXY_USER_DERIVED_FP=""
            ;;
        protocol)
            PROXY_PROTOCOL_INVENTORY_FP=""
            PROXY_PORT_MAP_FP=""
            ;;
        routing)
            PROXY_ROUTING_CONTEXT_FP=""
            ;;
        config)
            # Invalidate all
            PROXY_USER_META_FP="" PROXY_PROTOCOL_INVENTORY_FP="" PROXY_ROUTING_CONTEXT_FP=""
            ;;
    esac
    # Do not rebuild immediately — Lazy rebuilding: rebuild only upon finding empty values during the next read
}
```

---

## 4. Menu State Flow Design

### 4.1 Current State Flow (Problem)

```
show_main_menu  ─loop─>  ui_clear
                          │
                          ├─ print_dashboard (Synchronous: systemctl×2 + IP check + protocol enumeration)
                          ├─ render_main_menu_items
                          ├─ read input
                          ├─ dispatch_main_menu_choice
                          │    └─ load_named_menu_modules (Synchronous loading)
                          │    └─ handler() (Synchronous execution: config rebuild + service restart)
                          └─ Back to loop (All states discarded, recalculated next round)
```

### 4.2 New State Flow

```
run_cli_command("menu")
  │
  ├─ fingerprint_sweep()                    # One-time fingerprint collection
  ├─ snapshot_service_state()               # One-time service state collection → L2 cache
  ├─ prewarm_schedule()                     # Background prewarming for share/routing
  │
  └─ show_main_menu ─loop─>  ui_clear
                               │
                               ├─ proxy_main_menu_print()
                               │    └─ Hit L2 cache → cat (0ms)
                               │    └─ Miss → render + write cache
                               │
                               ├─ read input
                               │
                               ├─ dispatch_main_menu_choice
                               │    ├─ load_named_menu_modules (bundle, ≤30ms)
                               │    ├─ handler()
                               │    │    ├─ Data mutation operations
                               │    │    ├─ proxy_invalidate_after_mutation("scope")
                               │    │    └─ config_apply_async()     # Async: normalize + restart
                               │    │         └─ Executed in background child process
                               │    │         └─ Foreground immediately displays "Applying config..."
                               │    │         └─ Check completion status on next dashboard render
                               │    │
                               │    └─ Return to menu loop
                               │
                               └─ (Snapshot expired?) → Incremental refresh of fingerprints + snapshots
```

### 4.3 Asynchronous Config Application (Core Improvement)

```bash
config_apply_async() {
    local conf_file="$1"
    local apply_lock="$CACHE_DIR/apply.lock"
    local apply_log="$CACHE_DIR/apply.log"

    (
        flock -n 9 || exit 0
        # Background execution:
        normalize_singbox_top_level_key_order "$conf_file"
        systemctl restart sing-box 2>&1
        # Write completion marker
        echo "done:$(date +%s)" > "$CACHE_DIR/apply.status"
    ) 9>"$apply_lock" >"$apply_log" 2>&1 &

    # Foreground returns immediately
    green "⟳ Applying config..."
}
```

### 4.4 Minimalist UI Animations (Objective 4)

```bash
# Minimalist spinner (non-blocking)
proxy_spinner_start() {
    local msg="${1:-}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    PROXY_SPINNER_PID=""
    (
        local i=0
        while true; do
            printf '\r  %s %s' "${frames[$((i % ${#frames[@]}))]}" "$msg"
            sleep 0.1
            ((i++))
        done
    ) &
    PROXY_SPINNER_PID=$!
}

proxy_spinner_stop() {
    [[ -n "${PROXY_SPINNER_PID:-}" ]] && kill "$PROXY_SPINNER_PID" 2>/dev/null || true
    PROXY_SPINNER_PID=""
    printf '\r\033[K'
}

# Menu dividers using Unicode box drawing
proxy_menu_divider() {
    local width="${1:-45}"
    printf '  %s\n' "$(printf '─%.0s' $(seq 1 "$width"))"
}

# Status indicators
proxy_status_dot() {
    case "$1" in
        active)  printf '\033[32m●\033[0m' ;;  # Green dot
        failed)  printf '\033[31m●\033[0m' ;;  # Red dot
        *)       printf '\033[90m○\033[0m' ;;  # Grey circle
    esac
}
```

---

## 5. Phased Rollout Plan

### Phase 1 — Quick Wins (Eliminate P0 Blockers) ✅ Completed

*Scope*: No structural file changes, only modify hot path implementations.

1. ✅ **Config Render Pipelining**: Rewrote `render_singbox_json_with_compact_rule_lines()` — 4 temp files reduced to 1.
2. ✅ **Dashboard Status Snapshot**: Added `proxy_refresh_service_state_cache()` + 3s TTL.
3. ✅ **IP Stack Detection TTL**: Cached `detect_server_ip_stack()` results for 3600s.
4. ✅ **Fingerprint Sweep**: Added `proxy_fingerprint_sweep()` for one-time prefill at the main menu entry.

### Phase 2 — Cache Refactoring (Eliminate P1 Cascades) ✅ Completed

1. ✅ **Unified Cache Invalidation Entry**: `proxy_invalidate_after_mutation(scope)` — supports user/protocol/routing/config scopes.
2. ✅ **Protocol Inventory Deduplication**: `proxy_protocol_occupied_ports_cache_refresh()` skips generating inventory if cached.
3. ✅ **Lazy Cache Invalidation**: `proxy_user_meta_db_refresh_caches()` changed to only clear FP sentinels, rather than eagerly clearing associative arrays.
4. ✅ **Spinner Wrapping for Service Restarts**: `restart_singbox_if_present()` now uses `proxy_run_with_spinner` to show progress.
5. ✅ **Fast Unit Detection**: `restart_singbox_if_present()` utilizes `is-enabled`/`is-active` instead of `list-unit-files | grep`.

**Actual Effect**: Service restarting after operations transitioned from "unresponsive lag" to "feedback with spinner animation"; cascading cache invalidation shifted from eager scrubbing to lazy checking.

### Phase 3 — File Merging and UI Optimization ✅ Completed

1. ✅ **Module File Merging**: 59 → 39 files (including new `core/cache_ops.sh`).
2. ✅ **Bundle Group Streamlining**: 11 → 8 groups (`protocol_service` → `service`; `log` + `config_view` → `log_config`; `core` + `network` + `uninstall` → `system`).
3. ✅ **Slimming env.sh**: Cache utility functions stripped into `modules/core/cache_ops.sh`, reducing env.sh from 790 to 714 lines.
4. ✅ **UI Unification**: `proxy_status_dot()` centralized into `common_ops.sh`; `service_ops.sh` and `runtime_status_ops.sh` switched to using unified interfaces.

**Actual Effect**: Bundle count reduced from 11 to 8; env.sh trimmed by -76 lines; status indicators unified to `proxy_status_dot()`.

### Phase 4 — Regression Verification ✅ Completed

1. ✅ Full protocol install/uninstall regression.
2. ✅ Multi-user (5+) CRUD regression.
3. ✅ Routing-rule addition/deletion regression.
4. ✅ Subscription link generation regression.
5. ✅ Bundle rebuilding regression after self-updating.
6. ✅ Fallback verification with no bundles.

## 6. Risks and Constraints

- **Backward Compatibility**: Self-update scenarios must handle the transition between old bundles ↔ new modules; `self_update.sh` requires synchronized revamping.
- **Atomicity**: Asynchronous config application needs locking mechanisms to prevent concurrent applies.
- **Fallback Capability**: All merging retains function signatures unchanged, calling sources don't need modification.
- **Single Source of Truth in env.sh**: Manifest alterations must be synced fully alongside file merges.

---

## 7. Architecture Status Check & Phase 5 Acceptance (2026-03-10)

### 7.1 Overall Assessment

The current architecture is fundamentally sound, with all five phase goals shipped. Full acceptance conclusions follow below.

### 7.2 Accepted Design Points (Phase 1-4 + Phase 5)

| Design Point | Status | Description |
|--------------|--------|-------------|
| Three-layer loading model | ✅ Normal | Bootstrap→Base→On-demand clear stratification, complete fallback capabilities. |
| Source deduplication guards | ✅ Normal | Independent `PROXY_SOURCED_FILE_GUARD` in both `management.sh` and bundle builds. |
| Fingerprint sweep | ✅ Normal | Executed at `run_cli_command("menu")` entry, covering conf/user_meta/user_template/snell_conf. |
| Service state snapshot cache | ✅ Normal | Pre-filled by `proxy_refresh_service_state_cache()` at menu entry, invalidated via `proxy_invalidate_service_state_cache()` after operations. |
| Lazy cache invalidation | ✅ Normal | `proxy_invalidate_after_mutation(scope)` supports user/protocol/routing/config. |
| Main menu view caching | ✅ Normal | Checking code fingerprint alongside 5s TTL, 0-computation upon hit. |
| Prewarm background scheduling | ✅ Normal | `proxy_menu_prewarm_schedule()` prewarms share/routing cache in the background for multicpu setups. |
| Incremental download updates | ✅ Normal | `self_update.sh` uses GitHub Trees API for git blob SHA diffing, only downloading changed files (8 concurrent threads). |
| Automatic bundle rebuilds | ✅ Normal | Upon update, `proxy_changed_rel_paths_require_menu_bundle_rebuild()` checks env.sh/modules/*.sh changes and triggers full rebuild. |
| Special loading for autoconfig modules | ✅ Normal | `routing_autoconfig_ops.sh` loads on-demand via `ensure_menu_autoconfig_module_loaded()`, not in the base bundle. |
| **Main menu fingerprint completeness** | ✅ **Fixed** | `proxy_main_menu_view_code_fingerprint()` now covers management.sh + env.sh + all base module files. |
| **Module file count target achieved** | ✅ **Done** | `proxy_all_module_rel_paths` total 38 module files, hitting target (+1 new `bundle_build_ops.sh`, merged 5 old files). |
| **Decoupling of bundle build logic** | ✅ **Done** | Heredoc for `proxy_rebuild_menu_bundle` extracted to `modules/core/bundle_build_ops.sh`, lazy-loaded via `proxy_load_bundle_build_ops()` in env.sh; env.sh trimmed down from 714 lines to **439 lines** (-39%). |
| **Asynchronous config application** | ✅ **Done** | Complete logic for `config_apply_async()` + `config_apply_async_worker()` + `proxy_check_pending_apply_status()` integrated into `bootstrap_ops.sh`; check invoked at top of `proxy_main_menu_print()`; toggled by `PROXY_CONFIG_APPLY_MODE` (default sync, set to async to enable). |
| **Fallback contract documentation** | ✅ **Done** | Detailed header comments in `proxy_menu_module_rel_paths()`; newly added `proxy_menu_fallback_entry_rel_path()` and `proxy_assert_menu_fallback_contract()` as mandatory helpers to verify the contract explicitly. |

### 7.3 Final Metrics Comparison Across Phases

| Metric | Starting Value | Phase 3 Target | Current Measured Value |
|--------|----------------|----------------|------------------------|
| Module File Count | 59 | 38 | **38** ✅ |
| env.sh Line Count | ~824 | — | **450** (-45%; including new fallback contract helpers) |
| Bundle Group Count | 11 | 8 | **8** ✅ |
| Main Menu Fingerprint Coverage | 2 files | — | **management.sh + env.sh + all base modules** ✅ |
| Service Restart Interaction | Sync Blocking | Async | **Optional Async** (`PROXY_CONFIG_APPLY_MODE=async`) ✅ |

### 7.4 Breakdown of Phase 5 Merged Items

| Merged File | Merge Target |
|-------------|--------------|
| `protocol_install_support_ops.sh` | → `protocol_install_singbox_ops.sh` |
| `protocol_install_singbox_build_ops.sh` | → `protocol_install_singbox_ops.sh` |
| `protocol_certificate_ops.sh` | → `protocol_tls_ops.sh` |
| `protocol_service_overview_ops.sh` | → `service_ops.sh` |
| `runtime_shadowtls_ops.sh` | → `runtime_status_ops.sh` or `service_ops.sh` |
| Bundle Build Heredoc (inline env.sh) | → `modules/core/bundle_build_ops.sh` (new) |

### 7.5 Implementation Details of `config_apply_async` (Verified)

- **Status File Format**: `pending:<ts>:<request_id>` / `done:<ts>` / `failed:<ts>` (Colon-separated triple fields, request_id used for race condition detection).
- **Locking Mechanism**: Prioritizes using `flock -n`, downgrades to `mkdir` directory lock (compatible with non-flock environments).
- **Last-Writer-Wins**: After worker completes restart, checks status files. If a new pending request is found (written by the following operation), loop execution recurs to avoid lost applies.
- **Toggles**: Setting `PROXY_CONFIG_APPLY_MODE=async` switches to async mode; defaulting to `sync` to maintain legacy behavior ensuring a smooth switch.
- **Dashboard Integration**: Checks `proxy_check_pending_apply_status()` right at the top of `proxy_main_menu_print()`, showing "⟳ Applying config..." / "✗ Last config apply failed"; files auto-clean on `done` status.

### 7.6 Sign-off Confirmation (2026-03-10)

All leftover items fully actioned; zero unresolved entries.

**Fallback Contract Documentation (P3) — Completed**:
- `proxy_menu_module_rel_paths()` function header amended with detailed contractual comments, dictating responsibility boundaries of dependency management between the fallback and bundle modes.
- Added remarks "Bundle build expands the fallback entry into the full dependency set" directly to the `proxy_bundle_source_module_rel_paths` endpoints of `user`, `routing`, and `share` groups.
- Added `proxy_menu_fallback_entry_rel_path(group)` — Returns canonical fallback entry pathways for all groups.
- Added `proxy_assert_menu_fallback_contract(group, actual_rel)` — Assertive checks during CI or debugging to prove the fallback complies with the contract, lifting the implicit agreement to an explicitly verifiable state.

---

## 8. Phase 6 — CPU Hotspot Elimination (Based on 2026-03-11 Monitoring Report)

> **Source**: `docs/tmp/proxy-cpu-monitoring-report-2026-03-11.md`
> **Monitoring window**: 3m18s live session, 0.5s sampling via `ps -L`

### 8.1 Monitoring Findings Summary

The CPU monitoring captured a full interactive session (idle → user menus → config view → protocol install → flush/apply → exit). The dominant CPU consumers were **not** the top-level shell but short-lived `jq` subprocesses:

| Peak Event | CPU | Code Path | Root Cause |
|------------|-----|-----------|------------|
| SS inbound port check | 176% | `shadowtls_backend_type_by_target_port()` | Full `.inbounds[]` scan per port |
| Config pretty-print | 133% | `show_config_details()` via `jq -C -c .` | Full conf serialization |
| User name extraction (×N) | 100-118% | `proxy_user_membership_explicit_name()` | Per-user `jq -r '.name // ""'` with no cache |
| Batched metadata writeback | 94% | `proxy_user_meta_apply_protocol_memberships_batch()` | Full user-management.json rewrite |
| Membership fingerprint | 94% | `proxy_user_membership_cache_fingerprint()` | `jq -c '{name, disabled}'` on metadata |
| Reality keypair derivation | 60% | `resolve_reality_public_key()` | `sing-box generate reality-keypair` |
| Nested bash orchestration | 59% | Shell-side cache refresh chain | Multiple subshell spawns for metadata sync |

**Key insight**: The top-level shell is lightweight (0-0.6% CPU). All cost is in subprocess-heavy `jq` invocations during user metadata resolution and post-install flush paths.

### 8.2 Hotspot Analysis and Proposed Fixes

#### 8.2.1 Per-User `jq` Name Extraction (P0 — Highest Frequency)

**Current state**: `proxy_user_membership_explicit_name()` (`user_membership_ops.sh:134`) spawns `jq -r '.name // ""'` per membership entry. Called from two tight loops:
- `proxy_user_derived_cache_refresh()` (line 379) — iterates all membership lines
- `proxy_user_group_sync_from_memberships()` (line 471) — iterates all membership lines

With N users × M protocols, this spawns N×M `jq` subprocesses per cache rebuild.

**Proposed fix**: Extract `.name` during the initial `jq` scan in `proxy_user_collect_membership_lines_uncached()` where user JSON is already being parsed. The membership line format already carries `raw_name_b64` (field position after `in_tag`). Shift `proxy_user_membership_explicit_name()` to decode the pre-extracted name from the membership line instead of re-parsing user JSON.

```bash
# Before (per-user jq spawn):
explicit_name="$(proxy_user_decode_b64 "$user_b64" | jq -r '.name // ""' 2>/dev/null || true)"

# After (decode pre-extracted field, zero jq):
explicit_name="$(proxy_user_decode_b64 "$raw_name_b64" 2>/dev/null || true)"
# Fall back to meta cache only if raw_name is empty
```

**Impact**: Eliminates N×M `jq` subprocess spawns per cache rebuild. Reduces user-menu entry CPU from ~100% to near-zero for name resolution.

#### 8.2.2 Post-Install Flush Chain Compression (P0 — Highest Single-Event Cost)

**Current state**: `protocol_install_session_apply_pending_metadata()` (`protocol_install_singbox_ops.sh:758`) triggers:
1. `proxy_user_meta_apply_protocol_memberships_batch()` — rewrites `user-management.json` with full `jq --rawfile` (94% CPU)
2. `sync_user_template_route_rules()` — recompiles all user routes + potentially restarts sing-box
3. Post-sync triggers `routing_status_schedule_refresh_all_contexts()` (background)

The route sync internally calls `proxy_user_route_unique_auth_users()` → `proxy_user_collect_membership_lines()` → re-reads the metadata that was just written.

**Proposed fix — two-stage**:
1. **Invalidate membership cache after metadata batch write**: After `proxy_user_meta_apply_protocol_memberships_batch()` completes, explicitly clear `PROXY_USER_MEMBERSHIP_CACHE_FP` so the next `proxy_user_collect_membership_lines()` call rebuilds from the fresh file rather than using stale in-memory data.
2. **Skip redundant fingerprint rebuild in sync**: `sync_user_template_route_rules()` already has a `sync_input_fp` short-circuit. Ensure the post-install path supplies a pre-computed fingerprint so the sync can detect "nothing changed in routing inputs" and skip recompilation when only membership metadata (not routing templates) changed.

**Impact**: Reduces post-install flush from ~30s (observed in u-2-93) to the minimum: one metadata write + one route sync check (short-circuit if no routing changes).

#### 8.2.3 Structured JSON Snapshot for Metadata Reads (P1 — Repeated File Reads)

**Current state**: Multiple functions independently read `user-management.json`:
- `proxy_user_membership_cache_fingerprint()` — `jq -c '{name, disabled}'`
- `proxy_user_group_list()` — `jq -r '.groups // {} | to_entries | ...'`
- `proxy_user_meta_value_cache_refresh()` — `jq -r 'to_entries[] | ...'`
- `proxy_user_meta_apply_protocol_memberships_batch()` — `jq --rawfile rows ...`

Each call reads and parses the full file independently.

**Proposed fix**: Introduce a single-read structured snapshot:

```bash
proxy_user_meta_snapshot_refresh() {
    local current_fp
    current_fp="$(calc_file_meta_signature "$USER_META_DB_FILE" 2>/dev/null || true)"
    [[ "$PROXY_USER_META_SNAPSHOT_FP" != "$current_fp" ]] || return 0

    # Single jq call extracts all needed fields
    eval "$(jq -r '
        @text "PROXY_USER_META_SNAPSHOT_NAMES=\(.name // {} | tojson)"
        , @text "PROXY_USER_META_SNAPSHOT_GROUPS=\(.groups // {} | tojson)"
        , @text "PROXY_USER_META_SNAPSHOT_DISABLED=\(.disabled // {} | tojson)"
        , @text "PROXY_USER_META_SNAPSHOT_TEMPLATE=\(.template // {} | tojson)"
    ' "$USER_META_DB_FILE" 2>/dev/null)"
    PROXY_USER_META_SNAPSHOT_FP="$current_fp"
}
```

Downstream functions query the in-memory snapshot variables instead of re-parsing the file.

**Impact**: Collapses 4+ independent `jq` reads of `user-management.json` into 1 per fingerprint change.

#### 8.2.4 Reality Public-Key Disk Persistence (P2 — Moderate Single-Event Cost)

**Current state**: `resolve_reality_public_key()` (`share_ops.sh:660`) has in-memory cache (`REALITY_PUBLIC_KEY_CACHE`), but the cache is lost across process boundaries. Each new menu session or background subshell re-derives the public key via `sing-box generate reality-keypair` (60% CPU, ~0.5s).

**Proposed fix**: Add disk persistence alongside the in-memory cache:

```bash
# Cache file: $CACHE_DIR/reality-pubkey/<fingerprint_of_private_key>.txt
# On hit: read from disk (0ms)
# On miss: derive via sing-box, write to disk + memory
```

**Impact**: Reality public-key derivation becomes a one-time cost per private key. Subscription/share rendering in subsequent sessions or background jobs hits disk cache.

#### 8.2.5 Route Count Snapshot Reuse (P2 — Low Frequency, Moderate Cost)

**Current state**: `get_route_rule_count()` (`runtime_status_ops.sh:422`) runs a 3-level jq filter on the full conf_file. Called during dashboard rendering. The dashboard itself has caching, but after install flush the fingerprint changes and forces a rebuild.

**Proposed fix**: Compute and cache the route count as a side-effect of `sync_user_template_route_rules()` which already has the compiled rules in memory. Write the count to `$CACHE_DIR/snapshot/route-rule-count.txt`. Dashboard reads the cached count instead of re-parsing conf_file.

**Impact**: Eliminates one full-conf jq parse per dashboard rebuild after operations.

#### 8.2.6 Background Job Concurrency Control (P1 — Already Fixed in u-2-99)

**Status**: ✅ Completed. Both unlocked per-loop-iteration warmup jobs now have mkdir-based locks:
- `user_ops.sh:75` — `proxy_user_group_sync_from_memberships` lock
- `routing_menu_support_ops.sh:362` — `routing_prepare_target_user_selection_context` lock

### 8.3 Execution Priority

| Priority | Fix | Expected Impact | Complexity |
|----------|-----|-----------------|------------|
| **P0** | 8.2.1 Per-user jq name extraction | -100% CPU on user-menu entry | Low |
| **P0** | 8.2.2 Post-install flush chain compression | -50% flush time | Medium |
| **P1** | 8.2.3 Structured JSON snapshot | -75% metadata jq calls | Medium |
| **P1** | 8.2.6 Background job concurrency | ✅ Done (u-2-99) | — |
| **P2** | 8.2.4 Reality pubkey disk cache | -60% CPU on first share render | Low |
| **P2** | 8.2.5 Route count snapshot reuse | -1 jq parse per dashboard rebuild | Low |

### 8.4 Acceptance Criteria

1. User menu entry (list/rename/delete) triggers zero `jq` subprocesses for name resolution.
2. Post-install flush completes in ≤15s for a 6-protocol session (was 30s+ before u-2-93 fixes).
3. Repeated dashboard renders after operations reuse cached route counts.
4. Reality public-key derivation runs at most once per private key per host lifetime.
5. No background warmup jobs accumulate beyond 1 concurrent instance per family.
