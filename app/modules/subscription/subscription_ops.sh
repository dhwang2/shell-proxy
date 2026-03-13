# Subscription generation and cache operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

SHARE_META_OPS_FILE="${SHARE_META_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/share_meta_ops.sh}"
if [[ -f "$SHARE_META_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARE_META_OPS_FILE"
fi

SUBSCRIPTION_TARGET_OPS_FILE="${SUBSCRIPTION_TARGET_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/subscription_target_ops.sh}"
if [[ -f "$SUBSCRIPTION_TARGET_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SUBSCRIPTION_TARGET_OPS_FILE"
fi

USER_MEMBERSHIP_OPS_FILE="${USER_MEMBERSHIP_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../user/user_membership_ops.sh}"
if [[ -f "$USER_MEMBERSHIP_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_MEMBERSHIP_OPS_FILE"
fi

subscription_render_protocol_types() {
    local conf_file="${1:-}" rows=""
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        rows="$(jq -r '
            .inbounds[]?
            | (.type // "" | ascii_downcase)
            | if . == "shadowsocks" then "ss" else . end
        ' "$conf_file" 2>/dev/null | awk 'NF' | sort -u || true)"
    fi

    if [[ -f "$SNELL_CONF" ]]; then
        if [[ -n "$rows" ]]; then
            rows+=$'\n'
        fi
        rows+="snell"
    fi

    [[ -n "$rows" ]] && printf '%s\n' "$rows" | awk 'NF' | sort -u
}

subscription_cached_fingerprint_value() {
    local file="${1:-}"
    [[ -f "$file" ]] || return 0
    tr -d '\r\n' < "$file" 2>/dev/null || true
}

subscription_base64_no_wrap() {
    local base64_help
    base64_help="$(base64 --help 2>/dev/null || true)"
    if grep -q -- '-w' <<<"$base64_help"; then
        printf '%s' "${1-}" | base64 -w 0
    else
        printf '%s' "${1-}" | base64 | tr -d '\n'
    fi
}

subscription_decode_b64() {
    local value="${1:-}"
    printf '%s' "$value" | base64 -d 2>/dev/null
}

subscription_render_cache_write_user_map() {
    local file="${1:-}" user_list_name="${2:-}" map_name="${3:-}"
    [[ -n "$file" && -n "$user_list_name" && -n "$map_name" ]] || return 1

    local -n user_list_ref="$user_list_name"
    local -n map_ref="$map_name"
    local tmp_file user_name encoded

    tmp_file="$(mktemp 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || tmp_file="/tmp/proxy-subscription-map.$$.$RANDOM"
    : >"$tmp_file"
    for user_name in "${user_list_ref[@]}"; do
        [[ -n "$user_name" ]] || continue
        encoded="$(subscription_base64_no_wrap "${map_ref[$user_name]:-}")"
        printf '%s\t%s\n' "$user_name" "$encoded" >>"$tmp_file"
    done
    mv -f "$tmp_file" "$file"
}

subscription_render_cache_load_user_map() {
    local file="${1:-}" map_name="${2:-}"
    [[ -n "$file" && -n "$map_name" ]] || return 1
    local -n map_ref="$map_name"
    map_ref=()
    [[ -f "$file" ]] || return 0

    local user_name encoded decoded
    while IFS=$'\t' read -r user_name encoded; do
        [[ -n "$user_name" ]] || continue
        decoded="$(subscription_decode_b64 "$encoded" 2>/dev/null || true)"
        map_ref["$user_name"]="$decoded"
    done <"$file"
}

subscription_collect_bucket_user_names() {
    local sing_map_name="${1:-}" surge_map_name="${2:-}"
    [[ -n "$sing_map_name" && -n "$surge_map_name" ]] || return 0

    local user_name candidate_text=""
    local -n sing_map_ref="$sing_map_name"
    local -n surge_map_ref="$surge_map_name"

    for user_name in "${!sing_map_ref[@]}"; do
        [[ -n "$user_name" ]] || continue
        candidate_text+="${user_name}"$'\n'
    done
    for user_name in "${!surge_map_ref[@]}"; do
        [[ -n "$user_name" ]] || continue
        candidate_text+="${user_name}"$'\n'
    done

    [[ -n "$candidate_text" ]] || return 0
    printf '%s' "$candidate_text" | sed '/^[[:space:]]*$/d' | sort -u
}

ensure_subscription_render_cache() {
    local uuid="$1"
    local host="$2"
    local conf_file="${3:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"

    local cache_dir fp_file sing_file surge_file current_fp cached_fp
    cache_dir="$(subscription_render_cache_dir)"
    fp_file="$(subscription_render_cache_fp_file)"
    sing_file="$(subscription_render_cache_sing_file)"
    surge_file="$(subscription_render_cache_surge_file)"
    mkdir -p "$cache_dir"

    current_fp="$(calc_subscription_render_fingerprint "$host" "$conf_file" 2>/dev/null || true)"
    cached_fp="$(subscription_cached_fingerprint_value "$fp_file")"

    if [[ -n "$current_fp" && "$cached_fp" == "$current_fp" ]] \
        && [[ -f "$sing_file" && -f "$surge_file" ]]; then
        local cache_ready=1
        [[ -f "$(subscription_render_cache_user_list_file)" ]] || cache_ready=0
        [[ -f "$(subscription_render_cache_user_sing_map_file)" ]] || cache_ready=0
        [[ -f "$(subscription_render_cache_user_surge_map_file)" ]] || cache_ready=0
        if (( cache_ready == 1 )); then
            if declare -F subscription_share_view_cache_refresh_for_render >/dev/null 2>&1; then
                subscription_share_view_cache_refresh_for_render "$host" "$conf_file" "$current_fp" >/dev/null 2>&1 || true
            fi
            return 0
        fi
    fi

    local sing_links surge_links
    local protocol_rows=""
    protocol_rows="$(subscription_render_protocol_types "$conf_file" 2>/dev/null || true)"
    if [[ -z "${protocol_rows//[[:space:]]/}" ]]; then
        : > "$sing_file"
        : > "$surge_file"
        : > "$(subscription_render_cache_user_list_file)"
        : > "$(subscription_render_cache_user_sing_map_file)"
        : > "$(subscription_render_cache_user_surge_map_file)"
        if [[ -z "$current_fp" ]]; then
            current_fp="$(calc_subscription_render_fingerprint "$host" "$conf_file" 2>/dev/null || true)"
        fi
        [[ -n "$current_fp" ]] && printf '%s\n' "$current_fp" > "$fp_file"
        if declare -F subscription_share_view_cache_refresh_for_render >/dev/null 2>&1; then
            subscription_share_view_cache_refresh_for_render "$host" "$conf_file" "$current_fp" >/dev/null 2>&1 || true
        fi
        return 0
    fi
    local user_name user_sing_links user_surge_links
    local -a active_user_names=() candidate_user_names=()
    local -A sing_links_by_user=() surge_links_by_user=()
    subscription_render_context_begin "$host" "$conf_file"
    subscription_build_link_payload \
        "$host" "$conf_file" "subscription" "" "sing_links_by_user" "surge_links_by_user" \
        "sing_links" "surge_links"
    subscription_render_context_end
    mapfile -t candidate_user_names < <(subscription_collect_bucket_user_names "sing_links_by_user" "surge_links_by_user")
    for user_name in "${candidate_user_names[@]}"; do
        user_sing_links="${sing_links_by_user[$user_name]:-}"
        user_surge_links="${surge_links_by_user[$user_name]:-}"
        if [[ -z "${user_sing_links// }" && -z "${user_surge_links// }" ]]; then
            continue
        fi
        active_user_names+=("$user_name")
    done
    if (( ${#active_user_names[@]} > 0 )); then
        printf '%s\n' "${active_user_names[@]}" > "$(subscription_render_cache_user_list_file)"
    else
        : > "$(subscription_render_cache_user_list_file)"
    fi
    subscription_render_cache_write_user_map "$(subscription_render_cache_user_sing_map_file)" \
        "active_user_names" "sing_links_by_user" || return 1
    subscription_render_cache_write_user_map "$(subscription_render_cache_user_surge_map_file)" \
        "active_user_names" "surge_links_by_user" || return 1

    printf '%s' "$sing_links" > "$sing_file"
    printf '%s' "$surge_links" > "$surge_file"
    if [[ -z "$current_fp" ]]; then
        current_fp="$(calc_subscription_render_fingerprint "$host" "$conf_file" 2>/dev/null || true)"
    fi
    [[ -n "$current_fp" ]] && printf '%s\n' "$current_fp" > "$fp_file"
    if declare -F subscription_share_view_cache_refresh_from_payload >/dev/null 2>&1; then
        subscription_share_view_cache_refresh_from_payload \
            "$host" "$conf_file" "$current_fp" \
            "active_user_names" "sing_links_by_user" "surge_links_by_user" >/dev/null 2>&1 || true
    elif declare -F subscription_share_view_cache_refresh_for_render >/dev/null 2>&1; then
        subscription_share_view_cache_refresh_for_render "$host" "$conf_file" "$current_fp" >/dev/null 2>&1 || true
    fi
}

# --- subscription cache paths and fingerprints (merged from subscription_cache_ops.sh) ---

subscription_render_cache_dir() {
    echo "${CACHE_DIR}/subscription"
}

subscription_render_cache_fp_file() {
    echo "$(subscription_render_cache_dir)/.render-cache.fp"
}

subscription_render_cache_sing_file() {
    echo "$(subscription_render_cache_dir)/.render-sing-links"
}

subscription_render_cache_surge_file() {
    echo "$(subscription_render_cache_dir)/.render-surge-links"
}

subscription_render_cache_user_list_file() {
    echo "$(subscription_render_cache_dir)/.render-users"
}

subscription_render_cache_user_sing_map_file() {
    echo "$(subscription_render_cache_dir)/.render-user-sing.map"
}

subscription_render_cache_user_surge_map_file() {
    echo "$(subscription_render_cache_dir)/.render-user-surge.map"
}

calc_subscription_render_code_fingerprint() {
    local module_rel module_path fp rows=""
    while IFS= read -r module_rel; do
        [[ -n "$module_rel" ]] || continue
        module_path="${MODULE_DIR}/${module_rel}"
        fp="$(calc_file_meta_signature "$module_path" 2>/dev/null || calc_file_meta_signature "${WORK_DIR}/modules/${module_rel}" 2>/dev/null || echo "-")"
        rows+="${module_rel}=${fp}"$'\n'
    done <<'EOF'
subscription/subscription_target_ops.sh
subscription/subscription_ops.sh
subscription/share_ops.sh
user/user_meta_ops.sh
EOF
    printf '%s' "$rows" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

calc_subscription_render_fingerprint() {
    local host="$1"
    local conf_file="${2:-}"
    local node_name conf_fp snell_fp user_meta_fp verbose_flag shadowtls_fp script_fp
    node_name="$(detect_share_node_name 2>/dev/null || true)"
    # Use inbounds-only fingerprint so routing-rule changes (route.rules/dns)
    # do not invalidate the subscription cache.  Subscription links depend only
    # on inbound protocol state, not on routing configuration.
    conf_fp="$(jq -c '.inbounds // []' "$conf_file" 2>/dev/null | cksum 2>/dev/null | awk '{print $1":"$2}' || echo "-")"
    snell_fp="$(calc_file_meta_signature "$SNELL_CONF" 2>/dev/null || echo "-")"
    # Exclude .template from user-meta fingerprint: template bindings are
    # routing state, irrelevant to subscription link generation.
    user_meta_fp="$(jq -c 'del(.template)' "$USER_META_DB_FILE" 2>/dev/null | cksum 2>/dev/null | awk '{print $1":"$2}' || echo "-")"
    script_fp="$(calc_subscription_render_code_fingerprint 2>/dev/null || echo "-")"
    if surge_link_verbose_params_enabled; then
        verbose_flag="on"
    else
        verbose_flag="off"
    fi
    shadowtls_fp="$(calc_shadowtls_render_fingerprint | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$shadowtls_fp" ]] || shadowtls_fp="-"

    printf 'schema=%s\nhost=%s\nnode=%s\nconf=%s\nsnell=%s\nuser_meta=%s\nscript=%s\nshadowtls=%s\nsurge_verbose=%s\n' \
        "subscription-render-v3" \
        "$host" "$node_name" "$conf_fp" "$snell_fp" "$user_meta_fp" "$script_fp" "$shadowtls_fp" "$verbose_flag" \
        | cksum 2>/dev/null | awk '{print $1":"$2}'
}

sync_singbox_loaded_fingerprint() {
    local conf_file="$1"
    local conf_fp=""
    conf_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$conf_fp" ]] || return 1
    echo "$conf_fp" > "$SINGBOX_LOADED_FINGERPRINT_FILE"
}

file_mtime_epoch() {
    local file="$1"
    [[ -f "$file" ]] || { echo 0; return; }
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0
}

service_active_since_epoch() {
    local unit="$1"
    local ts
    ts="$(systemctl show -p ActiveEnterTimestamp --value "$unit" 2>/dev/null || true)"
    [[ -z "$ts" || "$ts" == "n/a" ]] && { echo 0; return; }
    date -d "$ts" +%s 2>/dev/null || echo 0
}

sync_singbox_loaded_fingerprint_passive() {
    local conf_file
    conf_file="$(get_conf_file)"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    systemctl is-active --quiet sing-box 2>/dev/null || return 0

    local conf_ts svc_ts
    conf_ts="$(file_mtime_epoch "$conf_file")"
    svc_ts="$(service_active_since_epoch sing-box)"
    [[ "$conf_ts" =~ ^[0-9]+$ ]] || conf_ts=0
    [[ "$svc_ts" =~ ^[0-9]+$ ]] || svc_ts=0

    if (( conf_ts > 0 && svc_ts > 0 && conf_ts <= svc_ts )); then
        sync_singbox_loaded_fingerprint "$conf_file" >/dev/null 2>&1 || true
    fi
}
