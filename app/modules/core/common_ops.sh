# Shared runtime helpers for proxy install/management modules.

if ! declare -F ui_clear >/dev/null 2>&1; then
ui_clear() {
    if [[ -t 1 ]] \
        && command -v clear >/dev/null 2>&1 \
        && command -v tput >/dev/null 2>&1 \
        && [[ -n "${TERM:-}" && "${TERM}" != "unknown" ]] \
        && tput cols >/dev/null 2>&1; then
        clear 2>/dev/null || true
    fi
}
fi

if ! declare -F proxy_prompt_tty_available >/dev/null 2>&1; then
proxy_prompt_tty_available() {
    [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]]
}
fi

if ! declare -F proxy_prompt_readline_available >/dev/null 2>&1; then
proxy_prompt_readline_available() {
    [[ -n "${BASH_VERSION:-}" ]] || return 1
    proxy_prompt_tty_available || return 1
    return 0
}
fi

if ! declare -F proxy_prompt_print >/dev/null 2>&1; then
proxy_prompt_print() {
    local text="${1:-}"
    if proxy_prompt_tty_available; then
        printf "%s" "$text" > /dev/tty
    else
        printf "%s" "$text" >&2
    fi
}
fi


if ! declare -F proxy_ui_color_enabled >/dev/null 2>&1; then
proxy_ui_color_enabled() {
    [[ -n "${PROXY_TTY_RENDER_FORCE:-}" || -t 1 ]]
}
fi

if ! declare -F proxy_menu_rule >/dev/null 2>&1; then
proxy_menu_rule() {
    local char="${1:-─}" width="${2:-68}" color="${3:-36}" line=""
    printf -v line '%*s' "$width" ''
    line="${line// /$char}"
    if proxy_ui_color_enabled; then
        printf '\033[%sm%s\033[0m\n' "$color" "$line"
    else
        printf '%s\n' "$line"
    fi
}
fi

if ! declare -F proxy_menu_header >/dev/null 2>&1; then
proxy_menu_header() {
    local title="${1:-}" subtitle="${2:-}" width="${3:-68}"
    proxy_menu_rule "═" "$width"
    if proxy_ui_color_enabled; then
        printf '\033[36;1m  %s\033[0m\n' "$title"
        [[ -n "$subtitle" ]] && printf '\033[90m  %s\033[0m\n' "$subtitle"
    else
        printf '  %s\n' "$title"
        [[ -n "$subtitle" ]] && printf '  %s\n' "$subtitle"
    fi
    proxy_menu_rule "═" "$width"
}
fi

if ! declare -F proxy_menu_divider >/dev/null 2>&1; then
proxy_menu_divider() {
    proxy_menu_rule "─" "${1:-68}"
}
fi

if ! declare -F proxy_status_dot >/dev/null 2>&1; then
proxy_status_dot() {
    local state="${1:-}" label="${2:-}"
    case "$state" in
        active)
            if [[ -n "$label" ]]; then
                echo -e "\033[32m\033[01m● ${label}\033[0m"
            else
                echo -e "\033[32m\033[01m● 运行中\033[0m"
            fi
            ;;
        failed)
            if [[ -n "$label" ]]; then
                echo -e "\033[31m\033[01m● ${label}\033[0m"
            else
                echo -e "\033[31m\033[01m● 故障\033[0m"
            fi
            ;;
        inactive|dead)
            if [[ -n "$label" ]]; then
                echo -e "\033[31m\033[01m● ${label}\033[0m"
            else
                echo -e "\033[31m\033[01m● 已停止\033[0m"
            fi
            ;;
        *)
            if [[ -n "$label" ]]; then
                printf '\033[90m○ %s\033[0m\n' "$label"
            else
                printf '\033[90m○\033[0m\n'
            fi
            ;;
    esac
}
fi

if ! declare -F read_prompt >/dev/null 2>&1; then
read_prompt() {
    local __var_name="$1"
    local __prompt="$2"
    local __input=""
    if proxy_prompt_tty_available; then
        if proxy_prompt_readline_available; then
            if ! IFS= read -r -e -p "$__prompt" __input < /dev/tty; then
                printf -v "$__var_name" '%s' ""
                return 1
            fi
        else
            proxy_prompt_print "$__prompt"
            if ! IFS= read -r __input < /dev/tty; then
                printf -v "$__var_name" '%s' ""
                return 1
            fi
        fi
    else
        proxy_prompt_print "$__prompt"
        if ! IFS= read -r __input; then
            printf -v "$__var_name" '%s' ""
            return 1
        fi
    fi
    while [[ "$__input" == *$'\r' ]]; do
        __input="${__input%$'\r'}"
    done
    printf -v "$__var_name" '%s' "$__input"
    return 0
}
fi

_PROXY_SPIN_FRAMES=(
    '▏' '▎' '▍' '▌' '▋' '▊' '▉' '█' '▉' '▊' '▋' '▌' '▍' '▎'
)
_PROXY_SPIN_COLOR='\033[38;2;215;119;87m'
_PROXY_SPIN_INTERVAL=0.12

if ! declare -F proxy_run_with_spinner >/dev/null 2>&1; then
proxy_run_with_spinner() {
    local message="${1:-处理中...}" tmp_out="" tmp_err="" pid="" rc=0 spin_idx=0
    shift
    [[ $# -gt 0 ]] || return 1

    if ! proxy_prompt_tty_available; then
        "$@"
        return $?
    fi

    tmp_out="$(mktemp 2>/dev/null || true)"
    tmp_err="$(mktemp 2>/dev/null || true)"
    if [[ -z "$tmp_out" || -z "$tmp_err" ]]; then
        rm -f "$tmp_out" "$tmp_err" 2>/dev/null || true
        "$@"
        return $?
    fi

    local -a _spin=("${_PROXY_SPIN_FRAMES[@]}")
    "$@" >"$tmp_out" 2>"$tmp_err" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[K  '"${_PROXY_SPIN_COLOR}"'%s\033[0m %s' "${_spin[$spin_idx]}" "$message" > /dev/tty
        spin_idx=$(( (spin_idx + 1) % ${#_spin[@]} ))
        sleep "${_PROXY_SPIN_INTERVAL}"
    done
    wait "$pid" || rc=$?
    printf '\r\033[K' > /dev/tty
    [[ -s "$tmp_out" ]] && cat "$tmp_out"
    [[ -s "$tmp_err" ]] && cat "$tmp_err" >&2
    rm -f "$tmp_out" "$tmp_err" 2>/dev/null || true
    return "$rc"
}
fi

if ! declare -F proxy_run_with_spinner_compact >/dev/null 2>&1; then
proxy_run_with_spinner_compact() {
    local message="${1:-处理中...}" tmp_out="" tmp_err="" pid="" rc=0 spin_idx=0
    shift
    [[ $# -gt 0 ]] || return 1

    if ! proxy_prompt_tty_available; then
        "$@"
        return $?
    fi

    tmp_out="$(mktemp 2>/dev/null || true)"
    tmp_err="$(mktemp 2>/dev/null || true)"
    if [[ -z "$tmp_out" || -z "$tmp_err" ]]; then
        rm -f "$tmp_out" "$tmp_err" 2>/dev/null || true
        "$@"
        return $?
    fi

    local -a _spin=("${_PROXY_SPIN_FRAMES[@]}")
    "$@" >"$tmp_out" 2>"$tmp_err" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[K'"${_PROXY_SPIN_COLOR}"'%s\033[0m %s' "${_spin[$spin_idx]}" "$message" > /dev/tty
        spin_idx=$(( (spin_idx + 1) % ${#_spin[@]} ))
        sleep "${_PROXY_SPIN_INTERVAL}"
    done
    wait "$pid" || rc=$?
    printf '\r\033[K' > /dev/tty
    [[ -s "$tmp_out" ]] && cat "$tmp_out"
    [[ -s "$tmp_err" ]] && cat "$tmp_err" >&2
    rm -f "$tmp_out" "$tmp_err" 2>/dev/null || true
    return "$rc"
}
fi

if ! declare -F proxy_run_with_spinner_fg >/dev/null 2>&1; then
proxy_run_with_spinner_fg() {
    local message="${1:-处理中...}" rc=0 spinner_pid=""
    shift
    [[ $# -gt 0 ]] || return 1

    if ! proxy_prompt_tty_available; then
        "$@"
        return $?
    fi

    local -a _spin=("${_PROXY_SPIN_FRAMES[@]}")
    (
        local spin_idx=0
        while true; do
            printf '\r\033[K'"${_PROXY_SPIN_COLOR}"'%s\033[0m %s' "${_spin[$spin_idx]}" "$message" > /dev/tty
            spin_idx=$(( (spin_idx + 1) % ${#_spin[@]} ))
            sleep "${_PROXY_SPIN_INTERVAL}"
        done
    ) &
    spinner_pid=$!

    "$@" || rc=$?

    kill "$spinner_pid" 2>/dev/null
    wait "$spinner_pid" 2>/dev/null
    printf '\r\033[K' > /dev/tty
    return "$rc"
}
fi

if ! declare -F proxy_is_blank_string >/dev/null 2>&1; then
proxy_is_blank_string() { [[ -z "${1//[[:space:]]/}" ]]; }
fi

if ! declare -F gen_rand_alnum >/dev/null 2>&1; then
gen_rand_alnum() {
    local n="${1:-16}"
    openssl rand -base64 $((n*2)) 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c "$n"
}
fi

if ! declare -F check_service_result >/dev/null 2>&1; then
check_service_result() {
    local service_name=$1
    local action_text=$2
    local display_name=${3:-$service_name}
    local _i=0 state="" sub="" result="" stable=""
    for _i in {1..14}; do
        state="$(systemctl show -p ActiveState --value "$service_name" 2>/dev/null || echo unknown)"
        sub="$(systemctl show -p SubState --value "$service_name" 2>/dev/null || echo unknown)"
        result="$(systemctl show -p Result --value "$service_name" 2>/dev/null || echo unknown)"

        case "${state}:${sub}" in
            active:running|active:exited)
                stable="active"
                break
                ;;
            failed:*|inactive:dead|inactive:failed)
                stable="failed"
                break
                ;;
            activating:*|deactivating:*)
                sleep 0.4
                ;;
            *)
                sleep 0.4
                ;;
        esac
    done

    if [[ "$stable" == "active" ]]; then
        green "$display_name $action_text成功"
    else
        red "$display_name $action_text失败，请检查配置或日志"
        [[ -n "$state" ]] && yellow "当前状态: ${state}/${sub} (result=${result})"
    fi
}
fi

if ! declare -F is_shadowtls_configured >/dev/null 2>&1; then
is_shadowtls_configured() {
    if [[ -f "$ST_SERVICE_FILE" ]] && grep -q "server --listen" "$ST_SERVICE_FILE" 2>/dev/null; then
        return 0
    fi
    local unit_file
    for unit_file in /etc/systemd/system/shadow-tls-*.service; do
        [[ -e "$unit_file" ]] || continue
        if grep -q "server --listen" "$unit_file" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}
fi

if ! declare -F is_snell_configured >/dev/null 2>&1; then
is_snell_configured() {
    [[ -f "$SNELL_CONF" ]] || return 1
    grep -q "^listen" "$SNELL_CONF" 2>/dev/null || return 1
    grep -q "^psk" "$SNELL_CONF" 2>/dev/null || return 1
    return 0
}
fi

# --- base service helpers (merged from service_base_ops.sh) ---

SHADOWTLS_DISPLAY_NAME="${SHADOWTLS_DISPLAY_NAME:-shadow-tls-v3}"

check_root() {
    [[ $EUID -ne 0 ]] && red "错误: 必须使用 root 用户运行此脚本！\n" && exit 1
}

proxy_singbox_config_exists() {
    [[ -f "${CONF_DIR}/sing-box.json" ]] && return 0
    ls "${CONF_DIR}"/*.json >/dev/null 2>&1
}

check_port() {
    local port=$1
    if [[ -z "$port" ]]; then return 1; fi
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then return 1; fi
    if ss -tuln | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

proxy_watchdog_service_exists() {
    [[ -f "$WATCHDOG_SERVICE_FILE" ]]
}

proxy_shadowtls_service_names() {
    if declare -F shadowtls_iter_service_names >/dev/null 2>&1; then
        shadowtls_iter_service_names
        return 0
    fi

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

proxy_operate_singbox_service() {
    local action="${1:-}"
    [[ -n "$action" ]] || return 1
    proxy_singbox_config_exists || return 2
    case "$action" in
        start|stop|restart)
            systemctl "$action" sing-box
            ;;
        status)
            systemctl status sing-box
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_operate_snell_service() {
    local action="${1:-}"
    [[ -n "$action" ]] || return 1
    is_snell_configured || return 2

    case "$action" in
        start|restart)
            systemctl "$action" snell-v5
            ;;
        stop)
            systemctl stop snell-v5 2>/dev/null || true
            ;;
        status)
            systemctl status snell-v5
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_operate_watchdog_service() {
    local action="${1:-}"
    [[ -n "$action" ]] || return 1
    proxy_watchdog_service_exists || return 2

    case "$action" in
        start|stop|restart)
            systemctl "$action" proxy-watchdog 2>/dev/null || true
            ;;
        status)
            systemctl status proxy-watchdog --no-pager 2>/dev/null || true
            ;;
        *)
            return 1
            ;;
    esac
}

proxy_operate_shadowtls_services() {
    local action="${1:-}"
    local status_mode="${2:-default}"
    local any=0 service_name=""
    [[ -n "$action" ]] || return 1
    is_shadowtls_configured || return 2

    while IFS= read -r service_name; do
        [[ -n "$service_name" ]] || continue
        any=1
        case "$action" in
            start|stop|restart)
                systemctl "$action" "$service_name" 2>/dev/null || true
                ;;
            status)
                if [[ "$status_mode" == "no-pager" ]]; then
                    systemctl status "$service_name" --no-pager
                else
                    systemctl status "$service_name"
                fi
                ;;
            *)
                return 1
                ;;
        esac
    done < <(proxy_shadowtls_service_names)

    (( any == 1 )) || return 3
    return 0
}
