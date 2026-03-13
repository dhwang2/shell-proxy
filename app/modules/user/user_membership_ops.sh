# User membership, derived cache, and protocol/name row support operations.

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

USER_META_OPS_FILE="${USER_META_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_meta_ops.sh}"
if [[ -f "$USER_META_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_META_OPS_FILE"
fi

PROTOCOL_INVENTORY_OPS_FILE="${PROTOCOL_INVENTORY_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../protocol/protocol_ops.sh}"
if [[ -f "$PROTOCOL_INVENTORY_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_INVENTORY_OPS_FILE"
fi

proxy_user_membership_meta_fp_cache_file() {
    local cache_key
    if declare -F routing_runtime_cache_key >/dev/null 2>&1; then
        cache_key="$(routing_runtime_cache_key "$USER_META_DB_FILE")"
    else
        cache_key="$(printf '%s' "$USER_META_DB_FILE" | cksum 2>/dev/null | awk '{print $1"-"$2}')"
    fi
    printf '%s\n' "$(routing_runtime_cache_dir)/membership-meta-${cache_key}.cache"
}

proxy_user_membership_meta_fingerprint() {
    local source_fp cache_file cached_source_fp cached_fp fp
    [[ -f "$USER_META_DB_FILE" ]] || { echo "0:0"; return 0; }

    source_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    cache_file="$(proxy_user_membership_meta_fp_cache_file 2>/dev/null || true)"
    if [[ -n "$cache_file" && -f "$cache_file" ]]; then
        IFS=$'\t' read -r cached_source_fp cached_fp <"$cache_file"
        if [[ -n "$cached_source_fp" && "$cached_source_fp" == "$source_fp" && -n "$cached_fp" ]]; then
            printf '%s\n' "$cached_fp"
            return 0
        fi
    fi

    fp="$(jq -c '{name:(.name // {}), disabled:(.disabled // {})}' "$USER_META_DB_FILE" 2>/dev/null | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$fp" ]] || fp="0:0"
    if [[ -n "$cache_file" ]]; then
        mkdir -p "$(routing_runtime_cache_dir)" >/dev/null 2>&1 || true
        printf '%s\t%s\n' "$source_fp" "$fp" >"$cache_file"
    fi
    printf '%s\n' "$fp"
}

proxy_user_membership_state_fp_cache_file() {
    local conf_file="${1:-}" cache_key raw_key
    raw_key="${conf_file}|${USER_META_DB_FILE}|${SNELL_CONF}"
    if declare -F routing_runtime_cache_key >/dev/null 2>&1; then
        cache_key="$(routing_runtime_cache_key "$raw_key")"
    else
        cache_key="$(printf '%s' "$raw_key" | cksum 2>/dev/null | awk '{print $1"-"$2}')"
    fi
    printf '%s\n' "$(routing_runtime_cache_dir)/membership-state-${cache_key}.cache"
}

proxy_user_membership_source_meta_fingerprint() {
    local conf_file="${1:-}" conf_meta meta_meta snell_meta
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    conf_meta="$(calc_file_meta_signature "$conf_file" 2>/dev/null || echo "0:0")"
    meta_meta="$(calc_file_meta_signature "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    snell_meta="$(calc_file_meta_signature "$SNELL_CONF" 2>/dev/null || echo "0:0")"
    printf '%s|%s|%s\n' "$conf_meta" "$meta_meta" "$snell_meta"
}

proxy_user_membership_cache_fingerprint() {
    local conf_file="${1:-}"
    local conf_fp meta_fp snell_fp source_meta_key cache_file cached_fp
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"
    proxy_user_meta_db_ensure >/dev/null 2>&1 || true

    source_meta_key="$(proxy_user_membership_source_meta_fingerprint "$conf_file" 2>/dev/null || echo "0:0|0:0|0:0")"
    if [[ "${PROXY_USER_MEMBERSHIP_STATE_FP_SOURCE_KEY:-}" == "$source_meta_key" \
        && -n "${PROXY_USER_MEMBERSHIP_STATE_FP_VALUE:-}" ]]; then
        printf '%s\n' "${PROXY_USER_MEMBERSHIP_STATE_FP_VALUE}"
        return 0
    fi
    cache_file="$(proxy_user_membership_state_fp_cache_file "$conf_file" 2>/dev/null || true)"
    if declare -F proxy_runtime_state_read_matching_value >/dev/null 2>&1; then
        cached_fp="$(proxy_runtime_state_read_matching_value "$cache_file" "$source_meta_key" 2>/dev/null || true)"
    else
        cached_fp=""
    fi
    if [[ -n "$cached_fp" ]]; then
        PROXY_USER_MEMBERSHIP_STATE_FP_SOURCE_KEY="$source_meta_key"
        PROXY_USER_MEMBERSHIP_STATE_FP_VALUE="$cached_fp"
        printf '%s\n' "$cached_fp"
        return 0
    fi

    if declare -F calc_singbox_inbounds_fingerprint >/dev/null 2>&1; then
        conf_fp="$(calc_singbox_inbounds_fingerprint "$conf_file" 2>/dev/null || echo 0:0)"
    else
        conf_fp="$(jq -c '.inbounds // []' "$conf_file" 2>/dev/null | cksum 2>/dev/null | awk '{print $1":"$2}')"
    fi
    meta_fp="$(proxy_user_membership_meta_fingerprint 2>/dev/null || echo 0:0)"
    [[ -n "$conf_fp" ]] || conf_fp="0:0"
    [[ -n "$meta_fp" ]] || meta_fp="0:0"
    snell_fp="$(calc_file_fingerprint "$SNELL_CONF" 2>/dev/null || echo 0:0)"
    cached_fp="$(printf '%s|%s|%s\n' "$conf_fp" "$meta_fp" "$snell_fp")"
    PROXY_USER_MEMBERSHIP_STATE_FP_SOURCE_KEY="$source_meta_key"
    PROXY_USER_MEMBERSHIP_STATE_FP_VALUE="$cached_fp"
    if [[ -n "$cache_file" ]]; then
        mkdir -p "$(routing_runtime_cache_dir)" >/dev/null 2>&1 || true
        if declare -F proxy_runtime_state_write_value >/dev/null 2>&1; then
            proxy_runtime_state_write_value "$cache_file" "$source_meta_key" "$cached_fp" >/dev/null 2>&1 || true
        else
            printf '%s\t%s\n' "$source_meta_key" "$cached_fp" >"$cache_file"
        fi
    fi
    printf '%s\n' "$cached_fp"
}

proxy_user_decode_b64() {
    local value="${1:-}"
    printf '%s' "$value" | base64 -d 2>/dev/null
}

proxy_user_membership_explicit_name() {
    local key_b64="${1:-}" user_b64="${2:-}"
    local explicit_name="" key=""

    if [[ -n "$user_b64" ]]; then
        explicit_name="$(proxy_user_decode_b64 "$user_b64" | jq -r '.name // ""' 2>/dev/null || true)"
        explicit_name="$(printf '%s' "$explicit_name" | tr -d '\r' | tr -d '\n')"
        if [[ -n "$explicit_name" ]]; then
            normalize_proxy_user_name "$explicit_name"
            return 0
        fi
    fi

    if [[ -n "$key_b64" ]]; then
        key="$(proxy_user_decode_b64 "$key_b64")"
        explicit_name="$(proxy_user_meta_get_name "$key" 2>/dev/null || true)"
        explicit_name="$(printf '%s' "$explicit_name" | tr -d '\r' | tr -d '\n')"
        if [[ -n "$explicit_name" ]]; then
            normalize_proxy_user_name "$explicit_name"
            return 0
        fi
    fi

    return 1
}

proxy_user_get_snell_psk() {
    [[ -f "$SNELL_CONF" ]] || return 1
    grep '^psk' "$SNELL_CONF" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '[:space:]'
}

proxy_user_find_inbound_index_by_tag() {
    local conf_file="${1:-}" proto="${2:-}" in_tag="${3:-}"
    [[ -n "$proto" && -n "$in_tag" ]] || return 1
    proxy_protocol_inventory_cache_refresh "$conf_file"

    local row row_proto idx tag port desc
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS=$'\t' read -r row_proto idx tag port desc <<<"$row"
        [[ "$row_proto" == "$proto" && "$tag" == "$in_tag" ]] || continue
        printf '%s\n' "$idx"
        return 0
    done <<< "$PROXY_PROTOCOL_INVENTORY_ROWS"
    return 1
}

proxy_user_matches_filter() {
    local proto="${1:-}" in_tag="${2:-}" user_id="${3:-}" raw_name="${4:-}" target_user="${5:-}"
    [[ -n "$target_user" ]] || return 0
    [[ "$(proxy_user_link_name "$proto" "$in_tag" "$user_id" "$raw_name")" == "$(normalize_proxy_user_name "$target_user")" ]]
}

proxy_user_collect_membership_lines_uncached() {
    local scope="${1:-any}" conf_file="${2:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        local line proto in_tag user_id_b64 raw_name_b64 user_b64 user_id raw_name display_name key key_b64
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            IFS='|' read -r proto in_tag user_id_b64 raw_name_b64 user_b64 <<< "$line"
            [[ -n "$proto" && -n "$in_tag" && -n "$user_id_b64" && -n "$user_b64" ]] || continue
            user_id="$(proxy_user_decode_b64 "$user_id_b64")"
            raw_name="$(proxy_user_decode_b64 "$raw_name_b64")"
            display_name="$(proxy_user_link_name "$proto" "$in_tag" "$user_id" "$raw_name")"
            key="$(proxy_user_key "$proto" "$in_tag" "$user_id")"
            key_b64="$(printf '%s' "$key" | base64_no_wrap)"
            printf 'active|%s|%s|%s|%s|%s|%s\n' "$display_name" "$proto" "$in_tag" "$user_id_b64" "$key_b64" "$user_b64"
        done < <(jq -r '
            def tag_for($entry):
                $entry.value.tag // ("inbound_" + ($entry.key | tostring));
            def base_user_list($in):
                if ($in.users | type) == "array" then $in.users
                elif ($in.users | type) == "object" then [$in.users]
                else []
                end;
            .inbounds
            | to_entries[]?
            | . as $entry
            | ($entry.value // {}) as $in
            | (($in.type // "") | ascii_downcase) as $type
            | if $type == "vless" then
                (
                    (base_user_list($in)[]? | select((.uuid // .id // empty) != "")
                    | "vless|\(tag_for($entry))|\((.uuid // .id // empty)|@base64)|\((.name // "")|@base64)|\((. + {flow:(.flow // "xtls-rprx-vision")})|tojson|@base64)"),
                    (if (($in.users | type) == "null" and ($in.uuid? != null)) then
                        "vless|\(tag_for($entry))|\(($in.uuid // $in.id // empty)|@base64)|\(($in.name // "")|@base64)|\(({name:($in.name // ""), uuid:($in.uuid // $in.id // ""), flow:($in.flow // "xtls-rprx-vision")})|tojson|@base64)"
                     else empty end)
                )
              elif $type == "tuic" then
                (
                    (base_user_list($in)[]? | select((.uuid // .id // empty) != "" and (.password // empty) != "")
                    | "tuic|\(tag_for($entry))|\((.uuid // .id // empty)|@base64)|\((.name // "")|@base64)|\((. + {password:(.password // "")})|tojson|@base64)"),
                    (if (($in.users | type) == "null" and ($in.uuid? != null) and ($in.password? != null)) then
                        "tuic|\(tag_for($entry))|\(($in.uuid // $in.id // empty)|@base64)|\(($in.name // "")|@base64)|\(({name:($in.name // ""), uuid:($in.uuid // $in.id // ""), password:($in.password // "")})|tojson|@base64)"
                     else empty end)
                )
              elif ($type == "trojan" or $type == "anytls") then
                (
                    if (($in.users | type) == "array") then $in.users
                    elif (($in.users | type) == "object") then [$in.users]
                    elif (($in.password? // null) != null) then [{name:($in.name // ""), password:($in.password // "")}]
                    else []
                    end
                )
                | .[]?
                | select((.password // empty) != "")
                | "\($type)|\(tag_for($entry))|\((.password // empty)|@base64)|\((.name // "")|@base64)|\(.|tojson|@base64)"
              elif ($type == "shadowsocks" or $type == "ss") then
                (
                    if ($in.users | type) == "array" then $in.users
                    elif ($in.users | type) == "object" then [$in.users]
                    elif ($in.password? != null) then [{name:($in.name // ""), method:($in.method // ""), password:$in.password}]
                    else []
                    end
                )
                | .[]?
                | select((.password // empty) != "")
                | "ss|\(tag_for($entry))|\((.password // empty)|@base64)|\((.name // "")|@base64)|\(({name:(.name // ""), method:(.method // ($in.method // "")), password:(.password // "")})|tojson|@base64)"
              else
                empty
              end
        ' "$conf_file" 2>/dev/null)
    fi

    if [[ -f "$SNELL_CONF" ]]; then
        local snell_psk snell_name snell_key snell_key_b64 snell_user_json snell_user_b64 snell_id_b64
        snell_psk="$(proxy_user_get_snell_psk 2>/dev/null || true)"
        if [[ -n "$snell_psk" ]]; then
            snell_name="$(proxy_user_link_name "snell" "snell-v5" "$snell_psk" "")"
            snell_key="$(proxy_user_key "snell" "snell-v5" "$snell_psk")"
            snell_key_b64="$(printf '%s' "$snell_key" | base64_no_wrap)"
            snell_user_json="$(jq -nc --arg n "$snell_name" --arg p "$snell_psk" '{name:$n, psk:$p}')"
            snell_user_b64="$(printf '%s' "$snell_user_json" | base64_no_wrap)"
            snell_id_b64="$(printf '%s' "$snell_psk" | base64_no_wrap)"
            printf 'active|%s|%s|%s|%s|%s|%s\n' "$snell_name" "snell" "snell-v5" "$snell_id_b64" "$snell_key_b64" "$snell_user_b64"
        fi
    fi

    if [[ "$scope" == "active" ]]; then
        return 0
    fi

    proxy_user_meta_db_ensure
    local key proto in_tag raw_name_b64 user_b64 user_id display_name key_b64 id_b64 raw_name
    while IFS=$'\t' read -r key proto in_tag raw_name_b64 user_b64; do
        [[ -n "$key" && -n "$proto" && -n "$in_tag" && -n "$user_b64" ]] || continue
        IFS='|' read -r _key_proto _key_tag user_id <<<"$key"
        raw_name="$(proxy_user_decode_b64 "$raw_name_b64")"
        display_name="$(proxy_user_link_name "$proto" "$in_tag" "$user_id" "$raw_name")"
        key_b64="$(printf '%s' "$key" | base64_no_wrap)"
        id_b64="$(printf '%s' "$user_id" | base64_no_wrap)"
        printf 'disabled|%s|%s|%s|%s|%s|%s\n' "$display_name" "$proto" "$in_tag" "$id_b64" "$key_b64" "$user_b64"
    done < <(jq -r '
        .disabled
        | to_entries[]?
        | "\(.key)\t\(.value.proto // "")\t\(.value.tag // "")\t\((.value.user.name // "")|@base64)\t\(.value.user|tojson|@base64)"
    ' "$USER_META_DB_FILE" 2>/dev/null)
}

proxy_user_membership_cache_refresh() {
    local conf_file="${1:-}"
    local current_fp cache_file tmp_cache
    current_fp="$(proxy_user_membership_cache_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$current_fp" ]] || current_fp="0:0|0:0|0:0"

    if [[ "$PROXY_USER_MEMBERSHIP_CACHE_FP" == "$current_fp" ]]; then
        return 0
    fi

    mkdir -p "$(routing_runtime_cache_dir)" >/dev/null 2>&1 || true
    cache_file="$(proxy_user_membership_cache_file_for_fp "$current_fp")"
    if [[ -f "$cache_file" ]]; then
        PROXY_USER_MEMBERSHIP_CACHE_ALL="$(cat "$cache_file" 2>/dev/null || true)"
        PROXY_USER_MEMBERSHIP_CACHE_FP="$current_fp"
        return 0
    fi

    PROXY_USER_MEMBERSHIP_CACHE_ALL="$(proxy_user_collect_membership_lines_uncached "any" "$conf_file" 2>/dev/null || true)"
    tmp_cache="$(mktemp)"
    printf '%s' "$PROXY_USER_MEMBERSHIP_CACHE_ALL" >"$tmp_cache"
    mv "$tmp_cache" "$cache_file"
    PROXY_USER_MEMBERSHIP_CACHE_FP="$current_fp"
}

proxy_user_collect_membership_lines() {
    local scope="${1:-any}" conf_file="${2:-}"
    proxy_user_membership_cache_refresh "$conf_file"

    if [[ "$scope" == "active" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" && "$line" == active\|* ]] || continue
            printf '%s\n' "$line"
        done <<< "$PROXY_USER_MEMBERSHIP_CACHE_ALL"
        return 0
    fi

    [[ -n "$PROXY_USER_MEMBERSHIP_CACHE_ALL" ]] && printf '%s\n' "$PROXY_USER_MEMBERSHIP_CACHE_ALL"
}

proxy_user_derived_cache_refresh() {
    local conf_file="${1:-}"
    local current_fp

    # During an active protocol install session the derived name cache (user
    # list, protocol counts) does not need to be rebuilt on every conf-file
    # write.  Within the session each protocol addition changes the conf mtime,
    # which would otherwise invalidate the membership fingerprint and trigger an
    # O(inbounds) jq rescan on every subsequent user-selection prompt.  The
    # pre-existing user list remains valid for the selection menu because
    # newly-queued memberships are applied in batch at session flush time, after
    # which the session ends and the next call runs a full rebuild normally.
    if [[ "${PROTOCOL_INSTALL_SESSION_ACTIVE:-0}" == "1" \
        && -n "${PROXY_USER_DERIVED_CACHE_FP:-}" ]]; then
        return 0
    fi

    proxy_user_group_sync_from_memberships "$conf_file" >/dev/null 2>&1 || true
    proxy_user_membership_cache_refresh "$conf_file"
    current_fp="$(proxy_user_membership_cache_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$current_fp" ]] || current_fp="0:0|0:0|0:0"

    if [[ "$PROXY_USER_DERIVED_CACHE_FP" == "$current_fp" ]]; then
        return 0
    fi

    local -A seen_names=() active_names=() active_counts=() disabled_counts=() active_name_counts=() disabled_name_counts=()
    local -a order=()
    local group_name line state name proto in_tag id_b64 key_b64 user_b64 cache_name explicit_name
    local proto_order=("vless" "tuic" "trojan" "ss" "anytls" "snell")

    proxy_user_group_list >/dev/null 2>&1 || true
    while IFS= read -r group_name; do
        [[ -n "$group_name" ]] || continue
        if [[ -z "${seen_names[$group_name]+x}" ]]; then
            seen_names["$group_name"]=1
            order+=("$group_name")
        fi
    done <<< "$PROXY_USER_GROUP_LIST_CACHE"

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state name proto in_tag id_b64 key_b64 user_b64 <<<"$line"
        [[ -n "$proto" ]] || continue
        explicit_name="$(proxy_user_membership_explicit_name "$key_b64" "$user_b64" 2>/dev/null || true)"
        [[ -n "$explicit_name" ]] || continue
        if [[ -z "${seen_names[$explicit_name]+x}" ]]; then
            seen_names["$explicit_name"]=1
            order+=("$explicit_name")
        fi
        if [[ "$state" == "active" ]]; then
            active_names["$explicit_name"]=1
            ((active_name_counts["$explicit_name"]+=1))
            ((active_counts["${explicit_name}|${proto}"]+=1))
        else
            ((disabled_name_counts["$explicit_name"]+=1))
            ((disabled_counts["${explicit_name}|${proto}"]+=1))
        fi
    done <<< "$PROXY_USER_MEMBERSHIP_CACHE_ALL"

    PROXY_USER_NAMES_CACHE_ANY=""
    PROXY_USER_NAMES_CACHE_ACTIVE=""
    PROXY_USER_PROTOCOL_ROWS_CACHE=""
    PROXY_USER_NAME_ROWS_CACHE=""
    PROXY_USER_GROUP_ROWS_CACHE_ANY=""
    PROXY_USER_GROUP_ROWS_CACHE_HAS_ACTIVE=""
    PROXY_USER_GROUP_ROWS_CACHE_HAS_DISABLED=""

    for cache_name in "${order[@]}"; do
        PROXY_USER_NAMES_CACHE_ANY+="${cache_name}"$'\n'
        [[ -n "${active_names[$cache_name]+x}" ]] && PROXY_USER_NAMES_CACHE_ACTIVE+="${cache_name}"$'\n'
    done

    local cache_proto active_count disabled_count total_count label desc summary
    local -a parts
    local group_proto_order=("vless" "tuic" "trojan" "anytls" "ss" "snell-v5")
    for cache_name in "${order[@]}"; do
        for cache_proto in "${proto_order[@]}"; do
            active_count="${active_counts["${cache_name}|${cache_proto}"]:-0}"
            disabled_count="${disabled_counts["${cache_name}|${cache_proto}"]:-0}"
            (( active_count + disabled_count > 0 )) || continue
            PROXY_USER_PROTOCOL_ROWS_CACHE+="${cache_name}"$'\t'"${cache_proto}"$'\t'"${active_count}"$'\t'"${disabled_count}"$'\n'
            PROXY_USER_NAME_ROWS_CACHE+="${cache_proto}"$'\t'"${cache_name}"$'\t'"${active_count}"$'\t'"${disabled_count}"$'\n'
        done

        parts=()
        for label in "${group_proto_order[@]}"; do
            cache_proto="$label"
            [[ "$cache_proto" == "snell-v5" ]] && cache_proto="snell"
            active_count="${active_counts["${cache_name}|${cache_proto}"]:-0}"
            disabled_count="${disabled_counts["${cache_name}|${cache_proto}"]:-0}"
            total_count=$(( active_count + disabled_count ))
            (( total_count > 0 )) || continue
            desc="${label}(${total_count})"
            parts+=("$desc")
        done
        if (( ${#parts[@]} == 0 )); then
            summary="-"
        else
            local IFS=', '
            summary="${parts[*]}"
        fi

        active_count="${active_name_counts[$cache_name]:-0}"
        disabled_count="${disabled_name_counts[$cache_name]:-0}"
        PROXY_USER_GROUP_ROWS_CACHE_ANY+="${cache_name}"$'\t'"${summary}"$'\t'"${active_count}"$'\t'"${disabled_count}"$'\n'
        (( active_count > 0 )) && PROXY_USER_GROUP_ROWS_CACHE_HAS_ACTIVE+="${cache_name}"$'\t'"${summary}"$'\t'"${active_count}"$'\t'"${disabled_count}"$'\n'
        (( disabled_count > 0 )) && PROXY_USER_GROUP_ROWS_CACHE_HAS_DISABLED+="${cache_name}"$'\t'"${summary}"$'\t'"${active_count}"$'\t'"${disabled_count}"$'\n'
    done

    PROXY_USER_DERIVED_CACHE_FP="$current_fp"
}

proxy_user_group_sync_from_memberships() {
    local conf_file="${1:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"
    local current_fp
    current_fp="$(proxy_user_membership_cache_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$current_fp" ]] || current_fp="0:0|0:0|0:0"
    if [[ "$PROXY_USER_GROUP_SYNC_FP" == "$current_fp" ]]; then
        return 0
    fi

    local -A seen=()
    local group_name
    proxy_user_group_list >/dev/null 2>&1 || true
    while IFS= read -r group_name; do
        [[ -n "$group_name" ]] || continue
        seen["$group_name"]=1
    done <<< "$PROXY_USER_GROUP_LIST_CACHE"

    proxy_user_membership_cache_refresh "$conf_file"
    local line state name proto in_tag id_b64 key_b64 user_b64 explicit_name
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state name proto in_tag id_b64 key_b64 user_b64 <<<"$line"
        explicit_name="$(proxy_user_membership_explicit_name "$key_b64" "$user_b64" 2>/dev/null || true)"
        [[ -n "$explicit_name" ]] || continue
        [[ -n "${seen[$explicit_name]+x}" ]] && continue
        seen["$explicit_name"]=1
        proxy_user_group_add "$explicit_name" >/dev/null 2>&1 || true
    done <<< "$PROXY_USER_MEMBERSHIP_CACHE_ALL"

    PROXY_USER_GROUP_SYNC_FP="$(proxy_user_membership_cache_fingerprint "$conf_file" 2>/dev/null || true)"
}

proxy_user_collect_names() {
    local scope="${1:-any}" conf_file="${2:-}"
    proxy_user_derived_cache_refresh "$conf_file"
    case "$scope" in
        active)
            [[ -n "$PROXY_USER_NAMES_CACHE_ACTIVE" ]] && printf '%s' "$PROXY_USER_NAMES_CACHE_ACTIVE"
            ;;
        *)
            [[ -n "$PROXY_USER_NAMES_CACHE_ANY" ]] && printf '%s' "$PROXY_USER_NAMES_CACHE_ANY"
            ;;
    esac
}

proxy_user_collect_protocol_rows_by_name() {
    local target_name="${1:-}" scope="${2:-any}" conf_file="${3:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || return 0
    proxy_user_derived_cache_refresh "$conf_file"

    local row name proto active_count disabled_count
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS=$'\t' read -r name proto active_count disabled_count <<<"$row"
        [[ "$name" == "$target_name" ]] || continue
        if [[ "$scope" == "active" && "$active_count" == "0" ]]; then
            continue
        fi
        printf '%s\t%s\t%s\n' "$proto" "$active_count" "$disabled_count"
    done <<< "$PROXY_USER_PROTOCOL_ROWS_CACHE"
}

proxy_user_has_protocol_for_name() {
    local target_name="${1:-}" target_proto="${2:-}" scope="${3:-any}" conf_file="${4:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$target_proto" ]] || return 1

    local row proto active_count disabled_count
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS=$'\t' read -r proto active_count disabled_count <<<"$row"
        [[ "$proto" == "$target_proto" ]] || continue
        (( active_count + disabled_count > 0 )) && return 0
    done < <(proxy_user_collect_protocol_rows_by_name "$target_name" "$scope" "$conf_file")
    return 1
}

# --- user data operations (merged from user_data_ops.sh) ---

proxy_user_protocol_label() {
    case "${1:-}" in
        snell) echo "snell-v5" ;;
        *) echo "${1:-}" ;;
    esac
}

proxy_user_select_name_for_protocol_action() {
    local title="${1:-选择用户名}" scope="${2:-any}" conf_file="${3:-}"
    local names=()
    mapfile -t names < <(proxy_user_collect_names "$scope" "$conf_file")

    if [[ ${#names[@]} -eq 0 ]]; then
        printf '未检测到已有用户名，请先到用户管理添加用户名。\n' >&2
        echo "__none__"
        return 0
    fi

    if [[ ${#names[@]} -eq 1 ]]; then
        printf '仅检测到 1 个用户名，默认使用: %s\n' "${names[0]}" >&2
        echo "${names[0]}"
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
