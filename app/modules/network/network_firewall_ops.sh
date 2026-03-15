# Firewall convergence operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

PROTOCOL_RUNTIME_OPS_FILE="${PROTOCOL_RUNTIME_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_runtime_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_OPS_FILE"
fi

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
    echo "80" | awk '/^[0-9]+$/' | sort -n -u
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
    local conf_file backend backend_display tcp_ports udp_ports yn
    conf_file="$(get_conf_file 2>/dev/null || true)"
    backend="$(network_firewall_backend)"
    backend_display="$(network_firewall_backend_display "$backend")"
    tcp_ports="$(network_firewall_desired_port_csv "tcp" "$conf_file")"
    udp_ports="$(network_firewall_desired_port_csv "udp" "$conf_file")"

    while :; do
        ui_clear
        proxy_menu_header "服务器防火墙收敛"
        echo "收敛策略:"
        echo "1. 自动检测当前入站协议端口并放行"
        echo "2. 协议端口变更后可重复执行以更新"
        echo "3. 自动保留 SSH / Caddy 等管理端口（IPv4/IPv6 同步）"
        echo "4. 除必要端口外，其余 IPv4/IPv6 入站默认关闭"
        proxy_menu_divider
        echo "防火墙后端: ${backend_display}"
        echo "目标开放端口:"
        network_firewall_render_desired_ports "$conf_file"
        proxy_menu_divider
        echo "1. 应用/更新防火墙收敛"
        echo "2. 查看当前防火墙规则"
        proxy_menu_rule "═"
        if ! read_prompt choice "选择序号(回车取消): "; then
            return 0
        fi
        [[ -z "$choice" ]] && return 0

        case "$choice" in
            1)
                if [[ "$backend" == "unsupported" ]]; then
                    red "未检测到可用的 nftables/iptables，无法执行防火墙收敛。"
                    pause
                    continue
                fi
                yellow "即将按检测结果重写受管防火墙规则。"
                yellow "将放行检测到的入站端口、SSH 端口，以及 Caddy 所需端口；其他入站默认关闭。"
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
                pause
                ;;
            2)
                network_firewall_show_current_rules "$backend"
                pause
                ;;
            *)
                return 0
                ;;
        esac
    done
}
