---
name: shell-proxy-verify
description: Structured real-world verification for shell-proxy via server menu interaction
---

# Shell-Proxy Verification Skill

Structured, modular verification procedures for shell-proxy changes that require real-world server menu interaction (Tier 2 and Tier 3).

## Invocation Interface

**Parameters:**
- `tier` (required): `2` or `3`
- `changed-files` (required): list of modified paths relative to `app/`

**Workflow:**
1. Map changed files → affected VM modules (via [file-module-map](references/file-module-map.md))
2. Resolve dependencies (via [dependency-graph](references/dependency-graph.md))
3. Tier 2: affected modules + direct dependents only
4. Tier 3: full topological traversal (skip VM-12 unless explicitly requested)
5. Execute pre-flight, then modules in dependency order

## Pre-flight (Common to All Modules)

Run before any module verification:

1. **Deploy** modified files to server `/etc/shell-proxy/`
2. **Rebuild bundles**: source `env.sh` + `bundle_build_ops.sh`, call `proxy_rebuild_menu_bundles_impl`
3. **Validate JSON configs**: `jq . /etc/shell-proxy/conf/sing-box.json`

## Verification Modules

### VM-01 — 安装协议 (Menu 1: Install Protocol)

| Field | Value |
|-------|-------|
| **Handler** | `add_protocol` |
| **Bundle group** | `protocol` |
| **Source files** | `modules/protocol/protocol_ops.sh`, `protocol_install_singbox_ops.sh`, `protocol_shadowtls_setup_ops.sh`, `protocol_port_ops.sh`, `protocol_tls_ops.sh`, `protocol_runtime_ops.sh` |
| **Tags** | `Function:Trojan-Install`, `Function:VLESS-Install`, `Function:TUIC-Install`, `Function:AnyTLS-Install`, `Function:SS-Install`, `Function:Snell-Install` |
| **Dependencies** | VM-03 |

**Procedures:**
1. Enter main menu → select `1` (安装协议)
2. Select a protocol type (e.g., Trojan)
3. Follow prompts: port, password/UUID, TLS settings
4. **Expected state checks:**
   - `systemctl status <protocol-service>` shows active
   - `ss -tuln | grep <port>` shows listening
   - `jq '.inbounds' /etc/shell-proxy/conf/sing-box.json` includes the new inbound

### VM-02 — 卸载协议 (Menu 2: Uninstall Protocol)

| Field | Value |
|-------|-------|
| **Handler** | `remove_protocol` |
| **Bundle group** | `protocol` |
| **Source files** | `modules/protocol/protocol_ops.sh`, `protocol_runtime_ops.sh` |
| **Tags** | `Function:Protocol-Uninstall` |
| **Dependencies** | VM-01 |

**Procedures:**
1. Enter main menu → select `2` (卸载协议)
2. Select protocol to uninstall
3. Confirm removal
4. **Expected state checks:**
   - Protocol removed from `sing-box.json` inbounds
   - Port freed: `ss -tuln | grep <port>` shows nothing
   - Service stopped: `systemctl is-active <service>` returns inactive

### VM-03 — 用户管理 (Menu 3: User Management)

| Field | Value |
|-------|-------|
| **Handler** | `manage_users` |
| **Bundle group** | `user` |
| **Source files** | `modules/user/user_ops.sh`, `user_meta_ops.sh`, `user_template_ops.sh`, `user_route_ops.sh`, `user_membership_ops.sh`, `user_batch_ops.sh` |
| **Tags** | `Function:User-List`, `Function:User-Add`, `Function:User-Reset`, `Function:User-Delete` |
| **Dependencies** | none (foundational) |

**Procedures:**
1. Enter main menu → select `3` (用户管理)
2. List existing users → verify display renders
3. Add a new user → enter username, select group
4. **Expected state checks:**
   - `user-management.json` updated with new user entry
   - User appears in group listing
5. Reset user password → confirm new credentials
6. Delete user → confirm removal from `user-management.json`

### VM-04 — 分流管理 (Menu 4: Routing Management)

| Field | Value |
|-------|-------|
| **Handler** | `manage_routing_menu` |
| **Bundle group** | `routing` |
| **Source files** | `modules/routing/routing_ops.sh`, `routing_menu_support_ops.sh`, `routing_rule_menu_ops.sh`, `routing_core_ops.sh`, `routing_context_ops.sh`, `routing_autoconfig_ops.sh`, `routing_preset_ops.sh`, `routing_res_socks_ops.sh`, `routing_test_ops.sh` |
| **Tags** | `Function:Chain-Proxy`, `Function:Route-Rule`, `Function:Direct-Outbound`, `Function:Route-Test` |
| **Dependencies** | VM-01 |

**Procedures:**
1. Enter main menu → select `4` (分流管理)
2. Add/modify routing rules → select rule type, configure parameters
3. Test route resolution
4. **Expected state checks:**
   - `routing_rules.json` reflects changes
   - `user-route-rules.json` updated for per-user rules
   - `jq '.route' /etc/shell-proxy/conf/sing-box.json` includes new rules

### VM-05 — 协议管理 (Menu 5: Protocol Service Management)

| Field | Value |
|-------|-------|
| **Handler** | `manage_protocol_services` |
| **Bundle group** | `service` |
| **Source files** | `modules/service/service_ops.sh`, `modules/protocol/protocol_ops.sh` |
| **Tags** | `Function:Service-Restart`, `Function:Service-Stop`, `Function:Service-Start`, `Function:Service-Status` |
| **Dependencies** | VM-01 |

**Procedures:**
1. Enter main menu → select `5` (协议管理)
2. View service status → verify all installed protocols listed
3. Stop a service → confirm `systemctl is-active` returns inactive
4. Start a service → confirm `systemctl is-active` returns active
5. Restart a service → confirm no errors, service active

### VM-06 — 订阅管理 (Menu 6: Subscription Management)

| Field | Value |
|-------|-------|
| **Handler** | `manage_share` |
| **Bundle group** | `share` |
| **Source files** | `modules/subscription/share_ops.sh`, `share_meta_ops.sh`, `subscription_ops.sh`, `subscription_target_ops.sh` |
| **Tags** | `Function:Subscription-View`, `Function:Subscription-Generate` |
| **Dependencies** | VM-01, VM-03 |

**Procedures:**
1. Enter main menu → select `6` (订阅管理)
2. View subscription links → verify URLs render
3. Generate/refresh subscription → verify output
4. **Expected state checks:**
   - `subscription.txt` updated with valid content
   - `caddy-sub` service active: `systemctl is-active caddy-sub`

### VM-07 — 查看配置 (Menu 7: View Configuration)

| Field | Value |
|-------|-------|
| **Handler** | `show_config_details` |
| **Bundle group** | `log_config` |
| **Source files** | `modules/runtime/log_ops.sh` |
| **Tags** | `Function:Config-View-Singbox`, `Function:Config-View-Snell`, `Function:Config-View-ShadowTLS` |
| **Dependencies** | VM-01 |

**Procedures:**
1. Enter main menu → select `7` (查看配置)
2. Select config to view (sing-box, snell, shadow-tls)
3. **Expected state checks:**
   - Output renders without error
   - JSON output is valid (parseable by `jq`)

### VM-08 — 运行日志 (Menu 8: Runtime Logs)

| Field | Value |
|-------|-------|
| **Handler** | `show_status_and_logs` |
| **Bundle group** | `log_config` |
| **Source files** | `modules/runtime/log_ops.sh`, `modules/runtime/runtime_status_ops.sh` |
| **Tags** | `Function:Log-View` |
| **Dependencies** | VM-01 |

**Procedures:**
1. Enter main menu → select `8` (运行日志)
2. View logs for installed protocol
3. **Expected state checks:**
   - Output renders without error
   - Log entries displayed (not empty, no stack traces)

### VM-09 — 内核管理 (Menu 9: Core Management)

| Field | Value |
|-------|-------|
| **Handler** | `manage_core` |
| **Bundle group** | `system` |
| **Source files** | `modules/core/core_ops.sh`, `modules/core/release_ops.sh` |
| **Tags** | `Function:Core-Version`, `Function:Core-Check-Update`, `Function:Core-Update` |
| **Dependencies** | none |

**Procedures:**
1. Enter main menu → select `9` (内核管理)
2. View current core version → verify version string displayed
3. Check for updates → verify update check completes
4. (Optional) Apply update → verify new version active

### VM-10 — 网络管理 (Menu 10: Network Management)

| Field | Value |
|-------|-------|
| **Handler** | `manage_network_management` |
| **Bundle group** | `system` |
| **Source files** | `modules/network/network_ops.sh`, `modules/network/network_firewall_ops.sh` |
| **Tags** | `Function:BBR-Optimize`, `Function:Firewall-Harden` |
| **Dependencies** | none |

**Procedures:**
1. Enter main menu → select `10` (网络管理)
2. View BBR status → verify sysctl output
3. View firewall rules → verify iptables state
4. **Expected state checks:**
   - `sysctl net.ipv4.tcp_congestion_control` reflects expected value
   - `iptables -L` shows expected rules

### VM-11 — 脚本更新 (Menu 11: Self-Update)

| Field | Value |
|-------|-------|
| **Handler** | `update_self` |
| **Bundle group** | (none — directly in management.sh) |
| **Source files** | `self_update.sh`, `modules/core/bootstrap_ops.sh` |
| **Tags** | `Function:Self-Update` |
| **Dependencies** | none |

**Procedures:**
1. Enter main menu → select `11` (脚本更新)
2. Trigger update flow
3. **Expected state checks:**
   - `.script_source_ref` updated with new version/commit
   - Script files refreshed on disk

### VM-12 — 卸载服务 (Menu 12: Full Uninstall)

| Field | Value |
|-------|-------|
| **Handler** | `uninstall_service` |
| **Bundle group** | `system` |
| **Source files** | `modules/service/service_ops.sh` |
| **Tags** | `Function:Full-Uninstall` |
| **Dependencies** | none (destructive — always last, optional) |

**Procedures:**
1. Enter main menu → select `12` (卸载服务)
2. Confirm uninstall prompt
3. **Expected state checks:**
   - All proxy services removed: `systemctl list-units | grep -E 'sing-box|snell|shadow-tls|caddy-sub|proxy-watchdog'` returns nothing
   - `/etc/shell-proxy/` directory cleaned or removed

> **WARNING**: VM-12 is destructive and irreversible. Only execute when explicitly requested. Always execute last.

## Tier Mapping

### Tier 2 — Targeted Verification

Execute: affected module(s) + direct dependents only.

Example: if `modules/user/user_ops.sh` changed → VM-03 (affected) + VM-01, VM-06 (direct dependents of VM-03).

### Tier 3 — Full Regression

Execute all modules in topological order, skipping VM-12 unless explicitly requested:

**VM-03 → VM-01 → VM-05 → VM-04 → VM-06 → VM-07 → VM-08 → VM-02 → VM-09 → VM-10 → VM-11 → (VM-12 optional)**

## Foundational File Rule

Changes to foundational files automatically trigger Tier 3:
- `env.sh`, `management.sh`, `install.sh`, `bootstrap.sh`, `watchdog.sh`
- `modules/core/common_ops.sh`, `modules/core/config_ops.sh`, `modules/core/bundle_build_ops.sh`
- `modules/core/systemd_ops.sh`, `modules/core/cache_ops.sh`

These files are loaded by all bundle groups and affect every menu path.
