# Systemd unit template rendering helpers.

_systemd_log_err() {
    local msg="$1"
    if declare -F red >/dev/null 2>&1; then
        red "$msg"
    else
        echo "$msg" >&2
    fi
}

_systemd_escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

SYSTEMD_TEMPLATE_DIR="${SYSTEMD_TEMPLATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../systemd" && pwd)}"

render_systemd_template() {
    local template_name="$1"
    local output_path="$2"
    shift 2

    local template_path="${SYSTEMD_TEMPLATE_DIR}/${template_name}"
    if [[ ! -f "$template_path" ]]; then
        _systemd_log_err "未找到 systemd 模板: ${template_path}"
        return 1
    fi

    local content
    content="$(cat "$template_path")"

    local pair key value escaped
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        escaped="$(_systemd_escape_sed_replacement "$value")"
        content="$(printf '%s' "$content" | sed "s|{{${key}}}|${escaped}|g")"
    done

    if printf '%s' "$content" | grep -q '{{'; then
        _systemd_log_err "模板渲染失败: ${template_name} 仍包含未替换占位符"
        return 1
    fi

    printf '%s\n' "$content" > "$output_path"
    chmod 644 "$output_path"
}

write_singbox_unit() {
    local output_path="$1"
    local exec_start="$2"
    render_systemd_template "sing-box.service.tpl" "$output_path" \
        "EXEC_START=${exec_start}" \
        "LOG_DIR=${LOG_DIR}"
}

write_snell_unit() {
    local output_path="$1"
    local exec_start="$2"
    render_systemd_template "snell-v5.service.tpl" "$output_path" \
        "EXEC_START=${exec_start}" \
        "LOG_DIR=${LOG_DIR}"
}

write_shadowtls_unit() {
    local output_path="$1"
    local exec_start="$2"
    local log_file="${3:-${LOG_DIR}/shadow-tls.service.log}"
    render_systemd_template "shadow-tls.service.tpl" "$output_path" \
        "EXEC_START=${exec_start}" \
        "LOG_FILE=${log_file}"
}

write_caddy_sub_unit() {
    local output_path="$1"
    local exec_start="$2"
    local exec_reload="$3"
    render_systemd_template "caddy-sub.service.tpl" "$output_path" \
        "EXEC_START=${exec_start}" \
        "EXEC_RELOAD=${exec_reload}" \
        "LOG_DIR=${LOG_DIR}" \
        "WORK_DIR=${WORK_DIR}" \
        "CADDY_XDG_DATA_HOME=${CADDY_XDG_DATA_HOME}" \
        "CADDY_XDG_CONFIG_HOME=${CADDY_XDG_CONFIG_HOME}"
}

write_proxy_watchdog_unit() {
    local output_path="$1"
    local exec_start="$2"
    local log_file="${3:-${PROXY_WATCHDOG_LOG}}"
    render_systemd_template "proxy-watchdog.service.tpl" "$output_path" \
        "EXEC_START=${exec_start}" \
        "LOG_FILE=${log_file}"
}
