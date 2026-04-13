# User metadata writeback and batch update helpers for user menus.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

PROTOCOL_RUNTIME_OPS_FILE="${PROTOCOL_RUNTIME_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../protocol/protocol_runtime_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_OPS_FILE"
fi

USER_TEMPLATE_OPS_FILE="${USER_TEMPLATE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_template_ops.sh}"
if [[ -f "$USER_TEMPLATE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_TEMPLATE_OPS_FILE"
fi

USER_OPS_FILE="${USER_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/user_ops.sh}"
if [[ -f "$USER_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_OPS_FILE"
fi

ensure_user_meta_db() {
    proxy_user_meta_db_ensure
    proxy_user_template_db_ensure
    if [[ ! -f "$USER_ROUTE_RULES_DB" ]] || ! [[ -s "$USER_ROUTE_RULES_DB" ]]; then
        printf '%s\n' '[]' > "$USER_ROUTE_RULES_DB"
    fi
}

user_meta_clear_key() {
    local key="$1"
    ensure_user_meta_db
    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg k "$key" 'del(.disabled[$k]) | del(.expiry[$k]) | del(.route[$k]) | del(.template[$k]) | del(.name[$k])' "$USER_META_DB" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]]; then
        mv "$tmp_json" "$USER_META_DB"
    else
        rm -f "$tmp_json"
        return 1
    fi
}

sync_user_route_rules() {
    ensure_user_meta_db
    sync_user_template_route_rules "$conf_file"
}

clear_snell_psk() {
    [[ -f "$SNELL_CONF" ]] || return 1
    sed -i '/^[[:space:]]*psk[[:space:]]*=/d' "$SNELL_CONF"
}

begin_user_group_batch() {
    BATCH_CONF_CHANGED=0
    BATCH_CONF_BACKUP_DONE=0
    BATCH_SNELL_ACTION=""
}

commit_user_group_conf() {
    local tmp_json="$1"
    if [[ ! -s "$tmp_json" ]]; then
        rm -f "$tmp_json"
        return 1
    fi
    if (( BATCH_CONF_BACKUP_DONE == 0 )); then
        backup_conf_file "$conf_file"
        BATCH_CONF_BACKUP_DONE=1
    fi
    mv "$tmp_json" "$conf_file"
    BATCH_CONF_CHANGED=1
    return 0
}

record_user_group_snell_action() {
    local action="$1"
    case "$action" in
        restart) BATCH_SNELL_ACTION="restart" ;;
        stop)
            if [[ "$BATCH_SNELL_ACTION" != "restart" ]]; then
                BATCH_SNELL_ACTION="stop"
            fi
            ;;
    esac
}

finalize_user_group_batch() {
    local sync_routes="${1:-0}"
    local already_restarted=0
    if (( sync_routes == 1 && BATCH_CONF_CHANGED == 1 )); then
        local conf_fp_before=""
        conf_fp_before="$(calc_file_meta_signature "$conf_file" 2>/dev/null || true)"
        sync_user_route_rules >/dev/null 2>&1 || true
        local conf_fp_after=""
        conf_fp_after="$(calc_file_meta_signature "$conf_file" 2>/dev/null || true)"
        if [[ "$conf_fp_before" != "$conf_fp_after" ]]; then
            already_restarted=1
        fi
    elif (( sync_routes == 1 )); then
        sync_user_route_rules >/dev/null 2>&1 || true
    fi
    if (( BATCH_CONF_CHANGED == 1 && already_restarted == 0 )); then
        restart_singbox_if_present
    fi
    case "$BATCH_SNELL_ACTION" in
        restart)
            systemctl restart snell-v5 2>/dev/null || systemctl start snell-v5 2>/dev/null || true
            check_service_result "snell-v5" "重启"
            ;;
        stop)
            systemctl stop snell-v5 2>/dev/null || true
            ;;
    esac
}

user_meta_update_disabled_name() {
    local key="$1" new_name="$2"
    [[ -n "$key" && -n "$new_name" ]] || return 1
    ensure_user_meta_db
    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg k "$key" --arg n "$new_name" '
        if .disabled[$k] != null then
            .disabled[$k].user = ((.disabled[$k].user // {}) + {name:$n})
        else
            .
        end
        | .name[$k] = $n
    ' "$USER_META_DB" > "$tmp_json" 2>/dev/null || true
    if [[ -s "$tmp_json" ]]; then
        mv "$tmp_json" "$USER_META_DB"
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

remove_active_user_from_conf() {
    local proto="$1" in_tag="$2" user_id="$3"
    local remove_result
    [[ -n "$proto" && -n "$in_tag" && -n "$user_id" ]] || return 1
    remove_result="$(proxy_user_remove_active_member_from_conf "$conf_file" "$proto" "$in_tag" "$user_id" 2>/dev/null || true)"
    [[ -n "$remove_result" ]] || return 1
    BATCH_CONF_CHANGED=1
    BATCH_CONF_BACKUP_DONE=1
    return 0
}

rename_active_user_entry() {
    local proto="$1" idx="$2" user_id="$3" new_name="$4"
    local tmp_json
    [[ -n "$proto" && -n "$idx" && -n "$user_id" && -n "$new_name" ]] || return 1
    tmp_json="$(mktemp)"
    case "$proto" in
        vless|tuic)
            jq --argjson i "$idx" --arg u "$user_id" --arg n "$new_name" '
                .inbounds[$i].users = (
                    if (.inbounds[$i].users | type) == "array" then
                        (.inbounds[$i].users | map(if (.uuid // "") == $u then . + {name:$n} else . end))
                    elif (.inbounds[$i].users | type) == "object" then
                        [(.inbounds[$i].users | if (.uuid // "") == $u then . + {name:$n} else . end)]
                    else
                        []
                    end
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        trojan|anytls)
            jq --argjson i "$idx" --arg u "$user_id" --arg n "$new_name" '
                .inbounds[$i].users = (
                    if (.inbounds[$i].users | type) == "array" then
                        (.inbounds[$i].users | map(if (.password // "") == $u then . + {name:$n} else . end))
                    elif (.inbounds[$i].users | type) == "object" then
                        [(.inbounds[$i].users | if (.password // "") == $u then . + {name:$n} else . end)]
                    else
                        []
                    end
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        ss)
            if [[ "$(jq -r --argjson i "$idx" '((.inbounds[$i].users | type) == "array" or (.inbounds[$i].users | type) == "object")' "$conf_file" 2>/dev/null || echo "false")" != "true" ]]; then
                rm -f "$tmp_json"
                return 2
            fi
            jq --argjson i "$idx" --arg u "$user_id" --arg n "$new_name" '
                .inbounds[$i] |= (
                    .users = (
                        if (.users | type) == "array" then
                            (.users | map(if (.password // "") == $u then . + {name:$n} else . end))
                        elif (.users | type) == "object" then
                            [(.users | if (.password // "") == $u then . + {name:$n} else . end)]
                        else
                            []
                        end
                    )
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        *)
            rm -f "$tmp_json"
            return 1
            ;;
    esac
    commit_user_group_conf "$tmp_json"
}
