# Routing menu and state mutation operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

USER_TEMPLATE_OPS_FILE="${USER_TEMPLATE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_template_ops.sh}"
if [[ -f "$USER_TEMPLATE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_TEMPLATE_OPS_FILE"
fi

ROUTING_CONTEXT_OPS_FILE="${ROUTING_CONTEXT_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_context_ops.sh}"
if [[ -f "$ROUTING_CONTEXT_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_CONTEXT_OPS_FILE"
fi

ROUTING_TEST_OPS_FILE="${ROUTING_TEST_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_test_ops.sh}"
if [[ -f "$ROUTING_TEST_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_TEST_OPS_FILE"
fi

ROUTING_RENDER_CONFIG_OPS_FILE="${ROUTING_RENDER_CONFIG_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/config_ops.sh}"
if [[ -f "$ROUTING_RENDER_CONFIG_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_RENDER_CONFIG_OPS_FILE"
fi

ROUTING_RES_SOCKS_OPS_FILE="${ROUTING_RES_SOCKS_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_res_socks_ops.sh}"
if [[ -f "$ROUTING_RES_SOCKS_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_RES_SOCKS_OPS_FILE"
fi

routing_user_load_state_json() {
    local target_name="${1:-}" conf_file="${2:-}"
    local template_ids=()
    local merged='[]' template_id rules_json state_fp cache_file tmp_cache
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || { echo "[]"; return 0; }
    routing_user_runtime_cache_refresh "$conf_file"

    if [[ -n "${ROUTING_USER_STATE_JSON_CACHE[$target_name]+x}" ]]; then
        printf '%s\n' "${ROUTING_USER_STATE_JSON_CACHE[$target_name]}"
        return 0
    fi

    mkdir -p "$(routing_runtime_cache_dir)" >/dev/null 2>&1 || true
    state_fp="${ROUTING_USER_RUNTIME_CACHE_FP}"
    cache_file="$(routing_user_state_cache_file_for_name_fp "$target_name" "$state_fp")"
    if [[ -f "$cache_file" ]]; then
        ROUTING_USER_STATE_JSON_CACHE["$target_name"]="$(cat "$cache_file" 2>/dev/null || echo "[]")"
        printf '%s\n' "${ROUTING_USER_STATE_JSON_CACHE[$target_name]}"
        return 0
    fi

    mapfile -t template_ids < <(routing_user_collect_template_ids_by_name "$target_name" "$conf_file")
    if [[ ${#template_ids[@]} -eq 0 ]]; then
        ROUTING_USER_STATE_JSON_CACHE["$target_name"]="[]"
        tmp_cache="$(mktemp)"
        printf '%s' "[]" >"$tmp_cache"
        mv "$tmp_cache" "$cache_file"
        echo "[]"
        return 0
    fi

    for template_id in "${template_ids[@]}"; do
        rules_json="$(proxy_user_template_get_rules_json "$template_id")"
        merged="$(jq -cn --argjson a "$merged" --argjson b "${rules_json:-[]}" '
            (($a | if type == "array" then . else [] end) + ($b | if type == "array" then . else [] end))
            | (map(select(.type != "all")) + map(select(.type == "all")))
        ' 2>/dev/null || echo "[]")"
    done
    ROUTING_USER_STATE_JSON_CACHE["$target_name"]="${merged:-[]}"
    tmp_cache="$(mktemp)"
    printf '%s' "${merged:-[]}" >"$tmp_cache"
    mv "$tmp_cache" "$cache_file"
    echo "${merged:-[]}"
}

routing_user_rules_count() {
    local target_name="${1:-}" conf_file="${2:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || { echo 0; return 0; }

    if [[ -n "${ROUTING_USER_RULE_COUNT_CACHE[$target_name]+x}" ]]; then
        printf '%s\n' "${ROUTING_USER_RULE_COUNT_CACHE[$target_name]}"
        return 0
    fi

    local count
    count="$(routing_user_load_state_json "$target_name" "$conf_file" | jq -r 'length' 2>/dev/null || echo 0)"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    ROUTING_USER_RULE_COUNT_CACHE["$target_name"]="$count"
    echo "$count"
}

routing_user_bind_template_to_name() {
    local target_name="${1:-}" template_id="${2:-}" conf_file="${3:-}"
    local line key proto current_template key_count=0 all_match=1
    local -a keys=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r key proto <<<"$line"
        [[ -n "$key" ]] || continue
        keys+=("$key")
        current_template="$(proxy_user_meta_get_template "$key")"
        if [[ -n "$template_id" ]]; then
            [[ "$current_template" == "$template_id" ]] || all_match=0
        else
            [[ -z "$current_template" ]] || all_match=0
        fi
        ((key_count++))
    done < <(routing_user_collect_bindable_keys_by_name "$target_name" "$conf_file")

    (( key_count > 0 )) || return 2
    (( all_match == 1 )) && return 0

    proxy_user_meta_apply_template_for_keys "$template_id" "${keys[@]}" >/dev/null 2>&1 || return 1
    return 0
}

proxy_user_inherit_template_for_key() {
    local target_name="${1:-}" key="${2:-}" conf_file="${3:-}"
    local template_id=""
    template_id="$(proxy_user_inherit_template_id_for_key "$target_name" "$key" "$conf_file" 2>/dev/null || true)"
    [[ -n "$template_id" ]] || return 0
    proxy_user_meta_set_template "$key" "$template_id" >/dev/null 2>&1 || true
    return 0
}

proxy_user_inherit_template_id_for_key() {
    local target_name="${1:-}" key="${2:-}" conf_file="${3:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$key" ]] || return 1
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local proto in_tag user_id mode template_id
    IFS='|' read -r proto in_tag user_id <<<"$key"
    [[ -n "$proto" && -n "$in_tag" && -n "$user_id" ]] || return 1
    [[ "$proto" == "snell" ]] && return 1

    [[ -n "$(proxy_user_meta_get_template "$key")" ]] && return 1

    mode="$(routing_user_template_mode "$target_name" "$conf_file" 2>/dev/null || true)"
    [[ "$mode" == "single" ]] || return 1

    template_id="$(routing_user_collect_template_ids_by_name "$target_name" "$conf_file" | head -n 1)"
    [[ -n "$template_id" ]] || return 1
    printf '%s\n' "$template_id"
    return 0
}

routing_user_requires_route_sync_after_protocol_add() {
    local target_name="${1:-}" key="${2:-}" conf_file="${3:-}"
    local template_id="" rules_json=""
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$key" && -n "$conf_file" && -f "$conf_file" ]] || return 1

    if declare -F routing_user_has_bindable_keys_for_name >/dev/null 2>&1; then
        if routing_user_has_bindable_keys_for_name "$target_name" "$conf_file"; then
            return 1
        fi
    fi

    template_id="$(proxy_user_inherit_template_id_for_key "$target_name" "$key" "$conf_file" 2>/dev/null || true)"
    [[ -n "$template_id" ]] || return 1

    rules_json="$(proxy_user_template_get_rules_json "$template_id" 2>/dev/null || echo '[]')"
    jq -e 'type == "array" and length > 0' <<<"$rules_json" >/dev/null 2>&1
}

routing_user_template_name_default() {
    local target_name="${1:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || target_name="$(normalize_proxy_user_name "$DEFAULT_PROXY_USER_NAME")"
    echo "${target_name}-routing"
}

routing_user_commit_state_change() {
    local target_name="${1:-}" new_state="${2:-[]}" conf_file="${3:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$conf_file" && -f "$conf_file" ]] || return 1

    local mode template_id ref_count
    local -a bindable_rows=() template_ids=()
    routing_user_runtime_cache_refresh "$conf_file"
    routing_user_collect_bindable_keys_array bindable_rows "$target_name" "$conf_file"
    if (( ${#bindable_rows[@]} == 0 )); then
        mode="unsupported"
    else
        routing_user_collect_template_ids_array template_ids "$target_name" "$conf_file"
        if (( ${#template_ids[@]} == 0 )); then
            mode="none"
        elif (( ${#template_ids[@]} == 1 )); then
            mode="single"
        else
            mode="multi"
        fi
    fi
    case "$mode" in
        unsupported)
            return 2
            ;;
        none|unbound)
            if [[ "$(echo "${new_state:-[]}" | jq -r 'length' 2>/dev/null || echo 0)" == "0" ]]; then
                return 0
            fi
            proxy_user_template_find_by_rules_json_into template_id "${new_state:-[]}" 2>/dev/null || template_id=""
            if [[ -z "$template_id" ]]; then
                template_id="$(proxy_user_template_create "$(routing_user_template_name_default "$target_name")" "${new_state:-[]}" "user-routing")" || return 1
            fi
            routing_user_bind_template_to_name "$target_name" "$template_id" "$conf_file" || return $?
            ;;
        single)
            template_id="${template_ids[0]:-}"
            [[ -n "$template_id" ]] || return 1
            ref_count="$(proxy_user_template_ref_count "$template_id")"
            [[ "$ref_count" =~ ^[0-9]+$ ]] || ref_count=0
            if (( ref_count > 1 )); then
                local existing_template_id
                proxy_user_template_find_by_rules_json_into existing_template_id "${new_state:-[]}" 2>/dev/null || existing_template_id=""
                if [[ -n "$existing_template_id" ]]; then
                    template_id="$existing_template_id"
                else
                    template_id="$(proxy_user_template_create "$(routing_user_template_name_default "$target_name")" "${new_state:-[]}" "user-routing-cow")" || return 1
                fi
            else
                proxy_user_template_set_rules "$template_id" "${new_state:-[]}" || return 1
            fi
            routing_user_bind_template_to_name "$target_name" "$template_id" "$conf_file" || return $?
            ;;
        multi|mixed)
            proxy_user_template_find_by_rules_json_into template_id "${new_state:-[]}" 2>/dev/null || template_id=""
            if [[ -z "$template_id" ]]; then
                template_id="$(proxy_user_template_create "$(routing_user_template_name_default "$target_name")" "${new_state:-[]}" "user-routing-merged")" || return 1
            fi
            routing_user_bind_template_to_name "$target_name" "$template_id" "$conf_file" || return $?
            ;;
        *)
            return 1
            ;;
    esac

    sync_user_template_route_rules "$conf_file" "skip-user-name-sanitize" >/dev/null 2>&1 || return 1
    if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
        routing_status_schedule_refresh_all_contexts "$conf_file" "$target_name" >/dev/null 2>&1 || true
    fi
    return 0
}

# --- routing render (merged from routing_render_ops.sh) ---

routing_colorize() {
    local code="$1"
    shift
    local text="$*"
    printf '\033[%sm%s\033[0m' "$code" "$text"
}

routing_render_to_temp_file() {
    local render_file=""
    render_file="$(mktemp 2>/dev/null || true)"
    if [[ -z "$render_file" ]]; then
        render_file="/tmp/proxy-routing-render.$$.$RANDOM"
        : > "$render_file"
    fi
    printf '%s\n' "$render_file"
}

routing_print_rendered_file() {
    local render_file="${1:-}"
    [[ -n "$render_file" && -f "$render_file" ]] || return 0
    cat "$render_file"
    rm -f "$render_file" 2>/dev/null || true
}

print_full_singbox_config_with_compact_rules() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    render_singbox_json_with_compact_rule_lines "$conf_file" 1 1 2>/dev/null || echo "{}"
}

routing_direct_mode_label_colored() {
    local mode="$1"
    local label
    label="$(routing_direct_mode_label "$mode")"
    case "$mode" in
        ipv4_only|ipv4) routing_colorize "32;1" "$label" ;;
        ipv6_only|ipv6) routing_colorize "36;1" "$label" ;;
        prefer_ipv4|prefer_ipv6) routing_colorize "33;1" "$label" ;;
        as_is|asis|"") routing_colorize "37;1" "$label" ;;
        *) routing_colorize "31;1" "$label" ;;
    esac
}

routing_outbound_label_colored() {
    local outbound="$1"
    local label
    label="$(routing_outbound_label "$outbound")"
    case "$outbound" in
        "🐸 direct") routing_colorize "32;1" "$label" ;;
        *)
            if is_res_socks_outbound_tag "$outbound"; then
                res_socks_display_label_colored_by_tag "$outbound"
            else
                routing_colorize "37;1" "$label"
            fi
            ;;
    esac
}

# --- routing selector (merged from routing_selector_ops.sh) ---

routing_select_outbound() {
    local conf_file="$1"
    local outbounds=("🐸 direct")
    local labels=("直连 (🐸 direct)")
    local node_id tag server port username password label
    while IFS=$'\t' read -r node_id tag server port username password; do
        [[ -n "$tag" ]] || continue
        res_socks_outbound_exists "$conf_file" "$tag" || continue
        label="$(res_socks_format_label_colored "$tag" "$server" "$port")"
        outbounds+=("$tag")
        labels+=("$label")
    done < <(res_socks_nodes_list_lines)

    while :; do
        local render_file=""
        render_file="$(routing_render_to_temp_file)"
        {
            echo "选择出口"
            local idx=1
            local label
            for label in "${labels[@]}"; do
                echo "  ${idx}. ${label}"
                ((idx++))
            done
            proxy_menu_rule "═"
        } >"$render_file"
        cat "$render_file" >&2
        rm -f "$render_file" 2>/dev/null || true
        local out_choice=""
        if ! read_prompt out_choice "选择序号(回车取消): "; then
            return 1
        fi
        [[ -z "$out_choice" || "$out_choice" == "0" ]] && return 1
        if [[ "$out_choice" =~ ^[0-9]+$ ]] && (( out_choice >= 1 && out_choice <= ${#outbounds[@]} )); then
            echo "${outbounds[$((out_choice-1))]}"
            return 0
        fi
        red "无效输入" >&2
    done
}

routing_rule_display_line() {
    local idx="${1:-}" entry="${2:-}"
    [[ -n "$entry" ]] || return 1
    local t out domains label
    t="$(jq -r '.type // ""' <<<"$entry" 2>/dev/null)"
    out="$(jq -r '.outbound // ""' <<<"$entry" 2>/dev/null)"
    domains="$(jq -r '.domains // ""' <<<"$entry" 2>/dev/null)"
    if [[ "$t" == "custom" && -n "$domains" ]]; then
        if [[ ${#domains} -gt 30 ]]; then
            domains="${domains:0:27}..."
        fi
        label="$(routing_preset_label "$t")(${domains}) -> $(routing_outbound_label "$out")"
    else
        label="$(routing_preset_label "$t") -> $(routing_outbound_label "$out")"
    fi
    if [[ -n "$idx" ]]; then
        printf '%s. %s\n' "$idx" "$label"
    else
        printf '%s\n' "$label"
    fi
}
