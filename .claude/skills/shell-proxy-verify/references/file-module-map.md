# File-to-Module Map

Maps every `app/` source file to its affected verification module(s).

## Foundational Files (ALL modules — triggers Tier 3)

| File | Reason |
|------|--------|
| `env.sh` | Module manifest, bundle definitions, all groups depend on it |
| `management.sh` | Main menu entry point, menu dispatch |
| `install.sh` | Installation entry point |
| `bootstrap.sh` | Bootstrap entry point |
| `watchdog.sh` | Watchdog service |
| `modules/core/common_ops.sh` | Base bundle — shared utilities loaded by all groups |
| `modules/core/bootstrap_ops.sh` | Base bundle — bootstrap operations |
| `modules/core/config_ops.sh` | Configuration operations used across all modules |
| `modules/core/bundle_build_ops.sh` | Bundle build system |
| `modules/core/cache_ops.sh` | Cache operations used across modules |
| `modules/core/systemd_ops.sh` | Systemd service management used across modules |
| `modules/runtime/runtime_status_ops.sh` | Base bundle — runtime status shared by all menus |

## Systemd Templates (ALL modules — triggers Tier 3)

| File | Reason |
|------|--------|
| `systemd/sing-box.service.tpl` | sing-box service definition |
| `systemd/snell-v5.service.tpl` | Snell service definition |
| `systemd/shadow-tls.service.tpl` | ShadowTLS service definition |
| `systemd/caddy-sub.service.tpl` | Subscription service definition |
| `systemd/proxy-watchdog.service.tpl` | Watchdog service definition |

## Protocol Module → VM-01, VM-02

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/protocol/protocol_ops.sh` | VM-01, VM-02 | VM-05 (service bundle includes it) |
| `modules/protocol/protocol_install_singbox_ops.sh` | VM-01 | — |
| `modules/protocol/protocol_shadowtls_setup_ops.sh` | VM-01 | — |
| `modules/protocol/protocol_port_ops.sh` | VM-01 | — |
| `modules/protocol/protocol_tls_ops.sh` | VM-01 | — |
| `modules/protocol/protocol_runtime_ops.sh` | VM-01, VM-02 | — |

## User Module → VM-03

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/user/user_ops.sh` | VM-03 | — |
| `modules/user/user_meta_ops.sh` | VM-03 | VM-01 (protocol bundle), VM-04 (routing bundle), VM-05 (service bundle) |
| `modules/user/user_template_ops.sh` | VM-03 | VM-01 (protocol bundle), VM-04 (routing bundle), VM-05 (service bundle) |
| `modules/user/user_route_ops.sh` | VM-03 | VM-01 (protocol bundle), VM-04 (routing bundle), VM-05 (service bundle) |
| `modules/user/user_membership_ops.sh` | VM-03 | VM-01 (protocol bundle), VM-04 (routing bundle), VM-05 (service bundle) |
| `modules/user/user_batch_ops.sh` | VM-03 | — |

## Routing Module → VM-04

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/routing/routing_ops.sh` | VM-04 | VM-01 (protocol bundle), VM-03 (user bundle) |
| `modules/routing/routing_menu_support_ops.sh` | VM-04 | — |
| `modules/routing/routing_rule_menu_ops.sh` | VM-04 | — |
| `modules/routing/routing_core_ops.sh` | VM-04 | — |
| `modules/routing/routing_context_ops.sh` | VM-04 | — |
| `modules/routing/routing_autoconfig_ops.sh` | VM-04 | — |
| `modules/routing/routing_preset_ops.sh` | VM-04 | — |
| `modules/routing/routing_res_socks_ops.sh` | VM-04 | — |
| `modules/routing/routing_test_ops.sh` | VM-04 | — |

## Service Module → VM-05, VM-12

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/service/service_ops.sh` | VM-05 | VM-09 (system bundle), VM-12 (system bundle) |

## Subscription Module → VM-06

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/subscription/share_ops.sh` | VM-06 | — |
| `modules/subscription/share_meta_ops.sh` | VM-06 | — |
| `modules/subscription/subscription_ops.sh` | VM-06 | — |
| `modules/subscription/subscription_target_ops.sh` | VM-06 | — |

## Runtime Module → VM-07, VM-08

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/runtime/log_ops.sh` | VM-07, VM-08 | — |

> Note: `modules/runtime/runtime_status_ops.sh` is in the base bundle (foundational).

## Core Module (non-foundational) → VM-09

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/core/core_ops.sh` | VM-09 | — |
| `modules/core/release_ops.sh` | VM-09 | — |

## Network Module → VM-10

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `modules/network/network_ops.sh` | VM-10 | — |
| `modules/network/network_firewall_ops.sh` | VM-10 | — |

## Self-Update → VM-11

| File | Primary VM | Secondary VM |
|------|-----------|-------------|
| `self_update.sh` | VM-11 | — |

> Note: `modules/core/bootstrap_ops.sh` is in the base bundle (foundational).

## Bundle Group ↔ Module Cross-Reference

| Bundle Group | Modules in Bundle | VM(s) |
|-------------|-------------------|-------|
| `base` | `common_ops.sh`, `bootstrap_ops.sh`, `runtime_status_ops.sh` | ALL (foundational) |
| `protocol` | `user_meta_ops.sh`, `user_template_ops.sh`, `user_route_ops.sh`, `user_membership_ops.sh`, `routing_ops.sh`, `protocol_ops.sh`, `protocol_shadowtls_setup_ops.sh`, `protocol_install_singbox_ops.sh` | VM-01 |
| `user` | `user_ops.sh`, `user_meta_ops.sh`, `user_template_ops.sh`, `user_route_ops.sh`, `user_membership_ops.sh`, `user_batch_ops.sh`, `routing_ops.sh` | VM-03 |
| `routing` | `routing_menu_support_ops.sh`, `routing_ops.sh`, `user_meta_ops.sh`, `user_template_ops.sh`, `user_route_ops.sh`, `user_membership_ops.sh`, `routing_test_ops.sh`, `routing_rule_menu_ops.sh` | VM-04 |
| `service` | `service_ops.sh`, `user_meta_ops.sh`, `user_template_ops.sh`, `user_route_ops.sh`, `user_membership_ops.sh`, `protocol_ops.sh` | VM-05 |
| `share` | `share_ops.sh`, `subscription_ops.sh` | VM-06 |
| `log_config` | `log_ops.sh` | VM-07, VM-08 |
| `system` | `service_ops.sh`, `core_ops.sh`, `network_firewall_ops.sh`, `network_ops.sh`, `protocol_ops.sh` | VM-09, VM-10, VM-12 |
