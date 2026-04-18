# Protocol port allocation and conflict detection.

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

# 新增入站统一随机端口范围，便于防火墙按区间放行。
INBOUND_RANDOM_PORT_MIN_DEFAULT=20000
INBOUND_RANDOM_PORT_MAX_DEFAULT=29999

resolve_inbound_random_port_range() {
    local min_port="${INBOUND_RANDOM_PORT_MIN:-$INBOUND_RANDOM_PORT_MIN_DEFAULT}"
    local max_port="${INBOUND_RANDOM_PORT_MAX:-$INBOUND_RANDOM_PORT_MAX_DEFAULT}"

    if ! [[ "$min_port" =~ ^[0-9]+$ ]] || ! [[ "$max_port" =~ ^[0-9]+$ ]]; then
        min_port="$INBOUND_RANDOM_PORT_MIN_DEFAULT"
        max_port="$INBOUND_RANDOM_PORT_MAX_DEFAULT"
    fi

    if (( min_port < 1024 || max_port > 65535 || min_port > max_port )); then
        min_port="$INBOUND_RANDOM_PORT_MIN_DEFAULT"
        max_port="$INBOUND_RANDOM_PORT_MAX_DEFAULT"
    fi

    echo "${min_port}|${max_port}"
}

inbound_port_prompt_text() {
    local range min_port max_port
    range="$(resolve_inbound_random_port_range)"
    IFS='|' read -r min_port max_port <<< "$range"
    echo "监听端口(默认优先常用端口，回退随机 ${min_port}-${max_port})"
}

common_ports_for_proto() {
    printf '%s\n' "${PROXY_PROTOCOL_COMMON_PORTS[${1:-}]:-}"
}

render_compact_port_summary_with_usage() {
    local candidate_ports="${1:-}"
    local occupied_ports="${2:-}"
    local range_min="${3:-20000}"
    local range_max="${4:-29999}"
    local normal_color="${5:-\033[90m}"
    local occupied_color="${6:-\033[9;31m}"
    local reset_color="\033[0m"

    local rendered="" port styled
    local seen_candidates=""
    local range_label="${range_min}~${range_max}"

    for port in $candidate_ports; do
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        if [[ " $seen_candidates " == *" ${port} "* ]]; then
            continue
        fi
        seen_candidates+=" ${port}"

        if [[ -n "$occupied_ports" && " ${occupied_ports} " == *" ${port} "* ]]; then
            styled="${occupied_color}${port}${reset_color}"
        else
            styled="${normal_color}${port}${reset_color}"
        fi

        if [[ -n "$rendered" ]]; then
            rendered+=",${styled}"
        else
            rendered="${styled}"
        fi
    done

    while IFS= read -r port; do
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        if [[ " $seen_candidates " == *" ${port} "* ]]; then
            continue
        fi
        if [[ -n "$rendered" ]]; then
            rendered+=",${occupied_color}${port}${reset_color}"
        else
            rendered="${occupied_color}${port}${reset_color}"
        fi
    done < <(
        printf '%s\n' $occupied_ports \
            | awk -v min="$range_min" -v max="$range_max" '$0 ~ /^[0-9]+$/ && $0 >= min && $0 <= max' \
            | sort -n -u
    )

    if [[ -n "$rendered" ]]; then
        rendered+=",${normal_color}${range_label}${reset_color}"
    else
        rendered="${normal_color}${range_label}${reset_color}"
    fi

    printf '%b' "$rendered"
}

is_usable_inbound_port() {
    local port="$1"
    local conf_file="${2:-}"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        return 1
    fi

    local port_ok=1
    if declare -F check_port >/dev/null 2>&1; then
        check_port "$port" || port_ok=0
    else
        if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            port_ok=0
        fi
    fi
    ((port_ok == 1)) || return 1

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        if jq -e --argjson p "$port" '.inbounds[]? | select((.listen_port // 0) == $p)' "$conf_file" >/dev/null 2>&1; then
            return 1
        fi
    fi

    return 0
}

pick_available_port_from_candidates() {
    local conf_file="${1:-}"
    shift || true
    local -a ports=("$@")
    (( ${#ports[@]} > 0 )) || return 1

    local normalized shuffled
    normalized="$(printf '%s\n' "${ports[@]}" | awk '/^[0-9]+$/' | awk '!seen[$0]++')"
    [[ -n "$normalized" ]] || return 1

    if command -v shuf >/dev/null 2>&1; then
        shuffled="$(printf '%s\n' "$normalized" | shuf)"
    else
        shuffled="$(while IFS= read -r p; do
            [[ -n "$p" ]] || continue
            printf '%05d %s\n' "$RANDOM" "$p"
        done <<< "$normalized" | sort -n | awk '{print $2}')"
    fi

    local port
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        if is_usable_inbound_port "$port" "$conf_file"; then
            echo "$port"
            return 0
        fi
    done <<< "$shuffled"

    return 1
}

gen_random_high_port() {
    local min_port="${1:-10000}"
    local max_port="${2:-60000}"
    local conf_file="${3:-}"
    local tries=120
    local port=""

    while ((tries > 0)); do
        if command -v shuf >/dev/null 2>&1; then
            port="$(shuf -i "${min_port}-${max_port}" -n 1 2>/dev/null)"
        else
            port="$((RANDOM % (max_port - min_port + 1) + min_port))"
        fi

        if ! is_usable_inbound_port "$port" "$conf_file"; then
            ((tries--))
            continue
        fi

        echo "$port"
        return 0
    done

    return 1
}

gen_random_inbound_port() {
    local conf_file="${1:-}"
    local range min_port max_port
    range="$(resolve_inbound_random_port_range)"
    IFS='|' read -r min_port max_port <<< "$range"
    gen_random_high_port "$min_port" "$max_port" "$conf_file"
}

gen_preferred_inbound_port() {
    local proto="${1:-}"
    local conf_file="${2:-}"
    local common_line picked
    common_line="$(common_ports_for_proto "$proto")"
    if [[ -n "$common_line" ]]; then
        local -a common_ports=()
        IFS=' ' read -r -a common_ports <<< "$common_line"
        picked="$(pick_available_port_from_candidates "$conf_file" "${common_ports[@]}")"
        if [[ -n "$picked" ]]; then
            echo "$picked"
            return 0
        fi
    fi

    gen_random_inbound_port "$conf_file"
}

list_inbounds_on_port() {
    local conf_file="$1"
    local port="$2"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    jq -r --argjson p "$port" '
        .inbounds[]?
        | select((.listen_port // 0) == $p)
        | "\(.type // "unknown"):\(.tag // "-")"
    ' "$conf_file" 2>/dev/null
}

list_non_inbound_protocol_port_conflicts() {
    local port="$1"
    local conf_file="${2:-}"
    local exclude_shadowtls_service="${3:-}"
    [[ "$port" =~ ^[0-9]+$ ]] || return 0

    local snell_port
    snell_port="$(snell_configured_listen_port)"
    if [[ "$snell_port" =~ ^[0-9]+$ ]] && [[ "$snell_port" == "$port" ]]; then
        echo "snell-v5:listen=${snell_port}"
    fi

    local st_line st_service st_listen st_target st_backend st_sni st_pass
    while IFS= read -r st_line; do
        [[ -n "$st_line" ]] || continue
        IFS='|' read -r st_service st_listen st_target st_backend st_sni st_pass <<< "$st_line"
        [[ -n "$exclude_shadowtls_service" && "$st_service" == "$exclude_shadowtls_service" ]] && continue
        [[ "$st_listen" == "$port" ]] || continue
        echo "shadow-tls-v3:${st_service}(listen=${st_listen}->${st_backend}:${st_target})"
    done < <(shadowtls_binding_lines "$conf_file")
}

pick_singbox_port_with_override() {
    local conf_file="$1"
    local default_port="$2"
    local prompt_text="${3:-监听端口}"

    while :; do
        local input_port port
        if ! read_prompt input_port "${prompt_text} [默认: ${default_port}]: "; then
            input_port=""
        fi
        port="${input_port:-$default_port}"

        if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
            yellow "端口无效，请输入 1-65535。" >&2
            continue
        fi

        local conflicts
        conflicts="$(list_inbounds_on_port "$conf_file" "$port")"
        if [[ -n "$conflicts" ]]; then
            yellow "检测到当前配置端口 ${port} 已被使用：" >&2
            while IFS= read -r line; do
                [[ -n "$line" ]] && echo "  - ${line}" >&2
            done <<< "$conflicts"
            if ! read_prompt yn "是否覆盖该端口配置? [y/N]: "; then
                yn=""
            fi
            if [[ "${yn,,}" == "y" ]]; then
                echo "${port}|1"
                return 0
            fi
            continue
        fi

        local protocol_conflicts
        protocol_conflicts="$(list_non_inbound_protocol_port_conflicts "$port" "$conf_file")"
        if [[ -n "${protocol_conflicts// }" ]]; then
            yellow "检测到端口 ${port} 已被其他协议使用：" >&2
            while IFS= read -r line; do
                [[ -n "$line" ]] && echo "  - ${line}" >&2
            done <<< "$protocol_conflicts"
            continue
        fi

        if check_port "$port"; then
            echo "${port}|0"
            return 0
        fi

        yellow "端口占用，请更换。" >&2
    done
}
