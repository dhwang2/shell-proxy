#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
if [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/env.sh"
elif [[ -f "/etc/shell-proxy/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "/etc/shell-proxy/env.sh"
else
    exit 1
fi

mkdir -p "${LOG_DIR}" >/dev/null 2>&1 || true
touch "${PROXY_WATCHDOG_LOG}" >/dev/null 2>&1 || true

INTERVAL_SEC="${WATCHDOG_INTERVAL_SEC:-15}"
MAX_RESTART_PER_WINDOW="${WATCHDOG_MAX_RESTART_PER_WINDOW:-3}"
RESTART_WINDOW_SEC="${WATCHDOG_RESTART_WINDOW_SEC:-180}"
HEARTBEAT_EVERY_LOOP="${WATCHDOG_HEARTBEAT_LOOP:-20}"
SHADOWTLS_UNITS_CACHE_TTL="${WATCHDOG_SHADOWTLS_CACHE_TTL:-60}"

declare -A LAST_STATE_MAP
declare -A RESTART_HISTORY_MAP
SHADOWTLS_UNITS_CACHE_VALUE=""
SHADOWTLS_UNITS_CACHE_SEEN_AT=-1

log_watchdog() {
    local level="$1"
    shift || true
    local message="$*"
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "${PROXY_WATCHDOG_LOG}" 2>/dev/null || true
}

rotate_watchdog_log_if_needed() {
    local max_bytes=$((5 * 1024 * 1024))
    local keep_lines=2000
    local size=0
    [[ -f "${PROXY_WATCHDOG_LOG}" ]] || return 0
    size="$(wc -c < "${PROXY_WATCHDOG_LOG}" 2>/dev/null || echo 0)"
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if (( size > max_bytes )); then
        tail -n "$keep_lines" "${PROXY_WATCHDOG_LOG}" > "${PROXY_WATCHDOG_LOG}.tmp" 2>/dev/null || true
        mv -f "${PROXY_WATCHDOG_LOG}.tmp" "${PROXY_WATCHDOG_LOG}" 2>/dev/null || true
        log_watchdog "INFO" "watchdog 日志已轮转"
    fi
}

unit_exists() {
    local unit="$1"
    local load_state=""
    load_state="$(systemctl show -p LoadState --value "$unit" 2>/dev/null || true)"
    [[ -n "$load_state" && "$load_state" != "not-found" ]]
}

snell_configured() {
    [[ -f "${SNELL_CONF}" ]] || return 1
    grep -q '^listen' "${SNELL_CONF}" 2>/dev/null || return 1
    grep -q '^psk' "${SNELL_CONF}" 2>/dev/null || return 1
    return 0
}

singbox_configured() {
    [[ -f "${CONF_DIR}/sing-box.json" ]] && return 0
    ls "${CONF_DIR}"/*.json >/dev/null 2>&1
}

shadowtls_units_uncached() {
    local unit_file unit_name
    for unit_file in /etc/systemd/system/shadow-tls*.service; do
        [[ -f "$unit_file" ]] || continue
        if grep -q "server --listen" "$unit_file" 2>/dev/null; then
            unit_name="$(basename "$unit_file")"
            [[ -n "$unit_name" ]] && echo "$unit_name"
        fi
    done | awk '!seen[$0]++'
}

refresh_shadowtls_units_cache() {
    SHADOWTLS_UNITS_CACHE_VALUE="$(shadowtls_units_uncached)"
    SHADOWTLS_UNITS_CACHE_SEEN_AT=$SECONDS
}

shadowtls_units() {
    local ttl="${SHADOWTLS_UNITS_CACHE_TTL:-60}"
    if ! [[ "$ttl" =~ ^[0-9]+$ ]]; then
        ttl=60
    fi
    if (( ttl <= 0 )); then
        shadowtls_units_uncached
        return 0
    fi
    if (( SHADOWTLS_UNITS_CACHE_SEEN_AT < 0 )) || (( SECONDS - SHADOWTLS_UNITS_CACHE_SEEN_AT >= ttl )); then
        refresh_shadowtls_units_cache
    fi
    [[ -n "$SHADOWTLS_UNITS_CACHE_VALUE" ]] && printf '%s\n' "$SHADOWTLS_UNITS_CACHE_VALUE"
}

collect_units() {
    local -a units=()
    if singbox_configured; then
        units+=("sing-box.service")
    fi
    if snell_configured; then
        units+=("snell-v5.service")
    fi
    if [[ -f "${CADDY_SERVICE_FILE}" ]]; then
        units+=("caddy-sub.service")
    fi

    local st_unit
    while IFS= read -r st_unit; do
        [[ -n "$st_unit" ]] || continue
        units+=("$st_unit")
    done < <(shadowtls_units)

    printf '%s\n' "${units[@]}" | awk '!seen[$0]++'
}

compact_restart_history() {
    local unit="$1"
    local now_ts="$2"
    local history="${RESTART_HISTORY_MAP[$unit]:-}"
    local compact=""
    local ts
    for ts in ${history//,/ }; do
        [[ "$ts" =~ ^[0-9]+$ ]] || continue
        if (( now_ts - ts < RESTART_WINDOW_SEC )); then
            if [[ -n "$compact" ]]; then
                compact+=",${ts}"
            else
                compact="${ts}"
            fi
        fi
    done
    RESTART_HISTORY_MAP["$unit"]="$compact"
}

restart_with_rate_limit() {
    local unit="$1"
    local state="$2"
    local sub_state="$3"
    local result="$4"
    local now_ts
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    [[ "$now_ts" =~ ^[0-9]+$ ]] || now_ts=0

    compact_restart_history "$unit" "$now_ts"

    local history="${RESTART_HISTORY_MAP[$unit]:-}"
    local restart_count=0
    if [[ -n "$history" ]]; then
        restart_count="$(awk -F',' '{print NF}' <<< "$history")"
    fi

    if (( restart_count >= MAX_RESTART_PER_WINDOW )); then
        log_watchdog "WARN" "${unit} 在 ${RESTART_WINDOW_SEC}s 内重启超过 ${MAX_RESTART_PER_WINDOW} 次，暂不再重启 (state=${state}/${sub_state}, result=${result})"
        return 1
    fi

    log_watchdog "ERROR" "${unit} 异常，尝试重启 (state=${state}/${sub_state}, result=${result})"
    if systemctl restart "$unit" >/dev/null 2>&1; then
        local active_after sub_after result_after
        active_after="$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || echo unknown)"
        sub_after="$(systemctl show -p SubState --value "$unit" 2>/dev/null || echo unknown)"
        result_after="$(systemctl show -p Result --value "$unit" 2>/dev/null || echo unknown)"
        log_watchdog "INFO" "${unit} 重启完成 -> ${active_after}/${sub_after} (result=${result_after})"

        if [[ -n "$history" ]]; then
            RESTART_HISTORY_MAP["$unit"]="${history},${now_ts}"
        else
            RESTART_HISTORY_MAP["$unit"]="${now_ts}"
        fi
        return 0
    fi

    log_watchdog "ERROR" "${unit} 重启失败"
    return 1
}

loop_index=0
log_watchdog "INFO" "watchdog 已启动 (interval=${INTERVAL_SEC}s, max_restart=${MAX_RESTART_PER_WINDOW}/${RESTART_WINDOW_SEC}s)"

trap 'log_watchdog "INFO" "watchdog 收到退出信号，停止监控"; exit 0' INT TERM

while :; do
    rotate_watchdog_log_if_needed
    while IFS= read -r unit; do
        [[ -n "$unit" ]] || continue
        unit_exists "$unit" || continue

        local_state="$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || echo unknown)"
        local_sub="$(systemctl show -p SubState --value "$unit" 2>/dev/null || echo unknown)"
        local_result="$(systemctl show -p Result --value "$unit" 2>/dev/null || echo unknown)"
        state_key="${local_state}/${local_sub}/${local_result}"

        if [[ "${LAST_STATE_MAP[$unit]:-}" != "$state_key" ]]; then
            log_watchdog "INFO" "${unit} 状态: ${state_key}"
            LAST_STATE_MAP["$unit"]="$state_key"
        fi

        case "${local_state}:${local_sub}:${local_result}" in
            failed:*:*|*:failed:*|*:*:failed|inactive:dead:success)
                restart_with_rate_limit "$unit" "$local_state" "$local_sub" "$local_result" || true
                ;;
            *)
                ;;
        esac
    done < <(collect_units)

    loop_index=$((loop_index + 1))
    if (( HEARTBEAT_EVERY_LOOP > 0 && loop_index % HEARTBEAT_EVERY_LOOP == 0 )); then
        log_watchdog "INFO" "watchdog 心跳正常"
    fi
    sleep "$INTERVAL_SEC"
done
