# Routing auto-config and ruleset catalog operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

CONFIG_OPS_FILE="${CONFIG_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/config_ops.sh}"
if [[ -f "$CONFIG_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_OPS_FILE"
fi

SINGBOX_AUTOCONFIG_CACHE_DIR="${CACHE_DIR}/view/autoconfig"
SINGBOX_AUTOCONFIG_STATE_FILE="${SINGBOX_AUTOCONFIG_CACHE_DIR}/startup.fp"
SINGBOX_AUTOCONFIG_LOCK_FILE="${SINGBOX_AUTOCONFIG_CACHE_DIR}/startup.lock"
ROUTING_RULES_DB="${ROUTING_RULES_DB:-${WORK_DIR}/routing_rules.json}"
DIRECT_IP_VERSION_FILE="${DIRECT_IP_VERSION_FILE:-${WORK_DIR}/direct_ip_version}"
RES_SOCKS_SECRET_DIR="${RES_SOCKS_SECRET_DIR:-${WORK_DIR}/secrets}"
RES_SOCKS_NODES_FILE="${RES_SOCKS_NODES_FILE:-${RES_SOCKS_SECRET_DIR}/res_socks_nodes.json}"

singbox_autoconfig_write_atomic() {
    local path="${1:-}" content="${2:-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

singbox_autoconfig_read_state_fingerprint() {
    [[ -f "$SINGBOX_AUTOCONFIG_STATE_FILE" ]] || return 1
    tr -d '[:space:]' <"$SINGBOX_AUTOCONFIG_STATE_FILE" 2>/dev/null
}

singbox_autoconfig_state_fingerprint() {
    local conf_file="${1:-}"
    local conf_fp direct_fp routing_fp user_meta_fp user_route_fp user_template_fp
    local res_nodes_fp source_ref snell_fp
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    conf_fp="$(calc_file_meta_signature "$conf_file" 2>/dev/null || echo "0:0")"
    direct_fp="$(calc_file_meta_signature "$DIRECT_IP_VERSION_FILE" 2>/dev/null || echo "0:0")"
    routing_fp="$(calc_file_meta_signature "$ROUTING_RULES_DB" 2>/dev/null || echo "0:0")"
    user_meta_fp="$(calc_file_meta_signature "$USER_META_DB_FILE" 2>/dev/null || echo "0:0")"
    user_route_fp="$(calc_file_meta_signature "$USER_ROUTE_RULES_DB_FILE" 2>/dev/null || echo "0:0")"
    user_template_fp="$(calc_file_meta_signature "$USER_TEMPLATE_DB_FILE" 2>/dev/null || echo "0:0")"
    res_nodes_fp="$(calc_file_meta_signature "$RES_SOCKS_NODES_FILE" 2>/dev/null || echo "0:0")"
    snell_fp="$(calc_file_meta_signature "$SNELL_CONF" 2>/dev/null || echo "0:0")"
    source_ref="$(read_script_source_ref 2>/dev/null || true)"
    [[ -n "$source_ref" ]] || source_ref="$(read_proxy_release_tag_cache 2>/dev/null || echo unknown)"
    [[ -n "$source_ref" ]] || source_ref="unknown"

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$conf_fp" "$direct_fp" "$routing_fp" "$user_meta_fp" "$user_route_fp" "$user_template_fp" \
        "$res_nodes_fp" "$snell_fp" "$source_ref" \
        | proxy_cksum_signature
}

singbox_autoconfig_state_is_fresh() {
    local conf_file="${1:-}" cached_fp expected_fp
    cached_fp="$(singbox_autoconfig_read_state_fingerprint 2>/dev/null || true)"
    [[ -n "$cached_fp" ]] || return 1

    expected_fp="$(singbox_autoconfig_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$expected_fp" ]] || return 1

    [[ "$cached_fp" == "$expected_fp" ]]
}

singbox_autoconfig_state_mark_fresh() {
    local conf_file="${1:-}" current_fp
    current_fp="$(singbox_autoconfig_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$current_fp" ]] || current_fp="0:0"
    singbox_autoconfig_write_atomic "$SINGBOX_AUTOCONFIG_STATE_FILE" "$current_fp"
}

routing_autoconfig_load_reconcile_modules() {
    if declare -F build_auto_singbox_base_json >/dev/null 2>&1 \
        && declare -F routing_load_state_json >/dev/null 2>&1 \
        && declare -F routing_build_rules_from_state >/dev/null 2>&1 \
        && declare -F sync_dns_with_route >/dev/null 2>&1 \
        && declare -F load_res_socks_secret >/dev/null 2>&1; then
        return 0
    fi

    local current_dir module_root
    current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for module_root in "${MODULE_DIR:-}" "${WORK_DIR}/modules" "$(cd "${current_dir}/.." && pwd)"; do
        [[ -n "$module_root" && -d "$module_root" ]] || continue

        if [[ -f "${module_root}/routing/routing_core_ops.sh" ]]; then
            # shellcheck disable=SC1090
            source "${module_root}/routing/routing_core_ops.sh"
        fi

        if declare -F build_auto_singbox_base_json >/dev/null 2>&1 \
            && declare -F routing_load_state_json >/dev/null 2>&1 \
            && declare -F routing_build_rules_from_state >/dev/null 2>&1 \
            && declare -F sync_dns_with_route >/dev/null 2>&1 \
            && declare -F load_res_socks_secret >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

singbox_autoconfig_reconcile_with_lock() {
    local rc=0
    routing_autoconfig_load_reconcile_modules || return 1
    mkdir -p "$SINGBOX_AUTOCONFIG_CACHE_DIR" >/dev/null 2>&1 || true

    if command -v flock >/dev/null 2>&1; then
        (
            flock -n 9 || exit 0
            ensure_singbox_auto_config 0 >/dev/null 2>&1
        ) 9>"$SINGBOX_AUTOCONFIG_LOCK_FILE"
        return $?
    fi

    local lock_dir="${SINGBOX_AUTOCONFIG_LOCK_FILE}.d"
    mkdir "$lock_dir" >/dev/null 2>&1 || return 0
    ensure_singbox_auto_config 0 >/dev/null 2>&1 || rc=$?
    rmdir "$lock_dir" >/dev/null 2>&1 || true
    return "$rc"
}

singbox_autoconfig_schedule_reconcile_if_stale() {
    local conf_file="${1:-}" defer_check="${2:-0}"

    if [[ "$defer_check" != "1" ]]; then
        if singbox_autoconfig_state_is_fresh "$conf_file"; then
            return 0
        fi
    fi

    (
        if [[ "$defer_check" == "1" ]]; then
            if singbox_autoconfig_state_is_fresh "$conf_file"; then
                exit 0
            fi
        fi
        singbox_autoconfig_reconcile_with_lock || true
    ) >/dev/null 2>&1 &
}

routing_autoconfig_ensure_user_route_sync_loaded() {
    if declare -F sync_user_template_route_rules >/dev/null 2>&1; then
        return 0
    fi

    local current_dir module_root
    current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for module_root in "${MODULE_DIR:-}" "${WORK_DIR}/modules" "$(cd "${current_dir}/.." && pwd)"; do
        [[ -n "$module_root" && -d "$module_root" ]] || continue

        if [[ -f "${module_root}/user/user_meta_ops.sh" ]]; then
            # shellcheck disable=SC1090
            source "${module_root}/user/user_meta_ops.sh"
        fi
        if [[ -f "${module_root}/user/user_template_ops.sh" ]]; then
            # shellcheck disable=SC1090
            source "${module_root}/user/user_template_ops.sh"
        fi
        if [[ -f "${module_root}/user/user_route_ops.sh" ]]; then
            # shellcheck disable=SC1090
            source "${module_root}/user/user_route_ops.sh"
        fi

        if declare -F sync_user_template_route_rules >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

auto_rule_set_catalog_json() {
    cat <<'CATALOG_EOF'
[{"tag":"geosite-openai","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs","download_detour":"🐸 direct"},{"tag":"geosite-anthropic","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/anthropic.srs","download_detour":"🐸 direct"},{"tag":"geosite-category-ai-!cn","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ai-!cn.srs","download_detour":"🐸 direct"},{"tag":"geosite-ai-!cn","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ai-!cn.srs","download_detour":"🐸 direct"},{"tag":"geoip-ai","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/ai.srs","download_detour":"🐸 direct"},{"tag":"geosite-google","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/google.srs","download_detour":"🐸 direct"},{"tag":"geosite-netflix","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/netflix.srs","download_detour":"🐸 direct"},{"tag":"geosite-disney","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/disney.srs","download_detour":"🐸 direct"},{"tag":"geosite-mytvsuper","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/mytvsuper.srs","download_detour":"🐸 direct"},{"tag":"geosite-youtube","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/youtube.srs","download_detour":"🐸 direct"},{"tag":"geosite-spotify","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/spotify.srs","download_detour":"🐸 direct"},{"tag":"geosite-tiktok","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/tiktok.srs","download_detour":"🐸 direct"},{"tag":"geosite-telegram","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/telegram.srs","download_detour":"🐸 direct"},{"tag":"geosite-category-ads-all","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ads-all.srs","download_detour":"🐸 direct"},{"tag":"geosite-twitter","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/twitter.srs","download_detour":"🐸 direct"},{"tag":"geosite-whatsapp","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/whatsapp.srs","download_detour":"🐸 direct"},{"tag":"geosite-facebook","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/facebook.srs","download_detour":"🐸 direct"},{"tag":"geosite-discord","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/discord.srs","download_detour":"🐸 direct"},{"tag":"geosite-instagram","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/instagram.srs","download_detour":"🐸 direct"},{"tag":"geosite-reddit","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/reddit.srs","download_detour":"🐸 direct"},{"tag":"geosite-linkedin","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/linkedin.srs","download_detour":"🐸 direct"},{"tag":"geosite-paypal","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/paypal.srs","download_detour":"🐸 direct"},{"tag":"geosite-microsoft","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/microsoft.srs","download_detour":"🐸 direct"},{"tag":"geosite-xai","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/xai.srs","download_detour":"🐸 direct"},{"tag":"geosite-meta","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/meta.srs","download_detour":"🐸 direct"},{"tag":"geosite-messenger","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/messenger.srs","download_detour":"🐸 direct"},{"tag":"geosite-github","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/github.srs","download_detour":"🐸 direct"},{"tag":"geoip-google","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/google.srs","download_detour":"🐸 direct"},{"tag":"geoip-netflix","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/netflix.srs","download_detour":"🐸 direct"},{"tag":"geoip-twitter","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/twitter.srs","download_detour":"🐸 direct"},{"tag":"geoip-telegram","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/telegram.srs","download_detour":"🐸 direct"},{"tag":"geoip-facebook","type":"remote","format":"binary","url":"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/facebook.srs","download_detour":"🐸 direct"}]
CATALOG_EOF
}

sync_route_rule_set_catalog() {
    local conf_file="$1"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local catalog_json tmp_json
    catalog_json="$(auto_rule_set_catalog_json)"
    [[ -n "$catalog_json" && "$catalog_json" != "[]" ]] || return 0

    tmp_json="$(mktemp)"
    jq --argjson catalog "$catalog_json" '
        .route = (.route // {})
        | .route.rule_set = (
            ((.route.rule_set // []) as $current
            | (
                $current
                | map(
                    . as $item
                    | if ((($item.type? // "") != "") or (($item.url? // "") != "") or (($item.path? // "") != "")) then
                        $item
                      else
                        ([ $catalog[]? | select(.tag == ($item.tag // "")) ] | .[0]) // empty
                      end
                  )
              ) as $normalized
            | reduce ($catalog[]?) as $item ($normalized;
                if ([ .[]?.tag ] | index($item.tag)) == null then
                    . + [$item]
                else
                    .
                end
              )
            )
          )
    ' "$conf_file" > "$tmp_json" 2>/dev/null || true

    if [[ -s "$tmp_json" ]]; then
        if ! cmp -s "$tmp_json" "$conf_file"; then
            mv "$tmp_json" "$conf_file"
            return 10
        fi
        rm -f "$tmp_json"
        return 0
    fi

    rm -f "$tmp_json"
    return 1
}

ensure_singbox_auto_config() {
    local force="${1:-0}"
    local conf_file old_conf old_inbounds old_final stack_mode direct_mode
    routing_autoconfig_load_reconcile_modules || return 1
    conf_file="$(get_conf_file)"

    if [[ "$force" != "1" && -n "$conf_file" && -f "$conf_file" ]]; then
        if singbox_autoconfig_state_is_fresh "$conf_file"; then
            return 0
        fi

        drop_acme_route_rules "$conf_file" || true
        sync_route_rule_set_catalog "$conf_file"
        local rs_sync_rc=$?
        if [[ "$rs_sync_rc" -eq 10 ]]; then
            yellow "已补齐 route.rule_set 规则库条目。"
            systemctl reset-failed sing-box >/dev/null 2>&1 || true
            systemctl restart sing-box >/dev/null 2>&1 || true
        fi
        if sanitize_singbox_inbound_uuids "$conf_file"; then
            yellow "检测到并修复了无效 UUID，已尝试自动重启 sing-box。"
            systemctl reset-failed sing-box >/dev/null 2>&1 || true
            systemctl restart sing-box >/dev/null 2>&1 || true
        fi
        sync_res_socks_outbounds_to_conf "$conf_file" || true
        local reconcile_state pre_fingerprint post_fingerprint
        reconcile_state="$(routing_load_state_json 2>/dev/null || echo "[]")"
        pre_fingerprint="$(proxy_cksum_signature <"$conf_file")"
        if routing_apply_rules_change "$conf_file" "$reconcile_state" "$reconcile_state"; then
            post_fingerprint="$(proxy_cksum_signature <"$conf_file")"
            if [[ -n "$pre_fingerprint" && -n "$post_fingerprint" && "$pre_fingerprint" != "$post_fingerprint" ]]; then
                yellow "已按当前分流状态同步 route/dns 规则。"
                systemctl reset-failed sing-box >/dev/null 2>&1 || true
                systemctl restart sing-box >/dev/null 2>&1 || true
            fi
        fi
        normalize_singbox_top_level_key_order "$conf_file" >/dev/null 2>&1 || true
        singbox_autoconfig_state_mark_fresh "$conf_file" || true
        return 0
    fi

    mkdir -p "$CONF_DIR" >/dev/null 2>&1 || true
    old_conf=""
    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        old_conf="$conf_file"
        backup_conf_file "$old_conf"
    fi

    stack_mode="$(detect_server_ip_stack)"
    direct_mode="$(cat "$DIRECT_IP_VERSION_FILE" 2>/dev/null | tr -d '[:space:]')"
    [[ -z "$direct_mode" ]] && direct_mode="$(stack_direct_strategy_for_mode "$stack_mode")"
    case "$direct_mode" in
        ipv4_only|ipv6_only|prefer_ipv4|prefer_ipv6|as_is) ;;
        *) direct_mode="$(stack_direct_strategy_for_mode "$stack_mode")" ;;
    esac

    local add_res_socks=0
    if load_res_socks_secret >/dev/null 2>&1; then
        add_res_socks=1
    fi

    old_final="🐸 direct"
    old_inbounds="[]"
    if [[ -n "$old_conf" && -f "$old_conf" ]]; then
        local _old_fields
        _old_fields="$(jq -r '[(.route.final // "🐸 direct"), (.inbounds // [] | tojson)] | @tsv' "$old_conf" 2>/dev/null || true)"
        if [[ -n "$_old_fields" ]]; then
            IFS=$'\t' read -r old_final old_inbounds <<<"$_old_fields"
        fi
    fi
    [[ -z "$old_final" || "$old_final" == "null" ]] && old_final="🐸 direct"
    if [[ "$old_final" != "🐸 direct" ]] && ! is_res_socks_outbound_tag "$old_final"; then
        old_final="🐸 direct"
    fi
    if is_res_socks_outbound_tag "$old_final" && [[ "$add_res_socks" -eq 0 ]]; then
        old_final="🐸 direct"
    fi

    local base_json
    base_json="$(build_auto_singbox_base_json "$stack_mode" "$direct_mode" "$add_res_socks" "$old_final")"
    if [[ -z "$base_json" ]]; then
        red "自动生成 sing-box 配置失败。"
        return 1
    fi

    if [[ -n "$old_conf" && -f "$old_conf" && "$old_inbounds" != "[]" ]]; then
        base_json="$(echo "$base_json" | jq -c --argjson inb "${old_inbounds:-[]}" '.inbounds = $inb' 2>/dev/null || true)"
    fi

    local target_conf="${CONF_DIR}/sing-box.json"
    local tmp_conf
    tmp_conf="$(mktemp)"
    if ! echo "$base_json" | jq . > "$tmp_conf" 2>/dev/null; then
        rm -f "$tmp_conf"
        red "自动生成 sing-box 配置失败（JSON 无效）。"
        return 1
    fi

    if (( add_res_socks == 1 )); then
        sync_res_socks_outbounds_to_conf "$tmp_conf" || true
    fi

    if [[ -f "$old_conf" && "$old_conf" != "$target_conf" ]]; then
        rm -f "${CONF_DIR}"/*.json
    fi
    mv "$tmp_conf" "$target_conf"

    local state_json route_rules_json
    state_json="$(routing_load_state_json)"
    route_rules_json="$(routing_build_rules_from_state "$state_json" "$target_conf")"
    if [[ -n "$route_rules_json" && "$route_rules_json" != "[]" ]]; then
        local tmp_rules
        tmp_rules="$(mktemp)"
        jq --argjson rr "$route_rules_json" '
            .route.rules = ((.route.rules // []) + $rr)
        ' "$target_conf" > "$tmp_rules" 2>/dev/null || true
        if [[ -s "$tmp_rules" ]]; then
            mv "$tmp_rules" "$target_conf"
        else
            rm -f "$tmp_rules"
        fi
    fi

    sanitize_singbox_inbound_uuids "$target_conf" >/dev/null 2>&1 || true
    drop_acme_route_rules "$target_conf" || true
    sync_dns_with_route "$target_conf" || true
    if routing_autoconfig_ensure_user_route_sync_loaded; then
        sync_user_template_route_rules "$target_conf" || true
    fi
    normalize_singbox_top_level_key_order "$target_conf" >/dev/null 2>&1 || true

    singbox_autoconfig_state_mark_fresh "$target_conf" || true
    return 0
}
