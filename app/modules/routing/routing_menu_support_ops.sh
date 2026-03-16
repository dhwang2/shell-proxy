# Routing menu interaction operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

ROUTING_CONTEXT_OPS_FILE="${ROUTING_CONTEXT_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_context_ops.sh}"
if [[ -f "$ROUTING_CONTEXT_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_CONTEXT_OPS_FILE"
fi

ROUTING_MENU_SUPPORT_CORE_OPS_FILE="${ROUTING_MENU_SUPPORT_CORE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_core_ops.sh}"
if [[ -f "$ROUTING_MENU_SUPPORT_CORE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_MENU_SUPPORT_CORE_OPS_FILE"
fi

ROUTING_MENU_SUPPORT_SELECTOR_LOADED="${ROUTING_MENU_SUPPORT_SELECTOR_LOADED:-0}"
ROUTING_MENU_SUPPORT_CHAIN_LOADED="${ROUTING_MENU_SUPPORT_CHAIN_LOADED:-0}"
ROUTING_MENU_SUPPORT_FULL_LOADED="${ROUTING_MENU_SUPPORT_FULL_LOADED:-0}"
ROUTING_MENU_VIEW_CACHE_TTL_SECONDS="${ROUTING_MENU_VIEW_CACHE_TTL_SECONDS:-2}"
ROUTING_TARGET_USER_SELECTION_NAMES_TEXT="${ROUTING_TARGET_USER_SELECTION_NAMES_TEXT:-}"

routing_menu_support_load_modules() {
    local module_files=("$@")
    [[ "${PROXY_ROUTING_MENU_BUNDLE_LOADED:-0}" == "1" ]] && return 0
    if declare -F load_module_group >/dev/null 2>&1; then
        load_module_group "${module_files[@]}" || return 1
    else
        local module_file=""
        for module_file in "${module_files[@]}"; do
            [[ -f "${MODULE_ROOT}/${module_file}" ]] || return 1
            # shellcheck disable=SC1090
            source "${MODULE_ROOT}/${module_file}" || return 1
        done
    fi

}

routing_menu_support_ensure_selector_support_loaded() {
    (( ROUTING_MENU_SUPPORT_SELECTOR_LOADED == 1 )) && return 0
    routing_menu_support_load_modules "modules/user/user_membership_ops.sh" || return 1
    ROUTING_MENU_SUPPORT_SELECTOR_LOADED=1
}

routing_menu_support_ensure_chain_support_loaded() {
    (( ROUTING_MENU_SUPPORT_CHAIN_LOADED == 1 )) && return 0
    routing_menu_support_load_modules \
        "modules/routing/routing_ops.sh" || return 1
    ROUTING_MENU_SUPPORT_CHAIN_LOADED=1
}

routing_menu_support_ensure_full_support_loaded() {
    (( ROUTING_MENU_SUPPORT_FULL_LOADED == 1 )) && return 0
    routing_menu_support_ensure_selector_support_loaded || return 1
    routing_menu_support_ensure_chain_support_loaded || return 1
    routing_menu_support_load_modules \
        "modules/user/user_meta_ops.sh" \
        "modules/user/user_template_ops.sh" \
        "modules/user/user_route_ops.sh" \
        "modules/user/user_membership_ops.sh" \
        "modules/routing/routing_test_ops.sh" \
        "modules/routing/routing_rule_menu_ops.sh" || return 1
    ROUTING_MENU_SUPPORT_FULL_LOADED=1
}

routing_prepare_target_user_selection_context() {
    local conf_file="${1:-}"
    routing_menu_support_ensure_selector_support_loaded || return 1
    if declare -F proxy_user_derived_cache_refresh >/dev/null 2>&1; then
        proxy_user_derived_cache_refresh "$conf_file" >/dev/null 2>&1 || true
    fi
    if declare -F proxy_user_collect_names >/dev/null 2>&1; then
        ROUTING_TARGET_USER_SELECTION_NAMES_TEXT="$(proxy_user_collect_names "any" "$conf_file" 2>/dev/null || true)"
    else
        ROUTING_TARGET_USER_SELECTION_NAMES_TEXT=""
    fi
}

routing_prepare_target_user_selection_context_with_spinner() {
    local conf_file="${1:-}" message="${2:-正在加载用户列表...}"
    if declare -F proxy_run_with_spinner_fg >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        proxy_run_with_spinner_fg "$message" routing_prepare_target_user_selection_context "$conf_file"
        return $?
    fi
    routing_prepare_target_user_selection_context "$conf_file"
}

routing_prepare_full_support_with_spinner() {
    local message="${1:-正在加载分流模块...}"
    if declare -F proxy_run_with_spinner_fg >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        proxy_run_with_spinner_fg "$message" routing_menu_support_ensure_full_support_loaded
        return $?
    fi
    routing_menu_support_ensure_full_support_loaded
}

routing_menu_view_cache_key() {
    local conf_file="${1:-}" cache_raw
    cache_raw="routing-menu|${conf_file}"
    if declare -F proxy_runtime_cache_key >/dev/null 2>&1; then
        proxy_runtime_cache_key "$cache_raw"
        return 0
    fi
    printf '%s' "$cache_raw" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

routing_menu_view_text_file() {
    local conf_file="${1:-}" cache_key
    cache_key="$(routing_menu_view_cache_key "$conf_file")"
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-menu-${cache_key}.txt"
}

routing_menu_view_fp_file() {
    local conf_file="${1:-}" cache_key
    cache_key="$(routing_menu_view_cache_key "$conf_file")"
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-menu-${cache_key}.fp"
}

routing_menu_view_code_fingerprint() {
    calc_file_meta_signature "${BASH_SOURCE[0]}" 2>/dev/null || echo "0:0"
}

routing_menu_view_state_fingerprint() {
    local conf_file="${1:-}" status_fp code_fp
    status_fp="$(routing_status_cache_read_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$status_fp" ]] || status_fp="0:0"
    code_fp="$(routing_menu_view_code_fingerprint 2>/dev/null || echo "0:0")"
    printf '%s|%s\n' "$status_fp" "$code_fp" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

routing_menu_view_cache_recent_enough() {
    local conf_file="${1:-}" text_file ttl now ts age
    text_file="$(routing_menu_view_text_file "$conf_file")"
    [[ -f "$text_file" ]] || return 1
    ttl="${ROUTING_MENU_VIEW_CACHE_TTL_SECONDS:-2}"
    [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=2
    (( ttl > 0 )) || return 1
    now="$(date +%s 2>/dev/null || echo 0)"
    ts="$(stat -c %Y "$text_file" 2>/dev/null || stat -f %m "$text_file" 2>/dev/null || echo 0)"
    [[ "$now" =~ ^[0-9]+$ && "$ts" =~ ^[0-9]+$ ]] || return 1
    age=$((now - ts))
    (( age <= ttl ))
}

routing_menu_view_cache_is_fresh() {
    local conf_file="${1:-}" text_file fp_file cached_fp expected_fp status_text_file status_fp_file
    text_file="$(routing_menu_view_text_file "$conf_file")"
    fp_file="$(routing_menu_view_fp_file "$conf_file")"
    status_text_file="$(routing_status_cache_text_file "$conf_file")"
    status_fp_file="$(routing_status_cache_fp_file "$conf_file")"
    [[ -f "$text_file" && -f "$fp_file" && -f "$status_text_file" && -f "$status_fp_file" ]] || return 1
    if routing_menu_view_cache_recent_enough "$conf_file" && routing_status_cache_recent_enough "$conf_file"; then
        return 0
    fi
    routing_status_cache_is_fresh "$conf_file" || return 1
    cached_fp="$(tr -d '[:space:]' <"$fp_file" 2>/dev/null || true)"
    [[ -n "$cached_fp" ]] || return 1
    expected_fp="$(routing_menu_view_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$expected_fp" ]] || return 1
    [[ "$cached_fp" == "$expected_fp" ]]
}

routing_menu_view_cache_invalidate() {
    local conf_file="${1:-}" text_file fp_file
    [[ -n "$conf_file" ]] || return 0
    text_file="$(routing_menu_view_text_file "$conf_file")"
    fp_file="$(routing_menu_view_fp_file "$conf_file")"
    rm -f "$text_file" "$fp_file" 2>/dev/null || true
}

routing_menu_render_to_file() {
    local output_file="${1:-}" conf_file="${2:-}" status_text_file
    [[ -n "$output_file" ]] || return 1
    status_text_file="$(routing_status_cache_text_file "$conf_file")"
    if [[ ! -f "$status_text_file" ]] || [[ ! -f "$(routing_status_cache_fp_file "$conf_file")" ]]; then
        routing_menu_support_ensure_full_support_loaded || return 1
        routing_status_cache_rebuild "$conf_file" >/dev/null 2>&1 || true
    fi

    {
        proxy_menu_header "分流管理"
        if [[ -f "$status_text_file" ]]; then
            cat "$status_text_file"
        else
            routing_show_status "$conf_file"
        fi
        echo "  1. 链式代理"
        echo "  2. 配置分流"
        echo "  3. 直连出口"
        echo "  4. 测试分流"
        proxy_menu_rule "═"
    } >"$output_file"
}

routing_menu_view_cache_rebuild() {
    local conf_file="${1:-}" text_file fp_file tmp_file state_fp
    text_file="$(routing_menu_view_text_file "$conf_file")"
    fp_file="$(routing_menu_view_fp_file "$conf_file")"
    tmp_file="$(routing_render_to_temp_file)"
    routing_menu_render_to_file "$tmp_file" "$conf_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    state_fp="$(routing_menu_view_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"
    mkdir -p "$(dirname "$text_file")" >/dev/null 2>&1 || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    mv -f "$tmp_file" "$text_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    proxy_cache_write_atomic "$fp_file" "$state_fp" || {
        return 1
    }
}

routing_menu_view_cache_print() {
    local conf_file="${1:-}" text_file
    text_file="$(routing_menu_view_text_file "$conf_file")"
    if ! routing_menu_view_cache_is_fresh "$conf_file"; then
        proxy_run_with_spinner "正在整理分流视图..." \
            routing_menu_view_cache_rebuild "$conf_file" >/dev/null 2>&1 || true
    fi
    if [[ -f "$text_file" ]]; then
        cat "$text_file"
        return 0
    fi
    routing_menu_render_to_file /dev/stdout "$conf_file"
}

configure_direct_outbound_menu() {
    local conf_file
    conf_file="$(routing_conf_file_or_warn)" || return 1
    ui_clear
    local current
    current="$(routing_get_direct_mode "$conf_file")"
    local render_file=""
    render_file="$(routing_render_to_temp_file)"
    {
        proxy_menu_header "直连出口设置"
        if routing_context_is_user; then
            echo "当前用户: ${ROUTING_USER_CONTEXT_NAME}"
            echo "说明: 直连出口仍为全局共享设置，修改后会影响全部用户。"
            proxy_menu_divider
        fi
        echo "当前设置: $(routing_direct_mode_label "$current")"
        proxy_menu_divider
        echo "  1. 仅 IPv4"
        echo "  2. 仅 IPv6"
        echo "  3. 优先 IPv4"
        echo "  4. 优先 IPv6"
        echo "  5. AsIs"
        proxy_menu_rule "═"
    } >"$render_file"
    routing_print_rendered_file "$render_file"
    if ! read_prompt mode_choice "选择序号(回车取消): "; then
        return
    fi
    local new_mode=""
    case "$mode_choice" in
        1) new_mode="ipv4_only" ;;
        2) new_mode="ipv6_only" ;;
        3) new_mode="prefer_ipv4" ;;
        4) new_mode="prefer_ipv6" ;;
        5) new_mode="as_is" ;;
        0|"") return 0 ;;
        *) red "无效输入"; return 1 ;;
    esac

    if routing_apply_direct_mode_to_conf "$conf_file" "$new_mode"; then
        sync_dns_with_route "$conf_file" || true
        restart_singbox_if_present
        if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
            routing_status_schedule_refresh_all_contexts "$conf_file" >/dev/null 2>&1 || true
        fi
        green "直连出口已更新为: $(routing_direct_mode_label "$new_mode")"
    else
        red "更新直连出口失败"
    fi
}

manage_chain_proxy() {
    local conf_file
    conf_file="$(routing_conf_file_or_warn)" || return 1
    routing_menu_support_ensure_chain_support_loaded || return 1

    while :; do
        ui_clear
        local final_out
        final_out="$(jq -r '.route.final // "🐸 direct"' "$conf_file" 2>/dev/null || echo "🐸 direct")"
        local render_file=""
        render_file="$(routing_render_to_temp_file)"
        {
            proxy_menu_header "链式代理"
            echo "当前全局出口: $(routing_outbound_label "$final_out")"
            if routing_res_socks_ready "$conf_file"; then
                echo "链式节点: 已配置($(res_socks_nodes_count))"
            else
                local node_count
                node_count="$(res_socks_nodes_count)"
                if [[ "$node_count" =~ ^[0-9]+$ ]] && (( node_count > 0 )); then
                    echo "链式节点: 已保存(${node_count})"
                else
                    echo "链式节点: 未配置"
                fi
            fi
            proxy_menu_divider
            echo "  1. 添加节点"
            echo "  2. 删除节点"
            echo "  3. 查看节点"
            proxy_menu_rule "═"
        } >"$render_file"
        routing_print_rendered_file "$render_file"
        if ! read_prompt c_choice "选择序号(回车取消): "; then
            return
        fi
        case "$c_choice" in
            1)
                configure_res_socks_interactive "$conf_file" 1
                conf_file="$(routing_conf_file_or_warn)" || return 1
                ;;
            2)
                delete_res_socks_node_interactive "$conf_file" 1
                conf_file="$(routing_conf_file_or_warn)" || return 1
                ;;
            3)
                if res_socks_print_node_lines; then
                    :
                else
                    yellow "当前没有可用链式代理节点。"
                fi
                ;;
            0|"") return 0 ;;
            *) red "无效输入"; sleep 1 ;;
        esac
    done
}

manage_routing_menu() {
    while :; do
        local conf_file
        conf_file="$(routing_conf_file_or_warn)" || return 1
        # Pre-warm user selection context in background so option 2/4 responds
        # instantly when the user selects it.
        (
            local lock_dir="${CACHE_DIR:?}/.routing_menu_warmup.lock.d"
            mkdir "$lock_dir" >/dev/null 2>&1 || exit 0
            routing_prepare_target_user_selection_context "$conf_file" >/dev/null 2>&1 || true
            rmdir "$lock_dir" >/dev/null 2>&1 || true
        ) >/dev/null 2>&1 &
        ui_clear
        routing_menu_view_cache_print "$conf_file"
        if ! read_prompt routing_choice "选择序号(回车取消): "; then
            return
        fi
        case "$routing_choice" in
            1)
                routing_menu_support_ensure_chain_support_loaded || continue
                manage_chain_proxy
                ;;
            2)
                routing_prepare_target_user_selection_context_with_spinner "$conf_file" "正在加载用户列表..." || continue
                local target_name
                target_name="$(routing_select_target_user_name "选择用户名 (配置分流)" "$conf_file")"
                [[ -z "$target_name" ]] && continue
                [[ "$target_name" == "__none__" ]] && { yellow "当前没有可管理的用户名。"; continue; }
                [[ "$target_name" == "__invalid__" ]] && { red "输入无效"; sleep 1; continue; }
                routing_prepare_full_support_with_spinner "正在加载分流配置..." || continue
                routing_with_user_context "$target_name" configure_routing_rules_menu
                ;;
            3)
                configure_direct_outbound_menu
                ;;
            4)
                routing_prepare_target_user_selection_context_with_spinner "$conf_file" "正在加载用户列表..." || continue
                local target_name
                target_name="$(routing_select_target_user_name "选择用户名 (测试分流)" "$conf_file")"
                [[ -z "$target_name" ]] && continue
                [[ "$target_name" == "__none__" ]] && { yellow "当前没有可管理的用户名。"; continue; }
                [[ "$target_name" == "__invalid__" ]] && { red "输入无效"; sleep 1; continue; }
                routing_prepare_full_support_with_spinner "正在准备测试环境..." || continue
                local render_file=""
                render_file="$(routing_render_to_temp_file)"
                {
                    routing_with_user_context "$target_name" ui_clear
                    routing_with_user_context "$target_name" proxy_menu_header "测试分流效果"
                    routing_with_user_context "$target_name" test_routing_effect "$conf_file"
                } >"$render_file"
                routing_print_rendered_file "$render_file"
                ;;
            0|"") return 0 ;;
            *) red "无效输入"; sleep 1 ;;
        esac
    done
}
