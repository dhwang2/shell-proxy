# Lightweight share metadata and host detection helpers.

SHARE_META_COMMON_OPS_FILE="${SHARE_META_COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$SHARE_META_COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARE_META_COMMON_OPS_FILE"
fi

SHARE_META_CONFIG_OPS_FILE="${SHARE_META_CONFIG_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/config_ops.sh}"
if [[ -f "$SHARE_META_CONFIG_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARE_META_CONFIG_OPS_FILE"
fi

surge_link_verbose_params_enabled() {
    is_feature_enabled "$SURGE_LINK_VERBOSE_PARAMS"
}

shadowtls_join_code_enabled() {
    is_feature_enabled "$SHOW_JOIN_CODE"
}

share_host_cache_dir() {
    printf '%s\n' "${CACHE_DIR}/subscription"
}

share_host_cache_text_file() {
    printf '%s\n' "$(share_host_cache_dir)/.share-host"
}

share_host_cache_fp_file() {
    printf '%s\n' "$(share_host_cache_dir)/.share-host.fp"
}

share_host_cache_bucket() {
    local now_ts interval
    interval="${SHARE_HOST_CACHE_BUCKET_SECONDS:-600}"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=600
    (( interval > 0 )) || interval=600
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0
    printf '%s\n' $(( now_ts / interval ))
}

calc_share_host_source_fingerprint() {
    local conf_file domain_file domain_fp conf_fp bucket
    conf_file="$(get_conf_file 2>/dev/null || true)"
    domain_file="${WORK_DIR}/.domain"

    if [[ -f "$domain_file" ]]; then
        domain_fp="$(calc_file_meta_signature "$domain_file" 2>/dev/null || echo "0:0")"
        printf 'domain|%s\n' "$domain_fp" | cksum 2>/dev/null | awk '{print $1":"$2}'
        return 0
    fi

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        conf_fp="$(calc_file_meta_signature "$conf_file" 2>/dev/null || echo "0:0")"
        printf 'conf|%s\n' "$conf_fp" | cksum 2>/dev/null | awk '{print $1":"$2}'
        return 0
    fi

    bucket="$(share_host_cache_bucket)"
    printf 'fallback|%s\n' "$bucket" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

detect_share_host_uncached() {
    local conf_file host=""
    conf_file="$(get_conf_file 2>/dev/null || true)"

    if [[ -f "${WORK_DIR}/.domain" ]]; then
        host="$(cat "${WORK_DIR}/.domain" 2>/dev/null || true)"
    fi

    if [[ -z "$host" && -n "$conf_file" && -f "$conf_file" ]]; then
        host="$(jq -r '.inbounds[] | select(.tls.server_name) | .tls.server_name' "$conf_file" 2>/dev/null | grep -v "apple.com" | head -n 1)"
    fi

    if [[ -z "$host" ]]; then
        host="$(curl -s4 --connect-timeout 2 icanhazip.com 2>/dev/null || true)"
    fi
    printf '%s\n' "$host"
}

detect_share_host() {
    local host="" current_fp cached_fp text_file fp_file
    current_fp="$(calc_share_host_source_fingerprint 2>/dev/null || true)"
    [[ -n "$current_fp" ]] || current_fp="0:0"

    if [[ "${SHARE_HOST_CACHE_FP:-}" == "$current_fp" && -n "${SHARE_HOST_CACHE_VALUE:-}" ]]; then
        printf '%s\n' "$SHARE_HOST_CACHE_VALUE"
        return 0
    fi

    text_file="$(share_host_cache_text_file)"
    fp_file="$(share_host_cache_fp_file)"
    if [[ -f "$text_file" && -f "$fp_file" ]]; then
        cached_fp="$(tr -d '[:space:]' <"$fp_file" 2>/dev/null || true)"
        if [[ -n "$cached_fp" && "$cached_fp" == "$current_fp" ]]; then
            host="$(cat "$text_file" 2>/dev/null || true)"
            if [[ -n "$host" ]]; then
                SHARE_HOST_CACHE_FP="$current_fp"
                SHARE_HOST_CACHE_VALUE="$host"
                printf '%s\n' "$host"
                return 0
            fi
        fi
    fi

    host="$(detect_share_host_uncached 2>/dev/null || true)"
    mkdir -p "$(share_host_cache_dir)" >/dev/null 2>&1 || true
    printf '%s' "$host" >"$text_file" 2>/dev/null || true
    printf '%s\n' "$current_fp" >"$fp_file" 2>/dev/null || true
    SHARE_HOST_CACHE_FP="$current_fp"
    SHARE_HOST_CACHE_VALUE="$host"
    printf '%s\n' "$host"
}

sanitize_share_node_name() {
    local raw="${1:-}"
    raw="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | tr -d '\n')"
    raw="$(echo "$raw" | sed -E 's/[[:space:]]+/_/g')"
    raw="$(echo "$raw" | sed -E 's/[^a-z0-9._-]+/_/g; s/_+/_/g; s/^[_\\.-]+//; s/[_\\.-]+$//')"
    [[ -z "$raw" ]] && raw="server"
    echo "$raw"
}

detect_share_node_name() {
    if (( SUBSCRIPTION_RENDER_CONTEXT_ACTIVE == 1 )) && [[ -n "${SUBSCRIPTION_RENDER_CONTEXT_NODE_NAME:-}" ]]; then
        echo "$SUBSCRIPTION_RENDER_CONTEXT_NODE_NAME"
        return 0
    fi

    local raw=""
    if [[ -f "${WORK_DIR}/.node_name" ]]; then
        raw="$(head -n 1 "${WORK_DIR}/.node_name" 2>/dev/null || true)"
    fi
    if [[ -z "${raw// }" ]]; then
        raw="$(hostname 2>/dev/null || true)"
    fi
    if [[ -z "${raw// }" ]]; then
        raw="$(detect_share_host 2>/dev/null | tr -d '[:space:]')"
        if [[ "$raw" == *.* ]]; then
            raw="${raw%%.*}"
        fi
    fi
    sanitize_share_node_name "$raw"
}

format_share_uri_host() {
    local host="${1:-}"
    [[ -z "$host" ]] && return 1
    if [[ "$host" == *:* && "$host" != \[*\] ]]; then
        echo "[$host]"
    else
        echo "$host"
    fi
}
