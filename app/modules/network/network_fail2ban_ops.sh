# Fail2ban protection operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

NETWORK_FAIL2BAN_SSHD_JAIL_FILE="/etc/fail2ban/jail.d/sshd.local"

network_fail2ban_service_installed() {
    systemctl cat fail2ban >/dev/null 2>&1
}

network_fail2ban_service_running() {
    [[ "$(systemctl is-active fail2ban 2>/dev/null || true)" == "active" ]]
}

network_fail2ban_install() {
    network_fail2ban_service_installed && return 0

    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y fail2ban
        return $?
    fi
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y fail2ban
        return $?
    fi
    if command -v yum >/dev/null 2>&1; then
        yum install -y fail2ban
        return $?
    fi

    red "当前系统缺少可用的软件包管理器，无法安装 fail2ban。"
    return 1
}

network_fail2ban_write_sshd_jail() {
    mkdir -p "$(dirname "$NETWORK_FAIL2BAN_SSHD_JAIL_FILE")" >/dev/null 2>&1 || return 1
    cat >"$NETWORK_FAIL2BAN_SSHD_JAIL_FILE" <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 5
bantime = 86400
findtime = 600
EOF
}

network_fail2ban_extract_status_field() {
    local prefix="${1:-}" input="${2:-}" line=""
    [[ -n "$prefix" ]] || return 1
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed -E 's/^[|` -]+//')"
        [[ "$line" == "${prefix}"* ]] || continue
        printf '%s\n' "${line#${prefix}}"
        return 0
    done <<< "$input"
    return 1
}

network_fail2ban_show_status() {
    local service_status="未安装"
    local jail_status="未启用"
    local jail_output="" current_banned="" total_banned="" banned_ips="" max_retry="" ban_time="" find_time=""

    ui_clear
    proxy_menu_header "fail2ban 防护"

    if network_fail2ban_service_installed; then
        if network_fail2ban_service_running; then
            service_status="运行中"
        else
            service_status="已停止"
        fi
    fi

    echo "服务状态: ${service_status}"

    if network_fail2ban_service_running && command -v fail2ban-client >/dev/null 2>&1; then
        jail_output="$(fail2ban-client status sshd 2>/dev/null || true)"
        if [[ -n "$jail_output" ]]; then
            jail_status="已启用"
            current_banned="$(network_fail2ban_extract_status_field "Currently banned:" "$jail_output" 2>/dev/null || true)"
            total_banned="$(network_fail2ban_extract_status_field "Total banned:" "$jail_output" 2>/dev/null || true)"
            banned_ips="$(network_fail2ban_extract_status_field "Banned IP list:" "$jail_output" 2>/dev/null || true)"
            max_retry="$(fail2ban-client get sshd maxretry 2>/dev/null || true)"
            ban_time="$(fail2ban-client get sshd bantime 2>/dev/null || true)"
            find_time="$(fail2ban-client get sshd findtime 2>/dev/null || true)"
        fi
    fi

    echo "SSH Jail: ${jail_status}"
    [[ -n "$max_retry" ]] && echo "最大重试: ${max_retry}"
    [[ -n "$ban_time" ]] && echo "封禁时长: ${ban_time}s"
    [[ -n "$find_time" ]] && echo "检测时窗: ${find_time}s"
    [[ -n "$current_banned" ]] && echo "当前封禁: ${current_banned}"
    [[ -n "$total_banned" ]] && echo "累计封禁: ${total_banned}"
    if [[ -n "$banned_ips" ]]; then
        local banned_ip=""
        echo "封禁 IP:"
        for banned_ip in $banned_ips; do
            printf '  %s\n' "$banned_ip"
        done
    fi
    proxy_menu_divider
}

network_fail2ban_enable() {
    network_fail2ban_install || return 1
    network_fail2ban_write_sshd_jail || return 1
    systemctl enable --now fail2ban >/dev/null 2>&1 || return 1
    if command -v fail2ban-client >/dev/null 2>&1; then
        fail2ban-client reload >/dev/null 2>&1 || true
    fi
}

network_fail2ban_disable() {
    network_fail2ban_service_installed || return 0
    systemctl disable --now fail2ban >/dev/null 2>&1 || return 1
}

manage_fail2ban_protection() {
    local choice="" yn=""
    while :; do
        network_fail2ban_show_status
        echo "  1. 查看状态"
        echo "  2. 开启防护"
        echo "  3. 关闭防护"
        proxy_menu_rule "═"
        if ! read_prompt choice "选择序号(回车取消): "; then
            return 0
        fi
        [[ -z "$choice" ]] && return 0

        case "$choice" in
            1)
                continue
                ;;
            2)
                if ! read_prompt yn "确认开启 fail2ban SSH 防护? [y/N]: "; then
                    continue
                fi
                [[ "${yn,,}" == "y" ]] || continue
                if network_fail2ban_enable; then
                    green "fail2ban 已启用"
                else
                    red "fail2ban 启用失败"
                fi
                ;;
            3)
                if ! read_prompt yn "确认关闭 fail2ban 防护? [y/N]: "; then
                    continue
                fi
                [[ "${yn,,}" == "y" ]] || continue
                if network_fail2ban_disable; then
                    green "fail2ban 已停止并禁用"
                else
                    red "fail2ban 关闭失败"
                fi
                ;;
            *)
                return 0
                ;;
        esac
    done
}
