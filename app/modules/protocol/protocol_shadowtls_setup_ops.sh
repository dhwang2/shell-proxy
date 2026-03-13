# ShadowTLS setup, listen-port suggestion, and conflict rendering helpers.

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

PROTOCOL_PORT_OPS_FILE="${PROTOCOL_PORT_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_port_ops.sh}"
if [[ -f "$PROTOCOL_PORT_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_PORT_OPS_FILE"
fi

common_ports_for_shadowtls() {
    echo "443 8443 9443 2053 2083 2087 2096 1443 10443 11443 12443"
}

shadowtls_listen_port_conflict_reason() {
    local listen_port="$1"
    local target_port="${2:-}"
    local conf_file="${3:-}"
    local exclude_shadowtls_service="${4:-}"
    [[ "$listen_port" =~ ^[0-9]+$ ]] || { echo "端口 ${listen_port} 不合法。"; return 0; }

    if [[ -n "$target_port" && "$listen_port" == "$target_port" ]]; then
        echo "端口 ${listen_port} 与后端端口 ${target_port} 冲突。"
        return 0
    fi

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        local in_conflicts
        in_conflicts="$(list_inbounds_on_port "$conf_file" "$listen_port")"
        if [[ -n "${in_conflicts// }" ]]; then
            local in_first
            in_first="$(printf '%s\n' "$in_conflicts" | head -n 1)"
            echo "端口 ${listen_port} 已被 sing-box 入站占用（${in_first}）。"
            return 0
        fi
    fi

    local protocol_conflicts
    protocol_conflicts="$(list_non_inbound_protocol_port_conflicts "$listen_port" "$conf_file" "$exclude_shadowtls_service")"
    if [[ -n "${protocol_conflicts// }" ]]; then
        local proto_first
        proto_first="$(printf '%s\n' "$protocol_conflicts" | head -n 1)"
        echo "端口 ${listen_port} 已被其他协议占用（${proto_first}）。"
        return 0
    fi

    local current_port=""
    if [[ -n "$exclude_shadowtls_service" ]]; then
        current_port="$(shadowtls_listen_port "$exclude_shadowtls_service" 2>/dev/null || true)"
    fi
    if [[ -n "$current_port" && "$listen_port" == "$current_port" ]]; then
        return 1
    fi

    local port_free=1
    if declare -F check_port >/dev/null 2>&1; then
        check_port "$listen_port" || port_free=0
    else
        if ss -tuln 2>/dev/null | grep -q ":${listen_port} " || netstat -tuln 2>/dev/null | grep -q ":${listen_port} "; then
            port_free=0
        fi
    fi
    if (( port_free == 0 )); then
        echo "端口 ${listen_port} 已被系统占用。"
        return 0
    fi

    return 1
}

pick_default_shadowtls_listen_port() {
    local target_port="$1"
    local conf_file="${2:-}"
    local exclude_shadowtls_service="${3:-}"

    local common_line normalized shuffled port
    common_line="$(common_ports_for_shadowtls)"
    [[ -n "${common_line// }" ]] || return 1

    normalized="$(printf '%s\n' ${common_line} | awk '/^[0-9]+$/' | awk '!seen[$0]++')"
    [[ -n "$normalized" ]] || return 1

    if command -v shuf >/dev/null 2>&1; then
        shuffled="$(printf '%s\n' "$normalized" | shuf)"
    else
        shuffled="$(while IFS= read -r p; do
            [[ -n "$p" ]] || continue
            printf '%05d %s\n' "$RANDOM" "$p"
        done <<< "$normalized" | sort -n | awk '{print $2}')"
    fi

    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        if ! shadowtls_listen_port_conflict_reason "$port" "$target_port" "$conf_file" "$exclude_shadowtls_service" >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
    done <<< "$shuffled"

    return 1
}

pick_random_shadowtls_listen_port() {
    local target_port="$1"
    local conf_file="${2:-}"
    local exclude_shadowtls_service="${3:-}"
    local tries=160 port=""

    while (( tries > 0 )); do
        port="$(gen_random_inbound_port "$conf_file" 2>/dev/null || true)"
        if [[ -n "$port" ]] && ! shadowtls_listen_port_conflict_reason "$port" "$target_port" "$conf_file" "$exclude_shadowtls_service" >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
        ((tries--))
    done

    return 1
}

suggest_shadowtls_listen_port() {
    local target_port="$1"
    local conf_file="${2:-}"
    local exclude_shadowtls_service="${3:-}"
    local suggestion=""

    suggestion="$(pick_default_shadowtls_listen_port "$target_port" "$conf_file" "$exclude_shadowtls_service" 2>/dev/null || true)"
    if [[ -z "$suggestion" ]]; then
        suggestion="$(pick_random_shadowtls_listen_port "$target_port" "$conf_file" "$exclude_shadowtls_service" 2>/dev/null || true)"
    fi
    echo "$suggestion"
}

shadowtls_occupied_ports_summary() {
    local conf_file="${1:-}"
    local exclude_shadowtls_service="${2:-}"
    local st_line st_service st_port st_target st_backend st_sni st_pass
    local summary=""

    while IFS= read -r st_line; do
        [[ -n "$st_line" ]] || continue
        IFS='|' read -r st_service st_port st_target st_backend st_sni st_pass <<< "$st_line"
        [[ "$st_port" =~ ^[0-9]+$ ]] || continue

        local backend_hint item
        case "$st_backend" in
            snell) backend_hint="snell-v5" ;;
            ss) backend_hint="ss" ;;
            *) backend_hint="${st_backend:-unknown}" ;;
        esac

        item="${st_port}(${backend_hint})"
        if [[ -n "$exclude_shadowtls_service" && "$st_service" == "$exclude_shadowtls_service" ]]; then
            item="${item}[当前实例]"
        fi

        if [[ -n "$summary" ]]; then
            summary+=", ${item}"
        else
            summary="${item}"
        fi
    done < <(shadowtls_binding_lines "$conf_file")

    echo "$summary"
}

shadowtls_service_name_for_target() {
    local target_proto="${1:-unknown}"
    local target_port="${2:-0}"
    local safe_proto
    safe_proto="$(echo "$target_proto" | tr -c 'a-zA-Z0-9_-' '-')"
    safe_proto="${safe_proto#-}"
    safe_proto="${safe_proto%-}"
    [[ -z "$safe_proto" ]] && safe_proto="unknown"
    echo "shadow-tls-${safe_proto}-${target_port}"
}

configure_shadowtls_for_target() {
    local target_port="$1"
    local target_proto="${2:-unknown}"
    [[ "$target_port" =~ ^[0-9]+$ ]] || return 1

    local conf_file service_name service_unit service_log
    conf_file="$(get_conf_file)"
    service_name="$(shadowtls_service_name_for_target "$target_proto" "$target_port")"
    service_unit="$(shadowtls_service_unit_path "$service_name")"
    service_log="${LOG_DIR}/${service_name}.log"

    local current_st_port default_st_port st_port
    current_st_port="$(shadowtls_listen_port "$service_name" 2>/dev/null || true)"
    if [[ -n "$current_st_port" ]]; then
        default_st_port="$current_st_port"
    else
        default_st_port="$(suggest_shadowtls_listen_port "$target_port" "$conf_file" "$service_name" 2>/dev/null || true)"
        [[ -z "$default_st_port" ]] && default_st_port="443"
    fi

    local occupied_ports
    occupied_ports="$(shadowtls_occupied_ports_summary "$conf_file" "$service_name" 2>/dev/null || true)"

    echo -e "\033[33m提示: shadow-tls-v3 后端端口: ${target_proto}:${target_port}\033[0m"
    if [[ -n "${occupied_ports// }" ]]; then
        echo -e "\033[33m提示: shadow-tls-v3 已占用端口: ${occupied_ports}\033[0m"
    else
        echo -e "\033[33m提示: shadow-tls-v3 已占用端口: 无\033[0m"
    fi
    if [[ -n "${default_st_port// }" ]]; then
        echo -e "\033[33m提示: 推荐可用端口: ${default_st_port}\033[0m"
    fi
    echo -e "\033[33m提示: 默认端口为随机常用端口，并自动避开现有协议冲突。\033[0m"
    while :; do
        if ! read_prompt st_port "shadow-tls-v3 端口 [默认: ${default_st_port}, 勿冲突]: "; then
            st_port=""
        fi
        st_port="${st_port:-$default_st_port}"

        if ! [[ "$st_port" =~ ^[0-9]+$ ]] || ((st_port < 1 || st_port > 65535)); then
            red "错误: 端口不合法。"
            continue
        fi
        local st_conflict_reason=""
        st_conflict_reason="$(shadowtls_listen_port_conflict_reason "$st_port" "$target_port" "$conf_file" "$service_name" 2>/dev/null || true)"
        if [[ -n "${st_conflict_reason// }" ]]; then
            red "错误: ${st_conflict_reason}"
            local retry_suggest
            retry_suggest="$(suggest_shadowtls_listen_port "$target_port" "$conf_file" "$service_name" 2>/dev/null || true)"
            if [[ -n "${retry_suggest// }" ]]; then
                yellow "推荐可用端口: ${retry_suggest}"
            fi
            continue
        fi
        break
    done

    local st_host_default st_host st_pass
    st_host_default="$(pick_decoy_sni_domain)"
    yellow "默认优先推荐 Apple/Microsoft 伪装域名（已自动排除已使用项）。"
    if ! read_prompt st_host "伪装域名 [默认: ${st_host_default}]: "; then
        st_host=""
    fi
    st_host="${st_host:-$st_host_default}"
    remember_shadowtls_sni_domain "$st_host" || true
    st_pass="$(gen_rand_alnum 12)"

    chmod +x "$ST_BIN" 2>/dev/null
    local exec_cmd="${ST_BIN} --v3 server --listen :::${st_port} --server 127.0.0.1:${target_port} --tls ${st_host} --password ${st_pass}"
    write_shadowtls_unit "$service_unit" "${exec_cmd}" "$service_log"

    systemctl daemon-reload
    systemctl enable "$service_name" >/dev/null 2>&1 || true
    systemctl restart "$service_name"
    touch "${SHADOWTLS_MARKER:-${WORK_DIR}/.shadowtls_configured}"

    check_service_result "$service_name" "启动" "shadow-tls-v3(${target_proto}:${target_port})"
    echo -e "实例: ${service_name} | 端口: ${st_port} | 密码: ${st_pass} | 域名: ${st_host} | 后端: ${target_proto}:${target_port}"
    return 0
}
