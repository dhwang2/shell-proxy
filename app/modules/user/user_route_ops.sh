# User route compilation and active-member mutation operations for shell-proxy management.

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

USER_MEMBERSHIP_OPS_FILE="${USER_MEMBERSHIP_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_membership_ops.sh}"
if [[ -f "$USER_MEMBERSHIP_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_MEMBERSHIP_OPS_FILE"
fi

USER_TEMPLATE_OPS_FILE="${USER_TEMPLATE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_template_ops.sh}"
if [[ -f "$USER_TEMPLATE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_TEMPLATE_OPS_FILE"
fi

proxy_ensure_assoc_array \
    ROUTING_TEMPLATE_COMPILED_RULES_CACHE \
    ROUTING_TEMPLATE_COMPILED_FP_CACHE \
    ROUTING_USER_TEMPLATE_ROUTE_SYNC_INPUT_FP_CACHE \
    ROUTING_USER_TEMPLATE_ROUTE_CONF_MANAGED_FP_CACHE \
    ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE \
    ROUTING_USER_TEMPLATE_ROUTE_DB_JSON_CACHE

ROUTING_USER_TEMPLATE_ROUTE_CACHE_DIR="${CACHE_DIR}/routing/user-route-sync"
ROUTING_USER_TEMPLATE_ROUTE_META_SEP=$'\x1f'

proxy_user_remove_active_member_from_conf() {
    local conf_file="${1:-}" proto="${2:-}" in_tag="${3:-}" user_id="${4:-}"
    [[ -n "$conf_file" && -f "$conf_file" && -n "$proto" && -n "$in_tag" && -n "$user_id" ]] || return 1

    local idx port tmp_json
    idx="$(proxy_user_find_inbound_index_by_tag "$conf_file" "$proto" "$in_tag")"
    [[ "$idx" =~ ^[0-9]+$ ]] || return 2
    port="$(jq -r --argjson i "$idx" '.inbounds[$i].listen_port // ""' "$conf_file" 2>/dev/null || true)"
    tmp_json="$(mktemp)"

    case "$proto" in
        vless|tuic)
            jq --arg p "$proto" --arg t "$in_tag" --arg u "$user_id" '
                def matches:
                    (((.type // "") | ascii_downcase) == ($p | ascii_downcase)) and ((.tag // "") == $t);
                .inbounds = (
                    (.inbounds // [])
                    | map(
                        if matches then
                            .users = (
                                if (.users | type) == "array" then
                                    (.users | map(select((.uuid // .id // "") != $u)))
                                elif (.users | type) == "object" then
                                    (if ((.users.uuid // .users.id // "") == $u) then [] else [.users] end)
                                else
                                    []
                                end
                            )
                        else
                            .
                        end
                    )
                    | map(select(if matches then ((.users | type) == "array" and (.users | length) == 0) | not else true end))
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        trojan|anytls)
            jq --arg p "$proto" --arg t "$in_tag" --arg u "$user_id" '
                def matches:
                    (((.type // "") | ascii_downcase) == ($p | ascii_downcase)) and ((.tag // "") == $t);
                .inbounds = (
                    (.inbounds // [])
                    | map(
                        if matches then
                            .users = (
                                if (.users | type) == "array" then
                                    (.users | map(select((.password // "") != $u)))
                                elif (.users | type) == "object" then
                                    (if ((.users.password // "") == $u) then [] else [.users] end)
                                elif (.password? != null) then
                                    (if ((.password // "") == $u) then [] else [{name:(.name // ""), password:(.password // "")}] end)
                                else
                                    []
                                end
                            )
                        else
                            .
                        end
                    )
                    | map(select(if matches then ((.users | type) == "array" and (.users | length) == 0) | not else true end))
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        ss)
            jq --arg t "$in_tag" --arg u "$user_id" '
                def matches:
                    ((((.type // "") | ascii_downcase) as $tp | ($tp == "shadowsocks" or $tp == "ss"))) and ((.tag // "") == $t);
                .inbounds = (
                    (.inbounds // [])
                    | map(
                        if matches then
                            if (.users | type) == "array" then
                                .users = (.users | map(select((.password // "") != $u)))
                            elif (.users | type) == "object" then
                                .users = (if ((.users.password // "") == $u) then [] else [.users] end)
                            elif (.password? != null) then
                                if ((.password // "") == $u) then
                                    (. + {users: []} | del(.password))
                                else
                                    .
                                end
                            else
                                .
                            end
                        else
                            .
                        end
                    )
                    | map(select(
                        if matches then
                            if (.users | type) == "array" then
                                (.users | length) > 0
                            elif (.users | type) == "object" then
                                true
                            elif (.password? != null) then
                                true
                            else
                                false
                            end
                        else
                            true
                        end
                    ))
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        *)
            rm -f "$tmp_json"
            return 1
            ;;
    esac

    if [[ ! -s "$tmp_json" ]]; then
        rm -f "$tmp_json"
        return 1
    fi

    backup_conf_file "$conf_file"
    mv "$tmp_json" "$conf_file"

    local still_exists=0
    if [[ -n "$(proxy_user_find_inbound_index_by_tag "$conf_file" "$proto" "$in_tag")" ]]; then
        still_exists=1
    fi
    printf '%s|%s\n' "$port" "$still_exists"
}

proxy_user_route_auth_user_rows() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    local line auth_user proto in_tag id_b64 user_id
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r _state auth_user proto in_tag id_b64 _key_b64 _user_b64 <<<"$line"
        [[ -n "$auth_user" && -n "$proto" && -n "$in_tag" && -n "$id_b64" ]] || continue
        user_id="$(proxy_user_decode_b64 "$id_b64")"
        [[ -n "$user_id" ]] || continue
        printf '%s\t%s\t%s\t%s\n' "$proto" "$in_tag" "$user_id" "$auth_user"
    done < <(proxy_user_collect_membership_lines "active" "$conf_file")
}

proxy_user_route_unique_auth_users() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    proxy_user_route_auth_user_rows "$conf_file" \
        | awk -F'\t' 'NF >= 4 && $4 != "" { print $4 }' \
        | proxy_unique_lines
}

proxy_user_route_active_auth_users_json() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || { printf '%s\n' '[]'; return 0; }
    if ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' '[]'
        return 0
    fi
    proxy_user_route_unique_auth_users "$conf_file" \
        | jq -R . 2>/dev/null \
        | jq -sc '.' 2>/dev/null \
        || printf '%s\n' '[]'
}

proxy_user_route_conf_has_orphan_auth_user_rules() {
    local conf_file="${1:-}" active_users_json="${2:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1
    [[ -n "$active_users_json" ]] || active_users_json="$(proxy_user_route_active_auth_users_json "$conf_file" 2>/dev/null || printf '%s\n' '[]')"

    jq -e --argjson active "$active_users_json" '
        def has_orphan_auth_user:
            ((.auth_user? // null) | type) == "array"
            and (
                ((.auth_user // []) | length)
                != (((.auth_user // []) | map(select($active | index(.) != null))) | length)
            );
        any(
            ((.route.rules // []) + (.dns.rules // []))[]?;
            has_orphan_auth_user
        )
    ' "$conf_file" >/dev/null 2>&1
}

proxy_user_route_purge_deleted_name_state() {
    local target_name="${1:-}" conf_file="${2:-}"
    local route_db_changed=0 conf_changed=0
    local tmp_json=""
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || return 1

    if [[ -f "$USER_ROUTE_RULES_DB_FILE" ]]; then
        tmp_json="$(mktemp)"
        if jq --arg user "$target_name" '
            def prune_target_user:
                if ((.auth_user? // null) | type) == "array" then
                    .auth_user = ((.auth_user // []) | map(select(. != $user)))
                else
                    .
                end;
            def keep_rule:
                if ((.auth_user? // null) | type) == "array" then
                    ((.auth_user // []) | length) > 0
                else
                    true
                end;
            (if type == "array" then . else [] end)
            | map(prune_target_user)
            | map(select(keep_rule))
        ' "$USER_ROUTE_RULES_DB_FILE" >"$tmp_json" 2>/dev/null \
            && [[ -s "$tmp_json" ]]; then
            if ! cmp -s "$tmp_json" "$USER_ROUTE_RULES_DB_FILE"; then
                mv "$tmp_json" "$USER_ROUTE_RULES_DB_FILE"
                route_db_changed=1
            else
                rm -f "$tmp_json"
            fi
        else
            rm -f "$tmp_json"
        fi
    fi

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        tmp_json="$(mktemp)"
        if jq --arg user "$target_name" '
            def prune_target_user:
                if ((.auth_user? // null) | type) == "array" then
                    .auth_user = ((.auth_user // []) | map(select(. != $user)))
                else
                    .
                end;
            def keep_rule:
                if ((.auth_user? // null) | type) == "array" then
                    ((.auth_user // []) | length) > 0
                else
                    true
                end;
            .route = (.route // {})
            | .dns = (.dns // {})
            | .route.rules = (
                (.route.rules // [])
                | map(prune_target_user)
                | map(select(keep_rule))
            )
            | .dns.rules = (
                (.dns.rules // [])
                | map(prune_target_user)
                | map(select(keep_rule))
            )
        ' "$conf_file" >"$tmp_json" 2>/dev/null \
            && [[ -s "$tmp_json" ]]; then
            if ! cmp -s "$tmp_json" "$conf_file"; then
                backup_conf_file "$conf_file"
                mv "$tmp_json" "$conf_file"
                conf_changed=1
            else
                rm -f "$tmp_json"
            fi
        else
            rm -f "$tmp_json"
        fi
    fi

    if (( route_db_changed == 1 )); then
        rm -rf "$ROUTING_USER_TEMPLATE_ROUTE_CACHE_DIR" >/dev/null 2>&1 || true
    fi
    if (( route_db_changed == 1 || conf_changed == 1 )); then
        if declare -F proxy_invalidate_after_mutation >/dev/null 2>&1; then
            proxy_invalidate_after_mutation "config"
        fi
        if [[ -n "$conf_file" && -f "$conf_file" ]] \
            && declare -F routing_menu_view_cache_invalidate >/dev/null 2>&1; then
            routing_menu_view_cache_invalidate "$conf_file" >/dev/null 2>&1 || true
        fi
        if declare -F proxy_main_menu_view_cache_invalidate >/dev/null 2>&1; then
            proxy_main_menu_view_cache_invalidate >/dev/null 2>&1 || true
        fi
    fi
    if (( conf_changed == 1 )); then
        restart_singbox_if_present
    fi
    if [[ -n "$conf_file" && -f "$conf_file" ]] \
        && declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
        routing_status_schedule_refresh_all_contexts "$conf_file" >/dev/null 2>&1 || true
    fi
    return 0
}

proxy_user_route_template_rows() {
    local key
    proxy_user_meta_value_cache_refresh
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        printf '%s\t%s\n' "$key" "${PROXY_USER_META_TEMPLATE_CACHE["$key"]:-}"
    done < <(printf '%s\n' "${!PROXY_USER_META_TEMPLATE_CACHE[@]}" | sort)
}

proxy_user_route_template_rules_rows() {
    local template_id
    proxy_user_template_value_cache_refresh
    while IFS= read -r template_id; do
        [[ -n "$template_id" ]] || continue
        printf '%s\t%s\n' "$template_id" "${PROXY_USER_TEMPLATE_RULES_CACHE["$template_id"]:-[]}"
    done < <(printf '%s\n' "${!PROXY_USER_TEMPLATE_RULES_CACHE[@]}" | sort)
}

merge_user_template_compiled_rules() {
    local rules_json="${1:-[]}"
    jq -c '
        def canonical:
            if type == "object" then
                to_entries
                | sort_by(.key)
                | map(.value |= canonical)
                | from_entries
            elif type == "array" then
                map(canonical)
            else
                .
            end;
        def sort_unique_array($value):
            ($value // [])
            | if type == "array" then map(tostring) | unique | sort else [] end;
        def expand_rule_sets($rule):
            if ((($rule.rule_set? // null) | type) == "array") and (($rule.rule_set | length) > 1) then
                [ (($rule.rule_set | map(tostring) | unique | sort)[]) as $tag | ($rule + {rule_set: [$tag]}) ]
            else
                [ $rule ]
            end;
        def normalized_rule($rule):
            ($rule | canonical)
            | .rule_set = (
                if ((.rule_set? // null) | type) == "array" then sort_unique_array(.rule_set) else .rule_set end
              )
            | .auth_user = sort_unique_array(.auth_user);
        def rule_set_family($rule):
            if ((($rule.rule_set? // null) | type) == "array") and (($rule.rule_set | length) > 0) then
                if all($rule.rule_set[]; startswith("geosite-")) then "geosite"
                elif all($rule.rule_set[]; startswith("geoip-")) then "geoip"
                else "rule_set"
                end
            else
                ""
            end;
        def merge_by_rule($items):
            reduce $items[] as $raw (
                {order: [], seen: {}, by_key: {}};
                (normalized_rule($raw)) as $rule
                | (($rule | del(.auth_user, ._merge_key) | tostring)) as $merge_key
                | .by_key[$merge_key] = (
                    if (.by_key[$merge_key] // null) == null then
                        ($rule + {_merge_key:$merge_key})
                    else
                        (.by_key[$merge_key]
                         | .auth_user = (((.auth_user // []) + ($rule.auth_user // [])) | unique | sort))
                    end
                )
                | if (.seen[$merge_key] // 0) == 0 then
                    .seen[$merge_key] = 1
                    | .order += [$merge_key]
                  else
                    .
                  end
            )
            | [.order[] as $k | .by_key[$k]];
        def merge_rule_sets_back($items):
            reduce $items[] as $raw (
                {order: [], seen: {}, by_key: {}};
                (normalized_rule($raw)) as $rule
                | (((($rule.rule_set? // null) | type) == "array") and (($rule.rule_set | length) > 0)) as $has_rule_set
                | (
                    if $has_rule_set then
                        (rule_set_family($rule)) as $family
                        | (($rule | del(.rule_set, ._merge_key) + {_rule_set_family: $family} | tostring))
                    else
                        ($rule | tostring)
                    end
                  ) as $merge_key
                | .by_key[$merge_key] = (
                    if (.by_key[$merge_key] // null) == null then
                        ($rule + {_merge_key:$merge_key})
                    elif $has_rule_set then
                        (.by_key[$merge_key]
                         | .rule_set = (((.rule_set // []) + ($rule.rule_set // [])) | unique | sort))
                    else
                        .by_key[$merge_key]
                    end
                )
                | if (.seen[$merge_key] // 0) == 0 then
                    .seen[$merge_key] = 1
                    | .order += [$merge_key]
                  else
                    .
                  end
            )
            | [.order[] as $k | .by_key[$k]];
        def family_rank($rule):
            (rule_set_family($rule)) as $family
            | if $family == "geosite" then 0
              elif $family == "geoip" then 1
              else 2
              end;
        (if type == "array" then . else [] end)
        | (map(expand_rule_sets(.)) | add // [])
        | merge_by_rule(.)
        | merge_rule_sets_back(.)
        | map(del(._merge_key))
        | sort_by(family_rank(.), (.outbound // ""), ((.auth_user // []) | join(",")), ((.rule_set // []) | join(",")))
    ' <<<"${rules_json:-[]}" 2>/dev/null || echo "${rules_json:-[]}"
}

routing_managed_rules_dns_shape_fingerprint() {
    local rules_json="${1:-[]}" normalized
    normalized="$(jq -c '
        (if type == "array" then . else [] end)
        | map(
            {
                action: (.action // ""),
                outbound: (.outbound // ""),
                auth_user: (.auth_user // null),
                rule_set: (.rule_set // null),
                domain: (.domain // null),
                domain_suffix: (.domain_suffix // null),
                domain_keyword: (.domain_keyword // null),
                domain_regex: (.domain_regex // null)
            }
        )
        | sort_by(
            (.action // ""),
            (.outbound // ""),
            ((.auth_user // []) | if type == "array" then join(",") else "" end),
            ((.rule_set // []) | if type == "array" then join(",") else "" end),
            ((.domain // []) | if type == "array" then join(",") else "" end),
            ((.domain_suffix // []) | if type == "array" then join(",") else "" end),
            ((.domain_keyword // []) | if type == "array" then join(",") else "" end),
            ((.domain_regex // []) | if type == "array" then join(",") else "" end)
        )
    ' <<<"${rules_json:-[]}" 2>/dev/null || echo "[]")"
    printf '%s' "$normalized" | proxy_cksum_signature
}

routing_user_template_route_cache_dir() {
    echo "$ROUTING_USER_TEMPLATE_ROUTE_CACHE_DIR"
}

routing_user_template_route_compiled_cache_key() {
    local target_name="${1:-}"
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" ]] || target_name="_"
    if declare -F routing_runtime_cache_key >/dev/null 2>&1; then
        routing_runtime_cache_key "compiled-user|${target_name}"
        return 0
    fi
    printf '%s' "compiled-user|${target_name}" | proxy_cksum_cache_key
}

routing_user_template_route_compiled_input_fp_file() {
    local target_name="${1:-}" cache_key
    cache_key="$(routing_user_template_route_compiled_cache_key "$target_name")"
    echo "$(routing_user_template_route_cache_dir)/compiled-input-${cache_key}.fp"
}

routing_user_template_route_compiled_rules_file() {
    local target_name="${1:-}" cache_key
    cache_key="$(routing_user_template_route_compiled_cache_key "$target_name")"
    echo "$(routing_user_template_route_cache_dir)/compiled-rules-${cache_key}.json"
}

routing_user_template_route_compiled_rules_meta_file() {
    local target_name="${1:-}" cache_key
    cache_key="$(routing_user_template_route_compiled_cache_key "$target_name")"
    echo "$(routing_user_template_route_cache_dir)/compiled-rules-${cache_key}.meta"
}

routing_user_template_route_sync_input_meta_file() {
    echo "$(routing_user_template_route_cache_dir)/sync-input.meta"
}

routing_user_template_route_applied_state_file() {
    echo "$(routing_user_template_route_cache_dir)/applied-state.fp"
}

routing_user_template_route_fast_state_file() {
    echo "$(routing_user_template_route_cache_dir)/applied-fast.fp"
}

routing_user_template_route_template_map_state_file() {
    echo "$(routing_user_template_route_cache_dir)/template-map.fp"
}

routing_user_template_route_db_meta_file() {
    echo "$(routing_user_template_route_cache_dir)/route-db.meta"
}

routing_user_template_route_conf_managed_meta_file() {
    echo "$(routing_user_template_route_cache_dir)/conf-managed.meta"
}

routing_user_template_route_cache_write_atomic() {
    local path="${1:-}" content="${2-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

routing_user_template_route_remove_legacy_compiled_cache() {
    local cache_dir
    cache_dir="$(routing_user_template_route_cache_dir)"
    rm -f \
        "${cache_dir}/compiled-input.fp" \
        "${cache_dir}/compiled-rules.json" \
        "${cache_dir}/compiled-rules.meta" \
        2>/dev/null || true
}

routing_user_template_route_template_map_input_fingerprint() {
    local meta_fp template_fp
    meta_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    template_fp="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    printf '%s|%s\n' "$meta_fp" "$template_fp"
}

routing_user_template_route_template_map_is_fresh() {
    local expected_fp="${1:-}" state_file cached_fp
    [[ -n "$expected_fp" ]] || return 1
    state_file="$(routing_user_template_route_template_map_state_file)"
    [[ -f "$state_file" ]] || return 1
    cached_fp="$(tr -d '[:space:]' <"$state_file" 2>/dev/null || true)"
    [[ -n "$cached_fp" && "$cached_fp" == "$expected_fp" ]]
}

routing_user_template_route_template_map_mark_fresh() {
    local current_fp="${1:-}"
    [[ -n "$current_fp" ]] || return 1
    routing_user_template_route_cache_write_atomic "$(routing_user_template_route_template_map_state_file)" "$current_fp"
}

_routing_user_template_route_code_modules() {
    cat <<'EOF'
user/user_route_ops.sh
routing/routing_preset_ops.sh
routing/routing_core_ops.sh
user/user_meta_ops.sh
user/user_template_ops.sh
EOF
}

_routing_user_template_route_code_signature() {
    local calc_fn="${1:-calc_file_fingerprint}"
    local module_rel module_path sig rows=""
    while IFS= read -r module_rel; do
        [[ -n "$module_rel" ]] || continue
        module_path="${MODULE_DIR}/${module_rel}"
        sig="$("$calc_fn" "$module_path" 2>/dev/null || "$calc_fn" "${WORK_DIR}/modules/${module_rel}" 2>/dev/null || echo "-")"
        rows+="${module_rel}=${sig}"$'\n'
    done < <(_routing_user_template_route_code_modules)
    printf '%s' "$rows" | proxy_cksum_signature
}

routing_user_template_route_code_fingerprint() {
    _routing_user_template_route_code_signature calc_file_fingerprint
}

routing_user_template_route_code_meta_signature() {
    _routing_user_template_route_code_signature calc_file_meta_signature
}

routing_user_template_route_fast_state_key() {
    local conf_file="${1:-}" conf_meta user_meta_meta user_template_meta route_db_meta code_meta
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    conf_meta="$(calc_file_meta_signature "$conf_file" 2>/dev/null || echo "missing")"
    user_meta_meta="$(calc_file_meta_signature "$USER_META_DB_FILE" 2>/dev/null || echo "missing")"
    user_template_meta="$(calc_file_meta_signature "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "missing")"
    route_db_meta="$(calc_file_meta_signature "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || echo "missing")"
    code_meta="$(routing_user_template_route_code_meta_signature 2>/dev/null || echo "0:0")"

    printf 'schema=user-route-sync-fast-v1|conf=%s|meta=%s|template=%s|route_db=%s|code=%s\n' \
        "$conf_meta" "$user_meta_meta" "$user_template_meta" "$route_db_meta" "$code_meta"
}

routing_user_template_route_fast_state_is_fresh() {
    local expected_key="${1:-}" state_file cached_key
    [[ -n "$expected_key" ]] || return 1
    state_file="$(routing_user_template_route_fast_state_file)"
    [[ -f "$state_file" ]] || return 1
    cached_key="$(cat "$state_file" 2>/dev/null || true)"
    [[ -n "$cached_key" && "$cached_key" == "$expected_key" ]]
}

routing_user_template_route_mark_fast_state() {
    local conf_file="${1:-}" state_key=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1
    state_key="$(routing_user_template_route_fast_state_key "$conf_file" 2>/dev/null || true)"
    [[ -n "$state_key" ]] || return 1
    routing_user_template_route_cache_write_atomic "$(routing_user_template_route_fast_state_file)" "$state_key"
}

routing_user_template_route_sync_input_fingerprint() {
    local conf_file="${1:-}" conf_fp inbounds_fp ruleset_fp user_meta_fp user_template_fp code_fp cache_key result_fp
    local meta_file cached_key cached_fp
    [[ -n "$conf_file" && -f "$conf_file" ]] || { echo "0:0"; return 0; }

    # Use inbounds-only fingerprint for cache key so route-only changes to
    # conf_file (route.rules/dns rewrites) do not invalidate the sync cache.
    # Route sync only depends on inbound user/protocol state, not on the
    # routing rules themselves which are rebuilt from templates.
    conf_fp="$(jq -c '.inbounds // []' "$conf_file" 2>/dev/null | proxy_cksum_signature || echo "0:0")"
    user_meta_fp="$(calc_file_fingerprint "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    user_template_fp="$(calc_file_fingerprint "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    code_fp="$(routing_user_template_route_code_fingerprint 2>/dev/null || echo "0:0")"
    cache_key="schema=user-route-sync-v5|conf=${conf_fp}|meta=${user_meta_fp}|template=${user_template_fp}|code=${code_fp}"
    if [[ -n "${ROUTING_USER_TEMPLATE_ROUTE_SYNC_INPUT_FP_CACHE[$cache_key]+x}" ]]; then
        printf '%s\n' "${ROUTING_USER_TEMPLATE_ROUTE_SYNC_INPUT_FP_CACHE[$cache_key]}"
        return 0
    fi
    meta_file="$(routing_user_template_route_sync_input_meta_file)"
    if [[ -f "$meta_file" ]]; then
        IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r cached_key cached_fp <"$meta_file"
        if [[ -n "$cached_key" && "$cached_key" == "$cache_key" && -n "$cached_fp" ]]; then
            ROUTING_USER_TEMPLATE_ROUTE_SYNC_INPUT_FP_CACHE["$cache_key"]="$cached_fp"
            printf '%s\n' "$cached_fp"
            return 0
        fi
    fi

    if declare -F calc_singbox_inbounds_fingerprint >/dev/null 2>&1; then
        inbounds_fp="$(calc_singbox_inbounds_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    else
        inbounds_fp="$(jq -c '.inbounds // []' "$conf_file" 2>/dev/null | proxy_cksum_signature)"
    fi

    if declare -F routing_conf_ruleset_fingerprint >/dev/null 2>&1; then
        ruleset_fp="$(routing_conf_ruleset_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    else
        ruleset_fp="$(jq -r '.route.rule_set[]?.tag // empty' "$conf_file" 2>/dev/null | sort | proxy_cksum_signature)"
    fi
    [[ -n "$ruleset_fp" ]] || ruleset_fp="0:0"

    result_fp="$(printf 'schema=%s\ninbounds=%s\nruleset=%s\nmeta=%s\ntemplate=%s\ncode=%s\n' \
        "user-route-sync-v5" \
        "$inbounds_fp" "$ruleset_fp" "$user_meta_fp" "$user_template_fp" "$code_fp" \
        | proxy_cksum_signature)"
    ROUTING_USER_TEMPLATE_ROUTE_SYNC_INPUT_FP_CACHE["$cache_key"]="$result_fp"
    routing_user_template_route_cache_write_atomic \
        "$meta_file" \
        "$(printf '%s%s%s\n' "$cache_key" "$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" "$result_fp")" >/dev/null 2>&1 || true
    printf '%s\n' "$result_fp"
}

routing_user_template_route_apply_state_key() {
    local input_fp="${1:-0:0}" conf_fp="${2:-0:0}" route_db_fp="${3:-0:0}"
    printf '%s|%s|%s\n' "$input_fp" "$conf_fp" "$route_db_fp"
}

routing_user_template_route_read_applied_state_key() {
    local state_file
    state_file="$(routing_user_template_route_applied_state_file)"
    [[ -f "$state_file" ]] || return 1
    tr -d '[:space:]' <"$state_file" 2>/dev/null
}

routing_user_template_route_write_applied_state_key() {
    local key="${1:-}"
    [[ -n "$key" ]] || return 1
    routing_user_template_route_cache_write_atomic "$(routing_user_template_route_applied_state_file)" "$key"
}

routing_user_template_route_rules_meta_fields() {
    local rules_json="${1:-[]}" rules_fp dns_fp
    rules_fp="$(routing_user_template_rules_fingerprint "$rules_json" 2>/dev/null || echo "0:0")"
    dns_fp="$(routing_managed_rules_dns_shape_fingerprint "$rules_json" 2>/dev/null || echo "0:0")"
    printf '%s%s%s\n' "$rules_fp" "$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" "$dns_fp"
}

routing_user_template_route_rules_meta_write() {
    local meta_file="${1:-}" source_fp="${2:-}" rules_fp="${3:-}" dns_fp="${4:-}"
    [[ -n "$meta_file" && -n "$source_fp" && -n "$rules_fp" && -n "$dns_fp" ]] || return 1
    routing_user_template_route_cache_write_atomic \
        "$meta_file" \
        "$(printf '%s%s%s%s%s\n' "$source_fp" "$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" "$rules_fp" "$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" "$dns_fp")"
}

routing_user_template_route_rules_meta_read() {
    local meta_file="${1:-}" expected_source_fp="${2:-}" source_fp="" rules_fp="" dns_fp=""
    [[ -n "$meta_file" && -n "$expected_source_fp" && -f "$meta_file" ]] || return 1
    IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r source_fp rules_fp dns_fp <"$meta_file"
    [[ -n "$source_fp" && "$source_fp" == "$expected_source_fp" && -n "$rules_fp" && -n "$dns_fp" ]] || return 1
    printf '%s%s%s\n' "$rules_fp" "$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" "$dns_fp"
}

routing_user_template_route_mark_applied_state() {
    local conf_file="${1:-}" input_fp="${2:-0:0}" conf_managed_fp="${3:-}" route_db_fp="${4:-}" state_key
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1
    [[ -n "$conf_managed_fp" ]] || conf_managed_fp="$(routing_user_template_conf_managed_rules_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    [[ -n "$route_db_fp" ]] || route_db_fp="$(calc_file_fingerprint "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || echo "0:0")"
    state_key="$(routing_user_template_route_apply_state_key "$input_fp" "$conf_managed_fp" "$route_db_fp")"
    routing_user_template_route_write_applied_state_key "$state_key"
}

routing_user_template_route_db_json_read() {
    local source_fp="${1:-}" rules_json=""
    [[ -n "$source_fp" ]] || return 1
    if [[ -n "${ROUTING_USER_TEMPLATE_ROUTE_DB_JSON_CACHE[$source_fp]+x}" ]]; then
        printf '%s\n' "${ROUTING_USER_TEMPLATE_ROUTE_DB_JSON_CACHE[$source_fp]}"
        return 0
    fi
    rules_json="$(jq -c . "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || true)"
    [[ -n "$rules_json" ]] || return 1
    ROUTING_USER_TEMPLATE_ROUTE_DB_JSON_CACHE["$source_fp"]="$rules_json"
    printf '%s\n' "$rules_json"
}

routing_user_template_route_load_compiled_rules() {
    local target_name="${1:-}" input_fp="${2:-}" compiled_state_file compiled_rules_file compiled_fp cache_key
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$input_fp" ]] || return 1
    cache_key="${target_name}|${input_fp}"
    if [[ -n "${ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE[$cache_key]+x}" ]]; then
        printf '%s\n' "${ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE[$cache_key]}"
        return 0
    fi
    compiled_state_file="$(routing_user_template_route_compiled_input_fp_file "$target_name")"
    compiled_rules_file="$(routing_user_template_route_compiled_rules_file "$target_name")"
    [[ -f "$compiled_state_file" && -f "$compiled_rules_file" ]] || return 1
    compiled_fp="$(tr -d '[:space:]' <"$compiled_state_file" 2>/dev/null || true)"
    [[ -n "$compiled_fp" && "$compiled_fp" == "$input_fp" ]] || return 1
    ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE["$cache_key"]="$(jq -c . "$compiled_rules_file" 2>/dev/null || true)"
    [[ -n "${ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE[$cache_key]}" ]] || return 1
    printf '%s\n' "${ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE[$cache_key]}"
}

routing_user_template_route_store_compiled_rules() {
    local target_name="${1:-}" input_fp="${2:-}" rules_json="${3:-[]}" compiled_state_file compiled_rules_file compiled_meta_file cache_key
    local meta_fields rules_fp dns_fp
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$input_fp" ]] || return 1
    mkdir -p "$(routing_user_template_route_cache_dir)" >/dev/null 2>&1 || true
    compiled_state_file="$(routing_user_template_route_compiled_input_fp_file "$target_name")"
    compiled_rules_file="$(routing_user_template_route_compiled_rules_file "$target_name")"
    compiled_meta_file="$(routing_user_template_route_compiled_rules_meta_file "$target_name")"
    meta_fields="$(routing_user_template_route_rules_meta_fields "$rules_json" 2>/dev/null || echo "0:0${ROUTING_USER_TEMPLATE_ROUTE_META_SEP}0:0")"
    IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r rules_fp dns_fp <<<"$meta_fields"
    routing_user_template_route_cache_write_atomic "$compiled_rules_file" "${rules_json:-[]}" || return 1
    routing_user_template_route_rules_meta_write "$compiled_meta_file" "$input_fp" "${rules_fp:-0:0}" "${dns_fp:-0:0}" || return 1
    routing_user_template_route_cache_write_atomic "$compiled_state_file" "$input_fp" || return 1
    cache_key="${target_name}|${input_fp}"
    ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE["$cache_key"]="${rules_json:-[]}"
}

routing_user_template_route_user_input_fingerprint() {
    local target_name="${1:-}" conf_file="${2:-}" state_json="${3:-[]}"
    local ruleset_fp state_fp code_fp
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$conf_file" && -f "$conf_file" ]] || { echo "0:0"; return 0; }

    if declare -F routing_conf_ruleset_fingerprint >/dev/null 2>&1; then
        ruleset_fp="$(routing_conf_ruleset_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    else
        ruleset_fp="$(jq -r '.route.rule_set[]?.tag // empty' "$conf_file" 2>/dev/null | sort | proxy_cksum_signature)"
    fi
    [[ -n "$ruleset_fp" ]] || ruleset_fp="0:0"

    if declare -F routing_state_json_fingerprint >/dev/null 2>&1; then
        state_fp="$(routing_state_json_fingerprint "$state_json" 2>/dev/null || printf '%s' "$state_json" | proxy_cksum_signature)"
    else
        state_fp="$(printf '%s' "$state_json" | proxy_cksum_signature)"
    fi
    [[ -n "$state_fp" ]] || state_fp="0:0"

    code_fp="$(routing_user_template_route_code_fingerprint 2>/dev/null || echo "0:0")"
    printf '%s|%s|%s|%s\n' "$target_name" "$ruleset_fp" "$state_fp" "$code_fp" | proxy_cksum_signature
}

routing_user_template_rules_fingerprint() {
    local rules_json="${1:-[]}" normalized
    normalized="$(jq -c '
        def canonical:
            if type == "object" then
                to_entries
                | sort_by(.key)
                | map(.value |= canonical)
                | from_entries
            elif type == "array" then
                map(canonical)
            else
                .
            end;
        def sort_unique_array($value):
            ($value // [])
            | if type == "array" then map(tostring) | unique | sort else [] end;
        (if type == "array" then . else [] end)
        | map(
            (canonical)
            | .auth_user = sort_unique_array(.auth_user)
            | .rule_set = (
                if ((.rule_set? // null) | type) == "array" then
                    sort_unique_array(.rule_set)
                else
                    .rule_set
                end
            )
        )
        | map(tostring)
        | unique
        | sort
    ' <<<"${rules_json:-[]}" 2>/dev/null || echo "[]")"
    printf '%s' "$normalized" | proxy_cksum_signature
}

routing_user_template_conf_managed_rules_fingerprint() {
    local conf_file="${1:-}" normalized conf_file_fp meta_file cached_fp rules_fp
    [[ -n "$conf_file" && -f "$conf_file" ]] || { echo "0:0"; return 0; }

    conf_file_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    if [[ -n "${ROUTING_USER_TEMPLATE_ROUTE_CONF_MANAGED_FP_CACHE[$conf_file_fp]+x}" ]]; then
        printf '%s\n' "${ROUTING_USER_TEMPLATE_ROUTE_CONF_MANAGED_FP_CACHE[$conf_file_fp]}"
        return 0
    fi

    meta_file="$(routing_user_template_route_conf_managed_meta_file)"
    if [[ -f "$meta_file" ]]; then
        IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r cached_fp rules_fp <"$meta_file"
        if [[ -n "$cached_fp" && "$cached_fp" == "$conf_file_fp" && -n "$rules_fp" ]]; then
            ROUTING_USER_TEMPLATE_ROUTE_CONF_MANAGED_FP_CACHE["$conf_file_fp"]="$rules_fp"
            printf '%s\n' "$rules_fp"
            return 0
        fi
    fi

    normalized="$(jq -c '
        def canonical:
            if type == "object" then
                to_entries
                | sort_by(.key)
                | map(.value |= canonical)
                | from_entries
            elif type == "array" then
                map(canonical)
            else
                .
            end;
        def sort_unique_array($value):
            ($value // [])
            | if type == "array" then map(tostring) | unique | sort else [] end;
        (.route.rules // [])
        | map(select(((.auth_user? // null) | type) == "array"))
        | map(
            (canonical)
            | .auth_user = sort_unique_array(.auth_user)
            | .rule_set = (
                if ((.rule_set? // null) | type) == "array" then
                    sort_unique_array(.rule_set)
                else
                    .rule_set
                end
            )
        )
        | map(tostring)
        | unique
        | sort
    ' "$conf_file" 2>/dev/null || echo "[]")"
    rules_fp="$(printf '%s' "$normalized" | proxy_cksum_signature)"
    [[ -n "$rules_fp" ]] || rules_fp="0:0"
    ROUTING_USER_TEMPLATE_ROUTE_CONF_MANAGED_FP_CACHE["$conf_file_fp"]="$rules_fp"
    routing_user_template_route_cache_write_atomic \
        "$meta_file" \
        "$(printf '%s%s%s\n' "$conf_file_fp" "$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" "$rules_fp")" >/dev/null 2>&1 || true
    printf '%s\n' "$rules_fp"
}

sync_user_template_route_rules() {
    # Fast-path cache chain — 5 successively expensive checks, each short-circuiting
    # when it can prove no config mutation is needed:
    #   L1 fast_state       : file-based marker (stat + read), cheapest
    #   L2 applied_state    : composite of sync_input_fp + conf_managed_fp + route_db_fp
    #   L3 fingerprint_triple : old/new rules_fp + dns_fp + conf_managed_fp all agree (from meta cache)
    #   L4 dns_sync_skip    : same as L3 but after JSON reload populates missing fingerprints
    #   L5 cmp_content      : byte-level diff of rebuilt config vs current file
    local conf_file="${1:-}"
    local sanitize_mode="${2:-}"
    local active_auth_users_json="[]"
    local orphan_auth_user_rules_present=0
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    routing_user_template_route_remove_legacy_compiled_cache

    active_auth_users_json="$(proxy_user_route_active_auth_users_json "$conf_file" 2>/dev/null || printf '%s\n' '[]')"
    if proxy_user_route_conf_has_orphan_auth_user_rules "$conf_file" "$active_auth_users_json"; then
        orphan_auth_user_rules_present=1
    fi

    # L1 fast_state: marker file is fresh and no orphans → nothing to do.
    local fast_state_key=""
    fast_state_key="$(routing_user_template_route_fast_state_key "$conf_file" 2>/dev/null || true)"
    if [[ -n "$fast_state_key" ]] \
        && routing_user_template_route_fast_state_is_fresh "$fast_state_key" \
        && (( orphan_auth_user_rules_present == 0 )); then
        return 0
    fi

    # Keep route.auth_user aligned with sing-box runtime user names instead of
    # using per-protocol placeholders such as ss passwords.
    if [[ "$sanitize_mode" != "skip-user-name-sanitize" ]]; then
        if declare -F sanitize_singbox_inbound_user_names_if_needed >/dev/null 2>&1; then
            sanitize_singbox_inbound_user_names_if_needed "$conf_file" >/dev/null 2>&1 || true
        else
            sanitize_singbox_inbound_user_names "$conf_file" >/dev/null 2>&1 || true
        fi
    fi
    local route_db_fp_before="0:0" route_db_meta_fields_precheck=""
    if [[ -f "$USER_ROUTE_RULES_DB_FILE" ]]; then
        route_db_fp_before="$(calc_file_fingerprint "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || echo "0:0")"
        route_db_meta_fields_precheck="$(routing_user_template_route_rules_meta_read "$(routing_user_template_route_db_meta_file)" "$route_db_fp_before" 2>/dev/null || true)"
    fi
    if [[ ! -f "$USER_ROUTE_RULES_DB_FILE" ]] \
        || { [[ -z "$route_db_meta_fields_precheck" ]] && ! [[ -s "$USER_ROUTE_RULES_DB_FILE" ]]; }; then
        printf '%s\n' '[]' > "$USER_ROUTE_RULES_DB_FILE"
        route_db_fp_before="$(calc_file_fingerprint "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || echo "0:0")"
        route_db_meta_fields_precheck="$(routing_user_template_route_rules_meta_read "$(routing_user_template_route_db_meta_file)" "$route_db_fp_before" 2>/dev/null || true)"
    fi

    local meta_template_map_fp
    meta_template_map_fp="$(routing_user_template_route_template_map_input_fingerprint 2>/dev/null || echo "0:0|0:0")"
    if ! routing_user_template_route_template_map_is_fresh "$meta_template_map_fp"; then
        local tmp_meta meta_changed=0
        tmp_meta="$(mktemp)"
        if jq --slurpfile tpl "$USER_TEMPLATE_DB_FILE" '
            .template = (
                (.template // {})
                | with_entries(
                    select(
                        (.key | test("^[^|]+\\|[^|]+\\|.+$"))
                        and (($tpl[0].templates[.value] // null) != null)
                    )
                )
            )
        ' "$USER_META_DB_FILE" > "$tmp_meta" 2>/dev/null; then
            if ! cmp -s "$tmp_meta" "$USER_META_DB_FILE"; then
                mv "$tmp_meta" "$USER_META_DB_FILE"
                meta_changed=1
            else
                rm -f "$tmp_meta"
            fi
        else
            rm -f "$tmp_meta"
        fi
        if (( meta_changed == 1 )); then
            proxy_user_meta_db_refresh_caches
            meta_template_map_fp="$(routing_user_template_route_template_map_input_fingerprint 2>/dev/null || echo "0:0|0:0")"
        fi
        routing_user_template_route_template_map_mark_fresh "$meta_template_map_fp" >/dev/null 2>&1 || true
    fi

    # L2 applied_state: composite fingerprint matches previous successful apply.
    local sync_input_fp conf_managed_fp_before expected_apply_state cached_apply_state
    sync_input_fp="$(routing_user_template_route_sync_input_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    [[ -n "$sync_input_fp" ]] || sync_input_fp="0:0"
    conf_managed_fp_before="$(routing_user_template_conf_managed_rules_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    [[ -n "$route_db_fp_before" ]] || route_db_fp_before="$(calc_file_fingerprint "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || echo "0:0")"
    expected_apply_state="$(routing_user_template_route_apply_state_key "$sync_input_fp" "$conf_managed_fp_before" "$route_db_fp_before")"
    cached_apply_state="$(routing_user_template_route_read_applied_state_key 2>/dev/null || true)"
    if [[ -n "$cached_apply_state" && "$cached_apply_state" == "$expected_apply_state" ]]; then
        routing_user_template_route_mark_fast_state "$conf_file" >/dev/null 2>&1 || true
        return 0
    fi

    local new_rules=""
    local old_rules_meta_fields compiled_rules_meta_fields
    local old_rules_fp="" old_rules_dns_fp="" new_rules_fp="" new_rules_dns_fp="" conf_managed_fp

    old_rules_meta_fields="${route_db_meta_fields_precheck:-}"
    if [[ -z "$old_rules_meta_fields" ]]; then
        old_rules_meta_fields="$(routing_user_template_route_rules_meta_read "$(routing_user_template_route_db_meta_file)" "$route_db_fp_before" 2>/dev/null || true)"
    fi
    if [[ -n "$old_rules_meta_fields" ]]; then
        IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r old_rules_fp old_rules_dns_fp <<<"$old_rules_meta_fields"
    fi

    compiled_rules_meta_fields="$(routing_user_template_route_rules_meta_read "$(routing_user_template_route_compiled_rules_meta_file "__all__")" "$sync_input_fp" 2>/dev/null || true)"
    if [[ -n "$compiled_rules_meta_fields" ]]; then
        IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r new_rules_fp new_rules_dns_fp <<<"$compiled_rules_meta_fields"
    fi

    # L3 fingerprint_triple: rules_fp + dns_fp + conf_managed_fp all agree (meta cache hit).
    conf_managed_fp="$conf_managed_fp_before"
    if [[ -n "$old_rules_fp" && -n "$old_rules_dns_fp" && -n "$new_rules_fp" && -n "$new_rules_dns_fp" ]] \
        && [[ "$old_rules_dns_fp" == "$new_rules_dns_fp" ]] \
        && [[ "$old_rules_fp" == "$new_rules_fp" ]] \
        && [[ -n "$conf_managed_fp" && "$conf_managed_fp" == "$new_rules_fp" ]]; then
        routing_user_template_route_mark_applied_state "$conf_file" "$sync_input_fp" "$conf_managed_fp" "$route_db_fp_before" >/dev/null 2>&1 || true
        routing_user_template_route_mark_fast_state "$conf_file" >/dev/null 2>&1 || true
        return 0
    fi

    if ! routing_user_template_route_load_compiled_rules "__all__" "$sync_input_fp" >/dev/null 2>&1; then
        local tmp_rules_file
        tmp_rules_file="$(mktemp)"

        local auth_user state_json user_input_fp compiled_rules
        while IFS= read -r auth_user; do
            [[ -n "$auth_user" ]] || continue
            state_json="$(routing_user_load_state_json "$auth_user" "$conf_file" 2>/dev/null || echo '[]')"
            [[ -n "$state_json" && "$state_json" != "[]" ]] || continue

            user_input_fp="$(routing_user_template_route_user_input_fingerprint "$auth_user" "$conf_file" "$state_json" 2>/dev/null || echo "0:0")"
            compiled_rules="$(routing_user_template_route_load_compiled_rules "$auth_user" "$user_input_fp" 2>/dev/null || true)"
            if [[ -z "$compiled_rules" ]]; then
                compiled_rules="$(routing_build_rules_from_state "$state_json" "$conf_file" 2>/dev/null || echo '[]')"
                routing_user_template_route_store_compiled_rules "$auth_user" "$user_input_fp" "$compiled_rules" >/dev/null 2>&1 || true
            fi
            [[ -n "$compiled_rules" && "$compiled_rules" != "[]" ]] || continue

            echo "$compiled_rules" | jq -c --arg user "$auth_user" '
                .[]?
                | . + {auth_user: [$user]}
            ' 2>/dev/null >> "$tmp_rules_file"
        done < <(proxy_user_route_unique_auth_users "$conf_file")

        if [[ -s "$tmp_rules_file" ]]; then
            new_rules="$(jq -sc '.' "$tmp_rules_file" 2>/dev/null || echo '[]')"
            new_rules="$(merge_user_template_compiled_rules "$new_rules")"
        fi
        rm -f "$tmp_rules_file"
        routing_user_template_route_store_compiled_rules "__all__" "$sync_input_fp" "$new_rules" >/dev/null 2>&1 || true
        compiled_rules_meta_fields="$(routing_user_template_route_rules_meta_read "$(routing_user_template_route_compiled_rules_meta_file "__all__")" "$sync_input_fp" 2>/dev/null || true)"
        if [[ -n "$compiled_rules_meta_fields" ]]; then
            IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r new_rules_fp new_rules_dns_fp <<<"$compiled_rules_meta_fields"
        fi
    else
        new_rules="${ROUTING_USER_TEMPLATE_ROUTE_COMPILED_RULES_JSON_CACHE["__all__|$sync_input_fp"]:-[]}"
    fi

    local tmp_conf
    tmp_conf="$(mktemp)"
    local old_rules='[]'
    local need_dns_sync=1
    if [[ -z "$new_rules_fp" || -z "$new_rules_dns_fp" ]]; then
        compiled_rules_meta_fields="$(routing_user_template_route_rules_meta_fields "$new_rules" 2>/dev/null || echo "0:0${ROUTING_USER_TEMPLATE_ROUTE_META_SEP}0:0")"
        IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r new_rules_fp new_rules_dns_fp <<<"$compiled_rules_meta_fields"
    fi

    if [[ -z "$old_rules_fp" || -z "$old_rules_dns_fp" ]]; then
        routing_user_template_route_db_json_read "$route_db_fp_before" >/dev/null 2>&1 || true
        old_rules="${ROUTING_USER_TEMPLATE_ROUTE_DB_JSON_CACHE[$route_db_fp_before]:-[]}"
        old_rules_meta_fields="$(routing_user_template_route_rules_meta_fields "$old_rules" 2>/dev/null || echo "0:0${ROUTING_USER_TEMPLATE_ROUTE_META_SEP}0:0")"
        IFS="$ROUTING_USER_TEMPLATE_ROUTE_META_SEP" read -r old_rules_fp old_rules_dns_fp <<<"$old_rules_meta_fields"
    fi

    if [[ -n "$old_rules_dns_fp" && "$old_rules_dns_fp" == "$new_rules_dns_fp" ]]; then
        need_dns_sync=0
    fi
    if (( orphan_auth_user_rules_present == 1 )); then
        need_dns_sync=1
    fi

    # L4 dns_sync_skip: after JSON reload populates missing fingerprints, same triple holds.
    if (( need_dns_sync == 0 )) \
        && [[ -n "$old_rules_fp" && -n "$new_rules_fp" && "$old_rules_fp" == "$new_rules_fp" ]] \
        && [[ -n "$conf_managed_fp" && "$conf_managed_fp" == "$new_rules_fp" ]]; then
        rm -f "$tmp_conf"
        routing_user_template_route_rules_meta_write "$(routing_user_template_route_db_meta_file)" "$route_db_fp_before" "$old_rules_fp" "$old_rules_dns_fp" >/dev/null 2>&1 || true
        routing_user_template_route_mark_applied_state "$conf_file" "$sync_input_fp" "$conf_managed_fp" "$route_db_fp_before" >/dev/null 2>&1 || true
        if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
            routing_status_schedule_refresh_all_contexts "$conf_file" >/dev/null 2>&1 || true
        fi
        return 0
    fi

    routing_user_template_route_db_json_read "$route_db_fp_before" >/dev/null 2>&1 || true
    old_rules="${ROUTING_USER_TEMPLATE_ROUTE_DB_JSON_CACHE[$route_db_fp_before]:-[]}"

    jq --argjson old "$old_rules" --argjson new "$new_rules" --argjson active "$active_auth_users_json" '
        def prune_auth_user_rule:
            if ((.auth_user? // null) | type) == "array" then
                .auth_user = ((.auth_user // []) | map(select($active | index(.) != null)))
            else
                .
            end;
        def keep_pruned_rule:
            if ((.auth_user? // null) | type) == "array" then
                ((.auth_user // []) | length) > 0
            else
                true
            end;
        .route = (.route // {})
        | .route.rules = (
            (
                (($old + $new) | map(tostring) | reduce .[] as $key ({}; .[$key] = 1)) as $managed
                | (.route.rules // [])
                | map(
                    (tostring) as $rule_key
                    | select(($managed[$rule_key] // 0) == 0)
                    | prune_auth_user_rule
                  )
                | map(select(keep_pruned_rule))
            )
            + $new
          )
    ' "$conf_file" > "$tmp_conf" 2>/dev/null || { rm -f "$tmp_conf"; return 1; }

    if [[ ! -s "$tmp_conf" ]]; then
        rm -f "$tmp_conf"
        return 1
    fi

    if (( need_dns_sync == 1 )); then
        if ! sync_dns_with_route "$tmp_conf"; then
            rm -f "$tmp_conf"
            return 1
        fi
    fi

    if [[ ! -s "$tmp_conf" ]]; then
        rm -f "$tmp_conf"
        return 1
    fi

    # L5 cmp_content: byte-level diff of rebuilt config vs current file.
    if ! cmp -s "$tmp_conf" "$conf_file"; then
        backup_conf_file "$conf_file"
        mv "$tmp_conf" "$conf_file"
        restart_singbox_if_present
    else
        rm -f "$tmp_conf"
    fi

    local tmp_rules_db current_route_db_fp
    tmp_rules_db="$(mktemp)"
    printf '%s\n' "$new_rules" > "$tmp_rules_db"
    if [[ ! -f "$USER_ROUTE_RULES_DB_FILE" ]] || ! cmp -s "$tmp_rules_db" "$USER_ROUTE_RULES_DB_FILE"; then
        mv "$tmp_rules_db" "$USER_ROUTE_RULES_DB_FILE"
    else
        rm -f "$tmp_rules_db"
    fi
    current_route_db_fp="$(calc_file_fingerprint "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || echo "0:0")"
    ROUTING_USER_TEMPLATE_ROUTE_DB_JSON_CACHE["$current_route_db_fp"]="$new_rules"
    routing_user_template_route_rules_meta_write "$(routing_user_template_route_db_meta_file)" "$current_route_db_fp" "${new_rules_fp:-0:0}" "${new_rules_dns_fp:-0:0}" >/dev/null 2>&1 || true

    routing_user_template_route_mark_applied_state "$conf_file" "$sync_input_fp" "${new_rules_fp:-0:0}" "$current_route_db_fp" >/dev/null 2>&1 || true
    routing_user_template_route_mark_fast_state "$conf_file" >/dev/null 2>&1 || true
    if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
        routing_status_schedule_refresh_all_contexts "$conf_file" >/dev/null 2>&1 || true
    fi
    return 0
}
