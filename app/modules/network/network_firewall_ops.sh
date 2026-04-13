# Firewall convergence operations for shell-proxy management.

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

NETWORK_FIREWALL_CUSTOM_PORTS_FILE="${WORK_DIR}/firewall-ports.json"
NETWORK_FIREWALL_DOMAIN_FILE="${WORK_DIR}/.domain"

network_firewall_backend() {
    if command -v nft >/dev/null 2>&1 && nft list tables >/dev/null 2>&1; then
        echo "nft"
        return 0
    fi
    if command -v iptables >/dev/null 2>&1 && iptables -L >/dev/null 2>&1; then
        echo "iptables"
        return 0
    fi
    echo "unsupported"
}

network_firewall_ip_family_mode() {
    local backend="${1:-$(network_firewall_backend)}"
    case "$backend" in
        nft) printf '%s\n' "IPv4/IPv6" ;;
        iptables)
            if command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1; then
                printf '%s\n' "IPv4/IPv6"
            else
                printf '%s\n' "IPv4"
            fi
            ;;
        *) printf '%s\n' "-" ;;
    esac
}

network_firewall_backend_display() {
    local backend="${1:-$(network_firewall_backend)}"
    local families
    families="$(network_firewall_ip_family_mode "$backend")"
    case "$backend" in
        nft) printf '%s\n' "nftables (${families})" ;;
        iptables)
            if [[ "$families" == "IPv4/IPv6" ]]; then
                printf '%s\n' "iptables/ip6tables (${families})"
            else
                printf '%s\n' "iptables (${families})"
            fi
            ;;
        *) printf '%s\n' "unsupported" ;;
    esac
}

network_firewall_collect_ssh_ports() {
    {
        if command -v sshd >/dev/null 2>&1; then
            sshd -T 2>/dev/null | awk '/^port /{print $2}'
        fi
        grep -hE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}'
        ss -lntp 2>/dev/null | awk '/sshd/ {print $4}' | sed -E 's/.*:([0-9]+)$/\1/'
        echo "22"
    } | awk '/^[0-9]+$/' | sort -n -u
}

network_firewall_collect_caddy_ports() {
    if [[ -f "$CADDY_FILE" || -f "$NETWORK_FIREWALL_DOMAIN_FILE" ]]; then
        printf '%s\n' "80" "443" | awk '/^[0-9]+$/' | sort -n -u
    fi
}

network_firewall_custom_ports_file() {
    printf '%s\n' "$NETWORK_FIREWALL_CUSTOM_PORTS_FILE"
}

network_firewall_custom_ports_rows() {
    local file
    file="$(network_firewall_custom_ports_file)"
    [[ -f "$file" ]] || return 0

    jq -r '.ports[]? | [((.proto // "tcp") | ascii_downcase), (.port // 0)] | @tsv' "$file" 2>/dev/null \
        | while IFS=$'\t' read -r proto port; do
            [[ "$port" =~ ^[0-9]+$ ]] || continue
            (( port >= 1 && port <= 65535 )) || continue
            case "$proto" in
                udp) proto="udp" ;;
                *) proto="tcp" ;;
            esac
            printf '%s\t%s\n' "$proto" "$port"
        done \
        | LC_ALL=C sort -t $'\t' -k2,2n -k1,1 -u
}

network_firewall_split_custom_port_token() {
    local token="${1:-}" sep="${2:-/}" left="" right="" extra=""
    IFS="$sep" read -r left right extra <<< "$token"
    [[ -z "$extra" && -n "$left" && -n "$right" ]] || return 1
    left="$(printf '%s' "$left" | tr -d '[:space:]')"
    right="$(printf '%s' "$right" | tr -d '[:space:]')"

    if [[ "$left" =~ ^[0-9]+$ ]] && (( left >= 1 && left <= 65535 )); then
        printf '%s|%s\n' "$left" "$right"
        return 0
    fi
    if [[ "$right" =~ ^[0-9]+$ ]] && (( right >= 1 && right <= 65535 )); then
        printf '%s|%s\n' "$right" "$left"
        return 0
    fi
    return 1
}

network_firewall_parse_custom_port_protos() {
    local value
    value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$value" in
        tcp)
            printf '%s\n' "tcp"
            ;;
        udp)
            printf '%s\n' "udp"
            ;;
        tcp+udp|udp+tcp|both)
            printf '%s\n' "tcp"
            printf '%s\n' "udp"
            ;;
        *)
            return 1
            ;;
    esac
}

network_firewall_parse_custom_port_token() {
    local token="${1:-}" split_result="" port="" proto_spec="" proto=""
    token="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$token" ]] || return 0

    split_result="$(network_firewall_split_custom_port_token "$token" "/" 2>/dev/null || true)"
    [[ -n "$split_result" ]] || split_result="$(network_firewall_split_custom_port_token "$token" ":" 2>/dev/null || true)"
    if [[ -z "$split_result" ]]; then
        if ! [[ "$token" =~ ^[0-9]+$ ]] || (( token < 1 || token > 65535 )); then
            return 1
        fi
        printf 'tcp\t%s\n' "$token"
        return 0
    fi

    IFS='|' read -r port proto_spec <<< "$split_result"
    while IFS= read -r proto; do
        [[ -n "$proto" ]] || continue
        printf '%s\t%s\n' "$proto" "$port"
    done < <(network_firewall_parse_custom_port_protos "$proto_spec")
}

network_firewall_parse_custom_ports_input() {
    local input="${1:-}" token="" parsed="" parsed_token=""
    input="${input//,/$'\n'}"
    input="${input//，/$'\n'}"
    input="${input//;/$'\n'}"
    input="${input//；/$'\n'}"
    input="${input//$'\t'/$'\n'}"
    input="${input//$'\r'/$'\n'}"
    while IFS= read -r token; do
        [[ -n "$token" ]] || continue
        parsed_token="$(network_firewall_parse_custom_port_token "$token")" || return 1
        [[ -n "$parsed_token" ]] && parsed+="${parsed_token}"$'\n'
    done < <(printf '%s\n' "$input")
    [[ -n "$parsed" ]] || return 0
    printf '%s' "$parsed" | LC_ALL=C sort -t $'\t' -k2,2n -k1,1 -u
}

network_firewall_save_custom_ports_rows() {
    local file tmp_file line proto port
    local -a rows=()
    file="$(network_firewall_custom_ports_file)"
    mapfile -t rows

    if ((${#rows[@]} == 0)); then
        rm -f "$file" 2>/dev/null || true
        return 0
    fi

    mkdir -p "$(dirname "$file")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)" || return 1
    {
        for line in "${rows[@]}"; do
            [[ -n "$line" ]] || continue
            IFS=$'\t' read -r proto port <<< "$line"
            [[ "$port" =~ ^[0-9]+$ ]] || continue
            printf '{"proto":"%s","port":%s}\n' "$proto" "$port"
        done
    } | jq -s '{ports: .}' >"$tmp_file" 2>/dev/null || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    mv "$tmp_file" "$file"
}

network_firewall_format_custom_ports() {
    local -A protos_by_port=()
    local -a order=()
    local line proto port result="" token=""

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r proto port <<< "$line"
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        if [[ -z "${protos_by_port[$port]+x}" ]]; then
            order+=("$port")
            protos_by_port[$port]=""
        fi
        case ",${protos_by_port[$port]}," in
            *",${proto},"*) ;;
            *)
                if [[ -n "${protos_by_port[$port]}" ]]; then
                    protos_by_port[$port]+=",${proto}"
                else
                    protos_by_port[$port]="${proto}"
                fi
                ;;
        esac
    done < <(network_firewall_custom_ports_rows)

    ((${#order[@]} > 0)) || return 0
    IFS=$'\n' order=($(printf '%s\n' "${order[@]}" | sort -n))
    unset IFS

    for port in "${order[@]}"; do
        case "${protos_by_port[$port]}" in
            tcp,udp|udp,tcp)
                token="${port}/tcp+udp"
                ;;
            udp)
                token="${port}/udp"
                ;;
            *)
                token="${port}/tcp"
                ;;
        esac
        if [[ -n "$result" ]]; then
            result+=", ${token}"
        else
            result="${token}"
        fi
    done

    printf '%s\n' "$result"
}

network_firewall_managed_rules_active() {
    local backend="${1:-$(network_firewall_backend)}"
    case "$backend" in
        nft)
            nft list table inet proxy_firewall >/dev/null 2>&1
            ;;
        iptables)
            iptables -L PROXY_FIREWALL_INPUT >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

network_firewall_desired_port_rows() {
    local conf_file="${1:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"

    if declare -F proxy_protocol_inventory_cache_refresh >/dev/null 2>&1; then
        proxy_protocol_inventory_cache_refresh "$conf_file"
    fi

    local line proto idx tag port desc udp_enabled
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r proto idx tag port desc <<<"$line"
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        case "$proto" in
            vless|trojan|anytls)
                printf 'tcp\t%s\t%s\n' "$port" "$proto"
                ;;
            tuic)
                printf 'udp\t%s\t%s\n' "$port" "$proto"
                ;;
            ss)
                printf 'tcp\t%s\t%s\n' "$port" "$proto"
                printf 'udp\t%s\t%s\n' "$port" "$proto"
                ;;
            snell)
                printf 'tcp\t%s\t%s\n' "$port" "snell-v5"
                udp_enabled="$(grep '^udp' "$SNELL_CONF" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')"
                [[ "${udp_enabled,,}" == "true" ]] && printf 'udp\t%s\t%s\n' "$port" "snell-v5"
                ;;
        esac
    done <<< "${PROXY_PROTOCOL_INVENTORY_ROWS:-}"

    if declare -F shadowtls_binding_lines >/dev/null 2>&1; then
        local st_line st_service st_listen st_target st_backend st_sni st_pass
        while IFS= read -r st_line; do
            [[ -n "$st_line" ]] || continue
            IFS='|' read -r st_service st_listen st_target st_backend st_sni st_pass <<<"$st_line"
            [[ "$st_listen" =~ ^[0-9]+$ ]] || continue
            printf 'tcp\t%s\t%s\n' "$st_listen" "${SHADOWTLS_DISPLAY_NAME}"
        done < <(shadowtls_binding_lines "$conf_file")
    fi

    local port_value
    while IFS= read -r port_value; do
        [[ "$port_value" =~ ^[0-9]+$ ]] || continue
        printf 'tcp\t%s\t%s\n' "$port_value" "ssh"
    done < <(network_firewall_collect_ssh_ports)

    while IFS= read -r port_value; do
        [[ "$port_value" =~ ^[0-9]+$ ]] || continue
        printf 'tcp\t%s\t%s\n' "$port_value" "caddy"
    done < <(network_firewall_collect_caddy_ports)

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r proto port label <<< "$line"
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        printf '%s\t%s\t%s\n' "$proto" "$port" "custom"
    done < <(network_firewall_custom_ports_rows)
}

network_firewall_desired_port_csv() {
    local target_proto="${1:-tcp}" conf_file="${2:-}"
    local -A seen=()
    local -a ports=()
    local line proto port label
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r proto port label <<<"$line"
        [[ "$proto" == "$target_proto" && "$port" =~ ^[0-9]+$ ]] || continue
        [[ -n "${seen[$port]+x}" ]] && continue
        seen["$port"]=1
        ports+=("$port")
    done < <(network_firewall_desired_port_rows "$conf_file")

    ((${#ports[@]} > 0)) || return 0
    printf '%s\n' "${ports[@]}" | sort -n -u | paste -sd, -
}

network_firewall_render_desired_ports() {
    local conf_file="${1:-}"
    local -A labels=()
    local -a order=()
    local line proto port label key current
    local c_reset="" c_proto="" c_port="" c_label=""

    if [[ -t 1 ]]; then
        c_reset=$'\033[0m'
        c_proto=$'\033[36;1m'
        c_port=$'\033[32;1m'
        c_label=$'\033[33;1m'
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r proto port label <<<"$line"
        [[ "$port" =~ ^[0-9]+$ && -n "$proto" ]] || continue
        key="${proto}|${port}"
        if [[ -z "${labels[$key]+x}" ]]; then
            labels["$key"]="$label"
            order+=("$key")
            continue
        fi
        current=",${labels[$key]},"
        [[ "$current" == *",${label},"* ]] && continue
        labels["$key"]+=",${label}"
    done < <(network_firewall_desired_port_rows "$conf_file")

    if ((${#order[@]} == 0)); then
        echo "• 无"
        return 0
    fi

    local item
    for item in "${order[@]}"; do
        proto="${item%%|*}"
        port="${item##*|}"
        printf '• %b/%b [%b]\n' \
            "${c_proto}${proto}${c_reset}" \
            "${c_port}${port}${c_reset}" \
            "${c_label}${labels[$item]}${c_reset}"
    done
}

network_firewall_apply_nft() {
    local tcp_ports="${1:-}" udp_ports="${2:-}"
    local table_name="proxy_firewall"
    local tmp_rules
    tmp_rules="$(mktemp)"

    {
        echo "table inet ${table_name} {"
        echo "  chain input {"
        echo "    type filter hook input priority -10; policy accept;"
        echo "    ct state established,related accept"
        echo "    iifname \"lo\" accept"
        echo "    ip protocol icmp accept"
        echo "    ip6 nexthdr ipv6-icmp accept"
        if [[ -n "$tcp_ports" ]]; then
            echo "    tcp dport { $(printf '%s' "$tcp_ports" | sed 's/,/, /g') } accept"
        fi
        if [[ -n "$udp_ports" ]]; then
            echo "    udp dport { $(printf '%s' "$udp_ports" | sed 's/,/, /g') } accept"
        fi
        echo "    counter drop"
        echo "  }"
        echo "}"
    } > "$tmp_rules"

    nft delete table inet "$table_name" >/dev/null 2>&1 || true
    if nft -f "$tmp_rules" >/dev/null 2>&1; then
        rm -f "$tmp_rules"
        return 0
    fi

    rm -f "$tmp_rules"
    return 1
}

network_firewall_apply_iptables_ports() {
    local chain_name="$1" proto_name="$2" ports_csv="$3" cmd_bin="$4"
    [[ -n "$ports_csv" ]] || return 0
    local port_value
    IFS=',' read -r -a __ports <<<"$ports_csv"
    for port_value in "${__ports[@]}"; do
        [[ "$port_value" =~ ^[0-9]+$ ]] || continue
        "$cmd_bin" -A "$chain_name" -p "$proto_name" --dport "$port_value" -j ACCEPT
    done
}

network_firewall_apply_iptables() {
    local tcp_ports="${1:-}" udp_ports="${2:-}"
    local chain_v4="PROXY_FIREWALL_INPUT"
    local chain_v6="PROXY_FIREWALL_INPUT6"

    iptables -N "$chain_v4" >/dev/null 2>&1 || true
    iptables -F "$chain_v4"
    iptables -C INPUT -j "$chain_v4" >/dev/null 2>&1 || iptables -I INPUT 1 -j "$chain_v4"
    iptables -A "$chain_v4" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A "$chain_v4" -i lo -j ACCEPT
    iptables -A "$chain_v4" -p icmp -j ACCEPT
    network_firewall_apply_iptables_ports "$chain_v4" tcp "$tcp_ports" iptables
    network_firewall_apply_iptables_ports "$chain_v4" udp "$udp_ports" iptables
    iptables -A "$chain_v4" -j DROP

    if command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1; then
        ip6tables -N "$chain_v6" >/dev/null 2>&1 || true
        ip6tables -F "$chain_v6"
        ip6tables -C INPUT -j "$chain_v6" >/dev/null 2>&1 || ip6tables -I INPUT 1 -j "$chain_v6"
        ip6tables -A "$chain_v6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        ip6tables -A "$chain_v6" -i lo -j ACCEPT
        ip6tables -A "$chain_v6" -p ipv6-icmp -j ACCEPT
        network_firewall_apply_iptables_ports "$chain_v6" tcp "$tcp_ports" ip6tables
        network_firewall_apply_iptables_ports "$chain_v6" udp "$udp_ports" ip6tables
        ip6tables -A "$chain_v6" -j DROP
    fi
}

network_firewall_release_nft() {
    nft delete table inet proxy_firewall >/dev/null 2>&1 || true
}

network_firewall_release_iptables_chain() {
    local cmd_bin="${1:-}" chain_name="${2:-}"
    [[ -n "$cmd_bin" && -n "$chain_name" ]] || return 1
    command -v "$cmd_bin" >/dev/null 2>&1 || return 0
    "$cmd_bin" -L "$chain_name" >/dev/null 2>&1 || return 0
    while "$cmd_bin" -C INPUT -j "$chain_name" >/dev/null 2>&1; do
        "$cmd_bin" -D INPUT -j "$chain_name" >/dev/null 2>&1 || break
    done
    "$cmd_bin" -F "$chain_name" >/dev/null 2>&1 || true
    "$cmd_bin" -X "$chain_name" >/dev/null 2>&1 || true
}

network_firewall_release_iptables() {
    network_firewall_release_iptables_chain iptables PROXY_FIREWALL_INPUT
    if command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1; then
        network_firewall_release_iptables_chain ip6tables PROXY_FIREWALL_INPUT6
    fi
}

network_firewall_show_current_rules() {
    local backend="${1:-$(network_firewall_backend)}"
    case "$backend" in
        nft)
            nft list table inet proxy_firewall 2>/dev/null || echo "未检测到 proxy_firewall 规则表"
            ;;
        iptables)
            iptables -S PROXY_FIREWALL_INPUT 2>/dev/null || echo "未检测到 PROXY_FIREWALL_INPUT"
            if command -v ip6tables >/dev/null 2>&1; then
                echo
                ip6tables -S PROXY_FIREWALL_INPUT6 2>/dev/null || true
            fi
            ;;
        *)
            echo "当前系统未检测到可用的 nftables/iptables 后端。"
            ;;
    esac
}

manage_firewall_convergence() {
    local conf_file backend backend_display tcp_ports udp_ports yn choice custom_input custom_ports convergence_status
    conf_file="$(get_conf_file 2>/dev/null || true)"
    backend="$(network_firewall_backend)"
    backend_display="$(network_firewall_backend_display "$backend")"

    while :; do
        tcp_ports="$(network_firewall_desired_port_csv "tcp" "$conf_file")"
        udp_ports="$(network_firewall_desired_port_csv "udp" "$conf_file")"
        custom_ports="$(network_firewall_format_custom_ports 2>/dev/null || true)"
        convergence_status="未应用"
        network_firewall_managed_rules_active "$backend" && convergence_status="已应用"
        ui_clear
        proxy_menu_header "防火墙收敛"
        echo "收敛策略:"
        echo "1. 自动检测当前入站协议端口并放行"
        echo "2. 自动保留 SSH / ACME / 自定义端口"
        echo "3. 除必要端口外，其余 IPv4/IPv6 入站默认关闭"
        proxy_menu_divider
        echo "受管状态: ${convergence_status}"
        echo "防火墙后端: ${backend_display}"
        echo "自定义端口: ${custom_ports:-无}"
        echo "目标开放端口:"
        network_firewall_render_desired_ports "$conf_file"
        proxy_menu_divider
        echo "  1. 收敛防火墙（仅开放以上端口）"
        echo "  2. 释放防火墙收敛"
        echo "  3. 设置自定义端口"
        echo "  4. 查看当前防火墙规则"
        proxy_menu_rule "═"
        if ! read_prompt choice "选择序号(回车取消): "; then
            return 0
        fi
        [[ -z "$choice" ]] && return 0

        case "$choice" in
            1)
                if [[ "$backend" == "unsupported" ]]; then
                    red "未检测到可用的 nftables/iptables，无法执行防火墙收敛。"
                    continue
                fi
                yellow "即将按检测结果重写受管防火墙规则。"
                yellow "将放行检测到的入站端口、SSH 端口、ACME 端口和自定义端口；其他入站默认关闭。"
                if ! read_prompt yn "确认应用? [y/N]: "; then
                    continue
                fi
                [[ "${yn,,}" == "y" ]] || continue

                if [[ "$backend" == "nft" ]]; then
                    if network_firewall_apply_nft "$tcp_ports" "$udp_ports"; then
                        green "防火墙收敛已应用 (nftables)"
                    else
                        red "nftables 防火墙收敛失败"
                    fi
                else
                    if network_firewall_apply_iptables "$tcp_ports" "$udp_ports"; then
                        green "防火墙收敛已应用 (iptables)"
                    else
                        red "iptables 防火墙收敛失败"
                    fi
                fi
                ;;
            2)
                if [[ "$backend" == "unsupported" ]]; then
                    red "未检测到可用的 nftables/iptables，无法释放防火墙收敛。"
                    continue
                fi
                if ! read_prompt yn "确认释放受管防火墙规则? [y/N]: "; then
                    continue
                fi
                [[ "${yn,,}" == "y" ]] || continue
                if [[ "$backend" == "nft" ]]; then
                    network_firewall_release_nft
                else
                    network_firewall_release_iptables
                fi
                green "防火墙收敛已释放"
                ;;
            3)
                if ! read_prompt custom_input "自定义端口(格式 443、53/udp、8443/tcp+udp，留空清空): "; then
                    continue
                fi
                if [[ -z "${custom_input//[[:space:]]/}" ]]; then
                    if network_firewall_save_custom_ports_rows <<'EOF'
EOF
                    then
                        green "自定义端口已清空"
                    else
                        red "自定义端口清空失败"
                    fi
                    continue
                fi
                if network_firewall_parse_custom_ports_input "$custom_input" | network_firewall_save_custom_ports_rows; then
                    green "自定义端口已更新"
                else
                    red "自定义端口格式无效"
                fi
                ;;
            4)
                network_firewall_show_current_rules "$backend"
                ;;
            *)
                return 0
                ;;
        esac
    done
}
