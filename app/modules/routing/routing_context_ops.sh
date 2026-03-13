# Routing user-context and status rendering operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

if ! declare -p ROUTING_STATUS_STATE_FP_META_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_STATUS_STATE_FP_META_CACHE=()
fi
if ! declare -p ROUTING_STATUS_STATE_FP_VALUE_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_STATUS_STATE_FP_VALUE_CACHE=()
fi

ROUTING_STATUS_CACHE_TTL_SECONDS="${ROUTING_STATUS_CACHE_TTL_SECONDS:-2}"

routing_status_boolean_cache_file() {
    local name="${1:-}"
    [[ -n "$name" ]] || return 1
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-status-${name}.cache"
}

routing_status_boolean_cache_read() {
    local cache_file="${1:-}" expected_meta="${2:-}"
    local cached_value=""
    [[ -n "$cache_file" && -n "$expected_meta" ]] || return 1
    if declare -F proxy_runtime_state_read_matching_value >/dev/null 2>&1; then
        cached_value="$(proxy_runtime_state_read_matching_value "$cache_file" "$expected_meta" 2>/dev/null || true)"
        [[ -n "$cached_value" ]] || return 1
        printf '%s\n' "$cached_value"
        return 0
    fi
    return 1
}

routing_status_boolean_cache_write() {
    local cache_file="${1:-}" expected_meta="${2:-}" value="${3:-}"
    [[ -n "$cache_file" && -n "$expected_meta" ]] || return 1
    if declare -F proxy_runtime_state_write_value >/dev/null 2>&1; then
        proxy_runtime_state_write_value "$cache_file" "$expected_meta" "$value" >/dev/null 2>&1 || return 1
    fi
}

routing_status_has_user_groups_fast() {
    local source_meta cache_file cached_value
    [[ -f "$USER_META_DB_FILE" ]] || return 1
    source_meta="$(calc_file_meta_signature "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    cache_file="$(routing_status_boolean_cache_file "has-groups" 2>/dev/null || true)"
    cached_value="$(routing_status_boolean_cache_read "$cache_file" "$source_meta" 2>/dev/null || true)"
    if [[ "$cached_value" == "1" ]]; then
        return 0
    fi
    if [[ "$cached_value" == "0" ]]; then
        return 1
    fi
    if jq -e '((.groups // {}) | type) == "object" and (((.groups // {}) | length) > 0)' "$USER_META_DB_FILE" >/dev/null 2>&1; then
        routing_status_boolean_cache_write "$cache_file" "$source_meta" "1" >/dev/null 2>&1 || true
        return 0
    fi
    routing_status_boolean_cache_write "$cache_file" "$source_meta" "0" >/dev/null 2>&1 || true
    return 1
}

routing_status_has_res_socks_nodes_fast() {
    local source_meta cache_file cached_value
    [[ -f "$RES_SOCKS_NODES_FILE" ]] || return 1
    source_meta="$(calc_file_meta_signature "$RES_SOCKS_NODES_FILE" 2>/dev/null || echo "0:0")"
    cache_file="$(routing_status_boolean_cache_file "has-res-socks-nodes" 2>/dev/null || true)"
    cached_value="$(routing_status_boolean_cache_read "$cache_file" "$source_meta" 2>/dev/null || true)"
    if [[ "$cached_value" == "1" ]]; then
        return 0
    fi
    if [[ "$cached_value" == "0" ]]; then
        return 1
    fi
    if jq -e '((.nodes // []) | type) == "array" and (((.nodes // []) | length) > 0)' "$RES_SOCKS_NODES_FILE" >/dev/null 2>&1; then
        routing_status_boolean_cache_write "$cache_file" "$source_meta" "1" >/dev/null 2>&1 || true
        return 0
    fi
    routing_status_boolean_cache_write "$cache_file" "$source_meta" "0" >/dev/null 2>&1 || true
    return 1
}

routing_status_global_fast_path_ready() {
    routing_context_is_user && return 1
    routing_status_has_user_groups_fast && return 1
    routing_status_has_res_socks_nodes_fast && return 1
    return 0
}

routing_status_context_cache_scope() {
    if routing_context_is_user; then
        printf 'user:%s\n' "${ROUTING_USER_CONTEXT_NAME}"
    else
        printf 'global\n'
    fi
}

routing_status_cache_key() {
    local conf_file="${1:-}" context_scope cache_raw
    context_scope="$(routing_status_context_cache_scope)"
    cache_raw="routing-status|${context_scope}|${conf_file}"
    if declare -F proxy_runtime_cache_key >/dev/null 2>&1; then
        proxy_runtime_cache_key "$cache_raw"
        return 0
    fi
    printf '%s' "$cache_raw" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

routing_status_cache_text_file() {
    local conf_file="${1:-}" cache_key
    cache_key="$(routing_status_cache_key "$conf_file")"
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-status-${cache_key}.txt"
}

routing_status_cache_fp_file() {
    local conf_file="${1:-}" cache_key
    cache_key="$(routing_status_cache_key "$conf_file")"
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-status-${cache_key}.fp"
}

routing_status_render_code_fingerprint() {
    calc_file_fingerprint "${BASH_SOURCE[0]}" 2>/dev/null || echo "0:0"
}

routing_status_state_fp_runtime_key() {
    local conf_file="${1:-}" context_scope
    context_scope="$(routing_status_context_cache_scope)"
    printf '%s|%s\n' "$context_scope" "$conf_file"
}

routing_status_state_fp_cache_file() {
    local conf_file="${1:-}" raw_key cache_key
    raw_key="$(routing_status_state_fp_runtime_key "$conf_file")"
    if declare -F proxy_runtime_cache_key >/dev/null 2>&1; then
        cache_key="$(proxy_runtime_cache_key "routing-status-state|${raw_key}")"
    else
        cache_key="$(printf '%s' "routing-status-state|${raw_key}" | cksum 2>/dev/null | awk '{print $1"-"$2}')"
    fi
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-status-state-${cache_key}.cache"
}

routing_status_state_source_meta_fingerprint() {
    local conf_file="${1:-}" conf_meta route_db_meta direct_meta membership_meta
    local template_meta res_nodes_meta code_meta context_scope

    conf_meta="$(calc_file_meta_signature "$conf_file" 2>/dev/null || echo "0:0")"
    route_db_meta="$(calc_file_meta_signature "$ROUTING_RULES_DB" 2>/dev/null || echo "0:0")"
    direct_meta="$(calc_file_meta_signature "$DIRECT_IP_VERSION_FILE" 2>/dev/null || echo "0:0")"
    if declare -F proxy_user_membership_source_meta_fingerprint >/dev/null 2>&1; then
        membership_meta="$(proxy_user_membership_source_meta_fingerprint "$conf_file" 2>/dev/null || echo "0:0|0:0|0:0")"
    else
        membership_meta="0:0|0:0|0:0"
    fi
    template_meta="$(calc_file_meta_signature "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    res_nodes_meta="$(calc_file_meta_signature "$RES_SOCKS_NODES_FILE" 2>/dev/null || echo "0:0")"
    code_meta="$(calc_file_meta_signature "${BASH_SOURCE[0]}" 2>/dev/null || echo "0:0")"
    context_scope="$(routing_status_context_cache_scope)"

    if routing_status_global_fast_path_ready; then
        printf '%s|%s|%s|%s|%s|%s|fast-global\n' \
            "$context_scope" "$conf_meta" "$route_db_meta" "$direct_meta" \
            "$membership_meta" "$code_meta"
        return 0
    fi

    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "$context_scope" "$conf_meta" "$route_db_meta" "$direct_meta" \
        "$membership_meta" "$template_meta" "$res_nodes_meta|$code_meta"
}

routing_status_state_fingerprint() {
    local conf_file="${1:-}" conf_fp route_db_fp direct_fp membership_fp template_fp
    local res_nodes_fp code_fp context_scope
    local runtime_key source_meta_key cache_file cached_meta_key cached_fp
    local user_meta_meta

    runtime_key="$(routing_status_state_fp_runtime_key "$conf_file")"
    source_meta_key="$(routing_status_state_source_meta_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    cached_meta_key="${ROUTING_STATUS_STATE_FP_META_CACHE[$runtime_key]:-}"
    cached_fp="${ROUTING_STATUS_STATE_FP_VALUE_CACHE[$runtime_key]:-}"
    if [[ "$cached_meta_key" == "$source_meta_key" && -n "$cached_fp" ]]; then
        printf '%s\n' "$cached_fp"
        return 0
    fi
    cache_file="$(routing_status_state_fp_cache_file "$conf_file" 2>/dev/null || true)"
    if declare -F proxy_runtime_state_read_matching_value >/dev/null 2>&1; then
        cached_fp="$(proxy_runtime_state_read_matching_value "$cache_file" "$source_meta_key" 2>/dev/null || true)"
    else
        cached_fp=""
    fi
    if [[ -n "$cached_fp" ]]; then
        ROUTING_STATUS_STATE_FP_META_CACHE["$runtime_key"]="$source_meta_key"
        ROUTING_STATUS_STATE_FP_VALUE_CACHE["$runtime_key"]="$cached_fp"
        printf '%s\n' "$cached_fp"
        return 0
    fi

    conf_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    route_db_fp="$(calc_file_fingerprint "$ROUTING_RULES_DB" 2>/dev/null || echo "0:0")"
    direct_fp="$(calc_file_fingerprint "$DIRECT_IP_VERSION_FILE" 2>/dev/null || echo "0:0")"
    if routing_status_global_fast_path_ready; then
        user_meta_meta="$(calc_file_meta_signature "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
        code_fp="$(routing_status_render_code_fingerprint 2>/dev/null || echo "0:0")"
        context_scope="$(routing_status_context_cache_scope)"
        cached_fp="$(printf '%s|%s|%s|%s|%s|%s|fast-global\n' \
            "$context_scope" "$conf_fp" "$route_db_fp" "$direct_fp" "$user_meta_meta" "$code_fp" \
            | cksum 2>/dev/null | awk '{print $1":"$2}')"
        [[ -n "$cached_fp" ]] || cached_fp="0:0"
        ROUTING_STATUS_STATE_FP_META_CACHE["$runtime_key"]="$source_meta_key"
        ROUTING_STATUS_STATE_FP_VALUE_CACHE["$runtime_key"]="$cached_fp"
        if [[ -n "$cache_file" && -n "$source_meta_key" ]] && declare -F proxy_runtime_state_write_value >/dev/null 2>&1; then
            proxy_runtime_state_write_value "$cache_file" "$source_meta_key" "$cached_fp" >/dev/null 2>&1 || true
        fi
        printf '%s\n' "$cached_fp"
        return 0
    fi
    membership_fp="$(proxy_user_membership_cache_fingerprint "$conf_file" 2>/dev/null || echo "0:0|0:0|0:0")"
    template_fp="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    res_nodes_fp="$(calc_file_fingerprint "$RES_SOCKS_NODES_FILE" 2>/dev/null || echo "0:0")"
    code_fp="$(routing_status_render_code_fingerprint 2>/dev/null || echo "0:0")"
    context_scope="$(routing_status_context_cache_scope)"

    cached_fp="$(printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$context_scope" "$conf_fp" "$route_db_fp" "$direct_fp" "$membership_fp" \
        "$template_fp" "$res_nodes_fp" "$code_fp" \
        | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$cached_fp" ]] || cached_fp="0:0"
    ROUTING_STATUS_STATE_FP_META_CACHE["$runtime_key"]="$source_meta_key"
    ROUTING_STATUS_STATE_FP_VALUE_CACHE["$runtime_key"]="$cached_fp"
    if [[ -n "$cache_file" && -n "$source_meta_key" ]] && declare -F proxy_runtime_state_write_value >/dev/null 2>&1; then
        proxy_runtime_state_write_value "$cache_file" "$source_meta_key" "$cached_fp" >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$cached_fp"
}

routing_status_cache_read_fingerprint() {
    local conf_file="${1:-}" fp_file
    fp_file="$(routing_status_cache_fp_file "$conf_file")"
    [[ -f "$fp_file" ]] || return 1
    tr -d '[:space:]' <"$fp_file" 2>/dev/null
}

routing_status_cache_recent_enough() {
    local conf_file="${1:-}" text_file ttl now ts age
    text_file="$(routing_status_cache_text_file "$conf_file")"
    [[ -f "$text_file" ]] || return 1
    ttl="${ROUTING_STATUS_CACHE_TTL_SECONDS:-2}"
    [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=2
    (( ttl > 0 )) || return 1
    now="$(date +%s 2>/dev/null || echo 0)"
    ts="$(stat -c %Y "$text_file" 2>/dev/null || stat -f %m "$text_file" 2>/dev/null || echo 0)"
    [[ "$now" =~ ^[0-9]+$ && "$ts" =~ ^[0-9]+$ ]] || return 1
    age=$((now - ts))
    (( age <= ttl ))
}

routing_status_cache_is_fresh() {
    local conf_file="${1:-}" expected_fp cached_fp text_file
    text_file="$(routing_status_cache_text_file "$conf_file")"
    [[ -f "$text_file" ]] || return 1
    if routing_status_cache_recent_enough "$conf_file"; then
        return 0
    fi
    cached_fp="$(routing_status_cache_read_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$cached_fp" ]] || return 1
    expected_fp="$(routing_status_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$expected_fp" ]] || return 1
    [[ "$cached_fp" == "$expected_fp" ]]
}

routing_show_status_uncached() {
    local conf_file="$1" state_json="${2:-}"
    local direct_mode direct_label
    direct_mode="$(routing_get_direct_mode "$conf_file")"
    direct_label="$(routing_direct_mode_label_colored "$direct_mode")"
    if routing_status_global_fast_path_ready; then
        state_json="[]"
    else
        [[ -n "$state_json" ]] || state_json="$(routing_load_state_json)"
    fi

    echo
    if routing_context_is_user; then
        echo "当前用户: ${ROUTING_USER_CONTEXT_NAME}"
        echo "----------------------------------"
    fi
    echo "$(routing_colorize "36;1" "出口状态")"
    echo "----------------------------------"
    echo "直连: ${direct_label}"
    if routing_status_global_fast_path_ready; then
        echo "代理: $(routing_colorize "31;1" "○ 无节点")"
    elif routing_res_socks_ready "$conf_file"; then
        echo "代理: $(routing_colorize "36;1" "● $(res_socks_nodes_count) 个节点")"
    else
        echo "代理: $(routing_colorize "31;1" "○ 无节点")"
    fi
    echo "----------------------------------"
    if routing_context_is_user; then
        echo "$(routing_colorize "36;1" "当前用户分流规则")"
    else
        echo "$(routing_colorize "36;1" "分流规则")"
    fi
    echo "----------------------------------"
    if routing_context_is_user; then
        routing_render_rules_brief "$state_json"
    else
        routing_render_rules_brief_all_users "$conf_file"
    fi
    echo "----------------------------------"
}

routing_status_cache_rebuild() {
    local conf_file="${1:-}" state_fp text_file fp_file tmp_file
    text_file="$(routing_status_cache_text_file "$conf_file")"
    fp_file="$(routing_status_cache_fp_file "$conf_file")"
    state_fp="$(routing_status_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"
    mkdir -p "$(proxy_runtime_cache_dir)" >/dev/null 2>&1 || true
    tmp_file="$(mktemp 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || tmp_file="/tmp/proxy-routing-status.$$.$RANDOM"
    routing_show_status_uncached "$conf_file" >"$tmp_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    mv -f "$tmp_file" "$text_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    proxy_cache_write_atomic "$fp_file" "$state_fp" || return 1
}

routing_status_refresh_lock_file() {
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-status-refresh.lock"
}

routing_without_user_context() {
    local prev_active="${ROUTING_USER_CONTEXT_ACTIVE:-0}" prev_name="${ROUTING_USER_CONTEXT_NAME:-}"
    ROUTING_USER_CONTEXT_ACTIVE=0
    ROUTING_USER_CONTEXT_NAME=""
    "$@"
    local rc=$?
    ROUTING_USER_CONTEXT_ACTIVE="$prev_active"
    ROUTING_USER_CONTEXT_NAME="$prev_name"
    return "$rc"
}

routing_status_refresh_context_sync() {
    local conf_file="${1:-}" target_name="${2:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    if [[ -n "$target_name" ]]; then
        routing_with_user_context "$target_name" routing_status_cache_rebuild "$conf_file"
        return $?
    fi
    routing_without_user_context routing_status_cache_rebuild "$conf_file"
}

routing_status_refresh_all_contexts_sync() {
    local conf_file="${1:-}" target_name="${2:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0

    routing_status_refresh_context_sync "$conf_file" "" >/dev/null 2>&1 || true
    if [[ -n "$target_name" ]]; then
        routing_status_refresh_context_sync "$conf_file" "$target_name" >/dev/null 2>&1 || true
    fi
}

routing_status_schedule_refresh_all_contexts() {
    local conf_file="${1:-}" target_name="${2:-}" lock_file=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0

    lock_file="$(routing_status_refresh_lock_file)"
    mkdir -p "$(dirname "$lock_file")" >/dev/null 2>&1 || true

    if command -v flock >/dev/null 2>&1; then
        (
            flock -n 9 || exit 0
            routing_status_refresh_all_contexts_sync "$conf_file" "$target_name"
        ) 9>"$lock_file" >/dev/null 2>&1 &
        return 0
    fi

    (
        local lock_dir="${lock_file}.d"
        mkdir "$lock_dir" >/dev/null 2>&1 || exit 0
        routing_status_refresh_all_contexts_sync "$conf_file" "$target_name"
        rmdir "$lock_dir" >/dev/null 2>&1 || true
    ) >/dev/null 2>&1 &
}

routing_render_rules_brief() {
    local state_json="${1:-}"
    [[ -n "$state_json" ]] || state_json="$(routing_load_state_json)"
    local count
    count="$(jq -r 'length' <<<"$state_json" 2>/dev/null || echo 0)"

    if [[ "$count" -eq 0 ]]; then
        echo "  未配置分流规则"
        return 0
    fi

    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true

    local t out domains name out_name
    while IFS=$'\t' read -r t out domains; do
        [[ -n "$t$out$domains" ]] || continue
        name="$(routing_preset_label_colored "$t")"
        if [[ "$out" == "🐸 direct" ]]; then
            out_name="$(routing_outbound_label_colored "$out")"
        elif [[ -n "${ROUTING_RES_SOCKS_COLORED_LABEL_CACHE[$out]+x}" ]]; then
            out_name="${ROUTING_RES_SOCKS_COLORED_LABEL_CACHE[$out]}"
        else
            out_name="$(routing_outbound_label_colored "$out")"
        fi
        if [[ "$t" == "custom" && -n "$domains" ]]; then
            if [[ ${#domains} -gt 24 ]]; then
                domains="${domains:0:21}..."
            fi
            echo "  ● ${name}(${domains}) -> ${out_name}"
        else
            echo "  ● ${name} -> ${out_name}"
        fi
    done < <(jq -r '.[]? | [(.type // ""), (.outbound // ""), (.domains // "")] | @tsv' <<<"$state_json" 2>/dev/null)
}

routing_render_rules_brief_all_users() {
    local conf_file="${1:-}"
    local printed=0 user_name state_json count line

    if [[ ! -f "$USER_META_DB_FILE" ]] \
        || ! jq -e '((.groups // {}) | type) == "object" and (((.groups // {}) | length) > 0)' "$USER_META_DB_FILE" >/dev/null 2>&1; then
        echo "  未配置分流规则"
        return 0
    fi

    proxy_user_group_sync_from_memberships "$conf_file" >/dev/null 2>&1 || true
    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true

    while IFS= read -r user_name; do
        [[ -n "$user_name" ]] || continue
        count="$(routing_user_rules_count "$user_name" "$conf_file" 2>/dev/null || echo 0)"
        [[ "$count" =~ ^[0-9]+$ ]] || count=0
        (( count > 0 )) || continue

        state_json="$(routing_user_load_state_json "$user_name" "$conf_file" 2>/dev/null || echo '[]')"
        echo "  ${user_name}:"
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            echo "  ${line}"
        done < <(routing_render_rules_brief "$state_json")
        printed=1
    done < <(proxy_user_group_list)

    (( printed == 1 )) || echo "  未配置分流规则"
}

routing_show_status() {
    local conf_file="$1" state_json="${2:-}" text_file
    if [[ -n "$state_json" ]]; then
        routing_show_status_uncached "$conf_file" "$state_json"
        return 0
    fi

    text_file="$(routing_status_cache_text_file "$conf_file")"
    if routing_status_cache_is_fresh "$conf_file"; then
        cat "$text_file"
        return 0
    fi

    routing_status_cache_rebuild "$conf_file" >/dev/null 2>&1 || true
    if [[ -f "$text_file" ]]; then
        cat "$text_file"
        return 0
    fi

    routing_show_status_uncached "$conf_file"
}

routing_context_is_user() {
    (( ROUTING_USER_CONTEXT_ACTIVE == 1 )) && [[ -n "${ROUTING_USER_CONTEXT_NAME:-}" ]]
}

routing_with_user_context() {
    local target_name="${1:-}"
    shift
    [[ -n "$target_name" ]] || return 1

    local prev_active="${ROUTING_USER_CONTEXT_ACTIVE:-0}"
    local prev_name="${ROUTING_USER_CONTEXT_NAME:-}"
    ROUTING_USER_CONTEXT_ACTIVE=1
    ROUTING_USER_CONTEXT_NAME="$(normalize_proxy_user_name "$target_name")"
    "$@"
    local rc=$?
    ROUTING_USER_CONTEXT_ACTIVE="$prev_active"
    ROUTING_USER_CONTEXT_NAME="$prev_name"
    return "$rc"
}

routing_select_target_user_name() {
    local title="${1:-选择用户名}" conf_file="${2:-}"
    local names=()
    if [[ -n "${ROUTING_TARGET_USER_SELECTION_NAMES_TEXT:-}" ]]; then
        mapfile -t names <<<"${ROUTING_TARGET_USER_SELECTION_NAMES_TEXT}"
    else
        mapfile -t names < <(proxy_user_collect_names "any" "$conf_file")
    fi
    if [[ ${#names[@]} -eq 0 ]]; then
        echo "__none__"
        return 0
    fi

    echo >&2
    echo "$title" >&2
    local idx=1 name
    for name in "${names[@]}"; do
        printf '%d. %s\n' "$idx" "$name" >&2
        ((idx++))
    done

    if ! prompt_select_index pick; then
        echo ""
        return 130
    fi
    if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#names[@]} )); then
        echo "__invalid__"
        return
    fi
    echo "${names[$((pick-1))]}"
}

routing_user_collect_bindable_keys_by_name() {
    local -a rows=()
    routing_user_collect_bindable_keys_array rows "${1:-}" "${2:-}"
    (( ${#rows[@]} > 0 )) && printf '%s\n' "${rows[@]}"
}

routing_user_has_bindable_keys_for_name() {
    local target_name="${1:-}" conf_file="${2:-}"
    local -a rows=()
    routing_user_collect_bindable_keys_array rows "$target_name" "$conf_file"
    (( ${#rows[@]} > 0 ))
}

routing_user_requires_route_sync_on_protocol_add() {
    local target_name="${1:-}" conf_file="${2:-}"
    # Route rules are compiled by auth_user, not by protocol key.
    # Adding another bindable sing-box protocol for the same user only needs a
    # full sync when this is the user's first bindable protocol.
    if routing_user_has_bindable_keys_for_name "$target_name" "$conf_file"; then
        return 1
    fi
    return 0
}

routing_user_collect_bindable_keys_array() {
    local __array_name="${1:-}" target_name="${2:-}" conf_file="${3:-}"
    local -n rows_ref="$__array_name"
    rows_ref=()
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || return 0

    if [[ -n "${ROUTING_USER_BINDABLE_KEYS_CACHE[$target_name]+x}" ]]; then
        [[ -n "${ROUTING_USER_BINDABLE_KEYS_CACHE[$target_name]}" ]] && mapfile -t rows_ref <<<"${ROUTING_USER_BINDABLE_KEYS_CACHE[$target_name]}"
        return 0
    fi

    local line state name proto in_tag id_b64 key_b64 user_b64 key cache_value=""
    local -A seen=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state name proto in_tag id_b64 key_b64 user_b64 <<<"$line"
        [[ "$name" == "$target_name" ]] || continue
        [[ "$proto" == "snell" ]] && continue
        key="$(proxy_user_decode_b64 "$key_b64")"
        [[ -n "$key" ]] || continue
        [[ -z "${seen[$key]+x}" ]] || continue
        seen["$key"]=1
        rows_ref+=("${key}"$'\t'"${proto}")
        cache_value+="${cache_value:+$'\n'}${rows_ref[$((${#rows_ref[@]}-1))]}"
    done <<< "$PROXY_USER_MEMBERSHIP_CACHE_ALL"

    ROUTING_USER_BINDABLE_KEYS_CACHE["$target_name"]="$cache_value"
}

routing_user_collect_template_ids_by_name() {
    local target_name="${1:-}" conf_file="${2:-}"
    local -a template_ids=()
    routing_user_collect_template_ids_array template_ids "$target_name" "$conf_file"
    (( ${#template_ids[@]} > 0 )) && printf '%s\n' "${template_ids[@]}"
}

routing_user_collect_template_ids_array() {
    local __array_name="${1:-}" target_name="${2:-}" conf_file="${3:-}"
    local -n template_ids_ref="$__array_name"
    template_ids_ref=()
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || return 0

    if [[ -n "${ROUTING_USER_TEMPLATE_IDS_CACHE[$target_name]+x}" ]]; then
        [[ -n "${ROUTING_USER_TEMPLATE_IDS_CACHE[$target_name]}" ]] && mapfile -t template_ids_ref <<<"${ROUTING_USER_TEMPLATE_IDS_CACHE[$target_name]}"
        return 0
    fi

    local -a bindable_rows=()
    local line key proto template_id cache_value=""
    local -A seen=()
    routing_user_collect_bindable_keys_array bindable_rows "$target_name" "$conf_file"
    for line in "${bindable_rows[@]}"; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r key proto <<<"$line"
        template_id="$(proxy_user_meta_get_template "$key")"
        [[ -n "$template_id" ]] || continue
        [[ -z "${seen[$template_id]+x}" ]] || continue
        seen["$template_id"]=1
        template_ids_ref+=("$template_id")
        cache_value+="${cache_value:+$'\n'}${template_id}"
    done

    ROUTING_USER_TEMPLATE_IDS_CACHE["$target_name"]="$cache_value"
}

routing_user_template_mode() {
    local target_name="${1:-}" conf_file="${2:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || { echo "unsupported"; return 0; }
    routing_user_runtime_cache_refresh "$conf_file"

    if [[ -n "${ROUTING_USER_TEMPLATE_MODE_CACHE[$target_name]+x}" ]]; then
        printf '%s\n' "${ROUTING_USER_TEMPLATE_MODE_CACHE[$target_name]}"
        return 0
    fi

    local mode="unsupported"
    local -a bindable_rows=() template_ids=()
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

    ROUTING_USER_TEMPLATE_MODE_CACHE["$target_name"]="$mode"
    printf '%s\n' "$mode"
}
