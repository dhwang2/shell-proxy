# Protocol removal and cleanup operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

PROTOCOL_RUNTIME_OPS_FILE="${PROTOCOL_RUNTIME_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_runtime_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_OPS_FILE"
fi

proxy_protocol_remove_empty_entry() {
    local conf_file="${1:-}" proto="${2:-}"
    [[ -n "$proto" ]] || return 1
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    local changed=0 route_sync_needed=0
    local -a shadowtls_services_to_disable=()

    case "$proto" in
        snell)
            if [[ -f "$SNELL_CONF" ]]; then
                local snell_port snell_shadowtls_services=""
                snell_port="$(snell_configured_listen_port 2>/dev/null || true)"
                if [[ "$snell_port" =~ ^[0-9]+$ ]]; then
                    snell_shadowtls_services="$(shadowtls_service_names_by_backend_target_port "snell" "$snell_port" "$conf_file" 2>/dev/null || true)"
                fi
                systemctl stop snell-v5 2>/dev/null || true
                systemctl disable snell-v5 2>/dev/null || true
                rm -f "$SNELL_CONF" 2>/dev/null || true
                [[ -n "${snell_shadowtls_services// }" ]] && shadowtls_services_to_disable+=("$snell_shadowtls_services")
                changed=1
                route_sync_needed=1
            fi
            ;;
        vless|tuic|trojan|anytls|ss)
            [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

            proxy_protocol_inventory_cache_refresh "$conf_file"
            local row row_proto idx tag port desc
            local matched_count=0
            while IFS= read -r row; do
                [[ -n "$row" ]] || continue
                IFS=$'\t' read -r row_proto idx tag port desc <<<"$row"
                [[ "$row_proto" == "$proto" ]] || continue
                ((matched_count++))
                if [[ "$proto" == "ss" && "$port" =~ ^[0-9]+$ ]]; then
                    local ss_shadowtls_services=""
                    ss_shadowtls_services="$(shadowtls_service_names_by_backend_target_port "ss" "$port" "$conf_file" 2>/dev/null || true)"
                    [[ -n "${ss_shadowtls_services// }" ]] && shadowtls_services_to_disable+=("$ss_shadowtls_services")
                fi
            done <<< "$PROXY_PROTOCOL_INVENTORY_ROWS"

            (( matched_count > 0 )) || return 1

            local tmp_json
            tmp_json="$(mktemp)"
            case "$proto" in
                ss)
                    jq '
                        .inbounds = (
                            (.inbounds // [])
                            | map(select(
                                (((.type // "") | ascii_downcase) as $t | ($t == "shadowsocks" or $t == "ss")) | not
                            ))
                        )
                    ' "$conf_file" > "$tmp_json" 2>/dev/null || true
                    ;;
                *)
                    jq --arg p "$proto" '
                        .inbounds = (
                            (.inbounds // [])
                            | map(select((((.type // "") | ascii_downcase) == ($p | ascii_downcase)) | not))
                        )
                    ' "$conf_file" > "$tmp_json" 2>/dev/null || true
                    ;;
            esac

            if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
                backup_conf_file "$conf_file"
                mv "$tmp_json" "$conf_file"
                changed=1
                route_sync_needed=1
            else
                rm -f "$tmp_json"
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac

    if (( changed == 1 )) && [[ "$proto" != "snell" ]]; then
        restart_singbox_if_present
    fi
    if (( route_sync_needed == 1 )) && [[ -n "$conf_file" && -f "$conf_file" ]]; then
        sync_user_template_route_rules "$conf_file" >/dev/null 2>&1 || true
    fi
    if (( ${#shadowtls_services_to_disable[@]} > 0 )); then
        local shadowtls_service_list
        shadowtls_service_list="$(printf '%s\n' "${shadowtls_services_to_disable[@]}" | sed '/^[[:space:]]*$/d' | sort -u)"
        [[ -n "${shadowtls_service_list// }" ]] && disable_shadowtls_services_from_list "$shadowtls_service_list"
    fi

    if (( changed == 1 )); then
        protocol_menu_cache_schedule_rebuild "$conf_file"
        return 0
    fi
    return 1
}

PROTOCOL_MENU_CACHE_DIR="${CACHE_DIR}/view/protocol"
PROTOCOL_MENU_CACHE_LOCK_FILE="${PROTOCOL_MENU_CACHE_DIR}/.rebuild.lock"
PROTOCOL_MENU_CACHE_STATE_FILE="${PROTOCOL_MENU_CACHE_DIR}/state.fp"
PROTOCOL_MENU_CACHE_PROTOCOLS_FILE="${PROTOCOL_MENU_CACHE_DIR}/remove-protocols.list"
PROTOCOL_MENU_CACHE_NAME_ROWS_FILE="${PROTOCOL_MENU_CACHE_DIR}/remove-name-rows.tsv"
PROTOCOL_MENU_CACHE_OCCUPIED_PORTS_FILE="${PROTOCOL_MENU_CACHE_DIR}/install-occupied-ports.txt"

protocol_menu_cache_write_atomic() {
    local path="${1:-}" content="${2:-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv "$tmp_file" "$path"
}

protocol_menu_cache_read_protocols() {
    [[ -f "$PROTOCOL_MENU_CACHE_PROTOCOLS_FILE" ]] || return 1
    cat "$PROTOCOL_MENU_CACHE_PROTOCOLS_FILE" 2>/dev/null
}

protocol_menu_cache_read_name_rows() {
    [[ -f "$PROTOCOL_MENU_CACHE_NAME_ROWS_FILE" ]] || return 1
    cat "$PROTOCOL_MENU_CACHE_NAME_ROWS_FILE" 2>/dev/null
}

protocol_menu_cache_read_occupied_ports() {
    [[ -f "$PROTOCOL_MENU_CACHE_OCCUPIED_PORTS_FILE" ]] || return 1
    cat "$PROTOCOL_MENU_CACHE_OCCUPIED_PORTS_FILE" 2>/dev/null
}

protocol_menu_cache_has_snapshot() {
    [[ -f "$PROTOCOL_MENU_CACHE_PROTOCOLS_FILE" && -f "$PROTOCOL_MENU_CACHE_NAME_ROWS_FILE" && -f "$PROTOCOL_MENU_CACHE_OCCUPIED_PORTS_FILE" ]]
}

protocol_menu_cache_read_state_fingerprint() {
    [[ -f "$PROTOCOL_MENU_CACHE_STATE_FILE" ]] || return 1
    tr -d '[:space:]' <"$PROTOCOL_MENU_CACHE_STATE_FILE" 2>/dev/null
}

protocol_menu_cache_state_fingerprint() {
    local conf_file="${1:-}"
    local conf_fp meta_fp snell_fp shadowtls_fp
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"
    conf_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    meta_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    snell_fp="$(calc_file_fingerprint "$SNELL_CONF" 2>/dev/null || echo "0:0")"
    shadowtls_fp="$(calc_shadowtls_render_fingerprint 2>/dev/null | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$shadowtls_fp" ]] || shadowtls_fp="0:0"
    printf '%s|%s|%s|%s\n' "$conf_fp" "$meta_fp" "$snell_fp" "$shadowtls_fp" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

protocol_menu_cache_is_fresh() {
    local conf_file="${1:-}" cached_fp expected_fp
    protocol_menu_cache_has_snapshot || return 1

    cached_fp="$(protocol_menu_cache_read_state_fingerprint 2>/dev/null || true)"
    [[ -n "$cached_fp" ]] || return 1

    expected_fp="$(protocol_menu_cache_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$expected_fp" ]] || return 1

    [[ "$cached_fp" == "$expected_fp" ]]
}

protocol_menu_cache_ensure_fresh() {
    local conf_file="${1:-}"
    if protocol_menu_cache_is_fresh "$conf_file"; then
        return 0
    fi
    protocol_menu_cache_rebuild_with_lock "$conf_file" >/dev/null 2>&1 || return 1
    protocol_menu_cache_is_fresh "$conf_file"
}

protocol_menu_cache_rebuild_sync() {
    local conf_file="${1:-}" state_fp
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    proxy_protocol_inventory_cache_refresh "$conf_file"
    proxy_protocol_occupied_ports_cache_refresh "$conf_file"
    proxy_user_derived_cache_refresh "$conf_file"

    state_fp="$(protocol_menu_cache_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"

    protocol_menu_cache_write_atomic "$PROTOCOL_MENU_CACHE_PROTOCOLS_FILE" "${PROXY_PROTOCOL_INSTALLED_CACHE:-}" || return 1
    protocol_menu_cache_write_atomic "$PROTOCOL_MENU_CACHE_NAME_ROWS_FILE" "${PROXY_USER_NAME_ROWS_CACHE:-}" || return 1
    protocol_menu_cache_write_atomic "$PROTOCOL_MENU_CACHE_OCCUPIED_PORTS_FILE" "${PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE:-}" || return 1
    protocol_menu_cache_write_atomic "$PROTOCOL_MENU_CACHE_STATE_FILE" "${state_fp}" || return 1
}

protocol_menu_cache_rebuild_with_lock() {
    local conf_file="${1:-}"
    mkdir -p "$PROTOCOL_MENU_CACHE_DIR" >/dev/null 2>&1 || true

    if command -v flock >/dev/null 2>&1; then
        (
            flock -n 9 || exit 0
            protocol_menu_cache_rebuild_sync "$conf_file"
        ) 9>"$PROTOCOL_MENU_CACHE_LOCK_FILE"
        return $?
    fi

    local lock_dir="${PROTOCOL_MENU_CACHE_LOCK_FILE}.d"
    mkdir "$lock_dir" >/dev/null 2>&1 || return 0
    protocol_menu_cache_rebuild_sync "$conf_file"
    rmdir "$lock_dir" >/dev/null 2>&1 || true
}

protocol_menu_cache_schedule_rebuild() {
    local conf_file="${1:-}"
    (
        protocol_menu_cache_rebuild_with_lock "$conf_file" >/dev/null 2>&1 || true
    ) >/dev/null 2>&1 &
}

protocol_menu_cache_schedule_rebuild_if_stale() {
    local conf_file="${1:-}"
    if protocol_menu_cache_is_fresh "$conf_file"; then
        return 0
    fi
    protocol_menu_cache_schedule_rebuild "$conf_file"
}

remove_protocol_collect_name_rows_from_text() {
    local target_proto="${1:-}"
    local rows_text="${2:-}"
    local row row_proto name active_count disabled_count
    [[ -n "$target_proto" ]] || return 0
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS=$'\t' read -r row_proto name active_count disabled_count <<<"$row"
        [[ "$row_proto" == "$target_proto" ]] || continue
        printf '%s\t%s\t%s\n' "$name" "$active_count" "$disabled_count"
    done <<< "$rows_text"
}

protocol_remove_apply_changes_with_feedback() {
    local conf_file="${1:-}" conf_changed="${2:-0}" route_sync_needed="${3:-0}" shadowtls_service_list="${4:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if (( conf_changed == 1 )); then
        restart_singbox_if_present
    fi
    if (( route_sync_needed == 1 )); then
        sync_user_template_route_rules "$conf_file" >/dev/null 2>&1 || true
    fi
    if [[ -n "${shadowtls_service_list// }" ]]; then
        disable_shadowtls_services_from_list "$shadowtls_service_list"
    fi
}

protocol_remove_apply_changes_with_spinner() {
    local conf_file="${1:-}" conf_changed="${2:-0}" route_sync_needed="${3:-0}" shadowtls_service_list="${4:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if declare -F proxy_run_with_spinner >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        proxy_run_with_spinner "正在应用协议卸载变更..." \
            protocol_remove_apply_changes_with_feedback "$conf_file" "$conf_changed" "$route_sync_needed" "$shadowtls_service_list"
        return $?
    fi

    protocol_remove_apply_changes_with_feedback "$conf_file" "$conf_changed" "$route_sync_needed" "$shadowtls_service_list"
}

remove_protocol() {
    while :; do
        ui_clear
        proxy_menu_header "卸载协议"

        local conf_file
        conf_file="$(get_conf_file)"

        local protocol_names=()
        local proto
        local cached_name_rows_text=""
        if ! protocol_menu_cache_ensure_fresh "$conf_file"; then
            protocol_menu_cache_schedule_rebuild_if_stale "$conf_file"
        fi
        mapfile -t protocol_names < <(protocol_menu_cache_read_protocols 2>/dev/null | awk 'NF')
        cached_name_rows_text="$(protocol_menu_cache_read_name_rows 2>/dev/null || true)"
        if [[ ${#protocol_names[@]} -eq 0 ]]; then
            yellow "当前未检测到可卸载的协议。"
            pause
            return
        fi

        local summary_block=""
        local row summary_parts name active_count disabled_count total_count user_count idx
        local -a protocol_name_rows
        local -a protocol_user_counts=()
        local -a summary_protos=() summary_labels=() summary_counts=() summary_users=()
        idx=1
        for proto in "${protocol_names[@]}"; do
            mapfile -t protocol_name_rows < <(remove_protocol_collect_name_rows_from_text "$proto" "$cached_name_rows_text")
            user_count="${#protocol_name_rows[@]}"
            protocol_user_counts+=("$user_count")
            summary_parts=()
            for row in "${protocol_name_rows[@]}"; do
                [[ -n "$row" ]] || continue
                IFS=$'\t' read -r name active_count disabled_count <<<"$row"
                total_count=$(( active_count + disabled_count ))
                summary_parts+=("${name}(${total_count})")
            done
            summary_protos+=("$idx")
            summary_labels+=("$(proxy_user_protocol_label "$proto")")
            summary_counts+=("$user_count")
            local IFS='  '; summary_users+=("${summary_parts[*]:-无}"); unset IFS
            ((idx++))
        done
        local target_proto
        printf '  %-4s %-14s %-6s %s\n' "#" "协议" "用户" "详情"
        proxy_menu_divider
        for ((idx=0; idx<${#summary_protos[@]}; idx++)); do
            printf '  %-4s %-14s %-6s %s\n' \
                "${summary_protos[$idx]}" "${summary_labels[$idx]}" "${summary_counts[$idx]}" "${summary_users[$idx]}"
        done
        proxy_menu_rule "═"
        echo
        if ! read_prompt pick "选择序号(回车取消): "; then
            return
        fi
        [[ -z "$pick" ]] && return
        if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#protocol_names[@]} )); then
            red "输入无效"
            pause
            continue
        fi
        target_proto="${protocol_names[$((pick-1))]}"

        # 执行动作前按实时数据二次确认，避免快照瞬时滞后导致误判。
        proxy_user_derived_cache_refresh "$conf_file"

        local name_rows=()
        mapfile -t name_rows < <(remove_protocol_collect_name_rows_from_text "$target_proto" "${PROXY_USER_NAME_ROWS_CACHE:-}")
        if [[ ${#name_rows[@]} -eq 0 ]]; then
            local target_label
            target_label="$(proxy_user_protocol_label "$target_proto")"
            yellow "当前协议已安装，但当前没有任何用户名使用。"
            if ! read_prompt yn "确认直接删除空协议 [${target_label}] 的入站配置? [y/N]: "; then
                yn=""
            fi
            [[ "${yn,,}" == "y" ]] || { yellow "已取消"; pause; continue; }

            if proxy_protocol_remove_empty_entry "$conf_file" "$target_proto"; then
                green "已删除空协议 ${target_label}"
                protocol_menu_cache_schedule_rebuild "$conf_file"
            else
                red "删除空协议 ${target_label} 失败"
            fi
            pause
            continue
        fi

        local target_name
        echo "选择用户名 (卸载 $(proxy_user_protocol_label "$target_proto"))"
        local idx=1 row active_count disabled_count
        for row in "${name_rows[@]}"; do
            IFS=$'\t' read -r target_name active_count disabled_count <<<"$row"
            printf '%d. %s\n' "$idx" "$target_name"
            ((idx++))
        done
        if ! read_prompt pick "选择序号(回车取消): "; then
            return
        fi
        [[ -z "$pick" ]] && return
        if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#name_rows[@]} )); then
            red "输入无效"
            pause
            continue
        fi
        IFS=$'\t' read -r target_name _active_count _disabled_count <<<"${name_rows[$((pick-1))]}"

        local protos=()
        [[ -z "$target_proto" ]] && return
        protos+=("$target_proto")

        if ! read_prompt yn "确认卸载用户名 [${target_name}] 的 ${#protos[@]} 项协议? [y/N]: "; then
            yn=""
        fi
        [[ "${yn,,}" == "y" ]] || { yellow "已取消"; pause; continue; }

        local removed_count=0 failed_count=0 conf_changed=0 route_sync_needed=0
        local -a removed_labels=() failed_labels=() shadowtls_services_to_disable=()

        for proto in "${protos[@]}"; do
            local memberships=()
            local line state line_name in_tag id_b64 key_b64 user_b64 key user_id remove_result remove_port still_exists
            while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                IFS='|' read -r state line_name _proto in_tag id_b64 key_b64 user_b64 <<<"$line"
                [[ "$line_name" == "$target_name" && "$_proto" == "$proto" ]] || continue
                memberships+=("$line")
            done < <(proxy_user_collect_membership_lines "any" "$conf_file")

            if [[ ${#memberships[@]} -eq 0 ]]; then
                continue
            fi

            for line in "${memberships[@]}"; do
                IFS='|' read -r state _line_name _proto in_tag id_b64 key_b64 user_b64 <<<"$line"
                key="$(proxy_user_decode_b64 "$key_b64")"
                user_id="$(proxy_user_decode_b64 "$id_b64")"

                if [[ "$state" == "disabled" ]]; then
                    if proxy_user_meta_clear_key "$key"; then
                        ((removed_count++))
                    else
                        failed_labels+=("$(proxy_user_protocol_label "$proto")")
                        ((failed_count++))
                    fi
                    continue
                fi

                if [[ "$proto" == "snell" ]]; then
                    local snell_port snell_shadowtls_services
                    snell_port="$(grep "^listen" "$SNELL_CONF" 2>/dev/null | awk -F':' '{print $NF}' | tr -d ' ')"
                    snell_shadowtls_services="$(shadowtls_service_names_by_backend_target_port "snell" "$snell_port" "$conf_file" 2>/dev/null || true)"
                    systemctl stop snell-v5 2>/dev/null || true
                    systemctl disable snell-v5 2>/dev/null || true
                    rm -f "$SNELL_CONF" 2>/dev/null || true
                    [[ -n "${snell_shadowtls_services// }" ]] && shadowtls_services_to_disable+=("$snell_shadowtls_services")
                    proxy_user_meta_clear_key "$key" >/dev/null 2>&1 || true
                    ((removed_count++))
                    route_sync_needed=1
                    continue
                fi

                local ss_shadowtls_services=""
                if [[ "$proto" == "ss" ]]; then
                    local ss_idx ss_port
                    ss_idx="$(proxy_user_find_inbound_index_by_tag "$conf_file" "$proto" "$in_tag")"
                    if [[ "$ss_idx" =~ ^[0-9]+$ ]]; then
                        ss_port="$(jq -r --argjson i "$ss_idx" '.inbounds[$i].listen_port // ""' "$conf_file" 2>/dev/null || true)"
                        [[ -n "$ss_port" ]] && ss_shadowtls_services="$(shadowtls_service_names_by_backend_target_port "ss" "$ss_port" "$conf_file" 2>/dev/null || true)"
                    fi
                fi

                remove_result="$(proxy_user_remove_active_member_from_conf "$conf_file" "$proto" "$in_tag" "$user_id" 2>/dev/null || true)"
                if [[ -z "$remove_result" ]]; then
                    failed_labels+=("$(proxy_user_protocol_label "$proto")")
                    ((failed_count++))
                    continue
                fi
                IFS='|' read -r remove_port still_exists <<<"$remove_result"
                proxy_user_meta_clear_key "$key" >/dev/null 2>&1 || true
                ((removed_count++))
                conf_changed=1
                route_sync_needed=1
                if [[ "$proto" == "ss" && "$still_exists" == "0" && -n "${ss_shadowtls_services// }" ]]; then
                    shadowtls_services_to_disable+=("$ss_shadowtls_services")
                fi
            done

            removed_labels+=("$(proxy_user_protocol_label "$proto")")
        done

        local shadowtls_service_list=""
        if (( ${#shadowtls_services_to_disable[@]} > 0 )); then
            shadowtls_service_list="$(printf '%s\n' "${shadowtls_services_to_disable[@]}" | sed '/^[[:space:]]*$/d' | sort -u)"
        fi
        if (( conf_changed == 1 || route_sync_needed == 1 )) || [[ -n "${shadowtls_service_list// }" ]]; then
            protocol_remove_apply_changes_with_spinner "$conf_file" "$conf_changed" "$route_sync_needed" "$shadowtls_service_list"
        fi

        (( removed_count > 0 )) && green "已为用户名 ${target_name} 卸载协议: ${removed_labels[*]}"
        (( failed_count > 0 )) && red "卸载失败协议: ${failed_labels[*]}"
        (( removed_count == 0 && failed_count == 0 )) && yellow "未发生变更"
        protocol_menu_cache_schedule_rebuild "$conf_file"
        pause
    done
}

# --- protocol inventory and port cache (merged from protocol_inventory_ops.sh) ---

proxy_protocol_inventory_cache_fingerprint() {
    local conf_file="${1:-}"
    local conf_fp snell_fp
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"
    conf_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    snell_fp="$(calc_file_fingerprint "$SNELL_CONF" 2>/dev/null || echo "0:0")"
    printf '%s|%s\n' "$conf_fp" "$snell_fp" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

proxy_protocol_inventory_cache_refresh() {
    local conf_file="${1:-}"
    local current_fp snell_port
    current_fp="$(proxy_protocol_inventory_cache_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$current_fp" ]] || current_fp="0:0|0:0"

    if [[ "$PROXY_PROTOCOL_INVENTORY_CACHE_FP" == "$current_fp" ]]; then
        return 0
    fi

    PROXY_PROTOCOL_INVENTORY_ROWS=""
    PROXY_PROTOCOL_INSTALLED_CACHE=""

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        PROXY_PROTOCOL_INVENTORY_ROWS="$(jq -r '
            .inbounds
            | to_entries[]?
            | ((.value.type // "") | ascii_downcase) as $type
            | if $type == "vless" then
                "vless\t\(.key)\t\(.value.tag // ("inbound_" + (.key|tostring)))\t\(.value.listen_port // "-")\tSNI=\(.value.tls.server_name // "-")"
              elif $type == "tuic" then
                "tuic\t\(.key)\t\(.value.tag // ("inbound_" + (.key|tostring)))\t\(.value.listen_port // "-")\tSNI=\(.value.tls.server_name // "-")"
              elif $type == "trojan" then
                "trojan\t\(.key)\t\(.value.tag // ("inbound_" + (.key|tostring)))\t\(.value.listen_port // "-")\tSNI=\(.value.tls.server_name // "-")"
              elif $type == "anytls" then
                "anytls\t\(.key)\t\(.value.tag // ("inbound_" + (.key|tostring)))\t\(.value.listen_port // "-")\tSNI=\(.value.tls.server_name // "-")"
              elif ($type == "shadowsocks" or $type == "ss") then
                "ss\t\(.key)\t\(.value.tag // ("inbound_" + (.key|tostring)))\t\(.value.listen_port // "-")\tmethod=\(.value.method // "-")"
              else
                empty
              end
        ' "$conf_file" 2>/dev/null || true)"
    fi

    snell_port="$(snell_configured_listen_port 2>/dev/null || true)"
    if [[ "$snell_port" =~ ^[0-9]+$ ]]; then
        if [[ -n "$PROXY_PROTOCOL_INVENTORY_ROWS" ]]; then
            PROXY_PROTOCOL_INVENTORY_ROWS+=$'\n'
        fi
        PROXY_PROTOCOL_INVENTORY_ROWS+=$'snell\tsnell\tsnell-v5\t'"${snell_port}"$'\tpsk=configured'
    fi

    if [[ -n "$PROXY_PROTOCOL_INVENTORY_ROWS" ]]; then
        PROXY_PROTOCOL_INSTALLED_CACHE="$(printf '%s\n' "$PROXY_PROTOCOL_INVENTORY_ROWS" | awk -F'\t' 'NF && $1 != "" && !seen[$1]++ {print $1}')"
    fi

    PROXY_PROTOCOL_INVENTORY_CACHE_FP="$current_fp"
}

proxy_protocol_occupied_ports_cache_refresh() {
    local conf_file="${1:-}"
    local inventory_fp shadowtls_fp current_fp
    local line proto idx tag port desc st_line st_service st_listen st_target st_backend st_sni st_pass

    # Reuse already-refreshed inventory if available; avoid redundant scan
    # when called right after proxy_protocol_inventory_cache_refresh.
    [[ -n "$PROXY_PROTOCOL_INVENTORY_CACHE_FP" ]] || proxy_protocol_inventory_cache_refresh "$conf_file"
    inventory_fp="${PROXY_PROTOCOL_INVENTORY_CACHE_FP:-0:0}"
    shadowtls_fp="$(calc_shadowtls_render_fingerprint | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$shadowtls_fp" ]] || shadowtls_fp="-"
    current_fp="$(printf '%s|%s\n' "$inventory_fp" "$shadowtls_fp" | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$current_fp" ]] || current_fp="0:0"

    if [[ "$PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE_FP" == "$current_fp" ]]; then
        return 0
    fi

    PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE="$({
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            IFS=$'\t' read -r proto idx tag port desc <<<"$line"
            [[ "$port" =~ ^[0-9]+$ ]] && printf '%s\n' "$port"
        done <<< "$PROXY_PROTOCOL_INVENTORY_ROWS"
        while IFS= read -r st_line; do
            [[ -n "$st_line" ]] || continue
            IFS='|' read -r st_service st_listen st_target st_backend st_sni st_pass <<<"$st_line"
            [[ "$st_listen" =~ ^[0-9]+$ ]] && printf '%s\n' "$st_listen"
        done < <(shadowtls_binding_lines "$conf_file")
    } | awk '/^[0-9]+$/' | sort -n | awk '!seen[$0]++' | paste -sd' ' -)"
    PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE_FP="$current_fp"
}

proxy_collect_inbound_rows_by_protocol() {
    local conf_file="${1:-}" proto="${2:-}"
    [[ -n "$proto" ]] || return 0
    proxy_protocol_inventory_cache_refresh "$conf_file"

    local row row_proto idx tag port desc
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS=$'\t' read -r row_proto idx tag port desc <<<"$row"
        [[ "$row_proto" == "$proto" ]] || continue
        printf '%s\t%s\t%s\t%s\n' "$idx" "$tag" "$port" "$desc"
    done <<< "$PROXY_PROTOCOL_INVENTORY_ROWS"
}
