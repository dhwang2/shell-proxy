# User menu and interaction operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

user_menu_support_load_modules() {
    local -a module_files=(
        "modules/user/user_meta_ops.sh"
        "modules/user/user_template_ops.sh"
        "modules/user/user_route_ops.sh"
        "modules/user/user_membership_ops.sh"
        "modules/user/user_batch_ops.sh"
        "modules/routing/routing_ops.sh"
    )
    local module_root="" rel=""

    [[ "${PROXY_USER_MENU_BUNDLE_LOADED:-0}" == "1" ]] && return 0

    if declare -F load_module_group >/dev/null 2>&1 && [[ -n "${MODULE_ROOT:-}" ]]; then
        load_module_group "${module_files[@]}"
        return $?
    fi

    module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
    for rel in "${module_files[@]}"; do
        # shellcheck disable=SC1090
        source "${module_root}/${rel}" || return 1
    done
}

user_menu_prepare_action() {
    local action_name="${1:-}" conf_file="${2:-}"
    [[ -n "$action_name" ]] || return 1

    USER_META_DB="$USER_META_DB_FILE"
    USER_ROUTE_RULES_DB="$USER_ROUTE_RULES_DB_FILE"
    USER_TEMPLATE_DB="$USER_TEMPLATE_DB_FILE"

    ensure_user_meta_db

    case "$action_name" in
        list_user_groups|rename_user_group|delete_user_group)
            [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
            proxy_user_group_sync_from_memberships "$conf_file" >/dev/null 2>&1 || true
            ;;
    esac
}

user_menu_run_action() {
    local action_name="${1:-}" conf_file="${2:-}"
    [[ -n "$action_name" ]] || return 1

    user_menu_support_load_modules || {
        red "用户管理模块加载失败，请执行 proxy update（shell-proxy）或重新安装。"
        return 1
    }
    user_menu_prepare_action "$action_name" "$conf_file" || return 1
    "$action_name"
}

manage_users() {
    conf_file=
    conf_file=$(get_conf_file)

    if [[ -z "$conf_file" ]]; then
        red "未发现 sing-box 配置文件，请先重建配置。"
        pause
        return
    fi

    while :; do
        (
            local lock_dir="${CACHE_DIR:?}/.user_menu_warmup.lock.d"
            mkdir "$lock_dir" >/dev/null 2>&1 || exit 0
            proxy_user_group_sync_from_memberships "$conf_file" >/dev/null 2>&1 || true
            rmdir "$lock_dir" >/dev/null 2>&1 || true
        ) >/dev/null 2>&1 &
        ui_clear
        proxy_menu_header "用户管理"
        echo "1. 用户列表"
        echo "2. 添加用户"
        echo "3. 重置用户"
        echo "4. 删除用户"
        proxy_menu_back_hint
        if ! read_prompt choice "选择: "; then
            return
        fi
        [[ -z "$choice" ]] && return

        case "$choice" in
            1)
                user_menu_run_action "list_user_groups" "$conf_file"
                pause
                ;;
            2)
                user_menu_run_action "add_user_group" "$conf_file"
                pause_unless_cancelled $?
                ;;
            3)
                user_menu_run_action "rename_user_group" "$conf_file"
                pause_unless_cancelled $?
                ;;
            4)
                user_menu_run_action "delete_user_group" "$conf_file"
                pause_unless_cancelled $?
                ;;
            *)
                red "无效输入"
                sleep 1
                ;;
        esac
    done
}

# --- user selector and summary helpers (merged from user_selector_ops.sh) ---

proto_group_label() {
    case "${1:-}" in
        snell) echo "snell-v5" ;;
        *) echo "${1:-}" ;;
    esac
}

find_inbound_index_by_tag() {
    local proto="$1" in_tag="$2"
    if [[ "$proto" == "snell" ]]; then
        is_snell_configured && printf '%s\n' "snell"
        return 0
    fi
    proxy_user_find_inbound_index_by_tag "$conf_file" "$proto" "$in_tag"
}

decode_b64() {
    local value="$1"
    printf '%s' "$value" | base64 -d 2>/dev/null
}

collect_all_user_membership_lines() {
    local line state name proto in_tag id_b64 key_b64 user_b64 idx
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state name proto in_tag id_b64 key_b64 user_b64 <<<"$line"
        idx="$(find_inbound_index_by_tag "$proto" "$in_tag")"
        printf '%s|%s|%s|%s|%s||%s|%s|%s\n' \
            "$state" "$name" "$proto" "${idx:-}" "$in_tag" "$id_b64" "$user_b64" "$key_b64"
    done < <(proxy_user_collect_membership_lines "any" "$conf_file")
}

render_user_group_rows() {
    local filter="${1:-any}"
    proxy_user_derived_cache_refresh "$conf_file"
    local cache_text="" row name summary active_count disabled_count
    case "$filter" in
        has_active) cache_text="$PROXY_USER_GROUP_ROWS_CACHE_HAS_ACTIVE" ;;
        has_disabled) cache_text="$PROXY_USER_GROUP_ROWS_CACHE_HAS_DISABLED" ;;
        *) cache_text="$PROXY_USER_GROUP_ROWS_CACHE_ANY" ;;
    esac
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS=$'\t' read -r name summary active_count disabled_count <<<"$row"
        printf '%s\t-\t%s\t%s\t%s\n' "$name" "$active_count" "$disabled_count" "$summary"
    done <<< "$cache_text"
}

collect_user_group_lines_by_name() {
    local target_name="$1" state_filter="${2:-any}"
    local line state name proto idx in_tag uidx id_b64 user_b64 key_b64
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state name proto idx in_tag uidx id_b64 user_b64 key_b64 <<<"$line"
        [[ "$name" == "$target_name" ]] || continue
        case "$state_filter" in
            active) [[ "$state" == "active" ]] || continue ;;
            disabled) [[ "$state" == "disabled" ]] || continue ;;
        esac
        printf '%s\n' "$line"
    done < <(collect_all_user_membership_lines)
}

user_group_member_count() {
    local target_name="$1" count=0 line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        ((count++))
    done < <(collect_user_group_lines_by_name "$target_name" "any")
    echo "$count"
}

list_user_groups() {
    echo
    echo "用户列表:"
    local rows=()
    mapfile -t rows < <(render_user_group_rows "any")
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (无)"
        return 0
    fi

    local idx=1 row name proto_list active_count disabled_count summary
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r name proto_list active_count disabled_count summary <<<"$row"
        printf "%d. %s [协议:%s]\n" "$idx" "$name" "$summary"
        ((idx++))
    done
}

choose_user_group_name() {
    local filter="$1" title="$2"
    local rows=()
    mapfile -t rows < <(render_user_group_rows "$filter")
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "__none__"
        return
    fi

    echo >&2
    echo "$title" >&2
    local idx=1 row name proto_list active_count disabled_count summary
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r name proto_list active_count disabled_count summary <<<"$row"
        printf "%d. %s\n" "$idx" "$name" >&2
        ((idx++))
    done

    local pick=""
    if ! prompt_select_index pick; then
        echo ""
        return 130
    fi
    if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#rows[@]} )); then
        echo "__invalid__"
        return
    fi
    IFS=$'\t' read -r name _proto_list _active_count _disabled_count _summary <<<"${rows[$((pick-1))]}"
    echo "$name"
}

user_group_name_exists() {
    local candidate="$1" exclude_name="${2:-}"
    candidate="$(normalize_proxy_user_name "$candidate")"
    [[ -n "$candidate" ]] || return 1
    local row name
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS=$'\t' read -r name _proto_list _active_count _disabled_count _summary <<<"$row"
        [[ "$name" == "$exclude_name" ]] && continue
        [[ "$name" == "$candidate" ]] && return 0
    done < <(render_user_group_rows "any")
    return 1
}

suggest_global_user_name() {
    local preferred="${1:-$DEFAULT_PROXY_USER_NAME}" exclude_name="${2:-}"
    local base candidate suffix=2
    base="$(normalize_proxy_user_name "$preferred")"
    candidate="$base"
    while user_group_name_exists "$candidate" "$exclude_name"; do
        candidate="${base}-${suffix}"
        ((suffix++))
    done
    echo "$candidate"
}

# --- user menu support (merged from user_menu_support_ops.sh) ---

add_user_group() {
    local input_name target_name yn
    echo
    read -r -p "用户名 (回车取消): " input_name
    proxy_is_blank_string "$input_name" && return 130
    target_name="$(printf '%s' "$input_name" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | tr -d '\n' | sed -E 's/[[:space:]]+/-/g; s/[^a-z0-9._-]+/-/g; s/-+/-/g; s/^[-_.]+//; s/[-_.]+$//')"
    [[ -n "$target_name" ]] || { red "用户名无效，请重新输入。"; return; }
    if user_group_name_exists "$target_name"; then
        yellow "用户名 ${target_name} 已存在，请直接使用该用户名或输入新的用户名。"
        return
    fi
    read -r -p "确认添加用户名 [${target_name}]? [y/N]: " yn
    [[ "${yn,,}" == "y" ]] || return 130
    if proxy_user_group_add "$target_name"; then
        green "已创建用户名 ${target_name}"
    else
        red "用户名创建失败"
    fi
}

delete_user_group() {
    local target_name rc yn
    target_name="$(choose_user_group_name "any" "选择用户名 (删除)")"
    rc=$?
    (( rc == 130 )) && return 130
    [[ -z "$target_name" ]] && return
    [[ "$target_name" == "__none__" ]] && { yellow "当前无可删除用户"; return; }
    [[ "$target_name" == "__invalid__" ]] && { red "输入无效"; return; }

    read -p "确认删除用户名 [${target_name}] 下的全部协议? [y/N]: " yn
    [[ "${yn,,}" == "y" ]] || return 130

    begin_user_group_batch
    local removed_count=0 failed_count=0
    local deleted_group=0
    local -a failed_items=()
    local line state name proto idx in_tag uidx id_b64 user_b64 key_b64 user_id key

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state name proto idx in_tag uidx id_b64 user_b64 key_b64 <<<"$line"
        user_id="$(decode_b64 "$id_b64")"
        key="$(decode_b64 "$key_b64")"
        if [[ "$state" == "active" ]]; then
            if [[ "$proto" == "snell" ]]; then
                local snell_port snell_shadowtls_services=""
                snell_port="$(snell_configured_listen_port 2>/dev/null || true)"
                if [[ "$snell_port" =~ ^[0-9]+$ ]]; then
                    snell_shadowtls_services="$(shadowtls_service_names_by_backend_target_port "snell" "$snell_port" "$conf_file" 2>/dev/null || true)"
                fi
                clear_snell_psk || true
                rm -f "$SNELL_CONF" 2>/dev/null || true
                [[ -n "${snell_shadowtls_services// }" ]] && disable_shadowtls_services_from_list "$snell_shadowtls_services"
                user_meta_clear_key "$key" >/dev/null 2>&1 || true
                record_user_group_snell_action "stop"
                ((removed_count++))
            else
                if remove_active_user_from_conf "$proto" "$in_tag" "$user_id"; then
                    user_meta_clear_key "$key" >/dev/null 2>&1 || true
                    ((removed_count++))
                else
                    failed_items+=("$(proto_group_label "$proto")")
                    ((failed_count++))
                fi
            fi
        else
            if user_meta_clear_key "$key"; then
                ((removed_count++))
            else
                failed_items+=("$(proto_group_label "$proto")")
                ((failed_count++))
            fi
        fi
    done < <(collect_user_group_lines_by_name "$target_name" "any")

    finalize_user_group_batch $(( removed_count > 0 ? 1 : 0 ))
    if [[ "$(user_group_member_count "$target_name")" == "0" ]]; then
        if proxy_user_group_delete "$target_name"; then
            deleted_group=1
            if declare -F proxy_user_route_purge_deleted_name_state >/dev/null 2>&1; then
                proxy_user_route_purge_deleted_name_state "$target_name" "$conf_file" >/dev/null 2>&1 || true
            fi
        fi
    fi

    if (( removed_count > 0 && deleted_group == 1 )); then
        green "已删除用户名 ${target_name} 及其名下全部协议"
    elif (( removed_count > 0 )); then
        green "已删除用户名 ${target_name} 下的全部协议用户"
    elif (( deleted_group == 1 )); then
        green "已删除空用户名 ${target_name}"
    fi
    (( failed_count > 0 )) && red "删除失败协议: ${failed_items[*]}"
    (( removed_count == 0 && deleted_group == 0 && failed_count == 0 )) && yellow "未发生变更"
}

rename_user_group() {
    local current_name rc
    current_name="$(choose_user_group_name "any" "选择用户名 (重命名)")"
    rc=$?
    (( rc == 130 )) && return 130
    [[ -z "$current_name" ]] && return
    [[ "$current_name" == "__none__" ]] && { yellow "无可修改用户名"; return; }
    [[ "$current_name" == "__invalid__" ]] && { red "输入无效"; return; }

    local proposed_name input_name
    proposed_name="$(suggest_global_user_name "$current_name" "$current_name")"
    read -p "用户名 [默认: ${proposed_name}]: " input_name
    proposed_name="$(suggest_global_user_name "${input_name:-$proposed_name}" "$current_name")"

    if [[ "$proposed_name" == "$current_name" ]]; then
        yellow "用户名未变化"
        return
    fi

    begin_user_group_batch
    local updated_count=0 failed_count=0 renamed_group=0
    local -a failed_items=()
    local line state name proto idx in_tag uidx id_b64 user_b64 key_b64 user_id key
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state name proto idx in_tag uidx id_b64 user_b64 key_b64 <<<"$line"
        user_id="$(decode_b64 "$id_b64")"
        key="$(decode_b64 "$key_b64")"
        if [[ "$state" == "disabled" ]]; then
            if user_meta_update_disabled_name "$key" "$proposed_name"; then
                ((updated_count++))
            else
                failed_items+=("$(proto_group_label "$proto")")
                ((failed_count++))
            fi
            continue
        fi

        if [[ "$proto" == "snell" ]]; then
            proxy_user_meta_set_name "$key" "$proposed_name" >/dev/null 2>&1 || true
            ((updated_count++))
            continue
        fi

        rename_active_user_entry "$proto" "$idx" "$user_id" "$proposed_name"
        case $? in
            0|2)
                proxy_user_meta_set_name "$key" "$proposed_name" >/dev/null 2>&1 || true
                ((updated_count++))
                ;;
            *)
                failed_items+=("$(proto_group_label "$proto")")
                ((failed_count++))
                ;;
        esac
    done < <(collect_user_group_lines_by_name "$current_name" "any")

    finalize_user_group_batch $(( updated_count > 0 ? 1 : 0 ))
    if (( failed_count == 0 )); then
        if proxy_user_group_rename "$current_name" "$proposed_name"; then
            renamed_group=1
        else
            failed_items+=("用户名组")
            ((failed_count++))
        fi
    fi
    (( updated_count > 0 || renamed_group == 1 )) && green "用户名已更新为: ${proposed_name}"
    (( failed_count > 0 )) && red "修改失败协议: ${failed_items[*]}"
    (( updated_count == 0 && renamed_group == 0 && failed_count == 0 )) && yellow "未发生变更"
}
