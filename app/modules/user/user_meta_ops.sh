# User metadata, template storage, and display-name operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

SHARE_LINK_OPS_FILE="${SHARE_LINK_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../subscription/share_ops.sh}"
if [[ -f "$SHARE_LINK_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARE_LINK_OPS_FILE"
fi

if ! declare -p PROXY_USER_META_NAME_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_META_NAME_CACHE=()
fi
if ! declare -p PROXY_USER_META_TEMPLATE_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_META_TEMPLATE_CACHE=()
fi
if ! declare -p PROXY_USER_META_EXPIRY_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_META_EXPIRY_CACHE=()
fi
if ! declare -p PROXY_USER_NORMALIZED_NAME_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_NORMALIZED_NAME_CACHE=()
fi
if ! declare -p PROXY_USER_SHARE_SUFFIX_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_SHARE_SUFFIX_CACHE=()
fi
if ! declare -p PROXY_USER_LINK_NAME_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_LINK_NAME_CACHE=()
fi
PROXY_USER_DISPLAY_NAME_CACHE_FP="${PROXY_USER_DISPLAY_NAME_CACHE_FP:-}"

proxy_user_meta_cache_dir() {
    local cache_dir
    if declare -F routing_runtime_cache_dir >/dev/null 2>&1; then
        cache_dir="$(routing_runtime_cache_dir)/user-meta"
    else
        cache_dir="${CACHE_DIR}/routing/user-meta"
    fi
    mkdir -p "$cache_dir" >/dev/null 2>&1 || true
    printf '%s\n' "$cache_dir"
}

proxy_user_meta_cache_write_atomic() {
    local path="${1:-}" content="${2-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

proxy_user_meta_db_ready_state_file() {
    printf '%s\n' "$(proxy_user_meta_cache_dir)/ready.fp"
}

proxy_user_meta_db_mark_ready() {
    local current_fp="${1:-}"
    [[ -n "$current_fp" ]] || return 1
    proxy_user_meta_cache_write_atomic "$(proxy_user_meta_db_ready_state_file)" "$current_fp"
}

normalize_proxy_user_name() {
    local raw="${1:-}"
    local cache_key normalized
    cache_key="${DEFAULT_PROXY_USER_NAME}"$'\x1f'"${raw}"
    if [[ -n "${PROXY_USER_NORMALIZED_NAME_CACHE[$cache_key]+x}" ]]; then
        printf '%s\n' "${PROXY_USER_NORMALIZED_NAME_CACHE[$cache_key]}"
        return 0
    fi

    raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '\r' | tr -d '\n')"
    raw="$(printf '%s' "$raw" | sed -E 's/[[:space:]]+/-/g; s/[^a-z0-9._-]+/-/g; s/-+/-/g; s/^[-_.]+//; s/[-_.]+$//')"
    if [[ -z "$raw" ]]; then
        raw="$(printf '%s' "$DEFAULT_PROXY_USER_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/-+/-/g; s/^[-_.]+//; s/[-_.]+$//')"
    fi
    [[ -z "$raw" ]] && raw="user"
    normalized="$raw"
    PROXY_USER_NORMALIZED_NAME_CACHE["$cache_key"]="$normalized"
    printf '%s\n' "$normalized"
}

proxy_user_key() {
    local proto="${1:-}" in_tag="${2:-}" user_id="${3:-}"
    printf '%s' "${proto}|${in_tag}|${user_id}"
}

proxy_user_meta_db_ensure() {
    local current_fp ready_state_file ready_fp tmp_json
    mkdir -p "$WORK_DIR" >/dev/null 2>&1 || true
    ready_state_file="$(proxy_user_meta_db_ready_state_file 2>/dev/null || true)"
    if [[ -f "$USER_META_DB_FILE" ]]; then
        current_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || true)"
        if [[ -n "$current_fp" && "$PROXY_USER_META_DB_READY_FP" == "$current_fp" ]]; then
            return 0
        fi
        if [[ -n "$ready_state_file" && -f "$ready_state_file" ]]; then
            ready_fp="$(tr -d '[:space:]' <"$ready_state_file" 2>/dev/null || true)"
            if [[ -n "$current_fp" && -n "$ready_fp" && "$ready_fp" == "$current_fp" ]]; then
                PROXY_USER_META_DB_READY_FP="$current_fp"
                return 0
            fi
        fi
    fi

    if [[ ! -f "$USER_META_DB_FILE" ]] || ! jq . "$USER_META_DB_FILE" >/dev/null 2>&1; then
        printf '%s\n' '{"schema":3,"disabled":{},"expiry":{},"route":{},"template":{},"name":{},"groups":{}}' > "$USER_META_DB_FILE"
        PROXY_USER_META_DB_READY_FP="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
        proxy_user_meta_db_mark_ready "$PROXY_USER_META_DB_READY_FP" >/dev/null 2>&1 || true
        return 0
    fi
    tmp_json="$(mktemp)"
    if jq '
        .schema = (((.schema // 3) | tonumber?) // 3 | if . < 3 then 3 else . end)
        | .disabled = (if (.disabled | type) == "object" then .disabled else {} end)
        | .expiry = (if (.expiry | type) == "object" then .expiry else {} end)
        | .route = (if (.route | type) == "object" then .route else {} end)
        | .template = (if (.template | type) == "object" then .template else {} end)
        | .name = (if (.name | type) == "object" then .name else {} end)
        | .groups = (if (.groups | type) == "object" then .groups else {} end)
    ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null; then
        if ! cmp -s "$tmp_json" "$USER_META_DB_FILE"; then
            mv "$tmp_json" "$USER_META_DB_FILE"
        else
            rm -f "$tmp_json"
        fi
        PROXY_USER_META_DB_READY_FP="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
        proxy_user_meta_db_mark_ready "$PROXY_USER_META_DB_READY_FP" >/dev/null 2>&1 || true
    else
        rm -f "$tmp_json"
        printf '%s\n' '{"schema":3,"disabled":{},"expiry":{},"route":{},"template":{},"name":{},"groups":{}}' > "$USER_META_DB_FILE"
        PROXY_USER_META_DB_READY_FP="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
        proxy_user_meta_db_mark_ready "$PROXY_USER_META_DB_READY_FP" >/dev/null 2>&1 || true
    fi
}

proxy_user_meta_db_refresh_caches() {
    local current_fp
    current_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    PROXY_USER_META_DB_READY_FP="$current_fp"
    proxy_user_meta_db_mark_ready "$current_fp" >/dev/null 2>&1 || true
    # Lazy invalidation: only wipe FP sentinels.  Downstream functions
    # (proxy_user_meta_value_cache_refresh, proxy_user_display_name_cache_refresh,
    # routing_user_runtime_cache_refresh, etc.) detect staleness via their own
    # fingerprint checks and rebuild associative-array caches on demand.
    if declare -F proxy_invalidate_after_mutation >/dev/null 2>&1; then
        proxy_invalidate_after_mutation "user"
    else
        PROXY_USER_META_VALUE_CACHE_FP=""
        PROXY_USER_GROUP_LIST_CACHE_FP=""
        PROXY_USER_DISPLAY_NAME_CACHE_FP=""
        PROXY_USER_SHARE_SUFFIX_CACHE=()
        PROXY_USER_LINK_NAME_CACHE=()
        if declare -F routing_user_reset_runtime_cache >/dev/null 2>&1; then
            routing_user_reset_runtime_cache
        fi
    fi
}

proxy_user_meta_value_cache_file_for_fp() {
    local fp="${1:-0:0}" cache_key cache_dir
    cache_dir="$(proxy_user_meta_cache_dir)"

    if declare -F routing_runtime_cache_key >/dev/null 2>&1; then
        cache_key="$(routing_runtime_cache_key "$fp")"
    else
        cache_key="$(printf '%s' "$fp" | cksum 2>/dev/null | awk '{print $1"-"$2}')"
    fi
    printf '%s\n' "${cache_dir}/value-${cache_key}.cache"
}

proxy_user_display_name_cache_refresh() {
    proxy_user_meta_value_cache_refresh
    local current_fp
    current_fp="${PROXY_USER_META_VALUE_CACHE_FP}|${DEFAULT_PROXY_USER_NAME}"
    if [[ "$PROXY_USER_DISPLAY_NAME_CACHE_FP" != "$current_fp" ]]; then
        PROXY_USER_SHARE_SUFFIX_CACHE=()
        PROXY_USER_LINK_NAME_CACHE=()
        PROXY_USER_DISPLAY_NAME_CACHE_FP="$current_fp"
    fi
}

proxy_user_meta_value_cache_refresh() {
    proxy_user_meta_db_ensure
    local current_fp section key value cache_file tmp_cache=""
    current_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    if [[ "$PROXY_USER_META_VALUE_CACHE_FP" == "$current_fp" ]]; then
        return 0
    fi

    PROXY_USER_META_NAME_CACHE=()
    PROXY_USER_META_TEMPLATE_CACHE=()
    PROXY_USER_META_EXPIRY_CACHE=()

    cache_file="$(proxy_user_meta_value_cache_file_for_fp "$current_fp" 2>/dev/null || true)"
    if [[ -n "$cache_file" && -f "$cache_file" ]]; then
        while IFS=$'\t' read -r section key value; do
            [[ -n "$section" && -n "$key" ]] || continue
            case "$section" in
                name) PROXY_USER_META_NAME_CACHE["$key"]="$value" ;;
                template) PROXY_USER_META_TEMPLATE_CACHE["$key"]="$value" ;;
                expiry) PROXY_USER_META_EXPIRY_CACHE["$key"]="$value" ;;
            esac
        done < "$cache_file"
        PROXY_USER_META_VALUE_CACHE_FP="$current_fp"
        return 0
    fi

    if [[ -n "$cache_file" ]]; then
        tmp_cache="$(mktemp)"
    fi
    while IFS=$'\t' read -r section key value; do
        [[ -n "$section" && -n "$key" ]] || continue
        case "$section" in
            name) PROXY_USER_META_NAME_CACHE["$key"]="$value" ;;
            template) PROXY_USER_META_TEMPLATE_CACHE["$key"]="$value" ;;
            expiry) PROXY_USER_META_EXPIRY_CACHE["$key"]="$value" ;;
        esac
        if [[ -n "$tmp_cache" ]]; then
            printf '%s\t%s\t%s\n' "$section" "$key" "$value" >> "$tmp_cache"
        fi
    done < <(jq -r '
        (.name // {} | to_entries[]? | "name\t\(.key)\t\(.value // "")"),
        (.template // {} | to_entries[]? | "template\t\(.key)\t\(.value // "")"),
        (.expiry // {} | to_entries[]? | "expiry\t\(.key)\t\(.value // "")")
    ' "$USER_META_DB_FILE" 2>/dev/null || true)

    if [[ -n "$tmp_cache" ]]; then
        mv "$tmp_cache" "$cache_file"
    fi

    PROXY_USER_META_VALUE_CACHE_FP="$current_fp"
}

proxy_user_meta_get_name() {
    local key="${1:-}"
    [[ -n "$key" ]] || return 0
    proxy_user_meta_value_cache_refresh
    printf '%s\n' "${PROXY_USER_META_NAME_CACHE["$key"]:-}"
}

proxy_user_meta_set_name() {
    local key="${1:-}" value="${2:-}"
    [[ -n "$key" ]] || return 1
    value="$(normalize_proxy_user_name "$value")"
    proxy_user_meta_db_ensure
    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg k "$key" --arg v "$value" '.name[$k] = $v' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$USER_META_DB_FILE"
        proxy_user_meta_db_refresh_caches
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

proxy_user_group_list() {
    proxy_user_meta_db_ensure
    local current_fp
    current_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    if [[ "$PROXY_USER_GROUP_LIST_CACHE_FP" != "$current_fp" ]]; then
        PROXY_USER_GROUP_LIST_CACHE="$(jq -r '
        .groups // {}
        | to_entries
        | sort_by(.value.created_at // "", .key)
        | .[]?
        | .key
    ' "$USER_META_DB_FILE" 2>/dev/null || true)"
        PROXY_USER_GROUP_LIST_CACHE_FP="$current_fp"
    fi
    [[ -n "$PROXY_USER_GROUP_LIST_CACHE" ]] && printf '%s\n' "$PROXY_USER_GROUP_LIST_CACHE"
}

proxy_user_group_add() {
    local name="${1:-}"
    [[ -n "${name//[[:space:]]/}" ]] || return 1
    name="$(normalize_proxy_user_name "$name")"
    [[ -n "$name" ]] || return 1

    proxy_user_meta_db_ensure
    if jq -e --arg name "$name" '(.groups[$name] | type) == "object"' "$USER_META_DB_FILE" >/dev/null 2>&1; then
        return 0
    fi
    local created_at tmp_json
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
    tmp_json="$(mktemp)"
    jq --arg name "$name" --arg created_at "$created_at" '
        .groups[$name] = (
            if (.groups[$name] | type) == "object" then
                .groups[$name]
            else
                {created_at:$created_at}
            end
        )
    ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$USER_META_DB_FILE"
        proxy_user_meta_db_refresh_caches
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

proxy_user_group_delete() {
    local name="${1:-}"
    name="$(normalize_proxy_user_name "$name")"
    [[ -n "$name" ]] || return 1

    proxy_user_meta_db_ensure
    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg name "$name" 'del(.groups[$name])' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$USER_META_DB_FILE"
        proxy_user_meta_db_refresh_caches
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

proxy_user_group_rename() {
    local old_name="${1:-}" new_name="${2:-}"
    old_name="$(normalize_proxy_user_name "$old_name")"
    new_name="$(normalize_proxy_user_name "$new_name")"
    [[ -n "$old_name" && -n "$new_name" ]] || return 1
    [[ "$old_name" == "$new_name" ]] && return 0

    proxy_user_meta_db_ensure
    local created_at tmp_json
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
    tmp_json="$(mktemp)"
    jq --arg old "$old_name" --arg new "$new_name" --arg created_at "$created_at" '
        .groups[$new] = (
            if (.groups[$new] | type) == "object" then
                .groups[$new]
            elif (.groups[$old] | type) == "object" then
                .groups[$old]
            else
                {created_at:$created_at}
            end
        )
        | del(.groups[$old])
    ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$USER_META_DB_FILE"
        proxy_user_meta_db_refresh_caches
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

proxy_user_meta_get_template() {
    local key="${1:-}"
    [[ -n "$key" ]] || return 0
    proxy_user_meta_value_cache_refresh
    printf '%s\n' "${PROXY_USER_META_TEMPLATE_CACHE["$key"]:-}"
}

proxy_user_meta_set_template() {
    local key="${1:-}" value="${2:-}"
    [[ -n "$key" && -n "$value" ]] || return 1
    proxy_user_meta_db_ensure
    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg k "$key" --arg v "$value" '.template[$k] = $v' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$USER_META_DB_FILE"
        proxy_user_meta_db_refresh_caches
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

proxy_user_meta_apply_protocol_membership() {
    local target_name="${1:-}" key="${2:-}" template_id="${3:-}"
    local created_at tmp_json
    [[ -n "${target_name//[[:space:]]/}" ]] || return 1
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$key" ]] || return 1

    proxy_user_meta_db_ensure
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
    tmp_json="$(mktemp)"
    if [[ -n "$template_id" ]]; then
        jq --arg name "$target_name" --arg key "$key" --arg tpl "$template_id" --arg created_at "$created_at" '
            .groups[$name] = (
                if (.groups[$name] | type) == "object" then
                    .groups[$name]
                else
                    {created_at:$created_at}
                end
            )
            | .name[$key] = $name
            | .template[$key] = $tpl
        ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    else
        jq --arg name "$target_name" --arg key "$key" --arg created_at "$created_at" '
            .groups[$name] = (
                if (.groups[$name] | type) == "object" then
                    .groups[$name]
                else
                    {created_at:$created_at}
                end
            )
            | .name[$key] = $name
        ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    fi

    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        if ! cmp -s "$tmp_json" "$USER_META_DB_FILE"; then
            mv "$tmp_json" "$USER_META_DB_FILE"
            proxy_user_meta_db_refresh_caches
        else
            rm -f "$tmp_json"
        fi
        return 0
    fi

    rm -f "$tmp_json"
    return 1
}

proxy_user_meta_apply_protocol_memberships_batch() {
    local records_file="${1:-}"
    local created_at tmp_json
    [[ -n "$records_file" && -s "$records_file" ]] || return 1

    proxy_user_meta_db_ensure
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
    tmp_json="$(mktemp)"
    jq --rawfile rows "$records_file" --arg created_at "$created_at" '
        .groups = (if (.groups | type) == "object" then .groups else {} end)
        | .name = (if (.name | type) == "object" then .name else {} end)
        | .template = (if (.template | type) == "object" then .template else {} end)
        | ($rows | split("\n") | map(select(length > 0) | split("\t"))) as $records
        | reduce $records[] as $row (.;
            ($row[0] // "") as $name
            | ($row[1] // "") as $key
            | ($row[2] // "") as $tpl
            | if ($name | length) == 0 or ($key | length) == 0 then
                  .
              else
                  .groups[$name] = (
                      if (.groups[$name] | type) == "object" then
                          .groups[$name]
                      else
                          {created_at:$created_at}
                      end
                  )
                  | .name[$key] = $name
                  | if ($tpl | length) > 0 then
                        .template[$key] = $tpl
                    else
                        .
                    end
              end
        )
    ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true

    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        if ! cmp -s "$tmp_json" "$USER_META_DB_FILE"; then
            mv "$tmp_json" "$USER_META_DB_FILE"
            proxy_user_meta_db_refresh_caches
        else
            rm -f "$tmp_json"
        fi
        return 0
    fi

    rm -f "$tmp_json"
    return 1
}

proxy_user_meta_apply_template_for_keys() {
    local value="${1-}"
    shift || true
    local -a keys=("$@")
    local keys_file="" tmp_json="" key=""

    (( ${#keys[@]} > 0 )) || return 1
    proxy_user_meta_db_ensure

    keys_file="$(mktemp)"
    for key in "${keys[@]}"; do
        [[ -n "$key" ]] || continue
        printf '%s\n' "$key" >> "$keys_file"
    done
    [[ -s "$keys_file" ]] || { rm -f "$keys_file"; return 1; }

    tmp_json="$(mktemp)"
    if [[ -n "$value" ]]; then
        jq --rawfile keys "$keys_file" --arg v "$value" '
            ($keys | split("\n") | map(select(length > 0))) as $list
            | reduce $list[] as $k (.; .template[$k] = $v)
        ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    else
        jq --rawfile keys "$keys_file" '
            ($keys | split("\n") | map(select(length > 0))) as $list
            | reduce $list[] as $k (.; del(.template[$k]))
        ' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    fi
    rm -f "$keys_file"

    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        if ! cmp -s "$tmp_json" "$USER_META_DB_FILE"; then
            mv "$tmp_json" "$USER_META_DB_FILE"
            proxy_user_meta_db_refresh_caches
        else
            rm -f "$tmp_json"
        fi
        return 0
    fi

    rm -f "$tmp_json"
    return 1
}

proxy_user_short_token() {
    local raw="${1:-}"
    printf '%s' "$raw" | cksum 2>/dev/null | awk '{print substr($1,1,4)}'
}

proxy_user_share_suffix_cached() {
    local proto="${1:-}" in_tag="${2:-}" user_id="${3:-}" raw_name="${4:-}"
    local key meta_name suffix cache_key
    cache_key="${proto}"$'\x1f'"${in_tag}"$'\x1f'"${user_id}"$'\x1f'"${raw_name}"
    if [[ -n "${PROXY_USER_SHARE_SUFFIX_CACHE[$cache_key]+x}" ]]; then
        printf '%s\n' "${PROXY_USER_SHARE_SUFFIX_CACHE[$cache_key]}"
        return 0
    fi

    suffix="$(normalize_proxy_user_name "$raw_name")"
    if [[ -n "$raw_name" && "$suffix" != "user" ]]; then
        PROXY_USER_SHARE_SUFFIX_CACHE["$cache_key"]="$suffix"
        printf '%s\n' "$suffix"
        return 0
    fi

    key="$(proxy_user_key "$proto" "$in_tag" "$user_id")"
    meta_name="${PROXY_USER_META_NAME_CACHE["$key"]:-}"
    if [[ -n "$meta_name" ]]; then
        suffix="$(normalize_proxy_user_name "$meta_name")"
        PROXY_USER_SHARE_SUFFIX_CACHE["$cache_key"]="$suffix"
        printf '%s\n' "$suffix"
        return 0
    fi

    if [[ -n "$user_id" ]]; then
        suffix="$(normalize_proxy_user_name "${DEFAULT_PROXY_USER_NAME}-$(proxy_user_short_token "$user_id")")"
    else
        suffix="$(normalize_proxy_user_name "$DEFAULT_PROXY_USER_NAME")"
    fi
    PROXY_USER_SHARE_SUFFIX_CACHE["$cache_key"]="$suffix"
    printf '%s\n' "$suffix"
}

proxy_user_share_suffix() {
    proxy_user_display_name_cache_refresh
    proxy_user_share_suffix_cached "$@"
}

proxy_user_link_name_cached() {
    local proto="${1:-}" in_tag="${2:-}" user_id="${3:-}" raw_name="${4:-}"
    local key meta_name display_name cache_key
    cache_key="${proto}"$'\x1f'"${in_tag}"$'\x1f'"${user_id}"$'\x1f'"${raw_name}"
    if [[ -n "${PROXY_USER_LINK_NAME_CACHE[$cache_key]+x}" ]]; then
        printf '%s\n' "${PROXY_USER_LINK_NAME_CACHE[$cache_key]}"
        return 0
    fi

    display_name="$(normalize_proxy_user_name "$raw_name")"
    if [[ -n "$raw_name" && "$display_name" != "user" ]]; then
        PROXY_USER_LINK_NAME_CACHE["$cache_key"]="$display_name"
        printf '%s\n' "$display_name"
        return 0
    fi

    key="$(proxy_user_key "$proto" "$in_tag" "$user_id")"
    meta_name="${PROXY_USER_META_NAME_CACHE["$key"]:-}"
    if [[ -n "$meta_name" ]]; then
        display_name="$(normalize_proxy_user_name "$meta_name")"
        PROXY_USER_LINK_NAME_CACHE["$cache_key"]="$display_name"
        printf '%s\n' "$display_name"
        return 0
    fi

    display_name="$(normalize_proxy_user_name "$DEFAULT_PROXY_USER_NAME")"
    PROXY_USER_LINK_NAME_CACHE["$cache_key"]="$display_name"
    printf '%s\n' "$display_name"
}

proxy_user_link_name() {
    proxy_user_display_name_cache_refresh
    proxy_user_link_name_cached "$@"
}

make_user_key() {
    local proto="${1:-}" in_tag="${2:-}" user_id="${3:-}"
    proxy_user_key "$proto" "$in_tag" "$user_id"
}

proxy_user_meta_clear_key() {
    local key="${1:-}"
    [[ -n "$key" ]] || return 1
    proxy_user_meta_db_ensure
    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg k "$key" 'del(.disabled[$k]) | del(.expiry[$k]) | del(.route[$k]) | del(.template[$k]) | del(.name[$k])' "$USER_META_DB_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$USER_META_DB_FILE"
        proxy_user_meta_db_refresh_caches
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}
