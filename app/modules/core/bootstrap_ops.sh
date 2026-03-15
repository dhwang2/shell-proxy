# Lightweight bootstrap/runtime helpers for management base loading.

BOOTSTRAP_COMMON_OPS_FILE="${BOOTSTRAP_COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common_ops.sh}"
if [[ -f "$BOOTSTRAP_COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$BOOTSTRAP_COMMON_OPS_FILE"
fi

BOOTSTRAP_RELEASE_OPS_FILE="${BOOTSTRAP_RELEASE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release_ops.sh}"
if [[ -f "$BOOTSTRAP_RELEASE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$BOOTSTRAP_RELEASE_OPS_FILE"
fi

get_conf_file() {
    if [[ -f "${CONF_DIR}/sing-box.json" ]]; then
        echo "${CONF_DIR}/sing-box.json"
        return 0
    fi
    ls "${CONF_DIR}"/*.json 2>/dev/null | head -n 1
}

PROXY_IP_STACK_CACHE_VALUE=""
PROXY_IP_STACK_CACHE_TS=0
PROXY_IP_STACK_CACHE_TTL="${PROXY_IP_STACK_CACHE_TTL:-3600}"

detect_server_ip_stack() {
    local now_ts=0
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0

    if [[ -n "$PROXY_IP_STACK_CACHE_VALUE" && "$PROXY_IP_STACK_CACHE_TS" =~ ^[0-9]+$ ]] \
        && (( now_ts > 0 && PROXY_IP_STACK_CACHE_TS > 0 && (now_ts - PROXY_IP_STACK_CACHE_TS) < PROXY_IP_STACK_CACHE_TTL )); then
        printf '%s\n' "$PROXY_IP_STACK_CACHE_VALUE"
        return 0
    fi

    local has_v4=0 has_v6=0

    if ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | grep -q .; then
        has_v4=1
    fi
    if ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | grep -vi '^fe80:' | grep -q .; then
        has_v6=1
    fi

    if (( has_v4 == 1 && has_v6 == 1 )); then
        PROXY_IP_STACK_CACHE_VALUE="dualstack"
    elif (( has_v6 == 1 )); then
        PROXY_IP_STACK_CACHE_VALUE="ipv6"
    else
        PROXY_IP_STACK_CACHE_VALUE="ipv4"
    fi
    PROXY_IP_STACK_CACHE_TS="$now_ts"
    printf '%s\n' "$PROXY_IP_STACK_CACHE_VALUE"
}


backup_conf_file() {
    local conf_file="$1"
    [[ -z "$conf_file" || ! -f "$conf_file" ]] && return 0
    mkdir -p "${WORK_DIR}/backup"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    cp "$conf_file" "${WORK_DIR}/backup/$(basename "$conf_file").${ts}.bak"
}

PROXY_APPLY_STATUS_FILE="${PROXY_APPLY_STATUS_FILE:-${CACHE_DIR}/apply.status}"
PROXY_APPLY_LOCK_FILE="${PROXY_APPLY_LOCK_FILE:-${CACHE_DIR}/apply.lock}"
PROXY_APPLY_PENDING_TIMEOUT_SECONDS="${PROXY_APPLY_PENDING_TIMEOUT_SECONDS:-30}"

proxy_apply_status_file() {
    printf '%s\n' "${PROXY_APPLY_STATUS_FILE}"
}

proxy_apply_lock_file() {
    printf '%s\n' "${PROXY_APPLY_LOCK_FILE}"
}

proxy_apply_write_status() {
    local status_file="${1:-}" content="${2:-}"
    [[ -n "$status_file" && -n "$content" ]] || return 1
    proxy_cache_write_atomic "$status_file" "$content"
}

proxy_apply_pending_status_line() {
    local now_ts=0 request_id=""
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0
    request_id="${BASHPID:-$$}-${RANDOM}${RANDOM}"
    printf 'pending:%s:%s\n' "$now_ts" "$request_id"
}

config_apply_sync() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0

    restart_singbox_preflight "$conf_file"

    if declare -F proxy_run_with_spinner >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        proxy_run_with_spinner "sing-box 重启中..." restart_singbox_service_with_check
    else
        systemctl restart sing-box && check_service_result "sing-box" "重启"
    fi
}

config_apply_async_worker() {
    local conf_file="${1:-}" status_file="${2:-}" lock_file="${3:-}"
    local current_line="" latest_line="" status_ts="" rc=0 lock_dir=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    [[ -n "$status_file" && -n "$lock_file" ]] || return 1

    if command -v flock >/dev/null 2>&1; then
        exec 9>"$lock_file"
        flock -n 9 || return 0
    else
        lock_dir="${lock_file}.d"
        mkdir "$lock_dir" >/dev/null 2>&1 || return 0
        trap 'rmdir "$lock_dir" >/dev/null 2>&1 || true' RETURN
    fi

    while :; do
        current_line="$(cat "$status_file" 2>/dev/null || true)"
        [[ "$current_line" == pending:* ]] || current_line="$(proxy_apply_pending_status_line)"

        rc=0
        restart_singbox_preflight "$conf_file" >/dev/null 2>&1 || rc=$?
        if (( rc == 0 )); then
            systemctl restart sing-box >/dev/null 2>&1 || rc=$?
        fi

        if (( rc == 0 )) && declare -F sync_singbox_loaded_fingerprint >/dev/null 2>&1; then
            sync_singbox_loaded_fingerprint "$conf_file" >/dev/null 2>&1 || true
        fi

        if declare -F proxy_invalidate_service_state_cache >/dev/null 2>&1; then
            proxy_invalidate_service_state_cache >/dev/null 2>&1 || true
        fi
        if declare -F proxy_main_menu_view_cache_invalidate >/dev/null 2>&1; then
            proxy_main_menu_view_cache_invalidate >/dev/null 2>&1 || true
        fi

        if (( rc != 0 )); then
            status_ts="$(date +%s 2>/dev/null || echo 0)"
            proxy_apply_write_status "$status_file" "failed:${status_ts}" >/dev/null 2>&1 || true
            if declare -F proxy_log >/dev/null 2>&1; then
                proxy_log "ERROR" "异步配置应用失败: conf=${conf_file}"
            fi
            return 0
        fi

        latest_line="$(cat "$status_file" 2>/dev/null || true)"
        if [[ "$latest_line" == pending:* && "$latest_line" != "$current_line" ]]; then
            continue
        fi

        status_ts="$(date +%s 2>/dev/null || echo 0)"
        proxy_apply_write_status "$status_file" "done:${status_ts}" >/dev/null 2>&1 || true
        if declare -F proxy_log >/dev/null 2>&1; then
            proxy_log "INFO" "异步配置应用完成: conf=${conf_file}"
        fi
        return 0
    done
}

config_apply_async() {
    local conf_file="${1:-}" status_file="" lock_file="" pending_line=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0

    status_file="$(proxy_apply_status_file)"
    lock_file="$(proxy_apply_lock_file)"
    pending_line="$(proxy_apply_pending_status_line)"
    proxy_apply_write_status "$status_file" "$pending_line" || return 1

    if declare -F proxy_invalidate_service_state_cache >/dev/null 2>&1; then
        proxy_invalidate_service_state_cache >/dev/null 2>&1 || true
    fi
    if declare -F proxy_log >/dev/null 2>&1; then
        proxy_log "INFO" "异步配置应用已排队: conf=${conf_file}"
    fi

    (
        config_apply_async_worker "$conf_file" "$status_file" "$lock_file"
    ) >/dev/null 2>&1 &

    green "⟳ 配置生效中..."
}

proxy_check_pending_apply_status() {
    local status_file="" status_line="" status="" ts="" _request_id=""
    local now_ts=0 age=0 pending_timeout=30

    status_file="$(proxy_apply_status_file)"
    [[ -f "$status_file" ]] || return 0

    status_line="$(cat "$status_file" 2>/dev/null || true)"
    [[ -n "$status_line" ]] || return 0
    IFS=':' read -r status ts _request_id <<<"$status_line"

    pending_timeout="${PROXY_APPLY_PENDING_TIMEOUT_SECONDS:-30}"
    [[ "$pending_timeout" =~ ^[0-9]+$ ]] || pending_timeout=30
    (( pending_timeout > 0 )) || pending_timeout=30

    case "$status" in
        pending)
            now_ts="$(date +%s 2>/dev/null || echo 0)"
            [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0
            [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
            age=$((now_ts - ts))
            if (( age < pending_timeout )); then
                yellow "  ⟳ 配置应用中..."
                return 0
            fi
            proxy_apply_write_status "$status_file" "failed:${now_ts}" >/dev/null 2>&1 || true
            red "  ✗ 上次配置应用失败，请检查日志"
            ;;
        done)
            rm -f "$status_file" 2>/dev/null || true
            ;;
        failed)
            red "  ✗ 上次配置应用失败，请检查日志"
            ;;
    esac
}

restart_singbox_preflight() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    if declare -F sanitize_singbox_inbound_uuids >/dev/null 2>&1; then
        if sanitize_singbox_inbound_uuids "$conf_file"; then
            yellow "检测到无效 UUID，已自动修复 sing-box 入站用户。"
        fi
    fi
    if declare -F sanitize_singbox_inbound_user_names_if_needed >/dev/null 2>&1; then
        if sanitize_singbox_inbound_user_names_if_needed "$conf_file"; then
            yellow "检测到缺失用户名，已自动补全 sing-box 入站用户名称。"
        fi
    fi
    if declare -F normalize_singbox_top_level_key_order >/dev/null 2>&1; then
        normalize_singbox_top_level_key_order "$conf_file" >/dev/null 2>&1 || true
    fi
}

restart_singbox_service_with_check() {
    systemctl restart sing-box && check_service_result "sing-box" "重启"
}

restart_singbox_if_present() {
    if ! systemctl is-enabled sing-box >/dev/null 2>&1 \
        && ! systemctl is-active sing-box >/dev/null 2>&1; then
        [[ -f /etc/systemd/system/sing-box.service ]] || return 0
    fi

    local conf_file
    conf_file="$(get_conf_file)"
    if [[ "${PROXY_CONFIG_APPLY_MODE:-sync}" == "async" ]]; then
        config_apply_async "$conf_file"
    else
        if config_apply_sync "$conf_file"; then
            if declare -F sync_singbox_loaded_fingerprint >/dev/null 2>&1; then
                sync_singbox_loaded_fingerprint "$conf_file" >/dev/null 2>&1 || true
            fi
        fi
    fi

    if declare -F proxy_invalidate_after_mutation >/dev/null 2>&1; then
        proxy_invalidate_after_mutation "config"
    fi
}

proxy_runtime_cache_dir() {
    echo "${CACHE_DIR}/runtime"
}

proxy_runtime_cache_key() {
    local raw="${1:-}"
    printf '%s' "$raw" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

proxy_runtime_cache_file() {
    local scope="${1:-}" raw_key="${2:-}" cache_key
    [[ -n "$scope" ]] || return 1
    cache_key="$(proxy_runtime_cache_key "${scope}|${raw_key}")"
    printf '%s\n' "$(proxy_runtime_cache_dir)/${scope}-${cache_key}.cache"
}

proxy_cache_write_atomic() {
    local path="${1:-}" content="${2-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

proxy_runtime_state_read_matching_value() {
    local cache_file="${1:-}" expected_key="${2:-}" cached_key="" cached_value=""
    [[ -n "$cache_file" && -n "$expected_key" && -f "$cache_file" ]] || return 1
    IFS=$'\t' read -r cached_key cached_value <"$cache_file"
    [[ -n "$cached_key" && "$cached_key" == "$expected_key" && -n "$cached_value" ]] || return 1
    printf '%s\n' "$cached_value"
}

proxy_runtime_state_write_value() {
    local cache_file="${1:-}" state_key="${2:-}" state_value="${3:-}"
    [[ -n "$cache_file" && -n "$state_key" ]] || return 1
    proxy_cache_write_atomic "$cache_file" "$(printf '%s\t%s\n' "$state_key" "$state_value")"
}

calc_file_meta_signature() {
    local file="${1:-}" meta_sig=""
    [[ -n "$file" && -f "$file" ]] || return 1

    if [[ -z "${PROXY_STAT_FORMAT_STYLE:-}" ]]; then
        if stat -Lc '%s:%Y:%i' "$file" >/dev/null 2>&1; then
            PROXY_STAT_FORMAT_STYLE="gnu"
        elif stat -f '%z:%m:%i' "$file" >/dev/null 2>&1; then
            PROXY_STAT_FORMAT_STYLE="bsd"
        else
            PROXY_STAT_FORMAT_STYLE="none"
        fi
    fi

    case "${PROXY_STAT_FORMAT_STYLE:-none}" in
        gnu)
            meta_sig="$(stat -Lc '%s:%Y:%i' "$file" 2>/dev/null || true)"
            ;;
        bsd)
            meta_sig="$(stat -f '%z:%m:%i' "$file" 2>/dev/null || true)"
            ;;
        *)
            meta_sig=""
            ;;
    esac
    [[ -n "$meta_sig" ]] || return 1
    printf '%s\n' "$meta_sig"
}

ensure_file_fp_cache_maps() {
    if ! declare -p PROXY_FILE_FP_META 2>/dev/null | grep -q 'declare -A'; then
        declare -gA PROXY_FILE_FP_META=()
    fi
    if ! declare -p PROXY_FILE_FP_VALUE 2>/dev/null | grep -q 'declare -A'; then
        declare -gA PROXY_FILE_FP_VALUE=()
    fi
    PROXY_FILE_FP_CACHE_INIT=1
}

calc_file_fingerprint() {
    local file="${1:-}" meta_sig="" cache_file="" cached_fp=""
    [[ -n "$file" && -f "$file" ]] || return 1
    meta_sig="$(calc_file_meta_signature "$file" 2>/dev/null || true)"
    [[ -n "$meta_sig" ]] || return 1
    cache_file="$(proxy_runtime_cache_file "file-fingerprint" "$file" 2>/dev/null || true)"
    cached_fp="$(proxy_runtime_state_read_matching_value "$cache_file" "$meta_sig" 2>/dev/null || true)"
    if [[ -n "$cached_fp" ]]; then
        printf '%s\n' "$cached_fp"
        return 0
    fi

    local fp=""
    if command -v sha256sum >/dev/null 2>&1; then
        fp="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        fp="$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')"
    elif command -v openssl >/dev/null 2>&1; then
        fp="$(openssl dgst -sha256 "$file" 2>/dev/null | awk '{print $NF}')"
    fi
    [[ -n "$fp" ]] || return 1

    proxy_runtime_state_write_value "$cache_file" "$meta_sig" "$fp" >/dev/null 2>&1 || true
    printf '%s\n' "$fp"
}

update_self() {
    local updater="${SELF_UPDATE_SCRIPT:-${WORK_DIR}/self_update.sh}"
    local management_script="${WORK_DIR}/management.sh"
    local update_mode="${1:-}"
    ensure_self_update_bootstrap() {
        local base_url repo_name resolved_ref ts source_rel
        repo_name="${REPO_USER}/${REPO_NAME}"
        resolved_ref="$(resolve_repo_branch_commit_sha_cached "$repo_name" "$BRANCH" 60 2>/dev/null || true)"
        if [[ -n "$resolved_ref" ]]; then
            base_url="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${resolved_ref}"
        else
            base_url="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}"
        fi
        source_rel="app/self_update.sh"
        ts="$(date +%s)"
        yellow "初始化脚本更新引导层..."
        mkdir -p "$WORK_DIR" >/dev/null 2>&1 || true
        curl -fsSL "${base_url}/${source_rel}?v=${ts}" -o "$updater" || {
            red "self_update.sh 初始化失败"
            rm -f "$updater" 2>/dev/null || true
            return 1
        }
        chmod +x "$updater"
        return 0
    }

    if [[ -z "$update_mode" ]]; then
        update_mode="repo"
    fi

    if [[ ! -f "$updater" ]]; then
        ensure_self_update_bootstrap || return 1
    fi

    bash "$updater" "$update_mode"
    local rc=$?
    if (( rc == 10 )); then
        if [[ -t 0 && -t 1 && -f "$management_script" ]]; then
            if declare -F proxy_run_with_spinner_compact >/dev/null 2>&1; then
                proxy_run_with_spinner_compact "正在启用新脚本..." sleep 0.2
            fi
            green "脚本更新已生效，正在切换到新菜单..."
            exec bash "$management_script" menu
            red "自动切换新菜单失败，请重新执行 proxy。"
        fi
        exit 0
    fi
    return "$rc"
}
