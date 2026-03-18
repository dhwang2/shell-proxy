# Service and system operation functions for shell-proxy management.

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

SERVICE_BASE_OPS_FILE="${SERVICE_BASE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$SERVICE_BASE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SERVICE_BASE_OPS_FILE"
fi

version_gt() {
    # Return 0 if $1 > $2 (semver-like, dot-separated integers).
    local a="$1" b="$2"
    [[ -z "$a" || -z "$b" ]] && return 1
    local IFS=.
    local -a va vb
    read -r -a va <<<"$a"
    read -r -a vb <<<"$b"
    local i max
    max=${#va[@]}
    (( ${#vb[@]} > max )) && max=${#vb[@]}
    for ((i=0; i<max; i++)); do
        local ai="${va[i]:-0}"
        local bi="${vb[i]:-0}"
        [[ "$ai" =~ ^[0-9]+$ ]] || ai=0
        [[ "$bi" =~ ^[0-9]+$ ]] || bi=0
        if (( ai > bi )); then return 0; fi
        if (( ai < bi )); then return 1; fi
    done
    return 1
}

github_latest_release_version() {
    local repo="$1" # owner/name
    local cache_file="${2:-}"
    local fallback_version="${3:-}"
    resolve_latest_github_release_version "$repo" "$cache_file" "$fallback_version"
}

current_singbox_version() {
    if [[ -x "$BIN_FILE" ]]; then
        "$BIN_FILE" version 2>/dev/null | awk '{print $3}' | head -n 1
    fi
}

current_shadowtls_version() {
    if [[ -x "$ST_BIN" ]]; then
        "$ST_BIN" --version 2>&1 | awk '{print $NF}' | head -n 1 | sed 's/^v//'
    fi
}

current_caddy_version() {
    if [[ -x "$CADDY_BIN" ]]; then
        "$CADDY_BIN" version 2>/dev/null | awk '{print $1}' | head -n 1 | sed 's/^v//'
    fi
}

current_snell_version() {
    if [[ -x "$SNELL_BIN" ]]; then
        # snell-server 版本信息通常输出到 stderr
        "$SNELL_BIN" -v 2>&1 | sed -n 's/.*snell-server v\([0-9.]\+\).*/\1/p' | head -n 1
    fi
}

shadowtls_service_names() {
    proxy_shadowtls_service_names
}

shadowtls_operate_all() {
    local action="$1"
    if [[ "$action" == "status" ]]; then
        proxy_operate_shadowtls_services "$action" "no-pager"
    else
        proxy_operate_shadowtls_services "$action"
    fi
}

update_singbox_core() {
    local latest="$1"
    [[ -z "$latest" ]] && return 1

    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) red "不支持的架构: $arch"; return 1 ;;
    esac

    local tmp="/tmp/proxy-update"
    rm -rf "$tmp"
    mkdir -p "$tmp"

    local filename="sing-box-${latest}-linux-${arch}.tar.gz"
    local url="https://github.com/SagerNet/sing-box/releases/download/v${latest}/${filename}"
    curl -fsSL --retry 3 --retry-delay 1 -o "${tmp}/${filename}" "$url" || return 1
    tar -zxf "${tmp}/${filename}" -C "$tmp" || return 1
    local extracted
    extracted="$(find "$tmp" -name sing-box -type f | head -n 1)"
    [[ -z "$extracted" || ! -f "$extracted" ]] && return 1

    install -m 755 "$extracted" "$BIN_FILE"
    rm -rf "$tmp"

    if systemctl is-active --quiet sing-box 2>/dev/null; then
        systemctl restart sing-box || true
    fi
    return 0
}

update_shadowtls_core() {
    local latest="$1"
    [[ -z "$latest" ]] && return 1

    local arch
    arch="$(uname -m)"
    local st_arch="x86_64-unknown-linux-musl"
    case "$arch" in
        x86_64|amd64) st_arch="x86_64-unknown-linux-musl" ;;
        aarch64|arm64) st_arch="aarch64-unknown-linux-musl" ;;
        *) red "不支持的架构: $arch"; return 1 ;;
    esac

    local tmp="/tmp/proxy-update"
    rm -rf "$tmp"
    mkdir -p "$tmp"

    local filename="shadow-tls-${st_arch}"
    local url="https://github.com/ihciah/shadow-tls/releases/download/v${latest}/${filename}"
    curl -fsSL --retry 3 --retry-delay 1 -o "${tmp}/${filename}" "$url" || return 1
    install -m 755 "${tmp}/${filename}" "$ST_BIN"
    rm -rf "$tmp"

    local st_service
    while IFS= read -r st_service; do
        [[ -n "$st_service" ]] || continue
        if systemctl is-active --quiet "$st_service" 2>/dev/null; then
            systemctl restart "$st_service" || true
        fi
    done < <(shadowtls_service_names)
    return 0
}

update_caddy_core() {
    local latest="$1"
    [[ -z "$latest" ]] && return 1

    local arch
    arch="$(detect_release_arch)" || {
        red "不支持的架构: $(uname -m)"
        return 1
    }

    local tmp="/tmp/proxy-update"
    rm -rf "$tmp"
    mkdir -p "$tmp"

    local filename="caddy_${latest}_linux_${arch}.tar.gz"
    download_caddy_release_archive "$latest" "$arch" "${tmp}/${filename}" || return 1
    tar -zxf "${tmp}/${filename}" -C "$tmp" caddy >/dev/null 2>&1 || return 1
    install -m 755 "${tmp}/caddy" "$CADDY_BIN"
    rm -rf "$tmp"

    if systemctl is-active --quiet caddy-sub 2>/dev/null; then
        systemctl restart caddy-sub || true
    fi
    return 0
}

proxy_cache_purge_all() {
    rm -rf "${CACHE_DIR}" 2>/dev/null || true
    rm -rf "${TEMP_DIR}/cache" "${TEMP_DIR}/tasks" 2>/dev/null || true
}

uninstall_service() {
    ui_clear
    proxy_menu_header "卸载服务"
    yellow "⚠️ 即将删除以下所有组件："
    echo "[1] 核心程序:"
    echo "  - $BIN_FILE (sing-box)"
    echo "  - $SNELL_BIN (snell-v5)"
    echo "  - $ST_BIN (shadow-tls-v3)"
    echo "  - $CADDY_BIN (caddy)"
    echo "[2] Systemd 服务:"
    echo "  - $SERVICE_FILE"
    echo "  - $SNELL_SERVICE_FILE"
    echo "  - $ST_SERVICE_FILE"
    echo "  - /etc/systemd/system/shadow-tls-*.service"
    echo "  - $CADDY_SERVICE_FILE"
    echo "  - $WATCHDOG_SERVICE_FILE"
    echo "[3] 配置文件与数据:"
    echo "  - $WORK_DIR (包含 conf, logs, subscription, caddy 证书/acme 数据)"
    echo "  - /usr/bin/sproxy (快捷指令)"
    echo "  - /usr/bin/proxy (旧快捷指令兼容清理)"
    proxy_menu_divider

    read -p "确认彻底卸载? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && return

    systemctl stop sing-box snell-v5 caddy-sub proxy-watchdog 2>/dev/null
    systemctl disable sing-box snell-v5 caddy-sub proxy-watchdog 2>/dev/null
    shadowtls_operate_all "stop" || true
    local st_service
    while IFS= read -r st_service; do
        [[ -n "$st_service" ]] || continue
        systemctl disable "$st_service" 2>/dev/null || true
    done < <(shadowtls_service_names)

    rm -f "$SERVICE_FILE" "$SNELL_SERVICE_FILE" "$ST_SERVICE_FILE" "$CADDY_SERVICE_FILE" "$WATCHDOG_SERVICE_FILE"
    rm -f /etc/systemd/system/shadow-tls-*.service 2>/dev/null || true
    systemctl daemon-reload

    proxy_cache_purge_all

    rm -f /usr/bin/sproxy /usr/bin/proxy
    rm -rf "$WORK_DIR"
    rm -rf "$TEMP_DIR"

    green "卸载完成，所有相关文件已清除。"
    exit 0
}

# --- service status rendering (merged from service_status_ops.sh) ---

print_kv() {
    local key="$1" val="$2" color="${3:-}"
    if [[ -n "$color" ]]; then
        echo -e "  ${key}: ${color}${val}\033[0m"
    else
        echo -e "  ${key}: ${val}"
    fi
}

service_state_colored() {
    local state="${1:-unknown}"
    case "$state" in
        active|failed|inactive|dead)
            proxy_status_dot "$state"
            ;;
        activating|reloading)
            echo -e "\033[33m\033[01m● 启动中\033[0m"
            ;;
        *)
            echo -e "\033[33m\033[01m● 未知(${state})\033[0m"
            ;;
    esac
}

print_service_status_line() {
    local unit="$1"
    local display="$2"
    local state
    state="$(systemctl is-active "$unit" 2>/dev/null || true)"
    [[ -z "$state" ]] && state="unknown"
    printf "  %-16s %b\n" "${display}:" "$(service_state_colored "$state")"
}

# --- protocol service overview/menu helpers (merged from protocol_service_overview_ops.sh) ---

protocol_label_from_type() {
    local proto="$1"
    case "$proto" in
        vless) echo "vless" ;;
        tuic) echo "tuic" ;;
        trojan) echo "trojan" ;;
        anytls) echo "anytls" ;;
        ss|shadowsocks) echo "ss" ;;
        *) echo "$proto" ;;
    esac
}

protocol_overview_user_color_code() {
    local name="${1:-}"
    if declare -F share_user_color_code >/dev/null 2>&1; then
        share_user_color_code "$name"
        return 0
    fi

    local -a palette=(36 33 32 35 34 96 93 92)
    local sum=0 i ord
    for ((i = 0; i < ${#name}; i++)); do
        printf -v ord '%d' "'${name:i:1}"
        ((sum += ord))
    done
    printf '%s\n' "${palette[$((sum % ${#palette[@]}))]}"
}

protocol_overview_user_name_colored() {
    local name="${1:-}"
    local code
    code="$(protocol_overview_user_color_code "$name" 2>/dev/null || true)"
    [[ "$code" =~ ^[0-9]+$ ]] || code="36"
    printf '\033[%s;1m%s\033[0m' "$code" "$name"
}

protocol_overview_inbound_port_map() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    jq -r '
        .inbounds[]?
        | select((.tag // "") != "" and (.listen_port != null))
        | "\(.tag)|\(.listen_port)"
    ' "$conf_file" 2>/dev/null
}

print_protocol_services_overview() {
    local C_RESET="\033[0m"
    local C_TITLE="\033[36m\033[1m"
    local C_SECTION="\033[33m\033[1m"
    local C_PROTO="\033[32m"
    local C_PORT="\033[35m"
    local C_PORT_FRONT="\033[35m"
    local C_PORT_BACK="\033[36m"
    local C_EMPTY="\033[90m"
    local C_BULLET="\033[32m"

    local conf_file
    conf_file="$(ls "${CONF_DIR}"/*.json 2>/dev/null | head -n 1)"

    local shadow_lines=""
    if declare -F shadowtls_binding_lines >/dev/null 2>&1; then
        shadow_lines="$(shadowtls_binding_lines "$conf_file" 2>/dev/null || true)"
    fi

    local -A shadow_front_port_by_backend_target=()
    local line st_service st_port st_target st_backend st_sni st_pass shadow_key
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r st_service st_port st_target st_backend st_sni st_pass <<< "$line"
        [[ "$st_backend" =~ ^(ss|snell)$ ]] || continue
        [[ "$st_port" =~ ^[0-9]+$ && "$st_target" =~ ^[0-9]+$ ]] || continue
        shadow_key="${st_backend}|${st_target}"
        shadow_front_port_by_backend_target["$shadow_key"]="$st_port"
    done <<< "$shadow_lines"

    proxy_menu_header "协议管理"
    local memberships=""
    memberships="$(proxy_user_collect_membership_lines "active" "$conf_file" 2>/dev/null || true)"

    local -a user_names=()
    local -A seen_user_names=()
    local group_name
    if declare -F proxy_user_group_list >/dev/null 2>&1; then
        while IFS= read -r group_name; do
            [[ -n "$group_name" ]] || continue
            [[ -n "${seen_user_names[$group_name]+x}" ]] && continue
            seen_user_names["$group_name"]=1
            user_names+=("$group_name")
        done < <(proxy_user_group_list)
    fi

    local membership_line state name proto in_tag _id_b64 _key_b64 _user_b64
    while IFS= read -r membership_line; do
        [[ -n "$membership_line" ]] || continue
        IFS='|' read -r state name proto in_tag _id_b64 _key_b64 _user_b64 <<< "$membership_line"
        [[ "$state" == "active" && -n "$name" ]] || continue
        [[ -n "${seen_user_names[$name]+x}" ]] && continue
        seen_user_names["$name"]=1
        user_names+=("$name")
    done <<< "$memberships"

    if (( ${#user_names[@]} == 0 )); then
        echo -e "  ${C_EMPTY}○ 未安装${C_RESET}"
        echo
        return 0
    fi

    local -A inbound_port_by_tag=()
    while IFS='|' read -r in_tag port; do
        [[ -n "$in_tag" && -n "$port" ]] || continue
        inbound_port_by_tag["$in_tag"]="$port"
    done < <(protocol_overview_inbound_port_map "$conf_file")

    local -A membership_lines_by_user=()
    while IFS= read -r membership_line; do
        [[ -n "$membership_line" ]] || continue
        IFS='|' read -r state name proto in_tag _id_b64 _key_b64 _user_b64 <<< "$membership_line"
        [[ "$state" == "active" && -n "$name" ]] || continue
        membership_lines_by_user["$name"]+="${membership_line}"$'\n'
    done <<< "$memberships"

    local snell_back_port=""
    if declare -F snell_configured_listen_port >/dev/null 2>&1; then
        snell_back_port="$(snell_configured_listen_port 2>/dev/null || true)"
    fi
    [[ -n "$snell_back_port" ]] || snell_back_port="$(grep "^listen" "$SNELL_CONF" 2>/dev/null | awk -F':' '{print $NF}' | tr -d ' ' | head -n 1)"

    local user_name entry_key port back_port front_port has_protocol=0
    local -A seen_entries=()
    for user_name in "${user_names[@]}"; do
        [[ -n "$user_name" ]] || continue
        echo -e "  $(protocol_overview_user_name_colored "$user_name")"
        seen_entries=()
        has_protocol=0

        while IFS= read -r membership_line; do
            [[ -n "$membership_line" ]] || continue
            IFS='|' read -r state name proto in_tag _id_b64 _key_b64 _user_b64 <<< "$membership_line"
            [[ -n "$proto" && -n "$in_tag" ]] || continue
            entry_key="${proto}|${in_tag}"
            [[ -n "${seen_entries[$entry_key]+x}" ]] && continue
            seen_entries["$entry_key"]=1

            case "$proto" in
                vless|tuic|trojan|anytls)
                    port="${inbound_port_by_tag["$in_tag"]:-}"
                    [[ -n "$port" ]] || port="未知"
                    echo -e "    ${C_BULLET}●${C_RESET} ${C_PROTO}$(protocol_label_from_type "$proto")${C_RESET} - ${C_PORT}${port}${C_RESET}"
                    has_protocol=1
                    ;;
                ss)
                    back_port="${inbound_port_by_tag["$in_tag"]:-}"
                    if [[ "$back_port" =~ ^[0-9]+$ ]] && [[ -n "${shadow_front_port_by_backend_target["ss|${back_port}"]:-}" ]]; then
                        front_port="${shadow_front_port_by_backend_target["ss|${back_port}"]}"
                        echo -e "    ${C_BULLET}●${C_RESET} ${C_PROTO}ss+shadow-tls-v3${C_RESET} - shadow-tls:${C_PORT_FRONT}${front_port}${C_RESET} -> ss:${C_PORT_BACK}${back_port}${C_RESET}"
                    else
                        [[ -n "$back_port" ]] || back_port="未知"
                        echo -e "    ${C_BULLET}●${C_RESET} ${C_PROTO}ss${C_RESET} - ${C_PORT}${back_port}${C_RESET}"
                    fi
                    has_protocol=1
                    ;;
                snell)
                    back_port="$snell_back_port"
                    if [[ "$back_port" =~ ^[0-9]+$ ]] && [[ -n "${shadow_front_port_by_backend_target["snell|${back_port}"]:-}" ]]; then
                        front_port="${shadow_front_port_by_backend_target["snell|${back_port}"]}"
                        echo -e "    ${C_BULLET}●${C_RESET} ${C_PROTO}snell-v5+shadow-tls-v3${C_RESET} - shadow-tls:${C_PORT_FRONT}${front_port}${C_RESET} -> snell:${C_PORT_BACK}${back_port}${C_RESET}"
                    else
                        [[ -n "$back_port" ]] || back_port="未知"
                        echo -e "    ${C_BULLET}●${C_RESET} ${C_PROTO}snell-v5${C_RESET} - ${C_PORT}${back_port}${C_RESET}"
                    fi
                    has_protocol=1
                    ;;
            esac
        done <<< "${membership_lines_by_user["$user_name"]}"

        if (( has_protocol == 0 )); then
            echo -e "    ${C_EMPTY}○ 无协议${C_RESET}"
        fi
    done
}

show_protocol_services_status_summary() {
    proxy_menu_header "协议服务状态"
    print_service_status_line "sing-box" "sing-box"

    if is_snell_configured; then
        print_service_status_line "snell-v5" "snell-v5"
    else
        print_kv "snell-v5" "未配置" "\033[33m"
    fi

    if is_shadowtls_configured; then
        local conf_file st_line st_service st_port st_target st_backend st_sni st_pass label shown=0
        conf_file="$(ls "${CONF_DIR}"/*.json 2>/dev/null | head -n 1)"
        if declare -F shadowtls_binding_lines >/dev/null 2>&1; then
            while IFS= read -r st_line; do
                [[ -n "$st_line" ]] || continue
                IFS='|' read -r st_service st_port st_target st_backend st_sni st_pass <<< "$st_line"
                label="${SHADOWTLS_DISPLAY_NAME}"
                [[ "$st_port" =~ ^[0-9]+$ ]] && label="${label}(${st_port})"
                print_service_status_line "$st_service" "$label"
                shown=1
            done < <(shadowtls_binding_lines "$conf_file")
        fi
        if (( shown == 0 )); then
            print_service_status_line "shadow-tls" "${SHADOWTLS_DISPLAY_NAME}"
        fi
    else
        print_kv "${SHADOWTLS_DISPLAY_NAME}" "未配置" "\033[33m"
    fi
}

operate_protocol_services() {
    local action="$1"
    case "$action" in
        start)
            proxy_operate_singbox_service "start"
            check_service_result "sing-box" "启动"
            if proxy_operate_snell_service "start"; then
                check_service_result "snell-v5" "启动"
            else
                yellow "snell-v5 未配置，已跳过。"
            fi
            proxy_operate_watchdog_service "start" || true
            if proxy_operate_shadowtls_services "start"; then
                green "${SHADOWTLS_DISPLAY_NAME} 全部实例已启动"
            elif is_shadowtls_configured; then
                yellow "${SHADOWTLS_DISPLAY_NAME} 未检测到可启动实例。"
            else
                yellow "${SHADOWTLS_DISPLAY_NAME} 未配置，已跳过。"
            fi
            ;;
        stop)
            proxy_operate_singbox_service "stop"
            proxy_operate_snell_service "stop" || true
            proxy_operate_watchdog_service "stop" || true
            proxy_operate_shadowtls_services "stop" || true
            green "协议服务已停止"
            ;;
        restart)
            proxy_operate_singbox_service "restart"
            check_service_result "sing-box" "重启"
            if proxy_operate_snell_service "restart"; then
                check_service_result "snell-v5" "重启"
            else
                yellow "snell-v5 未配置，已跳过。"
            fi
            proxy_operate_watchdog_service "restart" || true
            if proxy_operate_shadowtls_services "restart"; then
                green "${SHADOWTLS_DISPLAY_NAME} 全部实例已重启"
            elif is_shadowtls_configured; then
                yellow "${SHADOWTLS_DISPLAY_NAME} 未检测到可重启实例。"
            else
                yellow "${SHADOWTLS_DISPLAY_NAME} 未配置，已跳过。"
            fi
            ;;
    esac
}

manage_protocol_services() {
    while :; do
        ui_clear
        print_protocol_services_overview
        proxy_menu_divider
        echo "  1. 重启所有服务"
        echo "  2. 停止所有服务"
        echo "  3. 启动所有服务"
        echo "  4. 查看服务状态"
        proxy_menu_rule "═"
        if ! read_prompt choice "选择序号(回车取消): "; then
            return
        fi
        [[ -z "$choice" ]] && return
        case $choice in
            1) operate_protocol_services "restart" ;;
            2) operate_protocol_services "stop" ;;
            3) operate_protocol_services "start" ;;
            4) show_protocol_services_status_summary ;;
            *) return ;;
        esac
    done
}
