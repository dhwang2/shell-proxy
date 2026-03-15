# Routing rule menu actions for shell-proxy management.

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

ROUTING_RULE_MENU_CORE_OPS_FILE="${ROUTING_RULE_MENU_CORE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_core_ops.sh}"
if [[ -f "$ROUTING_RULE_MENU_CORE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_RULE_MENU_CORE_OPS_FILE"
fi

ROUTING_SELECTOR_OPS_FILE="${ROUTING_SELECTOR_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_ops.sh}"
if [[ -f "$ROUTING_SELECTOR_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_SELECTOR_OPS_FILE"
fi

ROUTING_RULE_SESSION_ACTIVE=0
ROUTING_RULE_SESSION_CONF_FILE=""
ROUTING_RULE_SESSION_OLD_STATE="[]"
ROUTING_RULE_SESSION_CURRENT_STATE="[]"
ROUTING_RULE_SESSION_DIRTY=0
ROUTING_RULE_SESSION_STATE_LOADED=0

routing_rule_session_begin() {
    local conf_file="${1:-}"
    ROUTING_RULE_SESSION_ACTIVE=1
    ROUTING_RULE_SESSION_CONF_FILE="$conf_file"
    ROUTING_RULE_SESSION_OLD_STATE="[]"
    ROUTING_RULE_SESSION_CURRENT_STATE="[]"
    ROUTING_RULE_SESSION_DIRTY=0
    ROUTING_RULE_SESSION_STATE_LOADED=0
}

routing_rule_session_end() {
    ROUTING_RULE_SESSION_ACTIVE=0
    ROUTING_RULE_SESSION_CONF_FILE=""
    ROUTING_RULE_SESSION_OLD_STATE="[]"
    ROUTING_RULE_SESSION_CURRENT_STATE="[]"
    ROUTING_RULE_SESSION_DIRTY=0
    ROUTING_RULE_SESSION_STATE_LOADED=0
}

routing_rule_session_ensure_state_loaded() {
    local loaded_state=""
    if (( ROUTING_RULE_SESSION_ACTIVE != 1 )); then
        return 1
    fi
    if (( ROUTING_RULE_SESSION_STATE_LOADED == 1 )); then
        return 0
    fi

    loaded_state="$(routing_load_state_json)"
    [[ -n "$loaded_state" ]] || loaded_state="[]"
    ROUTING_RULE_SESSION_OLD_STATE="$loaded_state"
    ROUTING_RULE_SESSION_CURRENT_STATE="$loaded_state"
    ROUTING_RULE_SESSION_STATE_LOADED=1
}

routing_rule_session_state_json() {
    if (( ROUTING_RULE_SESSION_ACTIVE == 1 )); then
        routing_rule_session_ensure_state_loaded >/dev/null 2>&1 || true
        printf '%s\n' "${ROUTING_RULE_SESSION_CURRENT_STATE:-[]}"
        return 0
    fi
    routing_load_state_json
}

routing_rule_session_set_state() {
    local new_state="${1:-[]}"
    if (( ROUTING_RULE_SESSION_ACTIVE != 1 )); then
        return 1
    fi
    routing_rule_session_ensure_state_loaded >/dev/null 2>&1 || true
    if [[ "${ROUTING_RULE_SESSION_CURRENT_STATE:-[]}" == "$new_state" ]]; then
        return 1
    fi
    ROUTING_RULE_SESSION_CURRENT_STATE="$new_state"
    ROUTING_RULE_SESSION_DIRTY=1
    return 0
}

routing_apply_state_change_with_feedback() {
    local conf_file="${1:-}" old_state="${2:-[]}" new_state="${3:-[]}" success_message="${4:-已应用变更}" failure_message="${5:-应用变更失败}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    backup_conf_file "$conf_file"
    local rc=0
    if routing_commit_state_change "$conf_file" "$old_state" "$new_state"; then
        if ! routing_context_is_user; then
            restart_singbox_if_present
        fi
        green "$success_message"
        return 0
    fi
    rc=$?
    [[ "$rc" -eq 2 ]] || red "$failure_message"
    return "$rc"
}

routing_apply_state_change_with_spinner() {
    local conf_file="${1:-}" old_state="${2:-[]}" new_state="${3:-[]}" spinner_message="${4:-正在应用分流变更...}"
    local success_message="${5:-已应用变更}" failure_message="${6:-应用变更失败}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if declare -F proxy_run_with_spinner >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        proxy_run_with_spinner "$spinner_message" \
            routing_apply_state_change_with_feedback "$conf_file" "$old_state" "$new_state" "$success_message" "$failure_message"
        return $?
    fi

    routing_apply_state_change_with_feedback "$conf_file" "$old_state" "$new_state" "$success_message" "$failure_message"
}

routing_rule_session_apply_pending() {
    local conf_file="${1:-$ROUTING_RULE_SESSION_CONF_FILE}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1
    if (( ROUTING_RULE_SESSION_ACTIVE != 1 )); then
        return 1
    fi
    if (( ROUTING_RULE_SESSION_DIRTY != 1 )); then
        yellow "当前没有待提交的分流变更。"
        return 0
    fi

    if routing_apply_state_change_with_spinner \
        "$conf_file" "$ROUTING_RULE_SESSION_OLD_STATE" "$ROUTING_RULE_SESSION_CURRENT_STATE" \
        "正在应用分流变更..." "已保存并应用待提交分流变更" "保存分流规则失败"; then
        ROUTING_RULE_SESSION_OLD_STATE="$ROUTING_RULE_SESSION_CURRENT_STATE"
        ROUTING_RULE_SESSION_DIRTY=0
        return 0
    fi
    return $?
}

routing_add_rule_interactive() {
    local conf_file="$1"
    ui_clear
    local render_file=""
    render_file="$(routing_render_to_temp_file)"
    {
        proxy_menu_header "添加分流规则"
        echo "1. OpenAI/ChatGPT"
        echo "2. Anthropic/Claude"
        echo "3. Google"
        echo "4. YouTube"
        echo "5. Telegram"
        echo "6. Twitter/X"
        echo "7. WhatsApp"
        echo "8. Facebook"
        echo "9. GitHub"
        echo "g. Discord"
        echo "h. Instagram"
        echo "i. Reddit"
        echo "j. xAI/Grok"
        echo "k. Microsoft"
        echo "l. LinkedIn"
        echo "m. PayPal"
        echo "n. Meta"
        echo "o. Messenger"
        echo "a. AI服务(国际)"
        echo "b. Netflix"
        echo "d. Disney+"
        echo "e. MyTVSuper"
        echo "s. Spotify"
        echo "t. TikTok"
        echo "r. 广告屏蔽"
        echo "c. 自定义域名/IP/CIDR"
        echo "f. 所有流量"
        echo "可多选: 1,2,3 或 b,s,r"
        proxy_menu_rule "═"
        echo
    } >"$render_file"
    routing_print_rendered_file "$render_file"
    if ! read_prompt rt_choice "选择: "; then
        return 1
    fi

    [[ -z "$rt_choice" || "$rt_choice" == "0" ]] && return 0

    local rt_compact token mapped_type
    local -a picked_types raw_tokens
    rt_compact="$(echo "$rt_choice" | tr '，；; ' ',,,,')"
    rt_compact="${rt_compact//,,/,}"
    rt_compact="${rt_compact#,}"
    rt_compact="${rt_compact%,}"
    [[ -z "$rt_compact" ]] && return 0

    IFS=',' read -r -a raw_tokens <<< "$rt_compact"
    local picked_csv=","
    for token in "${raw_tokens[@]}"; do
        token="$(echo "$token" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        [[ -z "$token" ]] && continue
        mapped_type=""
        case "$token" in
            1) mapped_type="openai" ;;
            2) mapped_type="anthropic" ;;
            3) mapped_type="google" ;;
            4) mapped_type="youtube" ;;
            5) mapped_type="telegram" ;;
            6) mapped_type="twitter" ;;
            7) mapped_type="whatsapp" ;;
            8) mapped_type="facebook" ;;
            9) mapped_type="github" ;;
            g) mapped_type="discord" ;;
            h) mapped_type="instagram" ;;
            i) mapped_type="reddit" ;;
            j) mapped_type="xai" ;;
            k) mapped_type="microsoft" ;;
            l) mapped_type="linkedin" ;;
            m) mapped_type="paypal" ;;
            n) mapped_type="meta" ;;
            o) mapped_type="messenger" ;;
            a) mapped_type="ai-intl" ;;
            b) mapped_type="netflix" ;;
            d) mapped_type="disney" ;;
            e) mapped_type="mytvsuper" ;;
            s) mapped_type="spotify" ;;
            t) mapped_type="tiktok" ;;
            r) mapped_type="ads" ;;
            c) mapped_type="custom" ;;
            f) mapped_type="all" ;;
            *) red "无效输入"; pause; return 1 ;;
        esac
        if [[ "$picked_csv" != *",$mapped_type,"* ]]; then
            picked_types+=("$mapped_type")
            picked_csv+="${mapped_type},"
        fi
    done
    [[ ${#picked_types[@]} -eq 0 ]] && { red "无效输入"; pause; return 1; }

    local outbound
    outbound="$(routing_select_outbound "$conf_file")" || return 0

    local domains=""
    if [[ "$picked_csv" == *",custom,"* ]]; then
        echo
        echo "示例: openai.com,claude.ai,1.2.3.4/32,keyword:telegram"
        read -p "输入匹配规则(逗号分隔): " domains
        domains="$(echo "$domains" | tr -d '[:space:]')"
        [[ -z "$domains" ]] && { yellow "输入为空，已取消"; pause; return 1; }
        local preview_rule
        preview_rule="$(routing_build_custom_rule "$outbound" "$domains")"
        [[ -z "$preview_rule" ]] && { red "自定义规则无有效匹配项，已取消"; pause; return 1; }
    fi

    local old_state new_state rule_id rule_type
    old_state="$(routing_rule_session_state_json)"
    new_state="$old_state"
    for rule_type in "${picked_types[@]}"; do
        rule_id="r$(date +%s)${RANDOM}"
        if [[ "$rule_type" == "custom" ]]; then
            new_state="$(echo "$new_state" | jq -c \
                --arg id "$rule_id" \
                --arg outbound "$outbound" \
                --arg domains "$domains" '
                (. + [{id:$id, type:"custom", outbound:$outbound, domains:$domains}])
                | (map(select(.type != "all")) + map(select(.type == "all")))
            ' 2>/dev/null)"
        else
            new_state="$(echo "$new_state" | jq -c \
                --arg id "$rule_id" \
                --arg type "$rule_type" \
                --arg outbound "$outbound" '
                ([.[] | select(.type != $type)] + [{id:$id, type:$type, outbound:$outbound, domains:""}])
                | (map(select(.type != "all")) + map(select(.type == "all")))
            ' 2>/dev/null)"
        fi
        [[ -z "$new_state" ]] && break
    done

    [[ -z "$new_state" ]] && { red "规则生成失败"; pause; return 1; }
    if (( ROUTING_RULE_SESSION_ACTIVE == 1 )); then
        if routing_rule_session_set_state "$new_state"; then
            green "分流规则已加入待提交（本次处理 ${#picked_types[@]} 项）"
        else
            yellow "规则未发生变化，无需提交。"
        fi
    else
        routing_apply_state_change_with_spinner \
            "$conf_file" "$old_state" "$new_state" \
            "正在应用分流变更..." "分流规则已更新（本次处理 ${#picked_types[@]} 项）" "更新分流规则失败"
    fi
    pause
}

routing_delete_rule_interactive() {
    local conf_file="$1"
    local state_json
    state_json="$(routing_rule_session_state_json)"
    local count
    count="$(echo "$state_json" | jq -r 'length' 2>/dev/null || echo 0)"
    if [[ "$count" -eq 0 ]]; then
        yellow "当前没有分流规则。"
        pause
        return 0
    fi

    ui_clear
    local render_file=""
    render_file="$(routing_render_to_temp_file)"
    {
        proxy_menu_header "删除分流规则"
        local idx=1 entry
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            routing_rule_display_line "$idx" "$entry"
            idx=$((idx + 1))
        done < <(echo "$state_json" | jq -c '.[]?' 2>/dev/null)
        proxy_menu_rule "═"
        echo
    } >"$render_file"
    routing_print_rendered_file "$render_file"
    if ! read_prompt del_choice "选择: "; then
        return 0
    fi
    [[ -z "$del_choice" || "$del_choice" == "0" ]] && return 0

    local del_compact token normalized deleted_count=0 yn
    local -a del_tokens selected_indexes
    local -A selected_map=()
    del_compact="$(echo "$del_choice" | tr '，；; ' ',,,,')"
    del_compact="${del_compact//,,/,}"
    del_compact="${del_compact#,}"
    del_compact="${del_compact%,}"
    [[ -z "$del_compact" ]] && return 0

    IFS=',' read -r -a del_tokens <<< "$del_compact"
    for token in "${del_tokens[@]}"; do
        normalized="$(echo "$token" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        [[ -z "$normalized" ]] && continue
        case "$normalized" in
            a|all|'*')
                local i
                for ((i=1; i<=count; i++)); do
                    selected_map["$i"]=1
                done
                ;;
            *)
                if ! [[ "$normalized" =~ ^[0-9]+$ ]] || (( normalized < 1 || normalized > count )); then
                    red "无效输入"
                    pause
                    return 1
                fi
                selected_map["$normalized"]=1
                ;;
        esac
    done

    for token in "${!selected_map[@]}"; do
        selected_indexes+=("$token")
    done
    (( ${#selected_indexes[@]} > 0 )) || { yellow "未选择任何规则"; pause; return 0; }

    IFS=$'\n' selected_indexes=($(printf '%s\n' "${selected_indexes[@]}" | sort -n))
    unset IFS
    deleted_count="${#selected_indexes[@]}"

    read -r -p "确认删除已选中的 ${deleted_count} 条分流规则? [y/N]: " yn
    [[ "${yn,,}" == "y" ]] || return 0

    local old_state new_state
    old_state="$state_json"
    local jq_indexes='[]'
    for token in "${selected_indexes[@]}"; do
        jq_indexes="$(jq -c --argjson idx "$((token - 1))" '. + [$idx]' <<<"$jq_indexes" 2>/dev/null || echo '[]')"
    done
    new_state="$(jq -c --argjson idxs "$jq_indexes" '
        to_entries | map(select((.key as $k | ($idxs | index($k))) == null)) | map(.value)
    ' <<<"$old_state" 2>/dev/null)"
    [[ -z "$new_state" ]] && { red "删除失败"; pause; return 1; }

    if (( ROUTING_RULE_SESSION_ACTIVE == 1 )); then
        if routing_rule_session_set_state "$new_state"; then
            green "已删除 ${deleted_count} 条分流规则（待提交）"
        else
            yellow "规则未发生变化，无需提交。"
        fi
    else
        routing_apply_state_change_with_spinner \
            "$conf_file" "$old_state" "$new_state" \
            "正在应用分流变更..." "已删除 ${deleted_count} 条分流规则" "删除分流规则失败"
    fi
    pause
}

routing_modify_rule_interactive() {
    local conf_file="$1"
    local state_json
    state_json="$(routing_rule_session_state_json)"
    local count
    count="$(jq -r 'length' <<<"$state_json" 2>/dev/null || echo 0)"
    if [[ "$count" -eq 0 ]]; then
        yellow "当前没有分流规则。"
        pause
        return 0
    fi

    ui_clear
    local render_file=""
    render_file="$(routing_render_to_temp_file)"
    {
        proxy_menu_header "修改分流规则"
        local idx=1 entry
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            routing_rule_display_line "$idx" "$entry"
            idx=$((idx + 1))
        done < <(jq -c '.[]?' <<<"$state_json" 2>/dev/null)
        proxy_menu_rule "═"
        echo
    } >"$render_file"
    routing_print_rendered_file "$render_file"
    local mod_choice=""
    if ! read_prompt mod_choice "选择: "; then
        return 0
    fi
    [[ -z "$mod_choice" || "$mod_choice" == "0" ]] && return 0

    local mod_compact token normalized modified_count=0 yn
    local -a mod_tokens selected_indexes
    local -A selected_map=()
    mod_compact="$(echo "$mod_choice" | tr '，；; ' ',,,,')"
    mod_compact="${mod_compact//,,/,}"
    mod_compact="${mod_compact#,}"
    mod_compact="${mod_compact%,}"
    [[ -z "$mod_compact" ]] && return 0

    IFS=',' read -r -a mod_tokens <<< "$mod_compact"
    for token in "${mod_tokens[@]}"; do
        normalized="$(echo "$token" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        [[ -z "$normalized" ]] && continue
        case "$normalized" in
            a|all|'*')
                local i
                for ((i=1; i<=count; i++)); do
                    selected_map["$i"]=1
                done
                ;;
            *)
                if ! [[ "$normalized" =~ ^[0-9]+$ ]] || (( normalized < 1 || normalized > count )); then
                    red "无效输入"
                    pause
                    return 1
                fi
                selected_map["$normalized"]=1
                ;;
        esac
    done

    for token in "${!selected_map[@]}"; do
        selected_indexes+=("$token")
    done
    (( ${#selected_indexes[@]} > 0 )) || { yellow "未选择任何规则"; pause; return 0; }

    IFS=$'\n' selected_indexes=($(printf '%s\n' "${selected_indexes[@]}" | sort -n))
    unset IFS
    modified_count="${#selected_indexes[@]}"

    local new_outbound
    new_outbound="$(routing_select_outbound "$conf_file")" || return 0

    local old_state new_state
    old_state="$state_json"
    local jq_indexes='[]'
    for token in "${selected_indexes[@]}"; do
        jq_indexes="$(jq -c --argjson idx "$((token - 1))" '. + [$idx]' <<<"$jq_indexes" 2>/dev/null || echo '[]')"
    done
    read -r -p "确认把已选中的 ${modified_count} 条分流规则改为出口 [${new_outbound}]? [y/N]: " yn
    [[ "${yn,,}" == "y" ]] || return 0
    new_state="$(jq -c --argjson idxs "$jq_indexes" --arg outbound "$new_outbound" '
        to_entries
        | map(if (.key as $k | ($idxs | index($k))) != null then (.value.outbound = $outbound | .value) else .value end)
    ' <<<"$old_state" 2>/dev/null)"
    [[ -z "$new_state" ]] && { red "修改失败"; pause; return 1; }

    if (( ROUTING_RULE_SESSION_ACTIVE == 1 )); then
        if routing_rule_session_set_state "$new_state"; then
            green "已更新 ${modified_count} 条分流规则的出口（待提交）"
        else
            yellow "规则未发生变化，无需提交。"
        fi
    else
        routing_apply_state_change_with_spinner \
            "$conf_file" "$old_state" "$new_state" \
            "正在应用分流变更..." "已更新 ${modified_count} 条分流规则的出口" "修改分流规则失败"
    fi
    pause
}

configure_routing_rules_menu() {
    local conf_file
    conf_file="$(routing_conf_file_or_warn)" || { pause; return 1; }
    routing_rule_session_begin "$conf_file"

    while :; do
        local state_json=""
        ui_clear
        local render_file=""
        render_file="$(routing_render_to_temp_file)"
        {
            proxy_menu_header "配置分流规则"
            if (( ROUTING_RULE_SESSION_DIRTY == 1 )); then
                state_json="$(routing_rule_session_state_json)"
                routing_show_status "$conf_file" "$state_json"
                echo "待提交变更: 是"
            else
                routing_show_status "$conf_file"
                echo "待提交变更: 否"
            fi
            echo "1. 添加分流规则"
            echo "2. 删除分流规则"
            echo "3. 修改分流规则"
            proxy_menu_rule "═"
            echo
        } >"$render_file"
        routing_print_rendered_file "$render_file"
        if ! read_prompt r_choice "选择: "; then
            routing_rule_session_end
            return
        fi
        case "$r_choice" in
            1) routing_add_rule_interactive "$conf_file" ;;
            2) routing_delete_rule_interactive "$conf_file" ;;
            3) routing_modify_rule_interactive "$conf_file" ;;
            0|"")
                if (( ROUTING_RULE_SESSION_DIRTY == 1 )); then
                    local yn=""
                    read -r -p "检测到未提交变更，保存并应用后再返回? [y/N]: " yn
                    if [[ "${yn,,}" == "y" ]]; then
                        if ! routing_rule_session_apply_pending "$conf_file"; then
                            pause
                            continue
                        fi
                    else
                        yellow "已放弃本次未提交变更。"
                    fi
                fi
                routing_rule_session_end
                return 0
                ;;
            *) red "无效输入"; sleep 1 ;;
        esac
        conf_file="$(routing_conf_file_or_warn)" || { routing_rule_session_end; return 1; }
    done
}
