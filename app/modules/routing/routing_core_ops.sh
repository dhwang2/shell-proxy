# Routing core and sing-box auto-config operations for shell-proxy management.

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

ROUTING_RES_SOCKS_OPS_FILE="${ROUTING_RES_SOCKS_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_res_socks_ops.sh}"
if [[ -f "$ROUTING_RES_SOCKS_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_RES_SOCKS_OPS_FILE"
fi

ROUTING_AUTOCONFIG_OPS_FILE="${ROUTING_AUTOCONFIG_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_autoconfig_ops.sh}"
if [[ -f "$ROUTING_AUTOCONFIG_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_AUTOCONFIG_OPS_FILE"
fi

ROUTING_OPS_FILE="${ROUTING_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_ops.sh}"
if [[ -f "$ROUTING_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_OPS_FILE"
fi

ROUTING_PRESET_OPS_FILE="${ROUTING_PRESET_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_preset_ops.sh}"
if [[ -f "$ROUTING_PRESET_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_PRESET_OPS_FILE"
fi

ROUTING_RULES_DB="${WORK_DIR}/routing_rules.json"
DIRECT_IP_VERSION_FILE="${WORK_DIR}/direct_ip_version"

routing_ensure_state_db() {
    mkdir -p "$WORK_DIR" >/dev/null 2>&1 || true
    if [[ ! -f "$ROUTING_RULES_DB" ]]; then
        echo "[]" > "$ROUTING_RULES_DB"
    fi
    if ! jq -e 'type=="array"' "$ROUTING_RULES_DB" >/dev/null 2>&1; then
        echo "[]" > "$ROUTING_RULES_DB"
    fi
}

routing_load_state_json() {
    local state_json="[]"
    if (( ROUTING_USER_CONTEXT_ACTIVE == 1 )) && [[ -n "${ROUTING_USER_CONTEXT_NAME:-}" ]]; then
        state_json="$(routing_user_load_state_json "$ROUTING_USER_CONTEXT_NAME")"
    else
        routing_ensure_state_db
        state_json="$(cat "$ROUTING_RULES_DB" 2>/dev/null || echo "[]")"
    fi

    if [[ "${state_json:-[]}" != *"\"outbound\":\"${RES_SOCKS_TAG}\""* \
        && "${state_json:-[]}" != *"\"outbound\": \"${RES_SOCKS_TAG}\""* ]]; then
        echo "${state_json:-[]}"
        return 0
    fi

    local first_tag
    first_tag="$(res_socks_first_outbound_tag 2>/dev/null || true)"
    if [[ -n "$first_tag" ]]; then
        jq -c --arg old "$RES_SOCKS_TAG" --arg new "$first_tag" '
            map(if (.outbound // "") == $old then .outbound = $new else . end)
        ' <<<"${state_json:-[]}" 2>/dev/null || echo "${state_json:-[]}"
        return 0
    fi
    echo "${state_json:-[]}"
}

routing_save_state_json() {
    local state_json="${1:-[]}"
    local tmp_json
    tmp_json="$(mktemp)"
    if echo "$state_json" | jq -c . > "$tmp_json" 2>/dev/null; then
        mv "$tmp_json" "$ROUTING_RULES_DB"
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

routing_commit_state_change() {
    local conf_file="$1" old_state="${2:-[]}" new_state="${3:-[]}"
    local refresh_target_name=""
    if (( ROUTING_USER_CONTEXT_ACTIVE == 1 )) && [[ -n "${ROUTING_USER_CONTEXT_NAME:-}" ]]; then
        refresh_target_name="${ROUTING_USER_CONTEXT_NAME}"
        local rc
        routing_user_commit_state_change "$ROUTING_USER_CONTEXT_NAME" "$new_state" "$conf_file"
        rc=$?
        if [[ "$rc" -eq 2 ]]; then
            yellow "当前用户下暂无可应用分流的协议，请先为该用户安装支持的协议。"
        fi
        if [[ "$rc" -eq 0 ]]; then
            # Prefer async status refresh to avoid blocking the menu return.
            # The sync variant is only needed when a subsequent read depends on
            # the refreshed status within the same call — which is not the case
            # here; the menu will re-render on its next loop iteration.
            if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
                routing_status_schedule_refresh_all_contexts "$conf_file" "$refresh_target_name" >/dev/null 2>&1 || true
            elif declare -F routing_status_refresh_all_contexts_sync >/dev/null 2>&1; then
                routing_status_refresh_all_contexts_sync "$conf_file" "$refresh_target_name" >/dev/null 2>&1 || true
            fi
            if declare -F routing_menu_view_cache_invalidate >/dev/null 2>&1; then
                routing_menu_view_cache_invalidate "$conf_file" >/dev/null 2>&1 || true
            fi
        fi
        return "$rc"
    fi

    if routing_apply_rules_change "$conf_file" "$old_state" "$new_state"; then
        routing_save_state_json "$new_state" || true
        if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
            routing_status_schedule_refresh_all_contexts "$conf_file" "$refresh_target_name" >/dev/null 2>&1 || true
        elif declare -F routing_status_refresh_all_contexts_sync >/dev/null 2>&1; then
            routing_status_refresh_all_contexts_sync "$conf_file" "$refresh_target_name" >/dev/null 2>&1 || true
        fi
        if declare -F routing_menu_view_cache_invalidate >/dev/null 2>&1; then
            routing_menu_view_cache_invalidate "$conf_file" >/dev/null 2>&1 || true
        fi
        return 0
    fi
    return 1
}

routing_conf_file_or_warn() {
    local conf_file
    conf_file="$(get_conf_file)"
    if [[ -z "$conf_file" || ! -f "$conf_file" ]]; then
        red "未发现 sing-box 配置文件，请先重建配置。"
        return 1
    fi
    echo "$conf_file"
}

routing_get_direct_mode() {
    local conf_file="$1"
    local mode=""
    if [[ -f "$DIRECT_IP_VERSION_FILE" ]]; then
        mode="$(cat "$DIRECT_IP_VERSION_FILE" 2>/dev/null | tr -d '[:space:]')"
    fi
    if [[ -z "$mode" && -n "$conf_file" && -f "$conf_file" ]]; then
        mode="$(jq -r --arg tag "🐸 direct" '
            .outbounds[]? | select(.tag==$tag)
            | (
                if ((.domain_resolver? // null) | type) == "object" and (.domain_resolver.strategy? != null) then
                    .domain_resolver.strategy
                else
                    empty
                end
              )
        ' "$conf_file" 2>/dev/null | head -n 1)"
    fi
    [[ -z "$mode" ]] && mode="as_is"
    echo "$mode"
}

routing_sync_dns_conf_fields() {
    local conf_file="${1:-}" direct_mode="" row="" route_final=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if [[ -f "$DIRECT_IP_VERSION_FILE" ]]; then
        direct_mode="$(tr -d '[:space:]' <"$DIRECT_IP_VERSION_FILE" 2>/dev/null || true)"
    fi

    if [[ -n "$direct_mode" ]]; then
        row="$(jq -r --arg sep "$ROUTING_SYNC_DNS_FIELD_SEP" '
            [(.route.final // "🐸 direct"), ""]
            | join($sep)
        ' "$conf_file" 2>/dev/null || true)"
        [[ -n "$row" ]] || row="🐸 direct${ROUTING_SYNC_DNS_FIELD_SEP}"
        IFS="$ROUTING_SYNC_DNS_FIELD_SEP" read -r route_final _ <<<"$row"
        printf '%s%s%s\n' "${route_final:-🐸 direct}" "$ROUTING_SYNC_DNS_FIELD_SEP" "$direct_mode"
        return 0
    fi

    jq -r --arg sep "$ROUTING_SYNC_DNS_FIELD_SEP" --arg tag "🐸 direct" '
        [
            (.route.final // "🐸 direct"),
            (
                [
                    .outbounds[]?
                    | select((.tag // "") == $tag)
                    | (
                        if ((.domain_resolver? // null) | type) == "object" and (.domain_resolver.strategy? != null) then
                            .domain_resolver.strategy
                        else
                            empty
                        end
                    )
                ][0] // ""
            )
        ] | join($sep)
    ' "$conf_file" 2>/dev/null
}

routing_direct_mode_label() {
    local mode="$1"
    case "$mode" in
        ipv4_only|ipv4) echo "仅 IPv4" ;;
        ipv6_only|ipv6) echo "仅 IPv6" ;;
        prefer_ipv4) echo "优先 IPv4" ;;
        prefer_ipv6) echo "优先 IPv6" ;;
        as_is|asis|"") echo "AsIs" ;;
        *) echo "未知(${mode})" ;;
    esac
}

routing_apply_direct_mode_to_conf() {
    local conf_file="$1"
    local mode="$2"
    local default_dns_tag
    [[ -z "$conf_file" || ! -f "$conf_file" ]] && return 1

    default_dns_tag="$(jq -r '.route.default_domain_resolver // .dns.final // "public4"' "$conf_file" 2>/dev/null | head -n 1)"
    [[ -z "$default_dns_tag" || "$default_dns_tag" == "null" ]] && default_dns_tag="public4"

    backup_conf_file "$conf_file"
    local tmp_json
    tmp_json="$(mktemp)"
    if [[ "$mode" == "as_is" ]]; then
        jq --arg tag "🐸 direct" '
            .outbounds |= map(
                if .tag == $tag then
                    del(.domain_strategy)
                    | (
                        if ((.domain_resolver? // null) | type) == "object" then
                            .domain_resolver |= del(.strategy)
                        else
                            .
                        end
                      )
                else
                    .
                end
            )
        ' "$conf_file" > "$tmp_json" 2>/dev/null || true
    else
        jq --arg tag "🐸 direct" --arg mode "$mode" --arg default_dns_tag "$default_dns_tag" '
            .outbounds |= map(
                if .tag == $tag then
                    .domain_resolver = (
                        if ((.domain_resolver? // null) | type) == "object" then
                            .domain_resolver
                        elif ((.domain_resolver? // null) | type) == "string" and (.domain_resolver | length) > 0 then
                            {server: .domain_resolver}
                        else
                            {server: $default_dns_tag}
                        end
                    )
                    | .domain_resolver.server = (.domain_resolver.server // $default_dns_tag)
                    | .domain_resolver.strategy = $mode
                    | del(.domain_strategy)
                else
                    .
                end
            )
        ' "$conf_file" > "$tmp_json" 2>/dev/null || true
    fi

    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$conf_file"
        echo "$mode" > "$DIRECT_IP_VERSION_FILE"
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

routing_res_socks_ready() {
    local conf_file="$1"
    res_socks_outbound_exists "$conf_file" || return 1
    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true
    (( ${ROUTING_RES_SOCKS_RUNTIME_COUNT:-0} > 0 )) || return 1
    return 0
}

routing_outbound_label() {
    local outbound="$1"
    case "$outbound" in
        "🐸 direct") echo "直连" ;;
        *)
            if is_res_socks_outbound_tag "$outbound"; then
                local label
                label="$(res_socks_display_label_by_tag "$outbound" 2>/dev/null || true)"
                if [[ -n "$label" ]]; then
                    echo "$label"
                else
                    echo "$outbound"
                fi
            else
                echo "$outbound"
            fi
            ;;
    esac
}

routing_apply_rules_change() {
    local conf_file="$1" old_state="${2:-[]}" new_state="${3:-[]}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    # 仅按当前分流状态补齐需要的 geosite/geoip 规则集，并统一 geosite 在前、geoip 在后。
    local rs_sync_rc
    routing_sync_required_rule_sets "$conf_file" "$new_state"
    rs_sync_rc=$?
    if [[ "$rs_sync_rc" -ne 0 && "$rs_sync_rc" -ne 10 ]]; then
        return 1
    fi

    local new_rules tmp_json
    new_rules="$(routing_build_rules_from_state "$new_state" "$conf_file")"
    [[ -z "$new_rules" ]] && new_rules="[]"

    tmp_json="$(mktemp)"
    jq --argjson new "$new_rules" '
        .route = (.route // {})
        | .route.rules = (
            ((.route.rules // [])
             | map(
                 select(
                   (
                     # 仅保留基础规则和用户级路由规则，菜单分流规则统一由 routing_rules.json 重建。
                     (.action // "") == "route"
                     and (
                       (((.auth_user? // null) | type) == "array")
                       or ((.ip_is_private // false) == true and (.outbound // "") == "🐸 direct")
                     ) | not
                   ) | not
                 )
               )
            ) + $new
        )
    ' "$conf_file" > "$tmp_json" 2>/dev/null || true

    if [[ ! -s "$tmp_json" ]] || ! jq . "$tmp_json" >/dev/null 2>&1; then
        rm -f "$tmp_json"
        return 1
    fi

    # 分流规则变更必须同步 route + dns，避免两者不一致。
    if ! sync_dns_with_route "$tmp_json"; then
        rm -f "$tmp_json"
        return 1
    fi
    if [[ ! -s "$tmp_json" ]] || ! jq . "$tmp_json" >/dev/null 2>&1; then
        rm -f "$tmp_json"
        return 1
    fi

    mv "$tmp_json" "$conf_file"
    return 0
}

ROUTING_SYNC_DNS_FIELD_SEP=$'\x1f'

routing_sync_dns_compute_context() {
    local conf_file="$1"
    local stack_mode route_final chain_ready=0 chain_global=0 dns_strategy public_dns_tag dns_final direct_mode conf_fields

    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    stack_mode="$(detect_server_ip_stack)"
    conf_fields="$(routing_sync_dns_conf_fields "$conf_file" 2>/dev/null || true)"
    IFS="$ROUTING_SYNC_DNS_FIELD_SEP" read -r route_final direct_mode <<<"$conf_fields"
    [[ -n "$route_final" ]] || route_final="🐸 direct"

    if routing_res_socks_ready "$conf_file"; then
        chain_ready=1
    fi

    if [[ "$chain_ready" -eq 1 ]] && is_res_socks_outbound_tag "$route_final"; then
        chain_global=1
    fi

    case "$direct_mode" in
        ipv4_only|ipv6_only|prefer_ipv4|prefer_ipv6)
            dns_strategy="$direct_mode"
            ;;
        *)
            dns_strategy="$(stack_dns_strategy_for_mode "$stack_mode")"
            ;;
    esac
    public_dns_tag="$(dns_public_tag_for_strategy "$dns_strategy")"

    dns_final="$public_dns_tag"
    if [[ "$chain_global" -eq 1 ]]; then
        dns_final="$(res_socks_dns_tag_for_outbound "$route_final" 2>/dev/null || echo "$RES_SOCKS_DNS_TAG")"
    fi

    jq -cn \
        --argjson chain_ready "$chain_ready" \
        --arg dns_strategy "$dns_strategy" \
        --arg dns_final "$dns_final" \
        --arg public_dns_tag "$public_dns_tag" '
        {
            chain_ready: $chain_ready,
            dns_strategy: $dns_strategy,
            dns_final: $dns_final,
            public_dns_tag: $public_dns_tag
        }
    '
}

routing_sync_dns_context_fields() {
    local context_json="${1:-}"
    [[ -n "$context_json" ]] || return 1

    jq -r --arg sep "$ROUTING_SYNC_DNS_FIELD_SEP" '
        [
            ((.chain_ready // 0) | tostring),
            (.dns_strategy // ""),
            (.dns_final // ""),
            (.public_dns_tag // "")
        ] | join($sep)
    ' <<<"$context_json" 2>/dev/null
}

routing_sync_dns_rules_jq_filter() {
    cat <<'EOF'
def is_geosite_rule:
    ((.rule_set? // null) | type) == "array"
    and ((.rule_set | length) > 0)
    and all(.rule_set[]; startswith("geosite-"));
def is_geoip_rule:
    ((.rule_set? // null) | type) == "array"
    and ((.rule_set | length) > 0)
    and all(.rule_set[]; startswith("geoip-"));
def is_domain_match_rule:
    ((.rule_set? // null) | type) != "array"
    and (
        has("domain")
        or has("domain_suffix")
        or has("domain_keyword")
        or has("domain_regex")
    );
def is_res_out($out):
    ($out | startswith($res_prefix));
def dns_tag_for_out($out):
    if $out == $res_prefix then $dns_prefix
    else ($out | sub("^" + $res_prefix; $dns_prefix))
    end;
def normalized_host($value):
    (($value // "") | tostring | gsub("^\\["; "") | gsub("\\]$"; ""));
def is_ipv6_literal($value):
    (normalized_host($value)) as $h
    | ($h | test("^[0-9A-Fa-f:.]+$"))
    and ($h | contains(":"));
def res_dns_strategy_for_out($root; $out):
    (
      [ $root.outbounds[]?
        | select((.tag // "") == $out)
        | ((.server // "") | tostring)
      ][0] // ""
    ) as $server
    | if is_ipv6_literal($server) then "ipv6_only" else "ipv4_only" end;
. as $root
| [
  $root.route.rules[]?
  | select(.action == "route")
  | select((.outbound // "") == "🐸 direct" or is_res_out(.outbound // ""))
  | (
      {
        action: "route",
        server: (
          if (is_res_out(.outbound // "") and $use_proxy == "1")
          then dns_tag_for_out(.outbound // "")
          else $public_tag
          end
        )
      }
      + (
          if (is_res_out(.outbound // "") and $use_proxy == "1") then
            {strategy: res_dns_strategy_for_out($root; (.outbound // ""))}
          else
            {}
          end
        )
      + (if .inbound then {inbound: .inbound} else {} end)
      + (if .auth_user then {auth_user: .auth_user} else {} end)
    )
    + (if .rule_set then {rule_set: .rule_set} else {} end)
    + (if .domain then {domain: .domain} else {} end)
    + (if .domain_suffix then {domain_suffix: .domain_suffix} else {} end)
    + (if .domain_keyword then {domain_keyword: .domain_keyword} else {} end)
    + (if .domain_regex then {domain_regex: .domain_regex} else {} end)
  | select(
      has("rule_set")
      or has("inbound")
      or has("auth_user")
      or has("domain")
      or has("domain_suffix")
      or has("domain_keyword")
      or has("domain_regex")
    )
]
| (
    reduce .[] as $r ([];
        if ([ .[] | tostring ] | index($r | tostring)) == null then
            . + [$r]
        else
            .
        end
    )
  )
| (
    map(select(is_domain_match_rule))
    + map(select(is_geosite_rule))
    + map(select(is_geoip_rule))
    + map(select((is_domain_match_rule or is_geosite_rule or is_geoip_rule) | not))
  )
EOF
}

routing_sync_dns_build_rules() {
    local conf_file="$1"
    local context_json="${2:-}"
    local context_fields chain_ready public_dns_tag dns_rules_json jq_filter

    context_fields="$(routing_sync_dns_context_fields "$context_json")" || return 1
    IFS="$ROUTING_SYNC_DNS_FIELD_SEP" read -r chain_ready _ _ public_dns_tag <<<"$context_fields"
    jq_filter="$(routing_sync_dns_rules_jq_filter)"

    dns_rules_json="$(jq -c \
        --arg use_proxy "$chain_ready" \
        --arg public_tag "$public_dns_tag" \
        --arg res_prefix "$RES_SOCKS_TAG" \
        --arg dns_prefix "$RES_SOCKS_DNS_TAG" \
        "$jq_filter" "$conf_file" 2>/dev/null)"
    [[ -n "$dns_rules_json" ]] || dns_rules_json="[]"
    echo "$dns_rules_json"
}

routing_sync_dns_public_servers_json() {
    cat <<'EOF'
[{"tag":"public4","type":"https","server":"8.8.8.8","server_port":443,"path":"/dns-query","tls":{"enabled":true,"server_name":"dns.google"}},{"tag":"public6","type":"https","server":"2001:4860:4860::8888","server_port":443,"path":"/dns-query","tls":{"enabled":true,"server_name":"dns.google"}}]
EOF
}

routing_sync_dns_base_route_rules_json() {
    cat <<'EOF'
[{"action":"sniff","sniffer":["http","tls","quic","dns"]},{"protocol":"dns","action":"hijack-dns"},{"ip_is_private":true,"action":"route","outbound":"🐸 direct"}]
EOF
}

routing_sync_dns_apply_jq_filter() {
    cat <<'EOF'
.dns = (.dns // {})
| .dns.servers = (
    $public_dns_servers
    + (
      if $chain_ready == 1 then
        $res_dns_servers
      else
        []
      end
    )
  )
| .dns.rules = $dns_rules
| .dns.final = (
    if ($dns_final | startswith("res-proxy")) then $dns_final
    else $public_dns_tag
    end
  )
| .dns.strategy = $dns_strategy
| .dns.reverse_mapping = true
| .dns.independent_cache = true
| .dns.cache_capacity = 8192
| .route = (.route // {})
| .route.rules = (
    $base_route_rules
    + (
      (.route.rules // [])
      | map(
          select(
            (
              ((.action // "") == "sniff")
              or ((.protocol // "") == "dns" and (.action // "") == "hijack-dns")
              or (
                (.ip_is_private // false) == true
                and (.action // "") == "route"
                and (.outbound // "") == "🐸 direct"
              )
            ) | not
          )
        )
    )
  )
| .route.default_domain_resolver = .dns.final
EOF
}

routing_sync_dns_apply_context() {
    local conf_file="$1"
    local context_json="${2:-}"
    local dns_rules_json="${3:-[]}"
    local context_fields chain_ready dns_strategy dns_final public_dns_tag tmp_json
    local public_dns_servers_json res_dns_servers_json base_route_rules_json jq_filter

    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1
    context_fields="$(routing_sync_dns_context_fields "$context_json")" || return 1
    IFS="$ROUTING_SYNC_DNS_FIELD_SEP" read -r chain_ready dns_strategy dns_final public_dns_tag <<<"$context_fields"

    public_dns_servers_json="$(routing_sync_dns_public_servers_json)"
    [[ -n "$public_dns_servers_json" ]] || public_dns_servers_json="[]"
    res_socks_ensure_dns_servers_json_cache >/dev/null 2>&1 || true
    res_dns_servers_json="${ROUTING_RES_SOCKS_RUNTIME_DNS_SERVERS_JSON:-[]}"
    base_route_rules_json="$(routing_sync_dns_base_route_rules_json)"
    [[ -n "$base_route_rules_json" ]] || base_route_rules_json="[]"
    jq_filter="$(routing_sync_dns_apply_jq_filter)"
    tmp_json="$(mktemp)"
    jq \
        --argjson chain_ready "$chain_ready" \
        --arg dns_strategy "$dns_strategy" \
        --arg dns_final "$dns_final" \
        --arg public_dns_tag "$public_dns_tag" \
        --argjson dns_rules "$dns_rules_json" \
        --argjson public_dns_servers "$public_dns_servers_json" \
        --argjson res_dns_servers "$res_dns_servers_json" \
        --argjson base_route_rules "$base_route_rules_json" \
        "$jq_filter" "$conf_file" > "$tmp_json" 2>/dev/null || true

    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$conf_file"
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

sync_dns_with_route() {
    local conf_file="$1"
    local context_json dns_rules_json
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    context_json="$(routing_sync_dns_compute_context "$conf_file")" || return 1

    dns_rules_json="$(routing_sync_dns_build_rules "$conf_file" "$context_json")" || return 1
    routing_sync_dns_apply_context \
        "$conf_file" \
        "$context_json" \
        "$dns_rules_json"
}

# --- routing base config (merged from routing_base_config_ops.sh) ---

build_auto_singbox_base_json() {
    local stack_mode="$1"
    local direct_mode="$2"
    local add_res_socks="$3"
    local route_final="$4"
    local dns_strategy dns_public_tag
    dns_strategy="$(stack_dns_strategy_for_mode "$stack_mode")"
    dns_public_tag="$(dns_public_tag_for_strategy "$dns_strategy")"

    local rule_set_json
    rule_set_json="$(auto_rule_set_catalog_json)"
    [[ -z "$rule_set_json" ]] && rule_set_json="[]"

    jq -cn \
        --arg work_dir "$WORK_DIR" \
        --arg log_dir "$LOG_DIR" \
        --arg dns_strategy "$dns_strategy" \
        --arg dns_public_tag "$dns_public_tag" \
        --arg direct_mode "$direct_mode" \
        --arg final_out "$route_final" \
        --argjson add_res "$add_res_socks" \
        --argjson rule_set "$rule_set_json" '
        {
          log: {
            disabled: false,
            level: "error",
            output: ($log_dir + "/sing-box.log"),
            timestamp: true
          },
          experimental: {
            cache_file: {
              enabled: true,
              cache_id: "cache.db",
              path: ($work_dir + "/cache.db"),
              store_fakeip: false,
              store_rdrc: true
            }
          },
          dns: {
            servers: [
              {
                tag: "public4",
                type: "https",
                server: "8.8.8.8",
                server_port: 443,
                path: "/dns-query",
                tls: {
                  enabled: true,
                  server_name: "dns.google"
                }
              },
              {
                tag: "public6",
                type: "https",
                server: "2001:4860:4860::8888",
                server_port: 443,
                path: "/dns-query",
                tls: {
                  enabled: true,
                  server_name: "dns.google"
                }
              }
            ],
            rules: [],
            final: $dns_public_tag,
            strategy: $dns_strategy,
            reverse_mapping: true,
            independent_cache: true,
            cache_capacity: 8192
          },
          inbounds: [],
          outbounds: [
            {
              type: "direct",
              tag: "🐸 direct"
            }
          ],
          route: {
            final: $final_out,
            default_domain_resolver: $dns_public_tag,
            rules: [
              {
                action: "sniff",
                sniffer: ["http", "tls", "quic", "dns"]
              },
              {
                ip_is_private: true,
                action: "route",
                outbound: "🐸 direct"
              },
              {
                protocol: "dns",
                action: "hijack-dns"
              }
            ],
            rule_set: $rule_set
          }
        }
        | if $direct_mode != "as_is" then
            .outbounds |= map(
              if .tag == "🐸 direct" then
                .domain_resolver = (
                  if ((.domain_resolver? // null) | type) == "object" then
                    .domain_resolver
                  elif ((.domain_resolver? // null) | type) == "string" and (.domain_resolver | length) > 0 then
                    {server: .domain_resolver}
                  else
                    {server: $dns_public_tag}
                  end
                )
                | .domain_resolver.server = (.domain_resolver.server // $dns_public_tag)
                | .domain_resolver.strategy = $direct_mode
                | del(.domain_strategy)
              else
                .
              end
            )
          else
            .outbounds |= map(
              if .tag == "🐸 direct" then
                del(.domain_strategy)
                | (
                    if ((.domain_resolver? // null) | type) == "object" then
                      .domain_resolver |= del(.strategy)
                    else
                      .
                    end
                  )
              else
                .
              end
            )
          end
        | if $add_res == 1 then
            .outbounds += [{
              type: "socks",
              tag: "res-socks",
              server: "127.0.0.1",
              server_port: 1080,
              version: "5",
              udp_over_tcp: false
            }]
            | .dns.servers += [{
              tag: "res-proxy",
              type: "https",
              server: "8.8.8.8",
              server_port: 443,
              path: "/dns-query",
              tls: {
                enabled: true,
                server_name: "dns.google"
              },
              detour: "res-socks"
            }]
          else
            .
          end
        '
}

drop_acme_route_rules() {
    local conf_file="$1"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local tmp_json
    tmp_json="$(mktemp)"
    jq '
        .route = (.route // {})
        | .route.rules = [
            (.route.rules // [])[]
            | select((.protocol // "") != "acme")
          ]
    ' "$conf_file" > "$tmp_json" 2>/dev/null || true

    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$conf_file"
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

singbox_template_mode() {
    local conf_file="$1"
    local base
    base="$(basename "${conf_file:-}")"
    case "$base" in
        *dualstack*.json) echo "dualstack" ;;
        *singlestack*.json) echo "ipv4" ;;
        *ipv4*.json) echo "ipv4" ;;
        *)
            if [[ -n "$conf_file" && -f "$conf_file" ]]; then
                local strategy
                strategy="$(jq -r '.dns.strategy // empty' "$conf_file" 2>/dev/null || true)"
                case "$strategy" in
                    ipv4_only) echo "ipv4"; return 0 ;;
                    ipv6_only) echo "ipv6"; return 0 ;;
                    prefer_ipv4|prefer_ipv6) echo "dualstack"; return 0 ;;
                esac
            fi
            detect_server_ip_stack
            ;;
    esac
}

singbox_inbound_listen_addr() {
    local conf_file="$1"
    local mode
    mode="$(singbox_template_mode "$conf_file")"
    case "$mode" in
        ipv4) echo "0.0.0.0" ;;
        dualstack|ipv6) echo "::" ;;
        *) echo "::" ;;
    esac
}

maybe_fix_bindv6only() {
    local listen_addr="${1:-}"
    [[ "$listen_addr" == "::" ]] || return 0

    if ! command -v sysctl >/dev/null 2>&1; then
        return 0
    fi
    local cur
    cur="$(sysctl -n net.ipv6.bindv6only 2>/dev/null | tr -d ' ' || true)"
    [[ "$cur" == "1" ]] || return 0

    yellow "检测到 net.ipv6.bindv6only=1，listen=\"::\" 可能无法接受 IPv4 连接。"
    read -p "是否修复为 0 并写入 /etc/sysctl.d/99-proxy.conf? [y/N]: " yn
    if [[ "${yn,,}" == "y" ]]; then
        mkdir -p /etc/sysctl.d 2>/dev/null || true
        cat > /etc/sysctl.d/99-proxy.conf <<EOF
net.ipv6.bindv6only = 0
EOF
        sysctl -w net.ipv6.bindv6only=0 >/dev/null 2>&1 || true
        green "已设置 net.ipv6.bindv6only=0"
    fi
}
