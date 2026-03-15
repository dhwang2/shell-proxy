#!/bin/bash

set -o pipefail

# shell-proxy 服务管理脚本入口

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)

if ! declare -p PROXY_SOURCED_FILE_GUARD 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_SOURCED_FILE_GUARD=()
fi

proxy_source_guard_key() {
    local target="${1:-}" abs_target="" resolved_dir=""
    [[ -n "$target" ]] || return 1

    if [[ "$target" != /* ]]; then
        abs_target="${PWD}/${target}"
    else
        abs_target="$target"
    fi

    resolved_dir="$(cd "${abs_target%/*}" 2>/dev/null && pwd -P)" || resolved_dir=""
    if [[ -n "$resolved_dir" ]]; then
        printf '%s/%s\n' "$resolved_dir" "${abs_target##*/}"
        return 0
    fi

    printf '%s\n' "$abs_target"
}

source() {
    local target="${1:-}" key rc
    if [[ -z "$target" ]]; then
        builtin source "$@"
        return $?
    fi

    key="$(proxy_source_guard_key "$target" 2>/dev/null || printf '%s\n' "$target")"

    if [[ -n "${PROXY_SOURCED_FILE_GUARD[$key]+x}" ]]; then
        return 0
    fi

    PROXY_SOURCED_FILE_GUARD["$key"]=1
    builtin source "$@"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        unset 'PROXY_SOURCED_FILE_GUARD[$key]'
    fi
    return "$rc"
}

if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
elif [[ -f "/etc/shell-proxy/env.sh" ]]; then
    source "/etc/shell-proxy/env.sh"
else
    echo "错误: 未找到 env.sh"
    exit 1
fi

MODULE_ROOT="$SCRIPT_DIR"
if [[ ! -d "$MODULE_ROOT/modules" && -d "/etc/shell-proxy/modules" ]]; then
    MODULE_ROOT="/etc/shell-proxy"
fi
MODULE_DIR="$MODULE_ROOT/modules"
MANAGEMENT_FIELD_SEP=$'\x1f'
PROXY_MENU_PREWARM_ENABLED="${PROXY_MENU_PREWARM_ENABLED:-off}"
PROXY_MENU_PREWARM_DELAY_SECONDS="${PROXY_MENU_PREWARM_DELAY_SECONDS:-2}"
PROXY_MAIN_MENU_VIEW_TTL_SECONDS="${PROXY_MAIN_MENU_VIEW_TTL_SECONDS:-5}"
PROXY_MAIN_MENU_CACHE_REUSE_ONCE="${PROXY_MAIN_MENU_CACHE_REUSE_ONCE:-0}"

ensure_menu_autoconfig_module_loaded() {
    local autoconfig_module="modules/routing/routing_autoconfig_ops.sh"
    if declare -F singbox_autoconfig_state_is_fresh >/dev/null 2>&1 \
        && declare -F singbox_autoconfig_schedule_reconcile_if_stale >/dev/null 2>&1 \
        && declare -F ensure_singbox_auto_config >/dev/null 2>&1; then
        return 0
    fi
    [[ -f "$MODULE_ROOT/$autoconfig_module" ]] || return 1
    load_module_group "$autoconfig_module"
}

load_rel_path_array() {
    local array_name="$1"
    shift
    local -n array_ref="$array_name"
    mapfile -t array_ref < <("$@")
}

resolve_base_module_files() {
    local bundle_rel=""
    bundle_rel="$(proxy_bundle_rel_path "base" 2>/dev/null || true)"
    if [[ -n "$bundle_rel" && -f "$MODULE_ROOT/$bundle_rel" ]]; then
        printf '%s\n' "$bundle_rel"
        return 0
    fi

    proxy_base_module_rel_paths
}

load_rel_path_array BASE_MODULE_FILES resolve_base_module_files

all_modules_exist() {
    local module_name
    for module_name in "$@"; do
        [[ -f "$MODULE_ROOT/$module_name" ]] || return 1
    done
    return 0
}

source_module_list() {
    local module_name
    declare -gA LOADED_MODULE_FILES
    for module_name in "$@"; do
        [[ -n "${LOADED_MODULE_FILES[$module_name]+x}" ]] && continue
        # shellcheck disable=SC1090
        source "$MODULE_ROOT/$module_name"
        LOADED_MODULE_FILES["$module_name"]=1
    done
}

require_base_modules() {
    all_modules_exist "${BASE_MODULE_FILES[@]}"
}

if ! require_base_modules; then
    red "错误: 未找到模块文件，请执行 proxy update（shell-proxy）或重新安装。"
    exit 1
fi

source_module_list "${BASE_MODULE_FILES[@]}"

load_module_group() {
    if ! all_modules_exist "$@"; then
        red "错误: 未找到菜单模块文件，请执行 proxy update（shell-proxy）或重新安装。"
        return 1
    fi
    source_module_list "$@"
}

resolve_named_menu_module_files() {
    local group="${1:-}" bundle_rel=""
    local -a fallback_module_files=()
    [[ -n "$group" ]] || return 1

    bundle_rel="$(proxy_menu_bundle_rel_path "$group" 2>/dev/null || true)"
    if [[ -n "$bundle_rel" && -f "$MODULE_ROOT/$bundle_rel" ]]; then
        printf '%s\n' "$bundle_rel"
        return 0
    fi

    mapfile -t fallback_module_files < <(proxy_menu_module_rel_paths "$group") || return 1
    if (( ${#fallback_module_files[@]} > 0 )) \
        && ! proxy_assert_menu_fallback_contract "$group" "" "${fallback_module_files[0]:-}"; then
        red "错误: 菜单 fallback 合同损坏，请执行 proxy update（shell-proxy）或重新安装。"
        return 1
    fi
    if proxy_menu_fallback_entry_rel_path "$group" >/dev/null 2>&1 \
        && (( ${#fallback_module_files[@]} != 1 )); then
        red "错误: 菜单 fallback 入口数量异常，请执行 proxy update（shell-proxy）或重新安装。"
        return 1
    fi
    printf '%s\n' "${fallback_module_files[@]}"
}

load_named_menu_modules() {
    local group="${1:-}"
    local -a module_files=()
    [[ -n "$group" ]] || return 1
    mapfile -t module_files < <(resolve_named_menu_module_files "$group") || return 1
    (( ${#module_files[@]} > 0 )) || return 1
    load_module_group "${module_files[@]}"
}

proxy_assert_menu_handler_loaded() {
    local handler="${1:-}"
    [[ -n "$handler" ]] || return 1
    declare -F "$handler" >/dev/null 2>&1
}

proxy_menu_prewarm_lock_file() {
    printf '%s\n' "${CACHE_DIR}/view/menu-prewarm.lock"
}

proxy_cpu_core_count() {
    local cpu_count=""
    cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
    [[ "$cpu_count" =~ ^[0-9]+$ ]] || cpu_count=1
    (( cpu_count > 0 )) || cpu_count=1
    printf '%s\n' "$cpu_count"
}

proxy_menu_should_prewarm() {
    case "${PROXY_MENU_PREWARM_ENABLED,,}" in
        1|true|yes|on)
            return 0
            ;;
        0|false|no|off|disabled)
            return 1
            ;;
    esac
    (( "$(proxy_cpu_core_count)" > 1 ))
}

proxy_lower_process_priority() {
    local pid="${1:-${BASHPID:-$$}}"
    command -v renice >/dev/null 2>&1 && renice -n 19 -p "$pid" >/dev/null 2>&1 || true
    command -v ionice >/dev/null 2>&1 && ionice -c3 -p "$pid" >/dev/null 2>&1 || true
}

proxy_menu_prewarm_run() {
    local conf_file="${1:-}" share_host=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0

    if load_named_menu_modules "share" >/dev/null 2>&1; then
        sync_singbox_loaded_fingerprint_passive >/dev/null 2>&1 || true
        share_host="$(detect_share_host 2>/dev/null || true)"
        if [[ -n "$share_host" ]]; then
            ensure_subscription_render_cache "_" "$share_host" "$conf_file" >/dev/null 2>&1 || true
            if declare -F subscription_share_view_cache_is_fresh >/dev/null 2>&1 \
                && ! subscription_share_view_cache_is_fresh >/dev/null 2>&1; then
                subscription_share_view_cache_rebuild "$share_host" "$conf_file" >/dev/null 2>&1 || true
            fi
        fi
    fi

    if load_named_menu_modules "routing" >/dev/null 2>&1; then
        if declare -F routing_status_refresh_context_sync >/dev/null 2>&1; then
            routing_status_refresh_context_sync "$conf_file" "" >/dev/null 2>&1 || true
        else
            routing_show_status "$conf_file" >/dev/null 2>&1 || true
        fi
    fi
}

proxy_menu_prewarm_schedule() {
    local conf_file="${1:-}" lock_file="" delay_seconds=0
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    proxy_menu_should_prewarm || return 0
    [[ "${PROXY_MENU_PREWARM_SCHEDULED:-0}" == "1" ]] && return 0
    PROXY_MENU_PREWARM_SCHEDULED=1

    delay_seconds="${PROXY_MENU_PREWARM_DELAY_SECONDS:-2}"
    [[ "$delay_seconds" =~ ^[0-9]+$ ]] || delay_seconds=2
    (( delay_seconds >= 0 )) || delay_seconds=2

    lock_file="$(proxy_menu_prewarm_lock_file)"
    mkdir -p "$(dirname "$lock_file")" >/dev/null 2>&1 || true

    if command -v flock >/dev/null 2>&1; then
        (
            flock -n 9 || exit 0
            proxy_lower_process_priority "${BASHPID:-$$}"
            (( delay_seconds > 0 )) && sleep "$delay_seconds"
            proxy_menu_prewarm_run "$conf_file"
        ) 9>"$lock_file" >/dev/null 2>&1 &
        return 0
    fi

    (
        local lock_dir="${lock_file}.d"
        mkdir "$lock_dir" >/dev/null 2>&1 || exit 0
        proxy_lower_process_priority "${BASHPID:-$$}"
        (( delay_seconds > 0 )) && sleep "$delay_seconds"
        proxy_menu_prewarm_run "$conf_file"
        rmdir "$lock_dir" >/dev/null 2>&1 || true
    ) >/dev/null 2>&1 &
}

proxy_main_menu_view_cache_file() {
    printf '%s\n' "${CACHE_DIR}/view/menu/main-menu.txt"
}

proxy_main_menu_view_code_file() {
    printf '%s\n' "${CACHE_DIR}/view/menu/main-menu.code"
}

proxy_main_menu_view_code_fingerprint() {
    local file="" rel_path="" rows=""

    # Use stat cache directly (populated by proxy_fingerprint_sweep) to avoid
    # forking stat subshells. Falls back to calc_file_meta_signature for cache misses.
    file="${BASH_SOURCE[0]}"
    rows+="${file}|${_PROXY_STAT_CACHE[$file]:-$(calc_file_meta_signature "$file" 2>/dev/null || echo "missing")}"$'\n'

    file="${SCRIPT_DIR}/env.sh"
    rows+="${file}|${_PROXY_STAT_CACHE[$file]:-$(calc_file_meta_signature "$file" 2>/dev/null || echo "missing")}"$'\n'

    while IFS= read -r rel_path; do
        [[ -n "$rel_path" ]] || continue
        file="${MODULE_ROOT}/${rel_path}"
        rows+="${rel_path}|${_PROXY_STAT_CACHE[$file]:-$(calc_file_meta_signature "$file" 2>/dev/null || echo "missing")}"$'\n'
    done < <(proxy_base_module_rel_paths)

    local _ck=""
    _ck="$(printf '%s' "$rows" | cksum 2>/dev/null)" || true
    printf '%s\n' "${_ck/ /:}"
}

proxy_main_menu_view_cache_is_fresh() {
    local cache_file code_file cached_code current_code ttl now ts age
    cache_file="$(proxy_main_menu_view_cache_file)"
    code_file="$(proxy_main_menu_view_code_file)"
    [[ -f "$cache_file" && -f "$code_file" ]] || return 1

    ttl="${PROXY_MAIN_MENU_VIEW_TTL_SECONDS:-5}"
    [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=5
    (( ttl >= 0 )) || ttl=5

    current_code="$(proxy_main_menu_view_code_fingerprint 2>/dev/null || true)"
    cached_code="$(< "$code_file" 2>/dev/null)" || cached_code=""
    cached_code="${cached_code//[[:space:]]/}"
    [[ -n "$current_code" && -n "$cached_code" && "$current_code" == "$cached_code" ]] || return 1

    if (( ttl == 0 )); then
        return 0
    fi

    printf -v now '%(%s)T' -1 2>/dev/null || now="$(date +%s 2>/dev/null || echo 0)"
    ts="$(proxy_file_mtime_epoch "$cache_file" 2>/dev/null || echo 0)"
    [[ "$now" =~ ^[0-9]+$ && "$ts" =~ ^[0-9]+$ ]] || return 1
    age=$((now - ts))
    (( age <= ttl ))
}

proxy_main_menu_view_cache_invalidate() {
    rm -f "$(proxy_main_menu_view_cache_file)" "$(proxy_main_menu_view_code_file)" 2>/dev/null || true
}

proxy_main_menu_schedule_cache_reuse_once() {
    PROXY_MAIN_MENU_CACHE_REUSE_ONCE=1
}

proxy_main_menu_consume_cache_reuse_once() {
    if [[ "${PROXY_MAIN_MENU_CACHE_REUSE_ONCE:-0}" == "1" ]]; then
        PROXY_MAIN_MENU_CACHE_REUSE_ONCE=0
        return 0
    fi
    return 1
}

proxy_main_menu_render_to_file() {
    local output_file="${1:-}"
    [[ -n "$output_file" ]] || return 1
    (
        export PROXY_TTY_RENDER_FORCE=1
        print_dashboard
        render_main_menu_items
        proxy_menu_rule "═" 68 "1;37"
    ) >"$output_file"
}

proxy_main_menu_view_cache_rebuild() {
    local cache_file code_file tmp_file code_fp
    cache_file="$(proxy_main_menu_view_cache_file)"
    code_file="$(proxy_main_menu_view_code_file)"
    tmp_file="$(mktemp 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || tmp_file="/tmp/proxy-main-menu.$$.$RANDOM"

    proxy_main_menu_render_to_file "$tmp_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    code_fp="$(proxy_main_menu_view_code_fingerprint 2>/dev/null || true)"
    [[ -n "$code_fp" ]] || code_fp="0:0"
    mkdir -p "$(dirname "$cache_file")" >/dev/null 2>&1 || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    mv -f "$tmp_file" "$cache_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    proxy_cache_write_atomic "$code_file" "$code_fp" || {
        return 1
    }
}

proxy_fingerprint_sweep() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    # Clear stat cache so mutations since last sweep are visible.
    _PROXY_STAT_CACHE=()
    ensure_file_fp_cache_maps
    calc_file_meta_signature "$conf_file" >/dev/null 2>&1 || true
    [[ -f "$USER_META_DB_FILE" ]] && calc_file_meta_signature "$USER_META_DB_FILE" >/dev/null 2>&1 || true
    [[ -f "$USER_TEMPLATE_DB_FILE" ]] && calc_file_meta_signature "$USER_TEMPLATE_DB_FILE" >/dev/null 2>&1 || true
    [[ -f "$SNELL_CONF" ]] && calc_file_meta_signature "$SNELL_CONF" >/dev/null 2>&1 || true
    # Pre-populate stat cache for code fingerprint files (avoids re-stat in subshell).
    calc_file_meta_signature "${BASH_SOURCE[0]}" >/dev/null 2>&1 || true
    calc_file_meta_signature "${SCRIPT_DIR}/env.sh" >/dev/null 2>&1 || true
    local _rel=""
    while IFS= read -r _rel; do
        [[ -n "$_rel" ]] && calc_file_meta_signature "${MODULE_ROOT}/${_rel}" >/dev/null 2>&1 || true
    done < <(proxy_base_module_rel_paths)
}

proxy_main_menu_print() {
    local cache_file
    cache_file="$(proxy_main_menu_view_cache_file)"
    if declare -F proxy_check_pending_apply_status >/dev/null 2>&1; then
        proxy_check_pending_apply_status
    fi
    if proxy_main_menu_consume_cache_reuse_once && [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi
    if ! proxy_main_menu_view_cache_is_fresh; then
        proxy_main_menu_view_cache_rebuild >/dev/null 2>&1 || true
    fi

    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    else
        export PROXY_TTY_RENDER_FORCE=1
        print_dashboard
        render_main_menu_items
        proxy_menu_rule "═" 68 "1;37"
        unset PROXY_TTY_RENDER_FORCE
    fi
}

run_menu_group_action() {
    local group="$1"
    local handler="$2"
    local should_invalidate_service_state="${3:-1}"
    local had_apply_mode=0 previous_apply_mode=""
    load_named_menu_modules "$group" || {
        return 1
    }
    if ! proxy_assert_menu_handler_loaded "$handler"; then
        red "错误: 菜单模块未导出处理函数 ${handler}，请执行 proxy update（shell-proxy）或重新安装。"
        return 1
    fi
    if [[ -n "${PROXY_CONFIG_APPLY_MODE+x}" ]]; then
        had_apply_mode=1
        previous_apply_mode="${PROXY_CONFIG_APPLY_MODE}"
    fi
    PROXY_CONFIG_APPLY_MODE="async"
    "$handler"
    if (( had_apply_mode == 1 )); then
        PROXY_CONFIG_APPLY_MODE="$previous_apply_mode"
    else
        unset PROXY_CONFIG_APPLY_MODE
    fi
    if [[ "$should_invalidate_service_state" != "0" ]] \
        && declare -F proxy_invalidate_service_state_cache >/dev/null 2>&1; then
        proxy_invalidate_service_state_cache
    fi
}

proxy_main_menu_handler_is_read_only() {
    case "${1:-}" in
        manage_share|show_config_details|show_status_and_logs)
            return 0
            ;;
    esac
    return 1
}

run_protocol_service_cli_action() {
    local action="${1:-}"
    local singbox_rc=0
    local shadowtls_rc=0
    [[ -n "$action" ]] || return 1

    case "$action" in
        start|stop|restart)
            proxy_log "INFO" "执行命令: ${action}"
            proxy_operate_singbox_service "$action"
            singbox_rc=$?
            if [[ "$singbox_rc" -eq 2 ]]; then
                yellow "sing-box 未配置，跳过 ${action}。"
            fi
            proxy_operate_snell_service "$action" || true
            proxy_operate_watchdog_service "$action" || true
            proxy_operate_shadowtls_services "$action" || true
            # Invalidate service state cache after service operations.
            if declare -F proxy_invalidate_service_state_cache >/dev/null 2>&1; then
                proxy_invalidate_service_state_cache
            fi
            ;;
        status)
            proxy_log "INFO" "执行命令: status"
            proxy_operate_singbox_service "status"
            singbox_rc=$?
            if [[ "$singbox_rc" -eq 2 ]]; then
                yellow "sing-box 未配置，跳过状态检查。"
            fi
            proxy_operate_snell_service "status" || true
            proxy_operate_watchdog_service "status" || true
            proxy_operate_shadowtls_services "status"
            shadowtls_rc=$?
            if [[ "$shadowtls_rc" -eq 2 ]]; then
                yellow "${SHADOWTLS_DISPLAY_NAME} 未配置，跳过状态检查。"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_main_menu_rows() {
    cat <<EOF
1${MANAGEMENT_FIELD_SEP}安装协议${MANAGEMENT_FIELD_SEP}protocol${MANAGEMENT_FIELD_SEP}add_protocol
2${MANAGEMENT_FIELD_SEP}卸载协议${MANAGEMENT_FIELD_SEP}protocol${MANAGEMENT_FIELD_SEP}remove_protocol
3${MANAGEMENT_FIELD_SEP}用户管理${MANAGEMENT_FIELD_SEP}user${MANAGEMENT_FIELD_SEP}manage_users
4${MANAGEMENT_FIELD_SEP}分流管理${MANAGEMENT_FIELD_SEP}routing${MANAGEMENT_FIELD_SEP}manage_routing_menu
5${MANAGEMENT_FIELD_SEP}协议管理${MANAGEMENT_FIELD_SEP}service${MANAGEMENT_FIELD_SEP}manage_protocol_services
6${MANAGEMENT_FIELD_SEP}订阅管理${MANAGEMENT_FIELD_SEP}share${MANAGEMENT_FIELD_SEP}manage_share
7${MANAGEMENT_FIELD_SEP}查看配置${MANAGEMENT_FIELD_SEP}log_config${MANAGEMENT_FIELD_SEP}show_config_details
8${MANAGEMENT_FIELD_SEP}运行日志${MANAGEMENT_FIELD_SEP}log_config${MANAGEMENT_FIELD_SEP}show_status_and_logs
9${MANAGEMENT_FIELD_SEP}内核管理${MANAGEMENT_FIELD_SEP}system${MANAGEMENT_FIELD_SEP}manage_core
10${MANAGEMENT_FIELD_SEP}网络管理${MANAGEMENT_FIELD_SEP}system${MANAGEMENT_FIELD_SEP}manage_network_management
11${MANAGEMENT_FIELD_SEP}脚本更新${MANAGEMENT_FIELD_SEP}${MANAGEMENT_FIELD_SEP}update_self
12${MANAGEMENT_FIELD_SEP}卸载服务${MANAGEMENT_FIELD_SEP}system${MANAGEMENT_FIELD_SEP}uninstall_service
0${MANAGEMENT_FIELD_SEP}完全退出${MANAGEMENT_FIELD_SEP}${MANAGEMENT_FIELD_SEP}__exit__
EOF
}

render_main_menu_items() {
    local -a menu_rows=()
    local row="" choice="" label="" group="" handler=""
    load_rel_path_array menu_rows proxy_main_menu_rows
    for row in "${menu_rows[@]}"; do
        [[ -n "$row" ]] || continue
        IFS="$MANAGEMENT_FIELD_SEP" read -r choice label group handler <<<"$row"
        if [[ "$choice" == "0" ]]; then
            proxy_menu_rule "═" 68 "1;37"
        fi
        printf "%8s %s\n" "(${choice})" "$label"
    done
}

dispatch_main_menu_choice() {
    local selected="${1:-}"
    local -a menu_rows=()
    local row="" choice="" label="" group="" handler=""
    local should_invalidate=1
    local should_invalidate_service_state=1
    [[ -n "$selected" ]] || return 1

    load_rel_path_array menu_rows proxy_main_menu_rows
    for row in "${menu_rows[@]}"; do
        [[ -n "$row" ]] || continue
        IFS="$MANAGEMENT_FIELD_SEP" read -r choice label group handler <<<"$row"
        [[ "$choice" == "$selected" ]] || continue
        if [[ "$handler" == "__exit__" ]]; then
            exit 0
        fi
        if proxy_main_menu_handler_is_read_only "$handler"; then
            should_invalidate=0
            should_invalidate_service_state=0
            proxy_main_menu_schedule_cache_reuse_once
        fi
        if [[ -n "$group" ]]; then
            run_menu_group_action "$group" "$handler" "$should_invalidate_service_state"
        else
            "$handler"
        fi
        (( should_invalidate == 1 )) && proxy_main_menu_view_cache_invalidate
        return 0
    done

    return 1
}

proxy_cli_rows() {
    cat <<EOF
menu${MANAGEMENT_FIELD_SEP}menu${MANAGEMENT_FIELD_SEP}${MANAGEMENT_FIELD_SEP}
log${MANAGEMENT_FIELD_SEP}menu_action${MANAGEMENT_FIELD_SEP}log_config${MANAGEMENT_FIELD_SEP}show_status_and_logs
start${MANAGEMENT_FIELD_SEP}service_action${MANAGEMENT_FIELD_SEP}${MANAGEMENT_FIELD_SEP}
stop${MANAGEMENT_FIELD_SEP}service_action${MANAGEMENT_FIELD_SEP}${MANAGEMENT_FIELD_SEP}
restart${MANAGEMENT_FIELD_SEP}service_action${MANAGEMENT_FIELD_SEP}${MANAGEMENT_FIELD_SEP}
status${MANAGEMENT_FIELD_SEP}service_action${MANAGEMENT_FIELD_SEP}${MANAGEMENT_FIELD_SEP}
EOF
}

run_cli_command() {
    local command_name="${1:-menu}"
    local -a cli_rows=()
    local row="" name="" kind="" group="" handler=""
    local conf_file="" sb_state=""

    load_rel_path_array cli_rows proxy_cli_rows
    for row in "${cli_rows[@]}"; do
        [[ -n "$row" ]] || continue
        IFS="$MANAGEMENT_FIELD_SEP" read -r name kind group handler <<<"$row"
        [[ "$name" == "$command_name" ]] || continue
        case "$kind" in
            menu)
                conf_file="$(get_conf_file 2>/dev/null || true)"
                # Fingerprint sweep: pre-populate file meta cache for all key files.
                proxy_fingerprint_sweep "$conf_file"
                # Pre-populate service state cache before entering menu loop.
                if declare -F proxy_refresh_service_state_cache >/dev/null 2>&1; then
                    proxy_refresh_service_state_cache
                fi
                sb_state="$PROXY_SERVICE_STATE_CACHE_SINGBOX"
                [[ -n "$sb_state" ]] || sb_state="$(systemctl is-active sing-box 2>/dev/null || true)"
                if [[ -n "$conf_file" && -f "$conf_file" ]] \
                    && [[ "$sb_state" == "active" ]] \
                    && declare -F singbox_autoconfig_state_is_fresh >/dev/null 2>&1 \
                    && declare -F singbox_autoconfig_schedule_reconcile_if_stale >/dev/null 2>&1; then
                    singbox_autoconfig_schedule_reconcile_if_stale "$conf_file" 1
                else
                    if [[ -z "$conf_file" || ! -f "$conf_file" ]]; then
                        ensure_menu_autoconfig_module_loaded >/dev/null 2>&1 || true
                        if declare -F ensure_singbox_auto_config >/dev/null 2>&1; then
                            ensure_singbox_auto_config 0 || true
                        fi
                    fi
                fi
                proxy_menu_prewarm_schedule "$conf_file"
                show_menu
                ;;
            menu_action)
                load_named_menu_modules "$group" || return 1
                "$handler"
                ;;
            service_action)
                run_protocol_service_cli_action "$name"
                ;;
            *)
                return 1
                ;;
        esac
        return 0
    done

    show_menu
    return 0
}
show_main_menu() {
    while :; do
        ui_clear
        proxy_main_menu_print
        if ! read_prompt choice "选择: "; then
            echo
            return
        fi
        proxy_log "INFO" "主菜单选择: ${choice:-<enter>}"
        [[ -z "${choice:-}" ]] && continue
        dispatch_main_menu_choice "$choice" || { red "无效输入" ; sleep 1; }
    done
}

show_menu() {
    show_main_menu
}

main() {
    check_root
    ensure_runtime_log_files
    proxy_log "INFO" "shell-proxy 管理脚本启动: cmd=${1:-menu}"
    run_cli_command "${1:-menu}"
}

main "$@"
