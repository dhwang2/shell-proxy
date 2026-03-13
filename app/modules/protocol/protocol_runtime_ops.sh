# Protocol runtime helpers for Snell and ShadowTLS service discovery.

PROTOCOL_RUNTIME_COMMON_OPS_FILE="${PROTOCOL_RUNTIME_COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_COMMON_OPS_FILE"
fi

PROTOCOL_RUNTIME_RELEASE_OPS_FILE="${PROTOCOL_RUNTIME_RELEASE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/release_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_RELEASE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_RELEASE_OPS_FILE"
fi

snell_configured_listen_port() {
    if is_snell_configured; then
        grep '^listen' "$SNELL_CONF" 2>/dev/null | awk -F':' '{print $NF}' | tr -d '[:space:]' | head -n 1
    fi
}

shadowtls_service_unit_path() {
    local service_name="${1:-shadow-tls}"
    if [[ "$service_name" == *.service ]]; then
        echo "$service_name"
    else
        echo "/etc/systemd/system/${service_name}.service"
    fi
}

shadowtls_iter_service_names() {
    if [[ -f "$ST_SERVICE_FILE" ]] && grep -q "server --listen" "$ST_SERVICE_FILE" 2>/dev/null; then
        echo "shadow-tls"
    fi
    local unit_file
    for unit_file in /etc/systemd/system/shadow-tls-*.service; do
        [[ -e "$unit_file" ]] || continue
        grep -q "server --listen" "$unit_file" 2>/dev/null || continue
        basename "${unit_file%.service}"
    done | sort -u
}

calc_shadowtls_render_fingerprint() {
    local service_name unit_path unit_fp
    while IFS= read -r service_name; do
        [[ -n "$service_name" ]] || continue
        unit_path="$(shadowtls_service_unit_path "$service_name" 2>/dev/null || true)"
        unit_fp="$(calc_file_meta_signature "$unit_path" 2>/dev/null || echo "missing")"
        printf '%s|%s\n' "$service_name" "$unit_fp"
    done < <(shadowtls_iter_service_names 2>/dev/null || true)
}

shadowtls_default_service_name() {
    local service_name
    while IFS= read -r service_name; do
        [[ -n "$service_name" ]] || continue
        echo "$service_name"
        return 0
    done < <(shadowtls_iter_service_names)
    return 1
}

shadowtls_execstart_line() {
    local service_name="${1:-}"
    [[ -z "$service_name" ]] && service_name="$(shadowtls_default_service_name 2>/dev/null || true)"
    [[ -n "$service_name" ]] || return 1

    local unit_file
    unit_file="$(shadowtls_service_unit_path "$service_name")"
    if [[ -f "$unit_file" ]]; then
        sed -n 's/^[[:space:]]*ExecStart=//p' "$unit_file" | tail -n 1
        return 0
    fi

    systemctl cat "$service_name" 2>/dev/null | sed -n 's/^[[:space:]]*ExecStart=//p' | tail -n 1
}

shadowtls_extract_arg() {
    local cmd="${1:-}"
    local arg="${2:-}"
    [[ -n "$cmd" && -n "$arg" ]] || return 1
    echo "$cmd" | grep -oE -- "${arg} [^ ]+" | awk '{print $2}'
}

shadowtls_listen_port() {
    local service_name="${1:-}"
    local cmd
    cmd="$(shadowtls_execstart_line "$service_name" 2>/dev/null || true)"
    [[ -n "$cmd" ]] || return 1
    shadowtls_extract_arg "$cmd" '--listen' | awk -F: '{print $NF}'
}

shadowtls_target_port() {
    local service_name="${1:-}"
    local cmd
    cmd="$(shadowtls_execstart_line "$service_name" 2>/dev/null || true)"
    [[ -n "$cmd" ]] || return 1
    shadowtls_extract_arg "$cmd" '--server' | awk -F: '{print $NF}'
}

shadowtls_sni() {
    local service_name="${1:-}"
    local cmd
    cmd="$(shadowtls_execstart_line "$service_name" 2>/dev/null || true)"
    [[ -n "$cmd" ]] || return 1
    shadowtls_extract_arg "$cmd" '--tls'
}

shadowtls_password() {
    local service_name="${1:-}"
    local cmd
    cmd="$(shadowtls_execstart_line "$service_name" 2>/dev/null || true)"
    [[ -n "$cmd" ]] || return 1
    shadowtls_extract_arg "$cmd" '--password'
}

shadowtls_protocol_version() {
    local service_name="${1:-}"
    local cmd
    cmd="$(shadowtls_execstart_line "$service_name" 2>/dev/null || true)"
    [[ -n "$cmd" ]] || { echo "2"; return 0; }

    if echo "$cmd" | grep -Eq -- '(^|[[:space:]])--v3([[:space:]]|$)'; then
        echo "3"
    else
        echo "2"
    fi
}

shadowtls_backend_type_by_target_port() {
    local target_port="${1:-}"
    local conf_file="${2:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"
    [[ "$target_port" =~ ^[0-9]+$ ]] || { echo "unknown"; return 0; }

    local snell_port
    snell_port="$(snell_configured_listen_port 2>/dev/null || true)"
    if [[ -n "$snell_port" && "$target_port" == "$snell_port" ]]; then
        echo "snell"
        return 0
    fi

    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        if jq -e --argjson p "$target_port" '.inbounds[]? | select((.type=="shadowsocks" or .type=="ss") and (.listen_port // 0) == $p)' "$conf_file" >/dev/null 2>&1; then
            echo "ss"
            return 0
        fi
    fi

    echo "unknown"
    return 0
}

shadowtls_backend_type() {
    local conf_file="${1:-}"
    local service_name="${2:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"
    is_shadowtls_configured || { echo ""; return 1; }

    local target_port
    target_port="$(shadowtls_target_port "$service_name" 2>/dev/null || true)"
    shadowtls_backend_type_by_target_port "$target_port" "$conf_file"
}

shadowtls_binding_lines_uncached() {
    local conf_file="${1:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"
    local service_name st_port st_target st_backend st_sni st_pass
    while IFS= read -r service_name; do
        [[ -n "$service_name" ]] || continue
        st_port="$(shadowtls_listen_port "$service_name" 2>/dev/null || true)"
        st_target="$(shadowtls_target_port "$service_name" 2>/dev/null || true)"
        st_backend="$(shadowtls_backend_type "$conf_file" "$service_name" 2>/dev/null || true)"
        st_sni="$(shadowtls_sni "$service_name" 2>/dev/null || true)"
        st_pass="$(shadowtls_password "$service_name" 2>/dev/null || true)"
        echo "${service_name}|${st_port}|${st_target}|${st_backend}|${st_sni}|${st_pass}"
    done < <(shadowtls_iter_service_names)
}

shadowtls_binding_lines() {
    local conf_file="${1:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"

    if (( SUBSCRIPTION_RENDER_CONTEXT_ACTIVE == 1 )) \
        && [[ "$conf_file" == "$SUBSCRIPTION_RENDER_CONTEXT_CONF" ]]; then
        [[ -n "$SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_BINDINGS" ]] \
            && printf '%s\n' "$SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_BINDINGS"
        return 0
    fi

    shadowtls_binding_lines_uncached "$conf_file"
}

shadowtls_backend_display_label() {
    case "${1:-}" in
        ss) echo "SS" ;;
        snell) echo "Snell" ;;
        *) echo "${1:-unknown}" ;;
    esac
}

shadowtls_service_names_by_backend_target_port() {
    local backend="${1:-}"
    local target_port="${2:-}"
    local conf_file="${3:-}"
    [[ -z "$backend" ]] && return 0
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"
    [[ "$target_port" =~ ^[0-9]+$ ]] || return 0

    local line service_name st_port st_target st_backend st_sni st_pass
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r service_name st_port st_target st_backend st_sni st_pass <<< "$line"
        if [[ "$st_backend" == "$backend" && "$st_target" == "$target_port" ]]; then
            echo "$service_name"
        fi
    done < <(shadowtls_binding_lines "$conf_file")
}

shadowtls_binding_exists_for_backend_target() {
    local backend="${1:-}"
    local target_port="${2:-}"
    local conf_file="${3:-}"
    [[ -z "$backend" ]] && return 1
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"
    [[ "$target_port" =~ ^[0-9]+$ ]] || return 1

    if (( SUBSCRIPTION_RENDER_CONTEXT_ACTIVE == 1 )) \
        && [[ "$conf_file" == "$SUBSCRIPTION_RENDER_CONTEXT_CONF" ]]; then
        grep -Fxq "${backend}|${target_port}" <<< "$SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_TARGET_KEYS"
        return $?
    fi

    local service_name
    service_name="$(shadowtls_service_names_by_backend_target_port "$backend" "$target_port" "$conf_file" 2>/dev/null | head -n 1)"
    [[ -n "${service_name// }" ]]
}

disable_shadowtls_service_unit() {
    local service_name="${1:-}"
    [[ -n "$service_name" ]] || return 1
    local unit_file
    unit_file="$(shadowtls_service_unit_path "$service_name")"

    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true

    if [[ "$service_name" == "shadow-tls" ]]; then
        write_shadowtls_unit "$ST_SERVICE_FILE" "/bin/false"
    else
        rm -f "$unit_file" 2>/dev/null || true
    fi
    return 0
}

disable_shadowtls_services_from_list() {
    local services_text="${1:-}"
    local removed=0 service_name
    while IFS= read -r service_name; do
        [[ -n "$service_name" ]] || continue
        disable_shadowtls_service_unit "$service_name" || true
        ((removed++))
    done <<< "$services_text"

    if (( removed > 0 )); then
        systemctl daemon-reload
    fi
    return 0
}

# --- protocol installation support (merged from protocol_support_ops.sh) ---

install_caddy() {
    if [[ -f "$CADDY_BIN" ]]; then
        if ! "$CADDY_BIN" version &>/dev/null; then
            yellow "检测到 caddy 文件损坏，准备重新安装..." >&2
            rm -f "$CADDY_BIN"
        else
            return 0
        fi
    fi

    echo "正在安装 caddy (github)..." >&2
    local arch version fallback_version archive_path
    arch="$(detect_release_arch)" || {
        red "不支持的架构: $(uname -m)" >&2
        return 1
    }
    version="$(resolve_caddy_release_version)"
    fallback_version="${CADDY_DEFAULT_VERSION}"

    mkdir -p "$BIN_DIR" "$LOG_DIR" "$WORK_DIR/caddy"

    archive_path="${CADDY_BIN}.tar.gz"
    if ! download_caddy_release_archive "$version" "$arch" "$archive_path"; then
        if [[ "$version" != "$fallback_version" ]]; then
            yellow "caddy 最新版本下载失败，回退到 v${fallback_version} 重试..." >&2
            version="$fallback_version"
            download_caddy_release_archive "$version" "$arch" "$archive_path" || {
                red "caddy 下载失败" >&2
                return 1
            }
        else
            red "caddy 下载失败" >&2
            return 1
        fi
    fi

    if [[ -f "$archive_path" ]]; then
        tar -zxf "$archive_path" -C "$(dirname "$CADDY_BIN")" caddy >/dev/null 2>&1
        rm -f "$archive_path"
        chmod +x "$CADDY_BIN"

        if "$CADDY_BIN" version &>/dev/null; then
            green "caddy 安装成功: $("$CADDY_BIN" version | awk '{print $1}')" >&2
        else
            red "caddy 安装失败: 二进制文件无法执行" >&2
            return 1
        fi
    else
        red "caddy 下载失败" >&2
        return 1
    fi
}

ss2022_key_length() {
    local method="${1:-}"
    case "$method" in
        2022-blake3-aes-128-gcm) echo 16 ;;
        2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) echo 32 ;;
        *) echo 0 ;;
    esac
}

is_ss2022_method() {
    local method="${1:-}"
    local key_len
    key_len="$(ss2022_key_length "$method")"
    [[ "$key_len" =~ ^[0-9]+$ ]] && (( key_len > 0 ))
}

gen_ss_password_by_method() {
    local method="${1:-}"
    local key_len
    key_len="$(ss2022_key_length "$method")"
    if [[ "$key_len" =~ ^[0-9]+$ ]] && (( key_len > 0 )); then
        openssl rand -base64 "$key_len" 2>/dev/null | tr -d '\n'
        return 0
    fi
    gen_rand_alnum 16
}

ss_base64_raw_length() {
    local value="${1:-}"
    [[ -n "$value" ]] || { echo 0; return 1; }

    local normalized="$value"
    normalized="${normalized//-/+}"
    normalized="${normalized//_/\/}"
    local mod=$(( ${#normalized} % 4 ))
    case "$mod" in
        0) ;;
        2) normalized="${normalized}==" ;;
        3) normalized="${normalized}=" ;;
        *) echo 0; return 1 ;;
    esac

    local decoded_len=""
    decoded_len="$(printf '%s' "$normalized" | base64 -d 2>/dev/null | wc -c | tr -d '[:space:]' || true)"
    if [[ "$decoded_len" =~ ^[0-9]+$ ]]; then
        echo "$decoded_len"
        return 0
    fi
    decoded_len="$(printf '%s' "$normalized" | base64 --decode 2>/dev/null | wc -c | tr -d '[:space:]' || true)"
    if [[ "$decoded_len" =~ ^[0-9]+$ ]]; then
        echo "$decoded_len"
        return 0
    fi
    decoded_len="$(printf '%s' "$normalized" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d '[:space:]' || true)"
    if [[ "$decoded_len" =~ ^[0-9]+$ ]]; then
        echo "$decoded_len"
        return 0
    fi
    echo 0
    return 1
}

validate_ss_password_for_method() {
    local method="${1:-}"
    local password="${2:-}"
    [[ -n "$password" ]] || return 1

    local expected_len
    expected_len="$(ss2022_key_length "$method")"
    if [[ "$expected_len" =~ ^[0-9]+$ ]] && (( expected_len > 0 )); then
        local raw_len
        raw_len="$(ss_base64_raw_length "$password")"
        [[ "$raw_len" =~ ^[0-9]+$ ]] || return 1
        (( raw_len == expected_len ))
        return
    fi

    return 0
}
