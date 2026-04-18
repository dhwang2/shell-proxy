# User routing template storage operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

USER_META_OPS_FILE="${USER_META_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_meta_ops.sh}"
if [[ -f "$USER_META_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_META_OPS_FILE"
fi

USER_TEMPLATE_ROUTING_CORE_OPS_FILE="${USER_TEMPLATE_ROUTING_CORE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../routing/routing_core_ops.sh}"
if [[ -f "$USER_TEMPLATE_ROUTING_CORE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_TEMPLATE_ROUTING_CORE_OPS_FILE"
fi

proxy_ensure_assoc_array \
    PROXY_USER_TEMPLATE_NAME_CACHE \
    PROXY_USER_TEMPLATE_RULES_CACHE
PROXY_USER_TEMPLATE_VALUE_CACHE_FP="${PROXY_USER_TEMPLATE_VALUE_CACHE_FP:-}"

proxy_user_template_runtime_cache_dir() {
    if declare -F routing_runtime_cache_dir >/dev/null 2>&1; then
        echo "$(routing_runtime_cache_dir)/user-template"
        return 0
    fi
    echo "${CACHE_DIR}/routing/user-template"
}

proxy_user_template_cache_write_atomic() {
    local path="${1:-}" content="${2-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

proxy_user_template_db_ready_state_file() {
    echo "$(proxy_user_template_runtime_cache_dir)/ready.fp"
}

proxy_user_template_db_mark_ready() {
    local current_fp="${1:-}"
    [[ -n "$current_fp" ]] || return 1
    proxy_user_template_cache_write_atomic "$(proxy_user_template_db_ready_state_file)" "$current_fp"
}

proxy_user_template_value_cache_file_for_fp() {
    local fp="${1:-0:0}" cache_key
    if declare -F routing_runtime_cache_key >/dev/null 2>&1; then
        cache_key="$(routing_runtime_cache_key "$fp")"
    else
        cache_key="$(printf '%s' "$fp" | proxy_cksum_cache_key)"
    fi
    printf '%s\n' "$(proxy_user_template_runtime_cache_dir)/value-${cache_key}.cache"
}

proxy_user_template_db_ensure() {
    local current_fp ready_state_file ready_fp tmp_json
    mkdir -p "$WORK_DIR" >/dev/null 2>&1 || true
    ready_state_file="$(proxy_user_template_db_ready_state_file 2>/dev/null || true)"
    if [[ -f "$USER_TEMPLATE_DB_FILE" ]]; then
        current_fp="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || true)"
        if [[ -n "$current_fp" && "$PROXY_USER_TEMPLATE_DB_READY_FP" == "$current_fp" ]]; then
            return 0
        fi
        if [[ -n "$ready_state_file" && -f "$ready_state_file" ]]; then
            ready_fp="$(tr -d '[:space:]' <"$ready_state_file" 2>/dev/null || true)"
            if [[ -n "$current_fp" && -n "$ready_fp" && "$ready_fp" == "$current_fp" ]]; then
                PROXY_USER_TEMPLATE_DB_READY_FP="$current_fp"
                return 0
            fi
        fi
    fi

    if [[ ! -f "$USER_TEMPLATE_DB_FILE" ]] || [[ ! -s "$USER_TEMPLATE_DB_FILE" ]]; then
        printf '%s\n' '{"schema":1,"templates":{}}' > "$USER_TEMPLATE_DB_FILE"
        PROXY_USER_TEMPLATE_DB_READY_FP="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
        proxy_user_template_db_mark_ready "$PROXY_USER_TEMPLATE_DB_READY_FP" >/dev/null 2>&1 || true
        return 0
    fi
    tmp_json="$(mktemp)"
    if jq '
        .schema = ((.schema // 1) | tonumber? // 1)
        | .templates = (if (.templates | type) == "object" then .templates else {} end)
    ' "$USER_TEMPLATE_DB_FILE" > "$tmp_json" 2>/dev/null; then
        if ! cmp -s "$tmp_json" "$USER_TEMPLATE_DB_FILE"; then
            mv "$tmp_json" "$USER_TEMPLATE_DB_FILE"
        else
            rm -f "$tmp_json"
        fi
        PROXY_USER_TEMPLATE_DB_READY_FP="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
        proxy_user_template_db_mark_ready "$PROXY_USER_TEMPLATE_DB_READY_FP" >/dev/null 2>&1 || true
    else
        rm -f "$tmp_json"
        printf '%s\n' '{"schema":1,"templates":{}}' > "$USER_TEMPLATE_DB_FILE"
        PROXY_USER_TEMPLATE_DB_READY_FP="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
        proxy_user_template_db_mark_ready "$PROXY_USER_TEMPLATE_DB_READY_FP" >/dev/null 2>&1 || true
    fi
}

proxy_user_template_db_refresh_caches() {
    PROXY_USER_TEMPLATE_DB_READY_FP="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    proxy_user_template_db_mark_ready "$PROXY_USER_TEMPLATE_DB_READY_FP" >/dev/null 2>&1 || true
    PROXY_USER_TEMPLATE_VALUE_CACHE_FP=""
    PROXY_USER_TEMPLATE_NAME_CACHE=()
    PROXY_USER_TEMPLATE_RULES_CACHE=()
    if declare -F routing_user_reset_runtime_cache >/dev/null 2>&1; then
        routing_user_reset_runtime_cache
    fi
}

proxy_user_template_value_cache_refresh() {
    proxy_user_template_db_ensure
    local current_fp template_id template_name rules_json cache_file tmp_cache=""
    current_fp="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    if [[ "$PROXY_USER_TEMPLATE_VALUE_CACHE_FP" == "$current_fp" ]]; then
        return 0
    fi

    PROXY_USER_TEMPLATE_NAME_CACHE=()
    PROXY_USER_TEMPLATE_RULES_CACHE=()

    cache_file="$(proxy_user_template_value_cache_file_for_fp "$current_fp" 2>/dev/null || true)"
    if [[ -n "$cache_file" && -f "$cache_file" ]]; then
        while IFS=$'\t' read -r template_id template_name rules_json; do
            [[ -n "$template_id" ]] || continue
            PROXY_USER_TEMPLATE_NAME_CACHE["$template_id"]="$template_name"
            PROXY_USER_TEMPLATE_RULES_CACHE["$template_id"]="${rules_json:-[]}"
        done < "$cache_file"
        PROXY_USER_TEMPLATE_VALUE_CACHE_FP="$current_fp"
        return 0
    fi

    if [[ -n "$cache_file" ]]; then
        tmp_cache="$(mktemp)"
    fi
    while IFS=$'\t' read -r template_id template_name rules_json; do
        [[ -n "$template_id" ]] || continue
        PROXY_USER_TEMPLATE_NAME_CACHE["$template_id"]="$template_name"
        PROXY_USER_TEMPLATE_RULES_CACHE["$template_id"]="${rules_json:-[]}"
        if [[ -n "$tmp_cache" ]]; then
            printf '%s\t%s\t%s\n' "$template_id" "$template_name" "${rules_json:-[]}" >> "$tmp_cache"
        fi
    done < <(
        jq -r '
            .templates // {}
            | to_entries[]?
            | [
                .key,
                (.value.name // ""),
                ((.value.rules // []) | if type == "array" then . else [] end | tojson)
              ]
            | @tsv
        ' "$USER_TEMPLATE_DB_FILE" 2>/dev/null || true
    )

    if [[ -n "$tmp_cache" ]]; then
        mv "$tmp_cache" "$cache_file"
    fi

    PROXY_USER_TEMPLATE_VALUE_CACHE_FP="$current_fp"
}

make_proxy_user_template_id() {
    local token
    token="$(gen_rand_alnum 6 | tr '[:upper:]' '[:lower:]')"
    echo "tpl_$(date +%Y%m%d%H%M%S)_${token}"
}

proxy_user_template_create() {
    local name="${1:-}" rules_json="${2:-[]}" origin="${3:-manual}" template_id="${4:-}"
    [[ -n "$name" ]] || return 1
    [[ -n "$template_id" ]] || template_id="$(make_proxy_user_template_id)"
    proxy_user_template_db_ensure

    local created_at tmp_json
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
    tmp_json="$(mktemp)"
    jq --arg id "$template_id" --arg name "$name" --arg origin "$origin" --arg created_at "$created_at" --argjson rules "$rules_json" '
        .templates[$id] = {
            name: $name,
            rules: (if ($rules | type) == "array" then $rules else [] end),
            origin: $origin,
            created_at: $created_at
        }
    ' "$USER_TEMPLATE_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]]; then
        mv "$tmp_json" "$USER_TEMPLATE_DB_FILE"
        proxy_user_template_db_refresh_caches
        echo "$template_id"
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

proxy_user_template_get_name() {
    local template_id="${1:-}"
    [[ -n "$template_id" ]] || return 0
    proxy_user_template_value_cache_refresh
    printf '%s\n' "${PROXY_USER_TEMPLATE_NAME_CACHE["$template_id"]:-}"
}

proxy_user_template_get_rules_json() {
    local template_id="${1:-}"
    [[ -n "$template_id" ]] || { echo "[]"; return 0; }
    proxy_user_template_value_cache_refresh
    printf '%s\n' "${PROXY_USER_TEMPLATE_RULES_CACHE["$template_id"]:-[]}"
}

proxy_user_template_find_by_rules_json_into() {
    local __result_var="${1:-}" rules_json="${2:-[]}"
    proxy_user_template_value_cache_refresh

    local template_id cached_rules found_template_id=""
    for template_id in "${!PROXY_USER_TEMPLATE_RULES_CACHE[@]}"; do
        cached_rules="${PROXY_USER_TEMPLATE_RULES_CACHE[$template_id]:-[]}"
        [[ "$cached_rules" == "$rules_json" ]] || continue
        found_template_id="$template_id"
        break
    done

    [[ -n "$__result_var" ]] && printf -v "$__result_var" '%s' "$found_template_id"
    [[ -n "$found_template_id" ]]
}

proxy_user_template_ref_count() {
    local template_id="${1:-}"
    [[ -n "$template_id" ]] || { echo 0; return 0; }
    proxy_user_meta_db_ensure
    jq -r --arg id "$template_id" '[.template // {} | to_entries[]? | select(.value == $id)] | length' "$USER_META_DB_FILE" 2>/dev/null || echo 0
}

proxy_user_template_set_rules() {
    local template_id="${1:-}" rules_json="${2:-[]}"
    [[ -n "$template_id" ]] || return 1
    proxy_user_template_db_ensure

    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg id "$template_id" --argjson rules "$rules_json" '
        if (.templates[$id] // null) == null then
            .
        else
            .templates[$id].rules = (if ($rules | type) == "array" then $rules else [] end)
        end
    ' "$USER_TEMPLATE_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]]; then
        mv "$tmp_json" "$USER_TEMPLATE_DB_FILE"
        proxy_user_template_db_refresh_caches
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}
