# Config and update operation functions for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

BOOTSTRAP_OPS_FILE="${BOOTSTRAP_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap_ops.sh}"
if [[ -f "$BOOTSTRAP_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$BOOTSTRAP_OPS_FILE"
fi

RELEASE_OPS_FILE="${RELEASE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release_ops.sh}"
if [[ -f "$RELEASE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$RELEASE_OPS_FILE"
fi

USER_TEMPLATE_OPS_FILE="${USER_TEMPLATE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_template_ops.sh}"
if [[ -f "$USER_TEMPLATE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_TEMPLATE_OPS_FILE"
fi

normalize_singbox_top_level_key_order() {
    local conf_file="$1"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local tmp_json
    tmp_json="$(mktemp)"
    if ! render_singbox_json_with_compact_rule_lines "$conf_file" >"$tmp_json"; then
        rm -f "$tmp_json"
        return 1
    fi

    if cmp -s "$conf_file" "$tmp_json"; then
        rm -f "$tmp_json"
        return 0
    fi

    mv "$tmp_json" "$conf_file"
    return 0
}

stack_dns_strategy_for_mode() {
    local mode="${1:-ipv4}"
    case "$mode" in
        dualstack) echo "prefer_ipv4" ;;
        ipv6) echo "ipv6_only" ;;
        *) echo "ipv4_only" ;;
    esac
}

stack_direct_strategy_for_mode() {
    local mode="${1:-ipv4}"
    case "$mode" in
        dualstack) echo "prefer_ipv4" ;;
        ipv6) echo "ipv6_only" ;;
        *) echo "ipv4_only" ;;
    esac
}

dns_public_tag_for_strategy() {
    local strategy="${1:-ipv4_only}"
    case "$strategy" in
        ipv6_only|prefer_ipv6) echo "public6" ;;
        *) echo "public4" ;;
    esac
}

SHOW_JOIN_CODE="${SHOW_JOIN_CODE:-off}"
SURGE_LINK_VERBOSE_PARAMS="${SURGE_LINK_VERBOSE_PARAMS:-on}"
SHADOWTLS_SNI_USED_FILE="${WORK_DIR}/.shadowtls_sni_used"
SINGBOX_LOADED_FINGERPRINT_FILE="${WORK_DIR}/.singbox_loaded_fingerprint"
DEFAULT_PROXY_USER_NAME="${DEFAULT_PROXY_USER_NAME:-user}"
USER_META_DB_FILE="${WORK_DIR}/user-management.json"
USER_ROUTE_RULES_DB_FILE="${WORK_DIR}/user-route-rules.json"
USER_TEMPLATE_DB_FILE="${WORK_DIR}/user-route-templates.json"
if ! declare -p SUBSCRIPTION_IP_DETECT_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA SUBSCRIPTION_IP_DETECT_CACHE=()
fi
if ! declare -p SUBSCRIPTION_DOMAIN_RESOLVE_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA SUBSCRIPTION_DOMAIN_RESOLVE_CACHE=()
fi
if ! declare -p REALITY_PUBLIC_KEY_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA REALITY_PUBLIC_KEY_CACHE=()
fi
SUBSCRIPTION_RENDER_CONTEXT_ACTIVE=0
SUBSCRIPTION_RENDER_CONTEXT_HOST=""
SUBSCRIPTION_RENDER_CONTEXT_CONF=""
SUBSCRIPTION_RENDER_CONTEXT_NODE_NAME=""
SUBSCRIPTION_RENDER_CONTEXT_SURGE_IP_TARGETS=""
SUBSCRIPTION_RENDER_CONTEXT_SURGE_DOMAIN_TARGETS=""
SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_BINDINGS=""
SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_TARGET_KEYS=""
SUBSCRIPTION_RENDER_CONTEXT_VLESS_INBOUNDS=""
SUBSCRIPTION_RENDER_CONTEXT_TUIC_INBOUNDS=""
SUBSCRIPTION_RENDER_CONTEXT_TROJAN_INBOUNDS=""
SUBSCRIPTION_RENDER_CONTEXT_ANYTLS_INBOUNDS=""
SUBSCRIPTION_RENDER_CONTEXT_SS_INBOUNDS=""
PROXY_USER_MEMBERSHIP_CACHE_FP=""
PROXY_USER_MEMBERSHIP_CACHE_ALL=""
PROXY_USER_DERIVED_CACHE_FP=""
PROXY_USER_NAMES_CACHE_ANY=""
PROXY_USER_NAMES_CACHE_ACTIVE=""
PROXY_USER_PROTOCOL_ROWS_CACHE=""
PROXY_USER_NAME_ROWS_CACHE=""
PROXY_USER_GROUP_ROWS_CACHE_ANY=""
PROXY_USER_GROUP_ROWS_CACHE_HAS_ACTIVE=""
PROXY_USER_GROUP_ROWS_CACHE_HAS_DISABLED=""
PROXY_USER_GROUP_SYNC_FP=""
PROXY_USER_META_DB_READY_FP=""
PROXY_USER_TEMPLATE_DB_READY_FP=""
PROXY_USER_META_VALUE_CACHE_FP=""
PROXY_USER_GROUP_LIST_CACHE_FP=""
PROXY_USER_GROUP_LIST_CACHE=""
PROXY_PROTOCOL_INVENTORY_CACHE_FP=""
PROXY_PROTOCOL_INVENTORY_ROWS=""
PROXY_PROTOCOL_INSTALLED_CACHE=""
PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE_FP=""
PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE=""
ROUTING_USER_CONTEXT_ACTIVE=0
ROUTING_USER_CONTEXT_NAME=""
if ! declare -p PROXY_USER_META_NAME_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_META_NAME_CACHE=()
fi
if ! declare -p PROXY_USER_META_TEMPLATE_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_META_TEMPLATE_CACHE=()
fi
if ! declare -p PROXY_USER_META_EXPIRY_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_USER_META_EXPIRY_CACHE=()
fi
ROUTING_USER_RUNTIME_CACHE_FP=""
ROUTING_USER_RUNTIME_INPUT_FP=""
ROUTING_USER_RUNTIME_INPUT_SOURCE_KEY=""
ROUTING_USER_RUNTIME_INPUT_CACHED_FP=""
ROUTING_IPV6_STACK_CACHE=""
if ! declare -p ROUTING_USER_BINDABLE_KEYS_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_USER_BINDABLE_KEYS_CACHE=()
fi
if ! declare -p ROUTING_USER_TEMPLATE_IDS_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_USER_TEMPLATE_IDS_CACHE=()
fi
if ! declare -p ROUTING_USER_STATE_JSON_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_USER_STATE_JSON_CACHE=()
fi
if ! declare -p ROUTING_USER_RULE_COUNT_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_USER_RULE_COUNT_CACHE=()
fi
if ! declare -p ROUTING_USER_TEMPLATE_MODE_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_USER_TEMPLATE_MODE_CACHE=()
fi

is_feature_enabled() {
    local value="${1:-off}"
    local normalized
    normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
        1|on|yes|true|y) return 0 ;;
        *) return 1 ;;
    esac
}

routing_user_reset_runtime_cache() {
    ROUTING_USER_RUNTIME_CACHE_FP=""
    ROUTING_USER_RUNTIME_INPUT_FP=""
    ROUTING_USER_BINDABLE_KEYS_CACHE=()
    ROUTING_USER_TEMPLATE_IDS_CACHE=()
    ROUTING_USER_STATE_JSON_CACHE=()
    ROUTING_USER_RULE_COUNT_CACHE=()
    ROUTING_USER_TEMPLATE_MODE_CACHE=()
}

routing_user_runtime_input_fingerprint() {
    local conf_file="${1:-}" conf_fp meta_fp template_fp snell_fp
    local source_meta_key cache_file cached_fp
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    source_meta_key="$(printf '%s|%s|%s|%s\n' \
        "$(calc_file_meta_signature "$conf_file" 2>/dev/null || echo "0:0")" \
        "$(calc_file_meta_signature "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")" \
        "$(calc_file_meta_signature "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")" \
        "$(calc_file_meta_signature "$SNELL_CONF" 2>/dev/null || echo "0:0")")"
    if [[ "$ROUTING_USER_RUNTIME_INPUT_SOURCE_KEY" == "$source_meta_key" \
        && -n "$ROUTING_USER_RUNTIME_INPUT_CACHED_FP" ]]; then
        printf '%s\n' "$ROUTING_USER_RUNTIME_INPUT_CACHED_FP"
        return 0
    fi

    cache_file="$(proxy_runtime_cache_file "routing-user-runtime-input-fp" "${conf_file}|${USER_META_DB_FILE}|${USER_TEMPLATE_DB_FILE}|${SNELL_CONF}" 2>/dev/null || true)"
    cached_fp="$(proxy_runtime_state_read_matching_value "$cache_file" "$source_meta_key" 2>/dev/null || true)"
    if [[ -n "$cached_fp" ]]; then
        ROUTING_USER_RUNTIME_INPUT_SOURCE_KEY="$source_meta_key"
        ROUTING_USER_RUNTIME_INPUT_CACHED_FP="$cached_fp"
        printf '%s\n' "$cached_fp"
        return 0
    fi

    conf_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    meta_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    template_fp="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    snell_fp="$(calc_file_fingerprint "$SNELL_CONF" 2>/dev/null || echo "0:0")"
    cached_fp="$(printf '%s|%s|%s|%s\n' "$conf_fp" "$meta_fp" "$template_fp" "$snell_fp")"
    ROUTING_USER_RUNTIME_INPUT_SOURCE_KEY="$source_meta_key"
    ROUTING_USER_RUNTIME_INPUT_CACHED_FP="$cached_fp"
    proxy_runtime_state_write_value "$cache_file" "$source_meta_key" "$cached_fp" >/dev/null 2>&1 || true
    printf '%s\n' "$cached_fp"
}

routing_user_runtime_cache_refresh() {
    local conf_file="${1:-}" current_fp="" input_fp=""
    input_fp="$(routing_user_runtime_input_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$input_fp" ]] || input_fp="0:0|0:0|0:0|0:0"
    if [[ -n "$ROUTING_USER_RUNTIME_CACHE_FP" && "$ROUTING_USER_RUNTIME_INPUT_FP" == "$input_fp" ]]; then
        return 0
    fi

    proxy_user_membership_cache_refresh "$conf_file"
    proxy_user_meta_value_cache_refresh
    proxy_user_template_db_ensure
    current_fp="${PROXY_USER_MEMBERSHIP_CACHE_FP}|${PROXY_USER_META_VALUE_CACHE_FP}|${PROXY_USER_TEMPLATE_DB_READY_FP}"
    if [[ "$ROUTING_USER_RUNTIME_CACHE_FP" == "$current_fp" ]]; then
        ROUTING_USER_RUNTIME_INPUT_FP="$input_fp"
        return 0
    fi
    routing_user_reset_runtime_cache
    ROUTING_USER_RUNTIME_CACHE_FP="$current_fp"
    ROUTING_USER_RUNTIME_INPUT_FP="$input_fp"
}

surge_link_verbose_params_enabled() {
    is_feature_enabled "$SURGE_LINK_VERBOSE_PARAMS"
}

prompt_select_index() {
    local __pick_var="$1" __pick_value=""
    if ! read_prompt __pick_value "选择序号(回车取消): "; then
        printf -v "$__pick_var" '%s' ""
        return 130
    fi
    if [[ -z "$__pick_value" ]]; then
        printf -v "$__pick_var" '%s' ""
        return 130
    fi
    printf -v "$__pick_var" '%s' "$__pick_value"
    return 0
}

shadowtls_join_code_enabled() {
    is_feature_enabled "$SHOW_JOIN_CODE"
}

is_valid_uuid_text() {
    local value="${1:-}"
    [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

first_valid_inbound_uuid() {
    local conf_file="$1"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1
    jq -r '
        [
            .inbounds[]?
            | select(.type=="vless" or .type=="tuic")
            | (if (.users | type) == "array" then .users[]?
               elif (.users | type) == "object" then .users
               else empty end)
            | .uuid?
            | strings
            | select(test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"))
        ][0] // empty
    ' "$conf_file" 2>/dev/null
}

sanitize_singbox_inbound_uuids() {
    local conf_file="$1"
    local fallback_uuid="${2:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if ! is_valid_uuid_text "$fallback_uuid"; then
        fallback_uuid="$(first_valid_inbound_uuid "$conf_file" 2>/dev/null || true)"
    fi
    if ! is_valid_uuid_text "$fallback_uuid"; then
        fallback_uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
    fi
    if ! is_valid_uuid_text "$fallback_uuid"; then
        fallback_uuid="AD3EF784-6895-48D7-82F9-0AEAC44EC4F3"
    fi

    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg u "$fallback_uuid" '
        def valid_uuid($s):
            ($s | type == "string")
            and ($s | test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"));
        def normalize_users:
            if (.users | type) == "array" then .users
            elif (.users | type) == "object" then [.users]
            else []
            end;
        .inbounds = ((.inbounds // []) | map(
            if (.type == "vless" or .type == "tuic") then
                .users = (normalize_users | map(
                    if valid_uuid(.uuid) then .
                    else . + {uuid: $u}
                    end
                ))
            else .
            end
        ))
    ' "$conf_file" > "$tmp_json" 2>/dev/null || {
        rm -f "$tmp_json"
        return 1
    }

    if [[ ! -s "$tmp_json" ]]; then
        rm -f "$tmp_json"
        return 1
    fi

    if cmp -s "$conf_file" "$tmp_json"; then
        rm -f "$tmp_json"
        return 2
    fi

    mv "$tmp_json" "$conf_file"
    return 0
}

sanitize_singbox_inbound_user_names() {
    local conf_file="$1"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    proxy_user_membership_cache_refresh "$conf_file"

    local map_file tmp_json line state display_name proto in_tag id_b64 key_b64 user_b64 user_id key meta_name effective_name
    map_file="$(mktemp)"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r state display_name proto in_tag id_b64 key_b64 user_b64 <<<"$line"
        [[ "$state" == "active" ]] || continue
        user_id="$(proxy_user_decode_b64 "$id_b64")"
        [[ -n "$display_name" && -n "$proto" && -n "$in_tag" && -n "$user_id" ]] || continue
        key="${proto}|${in_tag}|${user_id}"
        meta_name="$(proxy_user_meta_get_name "$key")"
        effective_name="${meta_name:-$display_name}"
        [[ -n "$effective_name" ]] || continue
        printf '%s\t%s\n' "$key" "$effective_name" >>"$map_file"
    done <<<"$PROXY_USER_MEMBERSHIP_CACHE_ALL"

    local name_map_json
    name_map_json="$(jq -Rn '
        reduce inputs as $line ({};
            ($line | split("\t")) as $parts
            | if ($parts | length) >= 2 then . + {($parts[0]): $parts[1]} else . end
        )
    ' <"$map_file" 2>/dev/null)"
    rm -f "$map_file"
    [[ -n "$name_map_json" && "$name_map_json" != "null" ]] || return 1

    tmp_json="$(mktemp)"
    jq --argjson names "$name_map_json" '
        def key_for($proto; $tag; $id): "\($proto)|\($tag)|\($id)";
        def desired_name($proto; $tag; $id): ($names[key_for($proto; $tag; $id)] // "");
        def fill_user_name($proto; $tag; $id):
            (desired_name($proto; $tag; $id)) as $n
            | if (($n | length) > 0 and ((.name // "") | length) == 0) then . + {name: $n} else . end;
        def normalize_ss_user($tag):
            (desired_name("ss"; $tag; (.password // ""))) as $n
            | (
                if (($n | length) > 0 and (($n != (.name // "")) or ((.name // "") | length) == 0)) then
                    . + {name: $n}
                else
                    .
                end
            )
            | del(.method);
        def ss_name_candidate($tag):
            (desired_name("ss"; $tag; (.password // ""))) as $mapped
            | if (($mapped | length) > 0) then $mapped else (.name // "") end;
        .inbounds = (
            (.inbounds // [])
            | to_entries
            | map(
                (.value.tag // ("inbound_" + (.key | tostring))) as $tag
                | (.value.type // "" | ascii_downcase) as $type
                | .value |= (
                    if $type == "vless" then
                        if (.users | type) == "array" then
                            .users |= map(fill_user_name("vless"; $tag; (.uuid // .id // "")))
                        elif (.users | type) == "object" then
                            .users |= fill_user_name("vless"; $tag; (.uuid // .id // ""))
                        elif ((.uuid // .id // "") | length) > 0 then
                            fill_user_name("vless"; $tag; (.uuid // .id // ""))
                        else
                            .
                        end
                    elif $type == "tuic" then
                        if (.users | type) == "array" then
                            .users |= map(fill_user_name("tuic"; $tag; (.uuid // .id // "")))
                        elif (.users | type) == "object" then
                            .users |= fill_user_name("tuic"; $tag; (.uuid // .id // ""))
                        elif ((.uuid // .id // "") | length) > 0 then
                            fill_user_name("tuic"; $tag; (.uuid // .id // ""))
                        else
                            .
                        end
                    elif ($type == "trojan" or $type == "anytls") then
                        if (.users | type) == "array" then
                            .users |= map(fill_user_name($type; $tag; (.password // "")))
                        elif (.users | type) == "object" then
                            .users |= fill_user_name($type; $tag; (.password // ""))
                        elif ((.password // "") | length) > 0 then
                            fill_user_name($type; $tag; (.password // ""))
                        else
                            .
                        end
                    elif ($type == "shadowsocks" or $type == "ss") then
                        if (.users | type) == "array" then
                            .users |= map(normalize_ss_user($tag))
                            | del(.name)
                        elif (.users | type) == "object" then
                            .users |= normalize_ss_user($tag)
                            | del(.name)
                        elif ((.password // "") | length) > 0 then
                            (ss_name_candidate($tag)) as $n
                            | if (($n | length) > 0) then
                                .users = [{name: $n, password: (.password // "")}]
                                | del(.name)
                              else
                                del(.name)
                              end
                        else
                            del(.name)
                        end
                    else
                        .
                    end
                )
            )
            | map(.value)
        )
    ' "$conf_file" > "$tmp_json" 2>/dev/null || {
        rm -f "$tmp_json"
        return 1
    }

    if [[ ! -s "$tmp_json" ]]; then
        rm -f "$tmp_json"
        return 1
    fi

    if cmp -s "$conf_file" "$tmp_json"; then
        rm -f "$tmp_json"
        return 2
    fi

    mv "$tmp_json" "$conf_file"
    return 0
}

SINGBOX_INBOUND_USER_NAMES_SANITIZED_FP="${SINGBOX_INBOUND_USER_NAMES_SANITIZED_FP:-}"

calc_singbox_inbounds_fingerprint() {
    local conf_file="${1:-}" conf_fp cache_file cached_fp inbounds_text fp
    [[ -n "$conf_file" && -f "$conf_file" ]] || { echo "0:0"; return 0; }

    conf_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    cache_file="$(proxy_runtime_cache_file "json-inbounds-fingerprint" "$conf_file" 2>/dev/null || true)"
    cached_fp="$(proxy_runtime_state_read_matching_value "$cache_file" "$conf_fp" 2>/dev/null || true)"
    if [[ -n "$cached_fp" ]]; then
        echo "$cached_fp"
        return 0
    fi

    # Fast path: sing-box config is emitted in stable top-level key order, so
    # we can hash the inbounds block text directly and avoid full JSON parsing.
    inbounds_text="$(
        awk '
            BEGIN { inb = 0 }
            /^[[:space:]]*"inbounds"[[:space:]]*:/ { inb = 1 }
            inb && /^[[:space:]]*"outbounds"[[:space:]]*:/ { exit }
            inb { print }
        ' "$conf_file" 2>/dev/null
    )"
    if [[ -n "$inbounds_text" ]]; then
        fp="$(printf '%s' "$inbounds_text" | cksum 2>/dev/null | awk '{print $1":"$2}')"
        if [[ -n "$fp" ]]; then
            proxy_runtime_state_write_value "$cache_file" "$conf_fp" "$fp" >/dev/null 2>&1 || true
            echo "$fp"
            return 0
        fi
    fi

    fp="$(jq -c '.inbounds // []' "$conf_file" 2>/dev/null | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$fp" ]] || fp="0:0"
    proxy_runtime_state_write_value "$cache_file" "$conf_fp" "$fp" >/dev/null 2>&1 || true
    echo "$fp"
}

calc_user_meta_name_fingerprint() {
    local meta_fp cache_file cached_fp fp
    [[ -f "$USER_META_DB_FILE" ]] || { echo "0:0"; return 0; }
    meta_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    cache_file="$(proxy_runtime_cache_file "json-meta-name-fingerprint" "$USER_META_DB_FILE" 2>/dev/null || true)"
    cached_fp="$(proxy_runtime_state_read_matching_value "$cache_file" "$meta_fp" 2>/dev/null || true)"
    if [[ -n "$cached_fp" ]]; then
        echo "$cached_fp"
        return 0
    fi
    fp="$(jq -c '.name // {}' "$USER_META_DB_FILE" 2>/dev/null \
        | cksum 2>/dev/null \
        | awk '{print $1":"$2}')"
    [[ -n "$fp" ]] || fp="0:0"
    proxy_runtime_state_write_value "$cache_file" "$meta_fp" "$fp" >/dev/null 2>&1 || true
    echo "$fp"
}

sanitize_singbox_inbound_user_names_if_needed() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local inbounds_fp meta_name_fp current_fp rc cache_file
    inbounds_fp="$(calc_singbox_inbounds_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    meta_name_fp="$(calc_user_meta_name_fingerprint 2>/dev/null || echo "0:0")"
    current_fp="${inbounds_fp}|${meta_name_fp}"
    if [[ "$SINGBOX_INBOUND_USER_NAMES_SANITIZED_FP" == "$current_fp" ]]; then
        return 2
    fi
    cache_file="$(proxy_runtime_cache_file "sanitize-inbound-user-names" "$conf_file" 2>/dev/null || true)"
    if [[ -n "$(proxy_runtime_state_read_matching_value "$cache_file" "$current_fp" 2>/dev/null || true)" ]]; then
        SINGBOX_INBOUND_USER_NAMES_SANITIZED_FP="$current_fp"
        return 2
    fi

    sanitize_singbox_inbound_user_names "$conf_file"
    rc=$?
    if [[ "$rc" -eq 0 || "$rc" -eq 2 ]]; then
        inbounds_fp="$(calc_singbox_inbounds_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
        meta_name_fp="$(calc_user_meta_name_fingerprint 2>/dev/null || echo "0:0")"
        SINGBOX_INBOUND_USER_NAMES_SANITIZED_FP="${inbounds_fp}|${meta_name_fp}"
        proxy_runtime_state_write_value "$cache_file" "$SINGBOX_INBOUND_USER_NAMES_SANITIZED_FP" "$SINGBOX_INBOUND_USER_NAMES_SANITIZED_FP" >/dev/null 2>&1 || true
    fi
    return "$rc"
}

proxy_invalidate_after_mutation() {
    local scope="${1:-config}"
    case "$scope" in
        user)
            PROXY_USER_META_VALUE_CACHE_FP=""
            PROXY_USER_GROUP_LIST_CACHE_FP=""
            PROXY_USER_DISPLAY_NAME_CACHE_FP=""
            PROXY_USER_DERIVED_CACHE_FP=""
            PROXY_USER_MEMBERSHIP_CACHE_FP=""
            ;;
        protocol)
            PROXY_PROTOCOL_INVENTORY_CACHE_FP=""
            PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE_FP=""
            ;;
        routing)
            if declare -F routing_user_reset_runtime_cache >/dev/null 2>&1; then
                routing_user_reset_runtime_cache
            fi
            ROUTING_IPV6_STACK_CACHE=""
            ;;
        config|*)
            PROXY_USER_META_VALUE_CACHE_FP=""
            PROXY_USER_GROUP_LIST_CACHE_FP=""
            PROXY_USER_DISPLAY_NAME_CACHE_FP=""
            PROXY_USER_DERIVED_CACHE_FP=""
            PROXY_USER_MEMBERSHIP_CACHE_FP=""
            PROXY_PROTOCOL_INVENTORY_CACHE_FP=""
            PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE_FP=""
            if declare -F routing_user_reset_runtime_cache >/dev/null 2>&1; then
                routing_user_reset_runtime_cache
            fi
            ROUTING_IPV6_STACK_CACHE=""
            ;;
    esac
    if declare -F proxy_invalidate_service_state_cache >/dev/null 2>&1; then
        proxy_invalidate_service_state_cache
    fi
}

routing_runtime_cache_dir() {
    echo "${CACHE_DIR}/routing"
}

routing_runtime_cache_key() {
    local raw="${1:-}"
    printf '%s' "$raw" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

proxy_user_membership_cache_file_for_fp() {
    local fp="${1:-}"
    local cache_key
    cache_key="$(routing_runtime_cache_key "$fp")"
    echo "$(routing_runtime_cache_dir)/membership-${cache_key}.cache"
}

routing_user_state_cache_file_for_name_fp() {
    local target_name="${1:-}" fp="${2:-}"
    local cache_key
    cache_key="$(routing_runtime_cache_key "${target_name}|${fp}")"
    echo "$(routing_runtime_cache_dir)/user-state-${cache_key}.cache"
}



# --- sing-box config rendering helpers (merged from singbox_render_ops.sh) ---

singbox_compact_rule_rows() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    jq -r '
        def emit_rule_rows($arr; $prefix):
            ($arr // [])
            | if type == "array" then
                  to_entries[]
                  | ["__PROXY_COMPACT_RULE_" + $prefix + "_" + (.key | tostring) + "__", (.value | tojson)]
                  | @tsv
              else empty end;
        emit_rule_rows(.dns.rules; "DNS"),
        emit_rule_rows(.route.rules; "ROUTE")
    ' "$conf_file"
}

singbox_render_json_with_rule_placeholders() {
    local conf_file="${1:-}" hide_route_rule_set="${2:-0}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    jq --argjson hide_rule_set "$hide_route_rule_set" '
        def ordered_top_level($keys):
            . as $src
            | (reduce $keys[] as $k ({};
                if ($src | has($k)) then . + {($k): $src[$k]} else . end
            ))
            + (
                $src
                | to_entries
                | map(select((.key as $k | $keys | index($k)) | not))
                | from_entries
            );
        def compact_rule_placeholders($prefix):
            if type == "array" then
                to_entries | map("__PROXY_COMPACT_RULE_" + $prefix + "_" + (.key | tostring) + "__")
            else
                .
            end;
        if type == "object" then
            ordered_top_level(["log","experimental","dns","inbounds","outbounds","route"])
        else
            .
        end
        | if ((.dns? // null) | type) == "object" and ((.dns.rules? // null) | type) == "array" then
              .dns.rules |= compact_rule_placeholders("DNS")
          else
              .
          end
        | if ((.route? // null) | type) == "object" and ((.route.rules? // null) | type) == "array" then
              .route.rules |= compact_rule_placeholders("ROUTE")
          else
              .
          end
        | if $hide_rule_set == 1
             and ((.route? // null) | type) == "object"
             and (.route | has("rule_set")) then
              .route.rule_set = ["..."]
          else
              .
          end
    ' "$conf_file"
}

render_singbox_json_with_compact_rule_lines() {
    local conf_file="${1:-}" hide_route_rule_set="${2:-0}" colorize_output="${3:-0}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local rows_data rendered_json tmp_map

    rows_data="$(singbox_compact_rule_rows "$conf_file" 2>/dev/null)" || return 1

    if [[ "$colorize_output" == "1" ]]; then
        rendered_json="$(singbox_render_json_with_rule_placeholders "$conf_file" "$hide_route_rule_set" 2>/dev/null | jq -C . 2>/dev/null)" || return 1
    else
        rendered_json="$(singbox_render_json_with_rule_placeholders "$conf_file" "$hide_route_rule_set" 2>/dev/null | jq . 2>/dev/null)" || return 1
    fi
    [[ -n "$rendered_json" ]] || return 1

    tmp_map="$(mktemp)"
    local __rr_token __rr_json
    while IFS=$'\t' read -r __rr_token __rr_json; do
        [[ -n "$__rr_token" ]] || continue
        if [[ "$colorize_output" == "1" ]]; then
            printf '%s\t%s\n' "$__rr_token" \
                "$(printf '%s\n' "${__rr_json:-null}" | jq -C -c . 2>/dev/null || printf '%s' "${__rr_json:-null}")"
        else
            printf '%s\t%s\n' "$__rr_token" "${__rr_json:-null}"
        fi
    done <<< "$rows_data" >"$tmp_map"

    awk -v map_file="$tmp_map" '
        BEGIN {
            while ((getline line < map_file) > 0) {
                tab = index(line, "\t")
                if (tab == 0) {
                    continue
                }
                token = substr(line, 1, tab - 1)
                json = substr(line, tab + 1)
                compact[token] = json
            }
            close(map_file)
        }
        {
            clean = $0
            gsub(/\033\[[0-9;]*m/, "", clean)
            if (clean ~ /^[[:space:]]*"__PROXY_COMPACT_RULE_(DNS|ROUTE)_[0-9]+__",?$/) {
                token = clean
                sub(/^[[:space:]]*"/, "", token)
                comma = ""
                if (token ~ /",$/) {
                    comma = ","
                }
                sub(/",?$/, "", token)
                indent_len = match(clean, /[^[:space:]]/)
                if (indent_len > 1) {
                    indent = substr(clean, 1, indent_len - 1)
                } else {
                    indent = ""
                }
                if (token in compact) {
                    printf "%s%s%s\n", indent, compact[token], comma
                    next
                }
            }
            print
        }
    ' <<< "$rendered_json"

    rm -f "$tmp_map"
}
