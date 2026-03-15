# res-socks menu and interactive operations for shell-proxy management.

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

RES_SOCKS_TAG="res-socks"
RES_SOCKS_DNS_TAG="res-proxy"
RES_SOCKS_SECRET_DIR="${WORK_DIR}/secrets"
RES_SOCKS_NODES_FILE="${RES_SOCKS_SECRET_DIR}/res_socks_nodes.json"

if ! declare -p ROUTING_RES_SOCKS_LABEL_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_RES_SOCKS_LABEL_CACHE=()
fi
if ! declare -p ROUTING_RES_SOCKS_COLORED_LABEL_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_RES_SOCKS_COLORED_LABEL_CACHE=()
fi
ROUTING_RES_SOCKS_RUNTIME_CACHE_FP=""
ROUTING_RES_SOCKS_RUNTIME_COUNT=0
ROUTING_RES_SOCKS_RUNTIME_FIRST_TAG=""
ROUTING_RES_SOCKS_RUNTIME_NODE_LINES=""
ROUTING_RES_SOCKS_RUNTIME_DNS_SERVERS_JSON=""
RES_SOCKS_RUNTIME_FIELD_SEP=$'\x1f'

parse_res_socks_compact_input() {
    local raw="${1:-}"
    raw="$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$raw" ]] || return 1

    local server="" port="" username="" password=""

    if [[ "$raw" =~ ^\[([0-9a-fA-F:]+)\]:([0-9]{1,5}):([^:]*):(.*)$ ]]; then
        server="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
        username="${BASH_REMATCH[3]}"
        password="${BASH_REMATCH[4]}"
    elif [[ "$raw" =~ ^([^:]+):([0-9]{1,5}):([^:]*):(.*)$ ]]; then
        server="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
        username="${BASH_REMATCH[3]}"
        password="${BASH_REMATCH[4]}"
    else
        return 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        return 1
    fi

    echo "${server}|${port}|${username}|${password}"
    return 0
}

res_socks_print_node_lines() {
    local had_output=0 index=1
    local node_id tag server port username password label
    while IFS=$'\t' read -r node_id tag server port username password; do
        [[ -n "$node_id" ]] || continue
        had_output=1
        label="$(res_socks_format_label_colored "$tag" "$server" "$port")"
        echo "${index}. ${label}"
        ((index++))
    done < <(res_socks_nodes_list_lines)
    (( had_output == 1 ))
}

res_socks_pick_node_id_interactive() {
    local title="$1"
    local node_ids=() labels=()
    local node_id tag server port username password label
    while IFS=$'\t' read -r node_id tag server port username password; do
        [[ -n "$node_id" ]] || continue
        label="$(res_socks_format_label_colored "$tag" "$server" "$port")"
        node_ids+=("$node_id")
        labels+=("$label")
    done < <(res_socks_nodes_list_lines)

    if (( ${#node_ids[@]} == 0 )); then
        echo "__none__"
        return 0
    fi

    ui_clear >&2
    proxy_menu_header "$title" >&2
    local idx=1
    for label in "${labels[@]}"; do
        echo "${idx}. ${label}" >&2
        ((idx++))
    done

    local pick=""
    if ! prompt_select_index pick; then
        echo ""
        return 0
    fi
    if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#node_ids[@]} )); then
        echo "__invalid__"
        return 0
    fi
    echo "${node_ids[$((pick-1))]}"
}

is_ipv4_literal() {
    local ip="${1:-}"
    [[ -n "$ip" ]] || return 1
    [[ "$ip" == *:* ]] && return 1

    local o1 o2 o3 o4 extra
    IFS='.' read -r o1 o2 o3 o4 extra <<<"$ip"
    [[ -n "$o1" && -n "$o2" && -n "$o3" && -n "$o4" && -z "$extra" ]] || return 1

    local octet
    for octet in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        ((octet >= 0 && octet <= 255)) || return 1
    done
    return 0
}

is_public_ipv4_literal() {
    local ip="${1:-}"
    is_ipv4_literal "$ip" || return 1

    local o1 o2 o3 o4
    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

    if (( o1 == 0 || o1 == 10 || o1 == 127 )); then
        return 1
    fi
    if (( o1 == 100 && o2 >= 64 && o2 <= 127 )); then
        return 1
    fi
    if (( o1 == 169 && o2 == 254 )); then
        return 1
    fi
    if (( o1 == 172 && o2 >= 16 && o2 <= 31 )); then
        return 1
    fi
    if (( o1 == 192 && o2 == 168 )); then
        return 1
    fi
    if (( o1 == 198 && (o2 == 18 || o2 == 19) )); then
        return 1
    fi
    if (( o1 >= 224 )); then
        return 1
    fi
    if (( o1 == 255 && o2 == 255 && o3 == 255 && o4 == 255 )); then
        return 1
    fi

    return 0
}

configure_res_socks_interactive() {
    local conf_file="${1:-}"
    local do_restart="${2:-1}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"

    ui_clear
    proxy_menu_header "配置链式代理节点"

    if [[ -z "$conf_file" || ! -f "$conf_file" ]]; then
        red "未发现 sing-box 配置文件，请先重建配置。"
        pause
        return 1
    fi

    echo
    yellow "输入格式: address:port:account:password"
    yellow "提示: 建议使用 IPv4 地址，避免 VPS 本地 DNS 解析。"

    echo
    echo "回车返回"
    echo
    local server port username password compact_input parsed_line
    if ! read_prompt compact_input "链式代理节点: "; then
        return 0
    fi
    [[ -z "${compact_input:-}" ]] && return 0

    parsed_line="$(parse_res_socks_compact_input "$compact_input" 2>/dev/null || true)"
    if [[ -z "$parsed_line" ]]; then
        red "格式错误，请按 address:port:account:password 输入。"
        pause
        return 1
    fi
    IFS='|' read -r server port username password <<<"$parsed_line"

    if ! is_ipv4_literal "$server"; then
        yellow "警告: 当前 address 非 IPv4，可能触发 VPS 本地 DNS 解析。"
        local yn=""
        read -r -p "仍然继续? [y/N]: " yn
        [[ "${yn,,}" != "y" ]] && return 1
    fi

    local node_id node_tag
    node_id="$(res_socks_add_node "$server" "$port" "$username" "$password" 2>/dev/null || true)"
    if [[ -z "$node_id" ]]; then
        red "保存链式代理节点失败"
        pause
        return 1
    fi

    node_tag="$(res_socks_outbound_tag_for_node_id "$node_id" 2>/dev/null || true)"
    if ! sync_res_socks_outbounds_to_conf "$conf_file"; then
        red "写入 sing-box 配置失败"
        pause
        return 1
    fi
    sync_dns_with_route "$conf_file" || true
    if [[ "$do_restart" -eq 1 ]]; then
        restart_singbox_if_present
    fi
    if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
        routing_status_schedule_refresh_all_contexts "$conf_file" >/dev/null 2>&1 || true
    fi
    green "链式代理节点已添加: ${node_tag:-$node_id}"
    pause
    return 0
}

delete_res_socks_node_interactive() {
    local conf_file="${1:-}"
    local do_restart="${2:-1}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"

    local node_id
    node_id="$(res_socks_pick_node_id_interactive "删除链式代理节点")"
    [[ -z "$node_id" ]] && return 0
    [[ "$node_id" == "__none__" ]] && { yellow "当前没有可删除的链式代理节点。"; pause; return 0; }
    [[ "$node_id" == "__invalid__" ]] && { red "输入无效"; sleep 1; return 1; }

    local count node_line node_tag server port username password
    count="$(res_socks_nodes_count)"
    node_line="$(res_socks_get_node_line_by_id "$node_id" 2>/dev/null || true)"
    IFS='|' read -r node_tag server port username password <<<"$node_line"

    if res_socks_conf_references_outbound "$conf_file" "$node_tag"; then
        yellow "当前配置仍在使用该链式代理节点(${node_tag})，请先修改全局出口或相关分流规则。"
        pause
        return 1
    fi

    local yn=""
    read -r -p "确认删除链式代理节点 [${node_tag} ${server}:${port}]? [y/N]: " yn
    [[ "${yn,,}" == "y" ]] || return 0

    if ! res_socks_delete_node "$node_id"; then
        red "删除链式代理节点失败"
        pause
        return 1
    fi

    if ! sync_res_socks_outbounds_to_conf "$conf_file"; then
        red "同步 sing-box 出站失败"
        pause
        return 1
    fi
    sync_dns_with_route "$conf_file" || true
    if [[ "$do_restart" -eq 1 ]]; then
        restart_singbox_if_present
    fi
    if declare -F routing_status_schedule_refresh_all_contexts >/dev/null 2>&1; then
        routing_status_schedule_refresh_all_contexts "$conf_file" >/dev/null 2>&1 || true
    fi
    green "已删除链式代理节点"
    pause
    return 0
}

# --- res-socks node storage and CRUD (merged from routing_res_socks_store_ops.sh) ---

res_socks_nodes_db_json_valid() {
    local f="${1:-}"
    [[ -n "$f" && -f "$f" ]] || return 1
    jq -e 'type == "object" and ((.nodes // []) | type) == "array"' "$f" >/dev/null 2>&1
}

res_socks_write_empty_nodes_db() {
    mkdir -p "$RES_SOCKS_SECRET_DIR" || return 1
    chmod 700 "$RES_SOCKS_SECRET_DIR" 2>/dev/null || true
    umask 077
    printf '%s\n' '{"schema":2,"nodes":[]}' > "$RES_SOCKS_NODES_FILE" 2>/dev/null || return 1
    chmod 600 "$RES_SOCKS_NODES_FILE" 2>/dev/null || true
    res_socks_reset_runtime_cache
    return 0
}

res_socks_tags_need_normalize() {
    local f="${1:-}"
    [[ -n "$f" && -f "$f" ]] || return 1
    jq -e --arg prefix "$RES_SOCKS_TAG" '
        ((.nodes // []) | map(.tag // "")) as $tags
        | (($tags | length) == (($tags | unique) | length))
          and all($tags[]?; startswith($prefix) and ((sub("^" + $prefix; "")) | test("^[0-9]+$")))
    ' "$f" >/dev/null 2>&1
}

res_socks_normalize_nodes_db() {
    local src_file="${1:-}" out_file="${2:-}"
    [[ -n "$src_file" && -f "$src_file" && -n "$out_file" ]] || return 1
    jq --arg prefix "$RES_SOCKS_TAG" '
        def keep_tag($tag):
            ($tag | startswith($prefix))
            and (($tag | sub("^" + $prefix; "")) | test("^[0-9]+$"));
        def assign_next:
            if .used[($prefix + (.next | tostring))] then
                (.next += 1 | assign_next)
            else
                .candidate = ($prefix + (.next | tostring))
            end;

        reduce (.nodes // [])[] as $node (
            {used: {}, next: 1, nodes: []};
            ($node.tag // "") as $raw_tag
            | if keep_tag($raw_tag) and ((.used[$raw_tag] // false) | not) then
                .used[$raw_tag] = true
                | .nodes += [$node]
                | .next += 1
              else
                assign_next
                | .candidate as $new_tag
                | .used[$new_tag] = true
                | .nodes += [($node + {tag: $new_tag})]
                | .next += 1
                | del(.candidate)
              end
        )
        | {schema: 2, nodes: .nodes}
    ' "$src_file" > "$out_file" 2>/dev/null
}

ensure_res_socks_nodes_db() {
    if [[ ! -f "$RES_SOCKS_NODES_FILE" ]]; then
        res_socks_write_empty_nodes_db
        return $?
    fi
    if ! res_socks_nodes_db_json_valid "$RES_SOCKS_NODES_FILE"; then
        res_socks_write_empty_nodes_db
        return $?
    fi
    if res_socks_tags_need_normalize "$RES_SOCKS_NODES_FILE"; then
        return 0
    fi
    local tmp_json
    tmp_json="$(mktemp)"
    if res_socks_normalize_nodes_db "$RES_SOCKS_NODES_FILE" "$tmp_json" && [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        mv "$tmp_json" "$RES_SOCKS_NODES_FILE"
        chmod 600 "$RES_SOCKS_NODES_FILE" 2>/dev/null || true
        res_socks_reset_runtime_cache
        return 0
    fi
    rm -f "$tmp_json"
    return 1
}

load_res_socks_secret() {
    res_socks_first_node_line 2>/dev/null || true
}

res_socks_add_node() {
    local server="$1" port="$2" username="${3:-}" password="${4:-}"
    local node_id tag tmp_json
    ensure_res_socks_nodes_db || return 1
    tag="$(res_socks_next_outbound_tag)"
    node_id="node-$(date +%Y%m%d%H%M%S)-$(gen_rand_alnum 6 | tr '[:upper:]' '[:lower:]')"
    tmp_json="$(mktemp)"
    jq \
        --arg id "$node_id" \
        --arg tag "$tag" \
        --arg server "$server" \
        --argjson port "$port" \
        --arg username "$username" \
        --arg password "$password" '
        .nodes = ((.nodes // []) + [{
            id: $id,
            tag: $tag,
            server: $server,
            server_port: $port,
            username: $username,
            password: $password
        }])
    ' "$RES_SOCKS_NODES_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ ! -s "$tmp_json" ]] || ! jq . "$tmp_json" >/dev/null 2>&1; then
        rm -f "$tmp_json"
        return 1
    fi
    mv "$tmp_json" "$RES_SOCKS_NODES_FILE"
    chmod 600 "$RES_SOCKS_NODES_FILE" 2>/dev/null || true
    res_socks_reset_runtime_cache
    echo "$node_id"
}

res_socks_delete_node() {
    local node_id="$1"
    [[ -n "$node_id" ]] || return 1
    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg id "$node_id" '.nodes = [(.nodes // [])[] | select((.id // "") != $id)]' "$RES_SOCKS_NODES_FILE" > "$tmp_json" 2>/dev/null || true
    if [[ ! -s "$tmp_json" ]] || ! jq . "$tmp_json" >/dev/null 2>&1; then
        rm -f "$tmp_json"
        return 1
    fi
    mv "$tmp_json" "$RES_SOCKS_NODES_FILE"
    chmod 600 "$RES_SOCKS_NODES_FILE" 2>/dev/null || true
    res_socks_reset_runtime_cache
}

res_socks_get_node_line_by_id() {
    local node_id="$1"
    [[ -n "$node_id" ]] || return 1
    jq -r --arg id "$node_id" '
        ((.nodes // [])[]? | select((.id // "") == $id) | [
            (.tag // ""),
            (.server // ""),
            ((.server_port // "") | tostring),
            (.username // ""),
            (.password // "")
        ] | join("|")) // empty
    ' "$RES_SOCKS_NODES_FILE" 2>/dev/null
}

res_socks_get_node_line_by_tag() {
    local tag="$1"
    [[ -n "$tag" ]] || return 1
    jq -r --arg tag "$tag" '
        ((.nodes // [])[]? | select((.tag // "") == $tag) | [
            (.server // ""),
            ((.server_port // "") | tostring),
            (.username // ""),
            (.password // "")
        ] | join("|")) // empty
    ' "$RES_SOCKS_NODES_FILE" 2>/dev/null
}

res_socks_outbound_tag_for_node_id() {
    local node_id="$1"
    [[ -n "$node_id" ]] || return 1
    jq -r --arg id "$node_id" '((.nodes // [])[]? | select((.id // "") == $id) | (.tag // "")) // empty' "$RES_SOCKS_NODES_FILE" 2>/dev/null
}

res_socks_nodes_outbounds_json() {
    jq -c '
        [(.nodes // [])[]? | {
            type: "socks",
            tag: (.tag // ""),
            server: (.server // ""),
            server_port: (.server_port // 0),
            version: "5",
            udp_over_tcp: false
        }
        + (if ((.username // "") | length) > 0 then {username: .username} else {} end)
        + (if ((.password // "") | length) > 0 then {password: .password} else {} end)
        ]
    ' "$RES_SOCKS_NODES_FILE" 2>/dev/null || echo "[]"
}

sync_res_socks_outbounds_to_conf() {
    local conf_file="$1"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local outbounds_json
    outbounds_json="$(res_socks_nodes_outbounds_json)"
    [[ -n "$outbounds_json" ]] || outbounds_json="[]"

    local tmp_json
    tmp_json="$(mktemp)"
    jq --arg prefix "$RES_SOCKS_TAG" --argjson outbounds "$outbounds_json" '
        .outbounds = (
            [(.outbounds // [])[] | select((((.tag // "") | startswith($prefix)) | not))]
            + $outbounds
        )
    ' "$conf_file" > "$tmp_json" 2>/dev/null || true
    if [[ ! -s "$tmp_json" ]] || ! jq . "$tmp_json" >/dev/null 2>&1; then
        rm -f "$tmp_json"
        return 1
    fi
    mv "$tmp_json" "$conf_file"
    return 0
}

# --- res-socks runtime cache and query (merged from routing_res_socks_query_ops.sh) ---

res_socks_reset_runtime_cache() {
    ROUTING_RES_SOCKS_RUNTIME_CACHE_FP=""
    ROUTING_RES_SOCKS_RUNTIME_COUNT=0
    ROUTING_RES_SOCKS_RUNTIME_FIRST_TAG=""
    ROUTING_RES_SOCKS_RUNTIME_NODE_LINES=""
    ROUTING_RES_SOCKS_RUNTIME_DNS_SERVERS_JSON=""
    ROUTING_RES_SOCKS_LABEL_CACHE=()
    ROUTING_RES_SOCKS_COLORED_LABEL_CACHE=()
}

res_socks_runtime_cache_fingerprint() {
    if [[ -f "$RES_SOCKS_NODES_FILE" ]]; then
        calc_file_fingerprint "$RES_SOCKS_NODES_FILE" 2>/dev/null || echo "__fp_error__"
    else
        echo "__missing__"
    fi
}

res_socks_json_escape_string() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

res_socks_normalize_host() {
    local value="${1:-}"
    value="${value#[}"
    value="${value%]}"
    printf '%s' "$value"
}

res_socks_server_is_ipv6_literal() {
    local server="${1:-}" normalized
    normalized="$(res_socks_normalize_host "$server")"
    [[ -n "$normalized" && "$normalized" == *:* ]] || return 1
    [[ "$normalized" =~ ^[0-9A-Fa-f:.]+$ ]]
}

res_socks_format_label() {
    local tag="${1:-}" server="${2:-}" port="${3:-}"
    local host_port="${server}:${port}"
    printf '%s: %s\n' "$tag" "$host_port"
}

res_socks_format_label_colored() {
    local tag="${1:-}" server="${2:-}" port="${3:-}"
    local host_port="${server}:${port}"
    printf '%s: %s\n' "$(routing_colorize "36;1" "$tag")" "$(routing_colorize "33;1" "$host_port")"
}

is_res_socks_outbound_tag() {
    local tag="${1:-}" suffix=""
    [[ -n "$tag" ]] || return 1
    [[ "$tag" == "$RES_SOCKS_TAG" ]] && return 0
    suffix="${tag#${RES_SOCKS_TAG}}"
    [[ "$suffix" != "$tag" && "$suffix" =~ ^[0-9]+$ ]]
}

res_socks_dns_tag_for_outbound() {
    local outbound="${1:-}" suffix=""
    [[ -n "$outbound" ]] || return 1
    if [[ "$outbound" == "$RES_SOCKS_TAG" ]]; then
        echo "$RES_SOCKS_DNS_TAG"
        return 0
    fi
    suffix="${outbound#${RES_SOCKS_TAG}}"
    if [[ "$suffix" != "$outbound" && "$suffix" =~ ^[0-9]+$ ]]; then
        echo "${RES_SOCKS_DNS_TAG}${suffix}"
        return 0
    fi
    return 1
}

res_socks_outbound_exists() {
    local conf_file="$1" tag="${2:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if [[ -n "$tag" ]]; then
        if grep -Eq "\"tag\"[[:space:]]*:[[:space:]]*\"${tag}\"" "$conf_file" 2>/dev/null; then
            return 0
        fi
        jq -e --arg tag "$tag" '.outbounds[]? | select((.tag // "") == $tag) | .tag' "$conf_file" >/dev/null 2>&1
    else
        if grep -Eq "\"tag\"[[:space:]]*:[[:space:]]*\"${RES_SOCKS_TAG}[0-9]*\"" "$conf_file" 2>/dev/null; then
            return 0
        fi
        jq -e --arg prefix "$RES_SOCKS_TAG" '.outbounds[]? | select((((.tag // "") | startswith($prefix)))) | .tag' "$conf_file" >/dev/null 2>&1
    fi
}

res_socks_refresh_runtime_cache() {
    local current_fp
    current_fp="$(res_socks_runtime_cache_fingerprint)"
    if [[ "$current_fp" == "$ROUTING_RES_SOCKS_RUNTIME_CACHE_FP" ]]; then
        return 0
    fi

    current_fp="$(res_socks_runtime_cache_fingerprint)"
    if [[ "$current_fp" == "$ROUTING_RES_SOCKS_RUNTIME_CACHE_FP" ]]; then
        return 0
    fi

    local count=0 first_tag="" node_lines=""
    local node_id tag server port username password host_port
    res_socks_reset_runtime_cache
    while IFS=$'\t' read -r node_id tag server port username password; do
        [[ -n "$tag" ]] || continue
        host_port="${server}:${port}"
        ROUTING_RES_SOCKS_LABEL_CACHE["$tag"]="$(res_socks_format_label "$tag" "$server" "$port")"
        ROUTING_RES_SOCKS_COLORED_LABEL_CACHE["$tag"]="$(res_socks_format_label_colored "$tag" "$server" "$port")"
        [[ -n "$first_tag" ]] || first_tag="$tag"
        node_lines+="${tag}${RES_SOCKS_RUNTIME_FIELD_SEP}${server}"$'\n'
        ((count++))
    done < <(
        jq -r '
            (.nodes // [])[]
            | [
                (.id // ""),
                (.tag // ""),
                (.server // ""),
                ((.server_port // "") | tostring),
                (.username // ""),
                (.password // "")
              ] | @tsv
        ' "$RES_SOCKS_NODES_FILE" 2>/dev/null
    )

    ROUTING_RES_SOCKS_RUNTIME_COUNT="$count"
    ROUTING_RES_SOCKS_RUNTIME_FIRST_TAG="$first_tag"
    ROUTING_RES_SOCKS_RUNTIME_NODE_LINES="$node_lines"
    ROUTING_RES_SOCKS_RUNTIME_CACHE_FP="$current_fp"
}

res_socks_ensure_dns_servers_json_cache() {
    local out="[" first=1 line tag server dns_tag dns_server

    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true
    if [[ -n "${ROUTING_RES_SOCKS_RUNTIME_DNS_SERVERS_JSON:-}" ]]; then
        return 0
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS="$RES_SOCKS_RUNTIME_FIELD_SEP" read -r tag server <<<"$line"
        [[ -n "$tag" ]] || continue

        dns_tag="$(res_socks_dns_tag_for_outbound "$tag" 2>/dev/null || true)"
        [[ -n "$dns_tag" ]] || continue

        if res_socks_server_is_ipv6_literal "$server"; then
            dns_server="2001:4860:4860::8888"
        else
            dns_server="8.8.8.8"
        fi

        if (( first == 0 )); then
            out+=","
        fi
        first=0
        out+="{\"tag\":\"$(res_socks_json_escape_string "$dns_tag")\",\"type\":\"https\",\"server\":\"$(res_socks_json_escape_string "$dns_server")\",\"server_port\":443,\"path\":\"/dns-query\",\"tls\":{\"enabled\":true,\"server_name\":\"dns.google\"},\"detour\":\"$(res_socks_json_escape_string "$tag")\"}"
    done <<<"${ROUTING_RES_SOCKS_RUNTIME_NODE_LINES:-}"

    out+="]"
    ROUTING_RES_SOCKS_RUNTIME_DNS_SERVERS_JSON="$out"
}

res_socks_nodes_count() {
    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true
    echo "${ROUTING_RES_SOCKS_RUNTIME_COUNT:-0}"
}

res_socks_first_node_line() {
    jq -r '
        ((.nodes // [])[0] // null)
        | if . == null then empty else
            [
              (.server // ""),
              ((.server_port // "") | tostring),
              (.username // ""),
              (.password // "")
            ] | join("|")
          end
    ' "$RES_SOCKS_NODES_FILE" 2>/dev/null
}

res_socks_next_outbound_tag() {
    local candidate=1 idx=""
    local -a used_indexes=()
    mapfile -t used_indexes < <(
        jq -r --arg prefix "$RES_SOCKS_TAG" '
            [(.nodes // [])[]? | (.tag // "") | select(startswith($prefix)) | sub("^" + $prefix; "") | tonumber?]
            | map(select(. != null))
            | sort
            | .[]
        ' "$RES_SOCKS_NODES_FILE" 2>/dev/null || true
    )
    for idx in "${used_indexes[@]}"; do
        [[ "$idx" =~ ^[0-9]+$ ]] || continue
        if (( idx == candidate )); then
            candidate=$((candidate + 1))
        elif (( idx > candidate )); then
            break
        fi
    done
    echo "${RES_SOCKS_TAG}${candidate}"
}

res_socks_first_outbound_tag() {
    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true
    printf '%s\n' "${ROUTING_RES_SOCKS_RUNTIME_FIRST_TAG:-}"
}

res_socks_nodes_list_lines() {
    jq -r '
        (.nodes // [])[]
        | [
            (.id // ""),
            (.tag // ""),
            (.server // ""),
            ((.server_port // "") | tostring),
            (.username // ""),
            (.password // "")
          ] | @tsv
    ' "$RES_SOCKS_NODES_FILE" 2>/dev/null
}

res_socks_display_label_by_tag() {
    local tag="${1:-}"
    [[ -n "$tag" ]] || return 1
    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true
    [[ -n "${ROUTING_RES_SOCKS_LABEL_CACHE[$tag]+x}" ]] || return 1
    printf '%s\n' "${ROUTING_RES_SOCKS_LABEL_CACHE[$tag]}"
}

res_socks_display_label_colored_by_tag() {
    local tag="${1:-}"
    res_socks_refresh_runtime_cache >/dev/null 2>&1 || true
    if [[ -n "${ROUTING_RES_SOCKS_COLORED_LABEL_CACHE[$tag]+x}" ]]; then
        printf '%s\n' "${ROUTING_RES_SOCKS_COLORED_LABEL_CACHE[$tag]}"
    else
        printf '%s\n' "$(routing_colorize "36;1" "$tag")"
    fi
}
