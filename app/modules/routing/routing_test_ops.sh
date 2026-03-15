# Routing test and probe operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

ROUTING_CONTEXT_OPS_FILE="${ROUTING_CONTEXT_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_context_ops.sh}"
if [[ -f "$ROUTING_CONTEXT_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_CONTEXT_OPS_FILE"
fi

ROUTING_TEST_EFFECT_BUCKET_SECONDS="${ROUTING_TEST_EFFECT_BUCKET_SECONDS:-180}"

routing_test_effect_cache_scope() {
    if routing_context_is_user; then
        printf 'user:%s\n' "${ROUTING_USER_CONTEXT_NAME}"
    else
        printf 'global\n'
    fi
}

routing_test_effect_cache_key() {
    local conf_file="${1:-}" raw_key
    raw_key="routing-test|$(routing_test_effect_cache_scope)|${conf_file}"
    if declare -F routing_runtime_cache_key >/dev/null 2>&1; then
        routing_runtime_cache_key "$raw_key"
        return 0
    fi
    printf '%s' "$raw_key" | cksum 2>/dev/null | awk '{print $1"-"$2}'
}

routing_test_effect_cache_text_file() {
    local conf_file="${1:-}" cache_key
    cache_key="$(routing_test_effect_cache_key "$conf_file")"
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-test-${cache_key}.txt"
}

routing_test_effect_cache_fp_file() {
    local conf_file="${1:-}" cache_key
    cache_key="$(routing_test_effect_cache_key "$conf_file")"
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-test-${cache_key}.fp"
}

routing_test_effect_refresh_lock_file() {
    printf '%s\n' "$(proxy_runtime_cache_dir)/routing-test-refresh.lock"
}

routing_test_effect_state_fingerprint() {
    local conf_file="${1:-}" context_scope bucket code_fp nodes_meta state_fp source_fp
    context_scope="$(routing_test_effect_cache_scope)"
    bucket="$(( ($(date +%s 2>/dev/null || echo 0)) / ROUTING_TEST_EFFECT_BUCKET_SECONDS ))"
    code_fp="$(calc_file_meta_signature "${BASH_SOURCE[0]}" 2>/dev/null || echo "0:0")"
    nodes_meta="$(calc_file_meta_signature "$RES_SOCKS_NODES_FILE" 2>/dev/null || echo "0:0")"

    if routing_context_is_user; then
        source_fp="$(routing_user_runtime_input_fingerprint "$conf_file" 2>/dev/null || echo "0:0|0:0|0:0|0:0")"
        state_fp="$(printf '%s|%s|%s\n' "${ROUTING_USER_CONTEXT_NAME:-}" "$source_fp" "$nodes_meta" \
            | cksum 2>/dev/null | awk '{print $1":"$2}')"
    else
        source_fp="$(printf '%s|%s|%s\n' \
            "$(calc_file_meta_signature "$ROUTING_RULES_DB" 2>/dev/null || echo "0:0")" \
            "$(calc_file_meta_signature "$DIRECT_IP_VERSION_FILE" 2>/dev/null || echo "0:0")" \
            "$nodes_meta")"
        state_fp="$(printf '%s' "$source_fp" | cksum 2>/dev/null | awk '{print $1":"$2}')"
    fi

    printf '%s|%s|%s|%s\n' "$context_scope" "$state_fp" "$bucket" "$code_fp" \
        | cksum 2>/dev/null | awk '{print $1":"$2}'
}

routing_test_effect_cache_read_fingerprint() {
    local conf_file="${1:-}" fp_file
    fp_file="$(routing_test_effect_cache_fp_file "$conf_file")"
    [[ -f "$fp_file" ]] || return 1
    tr -d '[:space:]' <"$fp_file" 2>/dev/null
}

routing_test_effect_cache_is_fresh() {
    local conf_file="${1:-}" expected_fp cached_fp text_file
    text_file="$(routing_test_effect_cache_text_file "$conf_file")"
    [[ -f "$text_file" ]] || return 1
    cached_fp="$(routing_test_effect_cache_read_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$cached_fp" ]] || return 1
    expected_fp="$(routing_test_effect_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$expected_fp" ]] || return 1
    [[ "$cached_fp" == "$expected_fp" ]]
}

routing_render_test_effect_uncached() {
    local conf_file="$1"
    local state_json count
    local ip4="" ip6=""
    local tmp_ip4="" tmp_ip6=""
    local pid_ip4="" pid_ip6=""
    local now_label=""
    local -a chain_outbounds=() chain_tmp_files=() chain_labels=() chain_pids=()
    local idx outbound tmp_file probe_result
    state_json="$(routing_load_state_json)"

    echo
    if routing_context_is_user; then
        echo "用户: ${ROUTING_USER_CONTEXT_NAME}"
        proxy_menu_divider
    fi
    yellow "测试分流效果（结果仅作快速自检）"
    proxy_menu_divider
    now_label="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
    [[ -n "$now_label" ]] && echo "探测时间: ${now_label}"

    tmp_ip4="$(mktemp)"
    tmp_ip6="$(mktemp)"
    (routing_probe_direct_ip 4 >"$tmp_ip4") & pid_ip4=$!
    (routing_probe_direct_ip 6 >"$tmp_ip6") & pid_ip6=$!

    mapfile -t chain_outbounds < <(routing_state_unique_res_socks_outbounds "$state_json")
    for outbound in "${chain_outbounds[@]}"; do
        tmp_file="$(mktemp)"
        chain_tmp_files+=("$tmp_file")
        chain_labels+=("$(res_socks_display_label_by_tag "$outbound" 2>/dev/null || printf '%s' "$outbound")")
        (routing_probe_socks_outbound_ip "$outbound" >"$tmp_file") & chain_pids+=($!)
    done

    [[ -n "$pid_ip4" ]] && wait "$pid_ip4" 2>/dev/null || true
    [[ -n "$pid_ip6" ]] && wait "$pid_ip6" 2>/dev/null || true
    ip4="$(cat "$tmp_ip4" 2>/dev/null || true)"
    ip6="$(cat "$tmp_ip6" 2>/dev/null || true)"
    rm -f "$tmp_ip4" "$tmp_ip6" 2>/dev/null || true

    echo "直连 IPv4: ${ip4:-获取失败}"
    echo "直连 IPv6: ${ip6:-获取失败}"

    if (( ${#chain_outbounds[@]} == 0 )); then
        if routing_res_socks_ready "$conf_file"; then
            echo "链式代理出口: 当前用户未使用"
        else
            echo "链式代理出口: 未配置"
        fi
    elif (( ${#chain_outbounds[@]} == 1 )); then
        [[ ${#chain_pids[@]} -gt 0 ]] && wait "${chain_pids[0]}" 2>/dev/null || true
        probe_result="$(cat "${chain_tmp_files[0]}" 2>/dev/null || true)"
        rm -f "${chain_tmp_files[0]}" 2>/dev/null || true
        echo "链式代理出口: ${chain_labels[0]} -> ${probe_result:-获取失败}"
    else
        echo "链式代理出口:"
        for idx in "${!chain_outbounds[@]}"; do
            wait "${chain_pids[$idx]}" 2>/dev/null || true
            probe_result="$(cat "${chain_tmp_files[$idx]}" 2>/dev/null || true)"
            rm -f "${chain_tmp_files[$idx]}" 2>/dev/null || true
            echo "  ${chain_labels[$idx]} -> ${probe_result:-获取失败}"
        done
    fi

    proxy_menu_divider
    count="$(echo "$state_json" | jq -r 'length' 2>/dev/null || echo 0)"
    if [[ "$count" -eq 0 ]]; then
        echo "分流规则: 未配置"
    else
        echo "分流规则: ${count} 条"
        routing_render_rules_brief
    fi
}

routing_test_effect_cache_rebuild() {
    local conf_file="${1:-}" render_text state_fp text_file fp_file
    text_file="$(routing_test_effect_cache_text_file "$conf_file")"
    fp_file="$(routing_test_effect_cache_fp_file "$conf_file")"
    render_text="$(routing_render_test_effect_uncached "$conf_file")"
    state_fp="$(routing_test_effect_state_fingerprint "$conf_file" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"
    mkdir -p "$(proxy_runtime_cache_dir)" >/dev/null 2>&1 || true
    proxy_cache_write_atomic "$text_file" "$render_text" || return 1
    proxy_cache_write_atomic "$fp_file" "$state_fp" || return 1
}

routing_test_effect_schedule_refresh() {
    local conf_file="${1:-}" target_name="${2:-}" lock_file=""
    local script_file="" mgmt_file="" q_mgmt="" q_conf="" q_target="" q_lock=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    lock_file="$(routing_test_effect_refresh_lock_file)"
    mkdir -p "$(dirname "$lock_file")" >/dev/null 2>&1 || true

    mgmt_file="${WORK_DIR}/management.sh"
    [[ -f "$mgmt_file" ]] || mgmt_file=""
    if [[ -n "$mgmt_file" ]] && command -v nohup >/dev/null 2>&1; then
        printf -v q_mgmt '%q' "$mgmt_file"
        printf -v q_conf '%q' "$conf_file"
        printf -v q_target '%q' "$target_name"
        printf -v q_lock '%q' "$lock_file"
        script_file="$(mktemp)"
        cat >"$script_file" <<EOF
#!/usr/bin/env bash
set -e
mgmt_file=${q_mgmt}
conf_file=${q_conf}
target_name=${q_target}
lock_file=${q_lock}
cleanup() {
    rm -f -- "\$0" >/dev/null 2>&1 || true
}
trap cleanup EXIT
source <(awk 'BEGIN{stop=0} /^main "\\\$@"$/{stop=1} !stop{print}' "\$mgmt_file")
load_named_menu_modules routing >/dev/null 2>&1 || true
routing_menu_support_ensure_selector_support_loaded >/dev/null 2>&1 || true
routing_menu_support_ensure_full_support_loaded >/dev/null 2>&1 || true
mkdir -p "\$(dirname "\$lock_file")" >/dev/null 2>&1 || true
if command -v flock >/dev/null 2>&1; then
    exec 9>"\$lock_file"
    flock -n 9 || exit 0
else
    lock_dir="\${lock_file}.d"
    mkdir "\$lock_dir" >/dev/null 2>&1 || exit 0
    cleanup() {
        rmdir "\$lock_dir" >/dev/null 2>&1 || true
        rm -f -- "\$0" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT
fi
if [[ -n "\$target_name" ]]; then
    routing_with_user_context "\$target_name" routing_test_effect_cache_rebuild "\$conf_file"
else
    routing_test_effect_cache_rebuild "\$conf_file"
fi
EOF
        chmod 700 "$script_file" >/dev/null 2>&1 || true
        nohup bash "$script_file" >/dev/null 2>&1 &
        return 0
    fi

    (
        local lock_dir="${lock_file}.d"
        mkdir "$lock_dir" >/dev/null 2>&1 || exit 0
        if [[ -n "$target_name" ]]; then
            routing_with_user_context "$target_name" routing_test_effect_cache_rebuild "$conf_file"
        else
            routing_test_effect_cache_rebuild "$conf_file"
        fi
        rmdir "$lock_dir" >/dev/null 2>&1 || true
    ) >/dev/null 2>&1 &
}

routing_test_effect_rebuild_sync_with_spinner() {
    local conf_file="${1:-}" target_name="${2:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if declare -F proxy_run_with_spinner_compact >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        if [[ -n "$target_name" ]]; then
            proxy_run_with_spinner_compact "正在探测分流出口..." \
                routing_with_user_context "$target_name" routing_test_effect_cache_rebuild "$conf_file"
        else
            proxy_run_with_spinner_compact "正在探测分流出口..." \
                routing_test_effect_cache_rebuild "$conf_file"
        fi
        return $?
    fi

    if [[ -n "$target_name" ]]; then
        routing_with_user_context "$target_name" routing_test_effect_cache_rebuild "$conf_file"
    else
        routing_test_effect_cache_rebuild "$conf_file"
    fi
}

routing_render_test_effect_pending_view() {
    local conf_file="${1:-}" state_json count
    state_json="$(routing_load_state_json)"

    echo
    if routing_context_is_user; then
        echo "用户: ${ROUTING_USER_CONTEXT_NAME}"
        proxy_menu_divider
    fi
    yellow "测试分流效果（结果仅作快速自检）"
    proxy_menu_divider
    echo "状态: 暂无可用探测缓存，已启动后台刷新"
    echo "提示: 稍后重新进入本页面查看最新出口 IP"
    proxy_menu_divider
    count="$(echo "$state_json" | jq -r 'length' 2>/dev/null || echo 0)"
    if [[ "$count" -eq 0 ]]; then
        echo "分流规则: 未配置"
    else
        echo "分流规则: ${count} 条"
        echo "规则摘要: 本次占位页不展开规则明细"
    fi
}

routing_probe_direct_ip() {
    local family="${1:-4}"
    local result=""
    case "$family" in
        4)
            result="$(curl -4 -s --connect-timeout 1 --max-time 2 https://api.ipify.org 2>/dev/null || true)"
            [[ -n "$result" ]] || result="$(curl -4 -s --connect-timeout 1 --max-time 2 https://ipv4.icanhazip.com 2>/dev/null || true)"
            ;;
        6)
            if [[ -z "$ROUTING_IPV6_STACK_CACHE" ]]; then
                if [[ "$(detect_server_ip_stack 2>/dev/null || echo ipv4)" != "ipv4" ]] \
                    && ip -6 route show default 2>/dev/null | grep -q .; then
                    ROUTING_IPV6_STACK_CACHE="ready"
                else
                    ROUTING_IPV6_STACK_CACHE="absent"
                fi
            fi
            if [[ "$ROUTING_IPV6_STACK_CACHE" != "ready" ]]; then
                printf '%s' "未配置"
                return 0
            fi
            result="$(curl -6 -s --connect-timeout 1 --max-time 2 https://api64.ipify.org 2>/dev/null || true)"
            [[ -n "$result" ]] || result="$(curl -6 -s --connect-timeout 1 --max-time 2 https://icanhazip.com 2>/dev/null || true)"
            ;;
    esac
    printf '%s' "${result//$'\n'/}"
}

routing_state_unique_res_socks_outbounds() {
    local state_json="${1:-[]}"
    jq -r '[.[]? | (.outbound // "") | select(length > 0)] | unique[]' <<<"$state_json" 2>/dev/null \
        | while IFS= read -r outbound; do
            [[ -n "$outbound" ]] || continue
            is_res_socks_outbound_tag "$outbound" || continue
            printf '%s\n' "$outbound"
        done
}

routing_probe_socks_outbound_ip() {
    local outbound_tag="${1:-}"
    local line="" server="" port="" username="" password=""
    local probe_output="" probe_error="" err_file="" curl_rc=0
    [[ -n "$outbound_tag" ]] || return 1

    line="$(res_socks_get_node_line_by_tag "$outbound_tag" 2>/dev/null || true)"
    [[ -n "$line" ]] || { printf '%s' "节点缺失"; return 1; }
    IFS='|' read -r server port username password <<<"$line"
    [[ -n "$server" && -n "$port" ]] || { printf '%s' "节点无效"; return 1; }

    err_file="$(mktemp)"
    if [[ -n "$username" || -n "$password" ]]; then
        probe_output="$(curl -sS --connect-timeout 1 --max-time 3 --proxy-user "${username}:${password}" --socks5-hostname "${server}:${port}" https://api.ipify.org 2>"$err_file")"
        curl_rc=$?
    else
        probe_output="$(curl -sS --connect-timeout 1 --max-time 3 --socks5-hostname "${server}:${port}" https://api.ipify.org 2>"$err_file")"
        curl_rc=$?
    fi

    probe_output="${probe_output//$'\n'/}"
    probe_error="$(cat "$err_file" 2>/dev/null || true)"
    rm -f "$err_file" 2>/dev/null || true

    if [[ $curl_rc -eq 0 && -n "$probe_output" ]]; then
        printf '%s' "$probe_output"
        return 0
    fi

    case "$probe_error" in
        *"User was rejected by the SOCKS5 server"*)
            printf '%s' "认证失败"
            ;;
        *"Connection refused"*)
            printf '%s' "连接被拒"
            ;;
        *"Could not resolve host"*)
            printf '%s' "解析失败"
            ;;
        *"timed out"*|*"Timeout"*)
            printf '%s' "连接超时"
            ;;
        *)
            printf '%s' "获取失败"
            ;;
    esac
    return 1
}

test_routing_effect() {
    local conf_file="$1"
    local text_file cached_target=""
    text_file="$(routing_test_effect_cache_text_file "$conf_file")"

    if routing_context_is_user; then
        cached_target="${ROUTING_USER_CONTEXT_NAME:-}"
    fi

    if routing_test_effect_cache_is_fresh "$conf_file"; then
        cat "$text_file"
        return 0
    fi

    if routing_test_effect_rebuild_sync_with_spinner "$conf_file" "$cached_target"; then
        if [[ -f "$text_file" ]]; then
            cat "$text_file"
            return 0
        fi
    fi

    if [[ -f "$text_file" ]]; then
        yellow "提示: 当前展示最近一次探测缓存，后台已启动刷新。"
        cat "$text_file"
        routing_test_effect_schedule_refresh "$conf_file" "$cached_target"
        return 0
    fi

    routing_render_test_effect_pending_view "$conf_file"
    routing_test_effect_schedule_refresh "$conf_file" "$cached_target"
}
