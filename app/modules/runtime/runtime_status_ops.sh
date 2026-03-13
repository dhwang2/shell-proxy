# Runtime log, dashboard, and lightweight status helpers for shell-proxy management.

RUNTIME_STATUS_COMMON_OPS_FILE="${RUNTIME_STATUS_COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$RUNTIME_STATUS_COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$RUNTIME_STATUS_COMMON_OPS_FILE"
fi

RUNTIME_STATUS_RELEASE_OPS_FILE="${RUNTIME_STATUS_RELEASE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/release_ops.sh}"
if [[ -f "$RUNTIME_STATUS_RELEASE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$RUNTIME_STATUS_RELEASE_OPS_FILE"
fi

SHADOWTLS_MARKER="${WORK_DIR}/.shadowtls_configured"
SHADOWTLS_DISPLAY_NAME="shadow-tls-v3"
RUNTIME_LOG_CLEAN_TS_FILE="${WORK_DIR}/.log_cleanup_ts"
RUNTIME_VIEW_CACHE_DIR="${CACHE_DIR}/view/runtime"
RUNTIME_DASHBOARD_STATIC_FILE="${RUNTIME_VIEW_CACHE_DIR}/dashboard-static.snapshot"
RUNTIME_DASHBOARD_STATE_FILE="${RUNTIME_VIEW_CACHE_DIR}/dashboard-static.fp"
RUNTIME_DASHBOARD_LOCK_FILE="${RUNTIME_VIEW_CACHE_DIR}/dashboard-static.lock"
RUNTIME_DASHBOARD_STACK_BUCKET_SECONDS="${RUNTIME_DASHBOARD_STACK_BUCKET_SECONDS:-3600}"

DASHBOARD_CACHE_OS_ID=""
DASHBOARD_CACHE_ARCH=""
DASHBOARD_CACHE_IP_STACK=""
DASHBOARD_CACHE_PROTOS=""
DASHBOARD_CACHE_PORTS=""
DASHBOARD_CACHE_RULES=""
DASHBOARD_CACHE_VERSION=""

ensure_runtime_log_files() {
    mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
    touch "$PROXY_SCRIPT_LOG" "$PROXY_WATCHDOG_LOG" >/dev/null 2>&1 || true
    cleanup_runtime_logs || true
}

cleanup_runtime_logs() {
    local now_ts last_ts
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    last_ts="$(cat "$RUNTIME_LOG_CLEAN_TS_FILE" 2>/dev/null || echo 0)"
    [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0
    [[ "$last_ts" =~ ^[0-9]+$ ]] || last_ts=0

    # 最多每 30 分钟做一次清理，避免频繁遍历目录。
    if (( now_ts > 0 && last_ts > 0 && (now_ts - last_ts) < 1800 )); then
        return 0
    fi

    # 清理陈旧的空日志占位文件。
    find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -size 0 -mtime +2 -delete 2>/dev/null || true

    # 超大日志保留末尾，避免无限增长。
    local f size max_bytes keep_lines
    max_bytes=$((20 * 1024 * 1024))
    keep_lines=3000
    for f in "$LOG_DIR"/*.log; do
        [[ -f "$f" ]] || continue
        size="$(wc -c <"$f" 2>/dev/null || echo 0)"
        [[ "$size" =~ ^[0-9]+$ ]] || size=0
        if (( size > max_bytes )); then
            tail -n "$keep_lines" "$f" > "${f}.tmp" 2>/dev/null || true
            mv -f "${f}.tmp" "$f" 2>/dev/null || true
        fi
    done

    # 删除超期归档（30 天前）。
    find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +30 -delete 2>/dev/null || true
    echo "$now_ts" > "$RUNTIME_LOG_CLEAN_TS_FILE" 2>/dev/null || true
}

rotate_script_log_if_needed() {
    local max_bytes=$((5 * 1024 * 1024))
    local keep_lines=1000
    local current_size=0

    [[ -f "$PROXY_SCRIPT_LOG" ]] || return
    current_size="$(wc -c <"$PROXY_SCRIPT_LOG" 2>/dev/null || echo 0)"
    if [[ "$current_size" =~ ^[0-9]+$ ]] && (( current_size > max_bytes )); then
        tail -n "$keep_lines" "$PROXY_SCRIPT_LOG" > "${PROXY_SCRIPT_LOG}.tmp" 2>/dev/null || true
        mv -f "${PROXY_SCRIPT_LOG}.tmp" "$PROXY_SCRIPT_LOG" 2>/dev/null || true
    fi
}

proxy_log() {
    local level="INFO"
    if [[ $# -gt 0 ]]; then
        level="$1"
        shift
    fi
    local message="$*"
    [[ -z "$message" ]] && return

    ensure_runtime_log_files
    rotate_script_log_if_needed
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >>"$PROXY_SCRIPT_LOG" 2>/dev/null || true
}

get_os_id() {
    local os_id="linux"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_id="${ID:-linux}"
    fi
    echo "$os_id"
}

get_arch() {
    uname -m 2>/dev/null || echo unknown
}

dashboard_version_label() {
    local current_ref="" value=""
    current_ref="$(read_script_source_ref 2>/dev/null || true)"
    case "$current_ref" in
        release:*)
            value="${current_ref#release:}"
            [[ "$value" == v* ]] || value="v${value}"
            echo "$value"
            ;;
        repo:*)
            value="${current_ref#repo:}"
            echo "${value:0:8}"
            ;;
        *)
            if [[ -n "$current_ref" ]]; then
                echo "${current_ref:0:8}"
            else
                local tag=""
                tag="$(read_proxy_release_tag_cache 2>/dev/null || true)"
                if [[ -n "$tag" ]]; then
                    [[ "$tag" == v* ]] || tag="v${tag}"
                    echo "$tag"
                else
                    echo "unknown"
                fi
            fi
            ;;
    esac
}

get_singbox_conf_file() {
    if [[ -f "${CONF_DIR}/sing-box.json" ]]; then
        echo "${CONF_DIR}/sing-box.json"
        return 0
    fi
    ls "${CONF_DIR}"/*.json 2>/dev/null | head -n 1
}

runtime_snell_configured_listen_port() {
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

shadowtls_backend_type_by_target_port() {
    local target_port="${1:-}"
    local conf_file="${2:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_singbox_conf_file)"
    [[ "$target_port" =~ ^[0-9]+$ ]] || { echo "unknown"; return 0; }

    local snell_port
    snell_port="$(runtime_snell_configured_listen_port 2>/dev/null || true)"
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
}

dashboard_conf_snapshot() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || {
        printf 'types=\nports=\nrules=0\n'
        return 0
    }

    jq -r '
        def norm_type:
            if . == "shadowsocks" then "ss" else . end;
        def join_csv($arr):
            ($arr | map(select(type == "string" and length > 0)) | unique | join(","));
        def join_plus($arr):
            ($arr | map(select(type == "string" and length > 0)) | unique | join("+"));
        "types=" + join_plus([.inbounds[]?.type // empty | norm_type]),
        "ports=" + join_csv([.inbounds[]?.listen_port // empty | tostring]),
        "rules=" + ((.route.rules | length // 0) | tostring)
    ' "$conf_file" 2>/dev/null || printf 'types=\nports=\nrules=0\n'
}

get_shadowtls_binding_lines_light() {
    local conf_file="${1:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_singbox_conf_file)"

    is_shadowtls_configured || return 0
    declare -F shadowtls_iter_service_names >/dev/null 2>&1 || return 0
    declare -F shadowtls_listen_port >/dev/null 2>&1 || return 0
    declare -F shadowtls_target_port >/dev/null 2>&1 || return 0
    declare -F shadowtls_backend_type_by_target_port >/dev/null 2>&1 || return 0

    local service_name st_port st_target st_backend
    while IFS= read -r service_name; do
        [[ -n "$service_name" ]] || continue
        st_port="$(shadowtls_listen_port "$service_name" 2>/dev/null || true)"
        st_target="$(shadowtls_target_port "$service_name" 2>/dev/null || true)"
        st_backend="$(shadowtls_backend_type_by_target_port "$st_target" "$conf_file" 2>/dev/null || true)"
        echo "${service_name}|${st_port}|${st_target}|${st_backend}"
    done < <(shadowtls_iter_service_names)
}

get_configured_protocols() {
    local conf_file="${1:-}"
    local st_lines="${2:-}"
    local base_protos="${3:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_singbox_conf_file)"
    local protos=""

    has_proto_token() {
        local token="$1"
        [[ -n "$token" ]] || return 1
        [[ "+${protos}+" == *"+${token}+"* ]]
    }

    append_proto_token() {
        local token="$1"
        [[ -n "$token" ]] || return 0
        has_proto_token "$token" && return 0
        if [[ -n "$protos" ]]; then
            protos+="+${token}"
        else
            protos="${token}"
        fi
    }

    replace_proto_token() {
        local old_token="$1"
        local new_token="$2"
        [[ -n "$old_token" && -n "$new_token" ]] || return 0
        local out="" p
        local -a __parts
        IFS='+' read -r -a __parts <<< "$protos"
        for p in "${__parts[@]}"; do
            [[ "$p" == "$old_token" ]] && p="$new_token"
            if [[ -n "$out" ]]; then
                out+="+${p}"
            else
                out="${p}"
            fi
        done
        protos="$out"
    }

    protos="$base_protos"

    if [[ -f "$SNELL_CONF" ]]; then
        append_proto_token "snell-v5"
    fi
    if is_shadowtls_configured; then
        local st_ss=0 st_snell=0 st_total=0 st_unknown=0
        local st_line st_service st_port st_target st_backend
        if [[ -z "${st_lines// }" ]]; then
            st_lines="$(get_shadowtls_binding_lines_light "$conf_file" 2>/dev/null || true)"
        fi
        while IFS= read -r st_line; do
            [[ -n "$st_line" ]] || continue
            IFS='|' read -r st_service st_port st_target st_backend <<< "$st_line"
            ((st_total++))
            case "$st_backend" in
                ss) ((st_ss++)) ;;
                snell) ((st_snell++)) ;;
                *) ((st_unknown++)) ;;
            esac
        done <<< "$st_lines"
        if (( st_snell > 0 )); then
            if has_proto_token "snell-v5"; then
                replace_proto_token "snell-v5" "snell-v5-shadow-tls-v3"
            else
                append_proto_token "snell-v5-shadow-tls-v3"
            fi
        fi

        if (( st_ss > 0 )); then
            if has_proto_token "ss"; then
                replace_proto_token "ss" "ss-shadow-tls-v3"
            else
                append_proto_token "ss-shadow-tls-v3"
            fi
        fi

        if (( st_unknown > 0 )); then
            append_proto_token "${SHADOWTLS_DISPLAY_NAME}"
        fi
    fi

    echo "${protos:-none}"
}

get_configured_ports() {
    local conf_file="${1:-}"
    local st_lines="${2:-}"
    local base_ports="${3:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_singbox_conf_file)"

    local port_lines=""
    if [[ -n "${base_ports// }" ]]; then
        port_lines+=$(printf '%s' "$base_ports" | tr ',' '\n')
        port_lines+=$'\n'
    fi

    if [[ -f "$SNELL_CONF" ]]; then
        local s_port
        s_port="$(grep "^listen" "$SNELL_CONF" 2>/dev/null | awk -F':' '{print $NF}' | tr -d ' ')"
        [[ -n "$s_port" ]] && port_lines+="${s_port}"$'\n'
    fi

    if is_shadowtls_configured; then
        local st_line st_service st_port st_target st_backend
        if [[ -z "${st_lines// }" ]]; then
            st_lines="$(get_shadowtls_binding_lines_light "$conf_file" 2>/dev/null || true)"
        fi
        while IFS= read -r st_line; do
            [[ -n "$st_line" ]] || continue
            IFS='|' read -r st_service st_port st_target st_backend <<< "$st_line"
            [[ "$st_port" =~ ^[0-9]+$ ]] && port_lines+="${st_port}"$'\n'
        done <<< "$st_lines"

    fi

    local ports
    ports="$(printf '%s' "$port_lines" | awk '/^[0-9]+$/' | sort -n -u | paste -sd, -)"
    echo "${ports:-none}"
}

get_route_rule_count() {
    local conf_file="${1:-}"
    local base_rules="${2:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_singbox_conf_file)"
    if [[ -z "$conf_file" || ! -f "$conf_file" ]]; then
        echo "0"
        return
    fi
    jq -r '
        (.route.rules // [])
        | map(select(
            (
                (.action // "") == "sniff"
                or ((.protocol // "") == "dns" and (.action // "") == "hijack-dns")
                or (
                    (.ip_is_private // false) == true
                    and (.action // "") == "route"
                    and (.outbound // "") == "🐸 direct"
                )
            ) | not
        ))
        | length
    ' "$conf_file" 2>/dev/null || echo "${base_rules:-0}"
}

PROXY_SERVICE_STATE_CACHE_SINGBOX=""
PROXY_SERVICE_STATE_CACHE_SNELL=""
PROXY_SERVICE_STATE_CACHE_TS=0
PROXY_SERVICE_STATE_CACHE_TTL="${PROXY_SERVICE_STATE_CACHE_TTL:-3}"

proxy_refresh_service_state_cache() {
    PROXY_SERVICE_STATE_CACHE_SINGBOX="$(systemctl is-active sing-box 2>/dev/null || true)"
    PROXY_SERVICE_STATE_CACHE_SNELL="$(systemctl is-active snell-v5 2>/dev/null || true)"
    [[ -z "$PROXY_SERVICE_STATE_CACHE_SINGBOX" ]] && PROXY_SERVICE_STATE_CACHE_SINGBOX="inactive"
    [[ -z "$PROXY_SERVICE_STATE_CACHE_SNELL" ]] && PROXY_SERVICE_STATE_CACHE_SNELL="inactive"
    PROXY_SERVICE_STATE_CACHE_TS="$(date +%s 2>/dev/null || echo 0)"
}

proxy_invalidate_service_state_cache() {
    PROXY_SERVICE_STATE_CACHE_TS=0
}

proxy_ensure_service_state_cache() {
    local now_ts=0
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0
    if [[ -n "$PROXY_SERVICE_STATE_CACHE_SINGBOX" && "$PROXY_SERVICE_STATE_CACHE_TS" =~ ^[0-9]+$ ]] \
        && (( now_ts > 0 && PROXY_SERVICE_STATE_CACHE_TS > 0 && (now_ts - PROXY_SERVICE_STATE_CACHE_TS) < PROXY_SERVICE_STATE_CACHE_TTL )); then
        return 0
    fi
    proxy_refresh_service_state_cache
}

get_overall_status() {
    proxy_ensure_service_state_cache
    local sb_state="$PROXY_SERVICE_STATE_CACHE_SINGBOX"
    local sn_state="$PROXY_SERVICE_STATE_CACHE_SNELL"

    if [[ "$sb_state" == "active" && ("$sn_state" == "active" || "$sn_state" == "inactive" || "$sn_state" == "unknown") ]]; then
        proxy_status_dot "active"
        return
    fi

    if [[ "$sb_state" == "active" || "$sn_state" == "active" ]]; then
        echo -e "\033[33m\033[01m● 部分故障\033[0m"
        return
    fi

    if [[ "$sb_state" == "failed" || "$sn_state" == "failed" ]]; then
        proxy_status_dot "failed"
        return
    fi

    proxy_status_dot "inactive"
}

runtime_cache_write_atomic() {
    local path="${1:-}" content="${2:-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

dashboard_static_stack_bucket() {
    local now_ts interval
    interval="${RUNTIME_DASHBOARD_STACK_BUCKET_SECONDS:-300}"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=300
    (( interval > 0 )) || interval=300
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0
    echo $((now_ts / interval))
}

dashboard_static_state_fingerprint() {
    local conf_file="${1:-}"
    local conf_fp snell_fp shadowtls_fp source_ref stack_bucket
    [[ -z "$conf_file" ]] && conf_file="$(get_singbox_conf_file 2>/dev/null || true)"

    conf_fp="$(calc_file_meta_signature "$conf_file" 2>/dev/null || echo "0:0")"
    snell_fp="$(calc_file_meta_signature "$SNELL_CONF" 2>/dev/null || echo "0:0")"
    shadowtls_fp="$(calc_shadowtls_render_fingerprint 2>/dev/null | cksum 2>/dev/null | awk '{print $1":"$2}')"
    [[ -n "$shadowtls_fp" ]] || shadowtls_fp="0:0"
    source_ref="$(read_script_source_ref 2>/dev/null || true)"
    [[ -n "$source_ref" ]] || source_ref="$(read_proxy_release_tag_cache 2>/dev/null || echo unknown)"
    [[ -n "$source_ref" ]] || source_ref="unknown"
    stack_bucket="$(dashboard_static_stack_bucket)"
    printf '%s|%s|%s|%s|%s\n' "$conf_fp" "$snell_fp" "$shadowtls_fp" "$source_ref" "$stack_bucket" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

dashboard_static_render_snapshot() {
    local conf_file="${1:-}"
    local os_id arch ip_stack protos ports rules st_lines
    local snapshot base_protos base_ports base_rules line key value
    local raw_stack version

    [[ -z "$conf_file" ]] && conf_file="$(get_singbox_conf_file 2>/dev/null || true)"

    os_id="$(get_os_id)"
    arch="$(get_arch)"

    snapshot="$(dashboard_conf_snapshot "$conf_file")"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
            types) base_protos="$value" ;;
            ports) base_ports="$value" ;;
            rules) base_rules="$value" ;;
        esac
    done <<< "$snapshot"

    st_lines="$(get_shadowtls_binding_lines_light "$conf_file" 2>/dev/null || true)"
    protos="$(get_configured_protocols "$conf_file" "$st_lines" "$base_protos")"
    ports="$(get_configured_ports "$conf_file" "$st_lines" "$base_ports")"
    rules="$(get_route_rule_count "$conf_file" "$base_rules")"
    raw_stack="$(detect_server_ip_stack 2>/dev/null || echo ipv4)"
    case "$raw_stack" in
        dualstack) ip_stack="ipv4/ipv6" ;;
        ipv6) ip_stack="ipv6" ;;
        *) ip_stack="ipv4" ;;
    esac
    version="$(dashboard_version_label)"

    cat <<EOF
os_id=${os_id}
arch=${arch}
ip_stack=${ip_stack}
protos=${protos:-none}
ports=${ports:-none}
rules=${rules:-0}
version=${version}
EOF
}

dashboard_static_assign_cache_vars() {
    local text="${1:-}" line key value
    DASHBOARD_CACHE_OS_ID="linux"
    DASHBOARD_CACHE_ARCH="unknown"
    DASHBOARD_CACHE_IP_STACK="ipv4"
    DASHBOARD_CACHE_PROTOS="none"
    DASHBOARD_CACHE_PORTS="none"
    DASHBOARD_CACHE_RULES="0"
    DASHBOARD_CACHE_VERSION="unknown"

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
            os_id) DASHBOARD_CACHE_OS_ID="$value" ;;
            arch) DASHBOARD_CACHE_ARCH="$value" ;;
            ip_stack) DASHBOARD_CACHE_IP_STACK="$value" ;;
            protos) DASHBOARD_CACHE_PROTOS="$value" ;;
            ports) DASHBOARD_CACHE_PORTS="$value" ;;
            rules) DASHBOARD_CACHE_RULES="$value" ;;
            version) DASHBOARD_CACHE_VERSION="$value" ;;
        esac
    done <<< "$text"
}

dashboard_static_cache_has_snapshot() {
    [[ -f "$RUNTIME_DASHBOARD_STATIC_FILE" && -f "$RUNTIME_DASHBOARD_STATE_FILE" ]]
}

dashboard_static_cache_read_state_fingerprint() {
    [[ -f "$RUNTIME_DASHBOARD_STATE_FILE" ]] || return 1
    tr -d '[:space:]' <"$RUNTIME_DASHBOARD_STATE_FILE" 2>/dev/null
}

dashboard_static_cache_is_fresh() {
    local conf_file="${1:-}" cached_fp expected_fp
    dashboard_static_cache_has_snapshot || return 1
    cached_fp="$(dashboard_static_cache_read_state_fingerprint 2>/dev/null || true)"
    [[ -n "$cached_fp" ]] || return 1
    expected_fp="$(dashboard_static_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$expected_fp" ]] || return 1
    [[ "$cached_fp" == "$expected_fp" ]]
}

dashboard_static_cache_rebuild_sync() {
    local conf_file="${1:-}" snapshot state_fp
    snapshot="$(dashboard_static_render_snapshot "$conf_file")"
    state_fp="$(dashboard_static_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"

    runtime_cache_write_atomic "$RUNTIME_DASHBOARD_STATIC_FILE" "$snapshot" || return 1
    runtime_cache_write_atomic "$RUNTIME_DASHBOARD_STATE_FILE" "$state_fp" || return 1
}

dashboard_static_cache_rebuild_with_lock() {
    local conf_file="${1:-}"
    mkdir -p "$RUNTIME_VIEW_CACHE_DIR" >/dev/null 2>&1 || true

    if command -v flock >/dev/null 2>&1; then
        (
            flock -n 9 || exit 0
            dashboard_static_cache_rebuild_sync "$conf_file"
        ) 9>"$RUNTIME_DASHBOARD_LOCK_FILE"
        return $?
    fi

    local lock_dir="${RUNTIME_DASHBOARD_LOCK_FILE}.d"
    mkdir "$lock_dir" >/dev/null 2>&1 || return 0
    dashboard_static_cache_rebuild_sync "$conf_file"
    rmdir "$lock_dir" >/dev/null 2>&1 || true
}

dashboard_static_cache_ensure_fresh() {
    local conf_file="${1:-}"
    if dashboard_static_cache_is_fresh "$conf_file"; then
        return 0
    fi
    dashboard_static_cache_rebuild_with_lock "$conf_file" >/dev/null 2>&1 || return 1
    dashboard_static_cache_is_fresh "$conf_file"
}

dashboard_static_cache_load_into_vars() {
    local conf_file="${1:-}" snapshot_text
    dashboard_static_cache_ensure_fresh "$conf_file" || return 1
    snapshot_text="$(cat "$RUNTIME_DASHBOARD_STATIC_FILE" 2>/dev/null || true)"
    [[ -n "$snapshot_text" ]] || return 1
    dashboard_static_assign_cache_vars "$snapshot_text"
}

print_dashboard() {
    local os_id arch ip_stack status protos ports rules conf_file version
    local C_RESET C_TITLE C_LABEL C_VAL_SYS C_VAL_PROTO C_VAL_PORT C_VAL_RULE
    if [[ -n "${PROXY_TTY_RENDER_FORCE:-}" || -t 1 ]]; then
        C_RESET=$'\033[0m'
        C_TITLE=$'\033[1;36m'
        C_LABEL=$'\033[1;37m'
        C_VAL_SYS=$'\033[1;33m'
        C_VAL_PROTO=$'\033[1;36m'
        C_VAL_PORT=$'\033[1;35m'
        C_VAL_RULE=$'\033[1;32m'
    else
        C_RESET=""
        C_TITLE=""
        C_LABEL=""
        C_VAL_SYS=""
        C_VAL_PROTO=""
        C_VAL_PORT=""
        C_VAL_RULE=""
    fi

    conf_file="$(get_singbox_conf_file)"
    if dashboard_static_cache_load_into_vars "$conf_file"; then
        os_id="${DASHBOARD_CACHE_OS_ID}"
        arch="${DASHBOARD_CACHE_ARCH}"
        ip_stack="${DASHBOARD_CACHE_IP_STACK}"
        protos="${DASHBOARD_CACHE_PROTOS}"
        ports="${DASHBOARD_CACHE_PORTS}"
        rules="${DASHBOARD_CACHE_RULES}"
        version="${DASHBOARD_CACHE_VERSION}"
    else
        dashboard_static_assign_cache_vars "$(dashboard_static_render_snapshot "$conf_file")"
        os_id="${DASHBOARD_CACHE_OS_ID}"
        arch="${DASHBOARD_CACHE_ARCH}"
        ip_stack="${DASHBOARD_CACHE_IP_STACK}"
        protos="${DASHBOARD_CACHE_PROTOS}"
        ports="${DASHBOARD_CACHE_PORTS}"
        rules="${DASHBOARD_CACHE_RULES}"
        version="${DASHBOARD_CACHE_VERSION}"
    fi

    status="$(get_overall_status)"

    echo -e "${C_TITLE}═════════════════════════════════════════════${C_RESET}"
    echo -e "${C_TITLE}      多协议代理 一键部署  [服务端]${C_RESET}"
    echo -e "${C_TITLE}  作者: dhwang2  命令: proxy  版本: ${version}${C_RESET}"
    echo -e "${C_TITLE}═════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_LABEL}服务端管理${C_RESET}"
    echo -e "  ${C_LABEL}系统:${C_RESET} ${C_VAL_SYS}${os_id}${C_RESET} ${C_LABEL}| 架构:${C_RESET} ${C_VAL_SYS}${arch}${C_RESET} ${C_LABEL}| 网络栈:${C_RESET} ${C_VAL_SYS}${ip_stack}${C_RESET}"
    echo -e "  ${C_LABEL}状态:${C_RESET} ${status}"
    echo -e "  ${C_LABEL}协议:${C_RESET} ${C_VAL_PROTO}${protos}${C_RESET}"
    echo -e "  ${C_LABEL}端口:${C_RESET} ${C_VAL_PORT}${ports}${C_RESET}"
    echo -e "  ${C_LABEL}分流:${C_RESET} ${C_VAL_RULE}${rules}条规则${C_RESET}"
    echo "─────────────────────────────────────────────"
}
