# Network optimization operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

SERVICE_BASE_OPS_FILE="${SERVICE_BASE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$SERVICE_BASE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SERVICE_BASE_OPS_FILE"
fi

NETWORK_FIREWALL_OPS_FILE="${NETWORK_FIREWALL_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/network_firewall_ops.sh}"
if [[ -f "$NETWORK_FIREWALL_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$NETWORK_FIREWALL_OPS_FILE"
fi

is_bbr_enabled() {
    local cc qdisc
    cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    [[ "$cc" == "bbr" && "$qdisc" == "fq" ]]
}

kernel_supports_bbr() {
    local kernel_ver kernel_major kernel_minor
    kernel_ver="$(uname -r 2>/dev/null | cut -d'-' -f1)"
    kernel_major="$(echo "$kernel_ver" | awk -F'.' '{print $1}')"
    kernel_minor="$(echo "$kernel_ver" | awk -F'.' '{print $2}')"

    [[ "$kernel_major" =~ ^[0-9]+$ ]] || return 1
    [[ "$kernel_minor" =~ ^[0-9]+$ ]] || kernel_minor=0
    if (( kernel_major < 4 || (kernel_major == 4 && kernel_minor < 9) )); then
        return 1
    fi
    return 0
}

get_memory_mb() {
    local mem_mb
    mem_mb="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' | head -n 1)"
    if ! [[ "$mem_mb" =~ ^[0-9]+$ ]]; then
        mem_mb="$(awk '/MemTotal/{printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null | head -n 1)"
    fi
    [[ "$mem_mb" =~ ^[0-9]+$ ]] || mem_mb=1024
    echo "$mem_mb"
}

manage_network_management() {
    while :; do
        ui_clear
        proxy_menu_header "网络管理"
        echo "1. BBR 网络优化"
        echo "2. 服务器防火墙收敛"
        proxy_menu_rule "═"
        echo
        if ! read_prompt choice "选择序号(回车取消): "; then
            return 0
        fi
        [[ -z "$choice" ]] && return 0
        case "$choice" in
            1) manage_network_optimization ;;
            2) manage_firewall_convergence ;;
            *) return 0 ;;
        esac
    done
}

manage_network_optimization() {
    local conf_file="/etc/sysctl.d/99-bbr-proxy.conf"

    ui_clear
    proxy_menu_header "BBR 网络优化"

    if ! kernel_supports_bbr; then
        red "内核版本 $(uname -r) 不支持 BBR (需要 4.9+)"
        pause
        return 1
    fi

    local mem_mb cpu_cores virt_type kernel_ver
    mem_mb="$(get_memory_mb)"
    cpu_cores="$(nproc 2>/dev/null || echo 1)"
    [[ "$cpu_cores" =~ ^[0-9]+$ ]] || cpu_cores=1
    kernel_ver="$(uname -r 2>/dev/null || echo unknown)"

    virt_type="unknown"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt_type="$(systemd-detect-virt 2>/dev/null || echo none)"
    elif grep -qi "hypervisor" /proc/cpuinfo 2>/dev/null; then
        virt_type="KVM/VMware"
    fi

    echo "系统信息"
    proxy_menu_divider
    echo "内核版本: ${kernel_ver} (支持 BBR)"
    echo "内存大小: ${mem_mb}MB"
    echo "CPU 核心: ${cpu_cores}"
    echo "虚拟化类型: ${virt_type}"
    proxy_menu_divider

    local current_cc current_qdisc
    current_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    echo "当前状态"
    echo "拥塞控制: ${current_cc}"
    echo "队列调度: ${current_qdisc}"

    if [[ -f "$conf_file" ]]; then
        local rmem wmem somaxconn file_max
        rmem="$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)"
        wmem="$(sysctl -n net.core.wmem_max 2>/dev/null || echo 0)"
        somaxconn="$(sysctl -n net.core.somaxconn 2>/dev/null || echo 0)"
        file_max="$(sysctl -n fs.file-max 2>/dev/null || echo 0)"
        [[ "$rmem" =~ ^[0-9]+$ ]] || rmem=0
        [[ "$wmem" =~ ^[0-9]+$ ]] || wmem=0
        echo "读缓冲区: $((rmem / 1024 / 1024))MB"
        echo "写缓冲区: $((wmem / 1024 / 1024))MB"
        echo "最大连接队列: ${somaxconn}"
        echo "最大文件句柄: ${file_max}"
    fi

    proxy_menu_divider

    local choice confirm
    if is_bbr_enabled; then
        green "BBR 已启用"
        echo "1. 重新优化 (更新参数)"
        echo "2. 卸载 BBR 优化"
        proxy_menu_rule "═"
        echo
        if ! read_prompt choice "选择序号(回车取消): "; then
            return 0
        fi
        case "$choice" in
            1) ;;
            2)
                yellow "卸载 BBR 优化配置..."
                rm -f "$conf_file"
                if ! sysctl --system >/dev/null 2>&1; then
                    sysctl -p >/dev/null 2>&1 || true
                fi
                green "BBR 优化配置已移除，系统恢复默认设置"
                if command -v proxy_log >/dev/null 2>&1; then
                    proxy_log "INFO" "网络优化: 已卸载 BBR 配置"
                fi
                pause
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    else
        if ! read_prompt confirm "确认开启 BBR 优化? [Y/n]: "; then
            return 0
        fi
        if [[ "$confirm" =~ ^[nN]$ ]]; then
            return 0
        fi
    fi

    yellow "加载 BBR 模块..."
    modprobe tcp_bbr 2>/dev/null || true
    if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        red "BBR 模块不可用，请检查内核配置"
        pause
        return 1
    fi

    local vm_tier rmem_max wmem_max tcp_rmem tcp_wmem somaxconn netdev_backlog file_max conntrack_max
    if (( mem_mb <= 512 )); then
        vm_tier="经典级(<=512MB)"
        rmem_max=8388608; wmem_max=8388608
        tcp_rmem="4096 65536 8388608"; tcp_wmem="4096 65536 8388608"
        somaxconn=32768; netdev_backlog=16384; file_max=262144; conntrack_max=131072
    elif (( mem_mb <= 1024 )); then
        vm_tier="轻量级(512MB-1GB)"
        rmem_max=16777216; wmem_max=16777216
        tcp_rmem="4096 65536 16777216"; tcp_wmem="4096 65536 16777216"
        somaxconn=49152; netdev_backlog=24576; file_max=524288; conntrack_max=262144
    elif (( mem_mb <= 2048 )); then
        vm_tier="标准级(1GB-2GB)"
        rmem_max=33554432; wmem_max=33554432
        tcp_rmem="4096 87380 33554432"; tcp_wmem="4096 65536 33554432"
        somaxconn=65535; netdev_backlog=32768; file_max=1048576; conntrack_max=524288
    elif (( mem_mb <= 4096 )); then
        vm_tier="高性能级(2GB-4GB)"
        rmem_max=67108864; wmem_max=67108864
        tcp_rmem="4096 131072 67108864"; tcp_wmem="4096 87380 67108864"
        somaxconn=65535; netdev_backlog=65535; file_max=2097152; conntrack_max=1048576
    elif (( mem_mb <= 8192 )); then
        vm_tier="企业级(4GB-8GB)"
        rmem_max=134217728; wmem_max=134217728
        tcp_rmem="8192 131072 134217728"; tcp_wmem="8192 87380 134217728"
        somaxconn=65535; netdev_backlog=65535; file_max=4194304; conntrack_max=2097152
    else
        vm_tier="旗舰级(>8GB)"
        rmem_max=134217728; wmem_max=134217728
        tcp_rmem="8192 131072 134217728"; tcp_wmem="8192 87380 134217728"
        somaxconn=65535; netdev_backlog=65535; file_max=8388608; conntrack_max=2097152
    fi

    yellow "应用 ${vm_tier} 优化配置..."
    cat >"$conf_file" <<EOF
# ==============================================================
# TCP/IP & BBR 优化配置 (由 proxy 脚本自动生成)
# 生成时间: $(date)
# 针对硬件: ${mem_mb}MB 内存, ${cpu_cores} 核 CPU (${vm_tier})
# ==============================================================

# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Socket 缓冲区
net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${wmem_max}
net.ipv4.tcp_rmem = ${tcp_rmem}
net.ipv4.tcp_wmem = ${tcp_wmem}

# 连接队列
net.core.somaxconn = ${somaxconn}
net.core.netdev_max_backlog = ${netdev_backlog}
net.ipv4.tcp_max_syn_backlog = ${somaxconn}

# TCP 优化
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 0
net.ipv4.tcp_max_tw_buckets = 180000
net.ipv4.tcp_slow_start_after_idle = 0

# 文件句柄
fs.file-max = ${file_max}

# 内存优化
vm.swappiness = 10
EOF

    if [[ -f /proc/sys/net/ipv4/tcp_fastopen ]]; then
        {
            echo
            echo "# TCP Fast Open"
            echo "net.ipv4.tcp_fastopen = 3"
        } >>"$conf_file"
    fi

    if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
        {
            echo
            echo "# 连接跟踪"
            echo "net.netfilter.nf_conntrack_max = ${conntrack_max}"
        } >>"$conf_file"
    fi

    yellow "应用配置..."
    local sysctl_output
    sysctl_output="$(sysctl -p "$conf_file" 2>&1)" || true

    if echo "$sysctl_output" | grep -Eq "Invalid argument|Permission denied"; then
        red "配置应用失败"
        echo "$sysctl_output"
        pause
        return 1
    fi
    if echo "$sysctl_output" | grep -q "unknown key"; then
        yellow "部分参数不支持（已忽略）"
    fi

    green "配置已生效"
    proxy_menu_divider
    local new_cc new_qdisc
    new_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    new_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    echo "优化结果"
    echo "配置档位: ${vm_tier}"
    echo "拥塞控制: ${new_cc}"
    echo "队列调度: ${new_qdisc}"
    echo "读缓冲区: $((rmem_max / 1024 / 1024))MB"
    echo "写缓冲区: $((wmem_max / 1024 / 1024))MB"
    echo "最大连接队列: ${somaxconn}"
    echo "最大文件句柄: ${file_max}"
    proxy_menu_divider

    if is_bbr_enabled; then
        green "BBR 优化已成功启用"
        if command -v proxy_log >/dev/null 2>&1; then
            proxy_log "INFO" "网络优化: BBR 已启用 (${vm_tier})"
        fi
    else
        yellow "BBR 可能未完全生效，请检查系统日志"
        if command -v proxy_log >/dev/null 2>&1; then
            proxy_log "WARN" "网络优化: BBR 未完全生效"
        fi
    fi
    pause
}
