#!/bin/bash

# shell-proxy 环境配置与常量定义

# 核心根目录
WORK_DIR='/etc/shell-proxy'
TEMP_DIR='/tmp/shell-proxy'

# 归类存放路径
BIN_DIR="${WORK_DIR}/bin"
CONF_DIR="${WORK_DIR}/conf"
LOG_DIR="${WORK_DIR}/logs"
CACHE_DIR="${WORK_DIR}/cache"
CADDY_CACHE_DIR="${CACHE_DIR}/caddy"
CADDY_XDG_DATA_HOME="${WORK_DIR}"
CADDY_XDG_CONFIG_HOME="${WORK_DIR}"
CADDY_CERT_BASE="${WORK_DIR}/caddy/certificates/acme-v02.api.letsencrypt.org-directory"
CADDY_DEFAULT_VERSION="2.9.1"

# 具体文件路径
BIN_FILE="${BIN_DIR}/sing-box"
SNELL_BIN="${BIN_DIR}/snell-server"
ST_BIN="${BIN_DIR}/shadow-tls"
CADDY_BIN="${BIN_DIR}/caddy"
SNELL_CONF="${WORK_DIR}/snell-v5.conf"
CADDY_FILE="${WORK_DIR}/Caddyfile"
SCRIPT_SOURCE_REF_FILE="${WORK_DIR}/.script_source_ref"
PROXY_RELEASE_TAG_CACHE_FILE="${CACHE_DIR}/proxy/latest-release-tag"
PROXY_REPO_COMMIT_CACHE_FILE="${CACHE_DIR}/proxy/latest-branch-commit"
PROXY_RELEASE_TAG_CACHE_TTL="${PROXY_RELEASE_TAG_CACHE_TTL:-300}"
PROXY_REPO_COMMIT_CACHE_TTL="${PROXY_REPO_COMMIT_CACHE_TTL:-120}"
SUB_FILE="${WORK_DIR}/subscription.txt"
SINGBOX_SERVICE_LOG="${LOG_DIR}/sing-box.service.log"
SNELL_SERVICE_LOG="${LOG_DIR}/snell-v5.service.log"
SHADOWTLS_SERVICE_LOG="${LOG_DIR}/shadow-tls.service.log"
CADDY_SUB_SERVICE_LOG="${LOG_DIR}/caddy-sub.service.log"
PROXY_SCRIPT_LOG="${LOG_DIR}/proxy-script.log"
PROXY_WATCHDOG_LOG="${LOG_DIR}/proxy-watchdog.log"
WATCHDOG_SCRIPT="${WORK_DIR}/watchdog.sh"
SELF_UPDATE_SCRIPT="${WORK_DIR}/self_update.sh"

# Systemd 服务文件
SERVICE_FILE='/etc/systemd/system/sing-box.service'
SNELL_SERVICE_FILE='/etc/systemd/system/snell-v5.service'
ST_SERVICE_FILE='/etc/systemd/system/shadow-tls.service'
CADDY_SERVICE_FILE='/etc/systemd/system/caddy-sub.service'
WATCHDOG_SERVICE_FILE='/etc/systemd/system/proxy-watchdog.service'

# 仓库信息
REPO_USER="dhwang2"
REPO_NAME="shell-proxy"
BRANCH="main"

proxy_unique_lines() {
    awk 'NF && !seen[$0]++'
}

proxy_base_module_rel_paths() {
    cat <<'EOF'
modules/core/common_ops.sh
modules/core/bootstrap_ops.sh
modules/runtime/runtime_status_ops.sh
EOF
}

# Fallback contract:
# - This function defines the raw module list used when a prebuilt bundle is missing.
# - Most groups list every directly required module here.
# - For `user` / `routing` / `share`, fallback intentionally points at a single entry module.
#   Those entry modules must source their full dependency tree by themselves.
# - When adding a new dependency under one of those entry modules, keep this contract explicit:
#   update the entry module's internal source chain, and update
#   `proxy_bundle_source_module_rel_paths()` when the prebuilt bundle should include that dependency.
proxy_menu_module_rel_paths() {
    local group="${1:-}"
    case "$group" in
        service)
            cat <<'EOF'
modules/service/service_ops.sh
modules/user/user_meta_ops.sh
modules/user/user_template_ops.sh
modules/user/user_route_ops.sh
modules/user/user_membership_ops.sh
modules/protocol/protocol_ops.sh
EOF
            ;;
        log_config)
            cat <<'EOF'
modules/runtime/log_ops.sh
EOF
            ;;
        system)
            cat <<'EOF'
modules/service/service_ops.sh
modules/core/core_ops.sh
modules/network/network_firewall_ops.sh
modules/network/network_ops.sh
modules/protocol/protocol_ops.sh
EOF
            ;;
        protocol)
            cat <<'EOF'
modules/user/user_meta_ops.sh
modules/user/user_template_ops.sh
modules/user/user_route_ops.sh
modules/user/user_membership_ops.sh
modules/routing/routing_ops.sh
modules/protocol/protocol_ops.sh
modules/protocol/protocol_shadowtls_setup_ops.sh
modules/protocol/protocol_install_singbox_ops.sh
EOF
            ;;
        user)
            # Fallback entry: `user_ops.sh` must source the complete user menu dependency tree.
            cat <<'EOF'
modules/user/user_ops.sh
EOF
            ;;
        routing)
            # Fallback entry: `routing_menu_support_ops.sh` must source the complete routing menu dependency tree.
            cat <<'EOF'
modules/routing/routing_menu_support_ops.sh
EOF
            ;;
        share)
            # Fallback entry: `share_ops.sh` must source the complete share/subscription dependency tree.
            cat <<'EOF'
modules/subscription/share_ops.sh
EOF
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_bundle_group_names() {
    cat <<'EOF'
base
protocol
service
user
routing
share
log_config
system
EOF
}

proxy_bundle_rel_path() {
    local group="${1:-}"
    case "$group" in
        base)
            printf '%s\n' 'bundles/base.bundle.sh'
            ;;
        protocol)
            printf '%s\n' 'bundles/protocol-menu.bundle.sh'
            ;;
        service)
            printf '%s\n' 'bundles/service-menu.bundle.sh'
            ;;
        user)
            printf '%s\n' 'bundles/user-menu.bundle.sh'
            ;;
        routing)
            printf '%s\n' 'bundles/routing-menu.bundle.sh'
            ;;
        share)
            printf '%s\n' 'bundles/share-menu.bundle.sh'
            ;;
        log_config)
            printf '%s\n' 'bundles/log-config-menu.bundle.sh'
            ;;
        system)
            printf '%s\n' 'bundles/system-menu.bundle.sh'
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_bundle_source_module_rel_paths() {
    local group="${1:-}"
    case "$group" in
        base)
            proxy_base_module_rel_paths
            ;;
        protocol|service|log_config|system)
            proxy_menu_module_rel_paths "$group"
            ;;
        user)
            # Bundle build expands the fallback entry into the full dependency set.
            cat <<'EOF'
modules/user/user_ops.sh
modules/user/user_meta_ops.sh
modules/user/user_template_ops.sh
modules/user/user_route_ops.sh
modules/user/user_membership_ops.sh
modules/user/user_batch_ops.sh
modules/routing/routing_ops.sh
EOF
            ;;
        routing)
            # Bundle build expands the fallback entry into the full dependency set.
            cat <<'EOF'
modules/routing/routing_menu_support_ops.sh
modules/routing/routing_ops.sh
modules/user/user_meta_ops.sh
modules/user/user_template_ops.sh
modules/user/user_route_ops.sh
modules/user/user_membership_ops.sh
modules/routing/routing_test_ops.sh
modules/routing/routing_rule_menu_ops.sh
EOF
            ;;
        share)
            # Bundle build expands the fallback entry into the full dependency set.
            cat <<'EOF'
modules/subscription/share_ops.sh
modules/subscription/subscription_ops.sh
EOF
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_bundle_prelude_lines() {
    local group="${1:-}"
    case "$group" in
        base)
            cat <<'EOF'
PROXY_BASE_BUNDLE_LOADED=1
EOF
            ;;
        protocol)
            cat <<'EOF'
PROXY_PROTOCOL_MENU_BUNDLE_LOADED=1
EOF
            ;;
        service)
            cat <<'EOF'
PROXY_SERVICE_MENU_BUNDLE_LOADED=1
EOF
            ;;
        user)
            cat <<'EOF'
PROXY_USER_MENU_BUNDLE_LOADED=1
EOF
            ;;
        routing)
            cat <<'EOF'
PROXY_ROUTING_MENU_BUNDLE_LOADED=1
ROUTING_MENU_SUPPORT_SELECTOR_LOADED=1
ROUTING_MENU_SUPPORT_CHAIN_LOADED=1
ROUTING_MENU_SUPPORT_FULL_LOADED=1
EOF
            ;;
        share)
            cat <<'EOF'
PROXY_SHARE_MENU_BUNDLE_LOADED=1
SHARE_MENU_FULL_LOADED=1
EOF
            ;;
        log_config)
            cat <<'EOF'
PROXY_LOG_CONFIG_MENU_BUNDLE_LOADED=1
EOF
            ;;
        system)
            cat <<'EOF'
PROXY_SYSTEM_MENU_BUNDLE_LOADED=1
EOF
            ;;
        *)
            return 0
            ;;
    esac
}

proxy_menu_bundle_rel_path() {
    proxy_bundle_rel_path "${1:-}"
}

proxy_menu_fallback_entry_rel_path() {
    case "${1:-}" in
        user)
            printf '%s\n' 'modules/user/user_ops.sh'
            ;;
        routing)
            printf '%s\n' 'modules/routing/routing_menu_support_ops.sh'
            ;;
        share)
            printf '%s\n' 'modules/subscription/share_ops.sh'
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_assert_menu_fallback_contract() {
    local group="${1:-}" expected_rel="${2:-}" actual_rel="${3:-}"
    [[ -n "$group" ]] || return 1
    expected_rel="$(proxy_menu_fallback_entry_rel_path "$group" 2>/dev/null || true)"
    [[ -n "$expected_rel" ]] || return 0
    [[ -n "$actual_rel" && "$actual_rel" == "$expected_rel" ]]
}

PROXY_BUNDLE_BUILD_OPS_FILE="${PROXY_BUNDLE_BUILD_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/modules/core/bundle_build_ops.sh}"

proxy_load_bundle_build_ops() {
    [[ "${PROXY_BUNDLE_BUILD_OPS_LOADED:-0}" == "1" ]] && return 0
    [[ -f "$PROXY_BUNDLE_BUILD_OPS_FILE" ]] || return 1
    # shellcheck disable=SC1090
    source "$PROXY_BUNDLE_BUILD_OPS_FILE" || return 1
    declare -F proxy_rebuild_menu_bundle_impl >/dev/null 2>&1 || return 1
    PROXY_BUNDLE_BUILD_OPS_LOADED=1
}

proxy_remove_menu_bundles() {
    proxy_load_bundle_build_ops || return 1
    proxy_remove_menu_bundles_impl "$@"
}

proxy_rebuild_menu_bundle() {
    proxy_load_bundle_build_ops || return 1
    proxy_rebuild_menu_bundle_impl "$@"
}

proxy_rebuild_menu_bundles() {
    proxy_load_bundle_build_ops || return 1
    proxy_rebuild_menu_bundles_impl "$@"
}

proxy_changed_rel_paths_require_menu_bundle_rebuild() {
    local rel_path=""
    for rel_path in "$@"; do
        case "$rel_path" in
            env.sh|modules/*.sh)
                return 0
                ;;
        esac
    done
    return 1
}

proxy_all_module_rel_paths() {
    cat <<'EOF'
modules/core/bundle_build_ops.sh
modules/core/cache_ops.sh
modules/core/bootstrap_ops.sh
modules/core/common_ops.sh
modules/core/config_ops.sh
modules/core/core_ops.sh
modules/core/release_ops.sh
modules/core/systemd_ops.sh
modules/network/network_firewall_ops.sh
modules/network/network_ops.sh
modules/protocol/protocol_install_singbox_ops.sh
modules/protocol/protocol_ops.sh
modules/protocol/protocol_port_ops.sh
modules/protocol/protocol_runtime_ops.sh
modules/protocol/protocol_shadowtls_setup_ops.sh
modules/protocol/protocol_tls_ops.sh
modules/routing/routing_autoconfig_ops.sh
modules/routing/routing_context_ops.sh
modules/routing/routing_core_ops.sh
modules/routing/routing_menu_support_ops.sh
modules/routing/routing_ops.sh
modules/routing/routing_preset_ops.sh
modules/routing/routing_res_socks_ops.sh
modules/routing/routing_rule_menu_ops.sh
modules/routing/routing_test_ops.sh
modules/runtime/log_ops.sh
modules/runtime/runtime_status_ops.sh
modules/service/service_ops.sh
modules/subscription/share_ops.sh
modules/subscription/share_meta_ops.sh
modules/subscription/subscription_ops.sh
modules/subscription/subscription_target_ops.sh
modules/user/user_batch_ops.sh
modules/user/user_membership_ops.sh
modules/user/user_meta_ops.sh
modules/user/user_ops.sh
modules/user/user_route_ops.sh
modules/user/user_template_ops.sh
EOF
}

proxy_managed_rel_paths() {
    {
        cat <<'EOF'
self_update.sh
management.sh
bootstrap.sh
env.sh
watchdog.sh
EOF
        proxy_all_module_rel_paths
        cat <<'EOF'
systemd/sing-box.service.tpl
systemd/snell-v5.service.tpl
systemd/shadow-tls.service.tpl
systemd/caddy-sub.service.tpl
systemd/proxy-watchdog.service.tpl
EOF
    } | proxy_unique_lines
}

proxy_managed_exec_rel_paths() {
    cat <<'EOF'
self_update.sh
management.sh
bootstrap.sh
watchdog.sh
EOF
}

proxy_managed_install_path() {
    local rel="${1:-}"
    [[ -n "$rel" ]] || return 1
    printf '%s\n' "${WORK_DIR}/${rel}"
}

# 颜色定义
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }


detect_release_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) return 1 ;;
    esac
}
