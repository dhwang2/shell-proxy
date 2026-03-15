# Runtime log display operations for shell-proxy management.

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

COMMON_BASE_OPS_FILE="${COMMON_BASE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_BASE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_BASE_OPS_FILE"
fi

CONFIG_VIEW_ROUTING_CORE_OPS_FILE="${CONFIG_VIEW_ROUTING_CORE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../routing/routing_core_ops.sh}"
if [[ -f "$CONFIG_VIEW_ROUTING_CORE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_VIEW_ROUTING_CORE_OPS_FILE"
fi

CONFIG_VIEW_ROUTING_OPS_FILE="${CONFIG_VIEW_ROUTING_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../routing/routing_ops.sh}"
if [[ -f "$CONFIG_VIEW_ROUTING_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_VIEW_ROUTING_OPS_FILE"
fi

show_status_and_logs() {
    local C_RESET="\033[0m"
    local C_PATH="\033[35m\033[1m"

    colorize_log_lines() {
        sed -E \
            -e $'s/(FATAL|ERROR|failed|失败)/\033[31;1m\\1\033[0m/g' \
            -e $'s/(WARN|WARNING|警告)/\033[33;1m\\1\033[0m/g' \
            -e $'s/(INFO|启动成功|重启成功|运行中)/\033[36;1m\\1\033[0m/g'
    }

    service_log_path() {
        local unit="$1"
        case "$unit" in
            sing-box)
                if [[ -f "${LOG_DIR}/sing-box.log" ]]; then
                    echo "${LOG_DIR}/sing-box.log"
                else
                    echo "${SINGBOX_SERVICE_LOG}"
                fi
                ;;
            snell-v5) echo "${SNELL_SERVICE_LOG}" ;;
            shadow-tls)
                if [[ -f "${LOG_DIR}/shadow-tls.log" ]]; then
                    echo "${LOG_DIR}/shadow-tls.log"
                else
                    echo "${SHADOWTLS_SERVICE_LOG}"
                fi
                ;;
            shadow-tls-*)
                if [[ -f "${LOG_DIR}/${unit}.log" ]]; then
                    echo "${LOG_DIR}/${unit}.log"
                else
                    echo "${SHADOWTLS_SERVICE_LOG}"
                fi
                ;;
            caddy-sub) echo "${CADDY_SUB_SERVICE_LOG}" ;;
            *) echo "" ;;
        esac
    }

    show_recent_logs() {
        local unit="$1"
        local lines="${2:-50}"
        local log_file
        local used_journal=0
        local printed=0
        log_file="$(service_log_path "$unit")"
        if [[ -n "$log_file" && -f "$log_file" && -s "$log_file" ]]; then
            tail -n "$lines" "$log_file" 2>/dev/null | colorize_log_lines || true
            printed=1
        else
            local journal_out=""
            journal_out="$(journalctl -u "$unit" --no-pager -n "$lines" 2>/dev/null || true)"
            if [[ -n "${journal_out//[[:space:]]/}" ]]; then
                printf '%s\n' "$journal_out" | colorize_log_lines || true
                used_journal=1
                printed=1
            fi
        fi
        if (( printed == 0 )); then
            yellow "未找到可显示的服务日志"
        elif (( used_journal == 1 )); then
            yellow "日志来源: journalctl -u ${unit}"
        fi
    }

    show_file_tail_logs() {
        local log_file="$1"
        local display_name="$2"
        local lines="${3:-50}"
        local note=""
        if [[ -f "$log_file" && -s "$log_file" ]]; then
            tail -n "$lines" "$log_file" 2>/dev/null | colorize_log_lines || true
        elif [[ -f "$log_file" ]]; then
            note="${display_name} 为空（尚未产生日志）"
        else
            note="${display_name} 文件不存在"
        fi
        echo
        proxy_menu_divider
        echo -e "${display_name} (${C_PATH}${log_file}${C_RESET})"
        [[ -n "$note" ]] && yellow "$note"
    }

    show_watchdog_logs() {
        local lines="${1:-50}"
        local note=""
        local source_note=""
        if [[ -f "$PROXY_WATCHDOG_LOG" && -s "$PROXY_WATCHDOG_LOG" ]]; then
            tail -n "$lines" "$PROXY_WATCHDOG_LOG" 2>/dev/null | colorize_log_lines || true
        elif systemctl list-unit-files 2>/dev/null | grep -q '^proxy-watchdog\.service'; then
            local journal_out=""
            journal_out="$(journalctl -u proxy-watchdog --no-pager -n "$lines" 2>/dev/null || true)"
            if [[ -n "${journal_out//[[:space:]]/}" ]]; then
                printf '%s\n' "$journal_out" | colorize_log_lines || true
                source_note="日志来源: journalctl -u proxy-watchdog"
            else
                note="Watchdog 日志为空（尚未产生日志）"
            fi
        else
            note="watchdog 未启用（当前未安装 proxy-watchdog.service），因此日志为空。"
        fi

        echo
        proxy_menu_divider
        echo -e "Watchdog 日志 (${C_PATH}${PROXY_WATCHDOG_LOG}${C_RESET})"
        [[ -n "$source_note" ]] && yellow "$source_note"
        [[ -n "$note" ]] && yellow "$note"
    }

    protocol_display_name() {
        local proto="$1"
        case "$proto" in
            ss|shadowsocks) echo "ss" ;;
            *) echo "$proto" ;;
        esac
    }

    show_service_logs_by_protocol() {
        while :; do
            local choices=()
            local conf_file
            conf_file="$(ls "${CONF_DIR}"/*.json 2>/dev/null | head -n 1)"

            local singbox_proto_list=""
            if [[ -n "$conf_file" && -f "$conf_file" ]]; then
                singbox_proto_list="$(
                    jq -r '.inbounds[]?.type // empty' "$conf_file" 2>/dev/null \
                        | while IFS= read -r proto; do
                            [[ -n "$proto" ]] || continue
                            protocol_display_name "$proto"
                        done \
                        | awk 'NF && !seen[$0]++' \
                        | paste -sd/ -
                )"
            fi
            if [[ -n "$singbox_proto_list" ]]; then
                choices+=("sing-box|sing-box 服务日志 (${singbox_proto_list})")
            fi

            if is_snell_configured; then
                choices+=("snell-v5|snell-v5 服务日志")
            fi

            if is_shadowtls_configured; then
                local st_line st_service st_port st_target st_backend st_sni st_pass st_label
                local has_shadow_choice=0
                if declare -F shadowtls_binding_lines >/dev/null 2>&1; then
                    while IFS= read -r st_line; do
                        [[ -n "$st_line" ]] || continue
                        IFS='|' read -r st_service st_port st_target st_backend st_sni st_pass <<< "$st_line"
                        st_label="${SHADOWTLS_DISPLAY_NAME} 服务日志"
                        case "$st_backend" in
                            snell) st_label="snell-v5+shadow-tls-v3 服务日志 (端口: ${st_port})" ;;
                            ss) st_label="ss+shadow-tls-v3 服务日志 (端口: ${st_port})" ;;
                            *)
                                if [[ -n "$st_port" ]]; then
                                    st_label="${SHADOWTLS_DISPLAY_NAME} 服务日志 (端口: ${st_port})"
                                fi
                                ;;
                        esac
                        if [[ -n "$st_service" ]]; then
                            choices+=("${st_service}|${st_label}")
                            has_shadow_choice=1
                        fi
                    done < <(shadowtls_binding_lines "$conf_file")
                fi
                if (( has_shadow_choice == 0 )); then
                    choices+=("shadow-tls|${SHADOWTLS_DISPLAY_NAME} 服务日志")
                fi
            fi

            if [[ -f "$CADDY_SERVICE_FILE" ]]; then
                choices+=("caddy-sub|caddy-sub 服务日志")
            fi

            if [[ "${#choices[@]}" -eq 0 ]]; then
                yellow "未检测到已安装协议，无法查看服务日志。"
                pause
                return 0
            fi

            echo
            echo "服务日志"
            proxy_menu_divider
            local idx=1
            local entry label
            for entry in "${choices[@]}"; do
                label="${entry#*|}"
                echo "${idx}. ${label}"
                idx=$((idx + 1))
            done
            proxy_menu_rule "═"
            if ! read_prompt svc_choice "选择序号(回车取消): "; then
                return 0
            fi

            [[ -z "$svc_choice" ]] && return 0
            if ! [[ "$svc_choice" =~ ^[0-9]+$ ]] || (( svc_choice < 1 || svc_choice > ${#choices[@]} )); then
                red "无效输入"
                sleep 1
                continue
            fi

            local selected="${choices[$((svc_choice - 1))]}"
            local selected_unit="${selected%%|*}"
            local selected_label="${selected#*|}"
            local selected_log_path
            selected_log_path="$(service_log_path "$selected_unit")"
            show_recent_logs "$selected_unit" 50
            echo
            proxy_menu_divider
            if [[ -n "$selected_log_path" ]]; then
                echo -e "${selected_label} (最近 50 行) (${C_PATH}${selected_log_path}${C_RESET})"
            else
                echo "${selected_label} (最近 50 行)"
            fi
            pause
        done
    }

    if command -v proxy_log >/dev/null 2>&1; then
        proxy_log "INFO" "打开运行日志菜单"
    fi

    mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
    touch "$PROXY_SCRIPT_LOG" "$PROXY_WATCHDOG_LOG" >/dev/null 2>&1 || true

    while :; do
        ui_clear
        proxy_menu_header "运行日志"
        echo "1. 查看脚本日志 (最近 50 行/静态)"
        echo "2. 查看 Watchdog 日志 (最近 50 行)"
        echo "3. 查看服务日志 (按协议选择)"
        proxy_menu_rule "═"
        if ! read_prompt choice "选择序号(回车取消): "; then
            return
        fi
        case "$choice" in
            1)
                if command -v proxy_log >/dev/null 2>&1; then
                    proxy_log "INFO" "运行日志: 查看脚本日志"
                fi
                show_file_tail_logs "$PROXY_SCRIPT_LOG" "脚本日志" 50
                pause
                ;;
            2)
                if command -v proxy_log >/dev/null 2>&1; then
                    proxy_log "INFO" "运行日志: 查看 Watchdog 日志"
                fi
                show_watchdog_logs 50
                pause
                ;;
            3)
                if command -v proxy_log >/dev/null 2>&1; then
                    proxy_log "INFO" "运行日志: 查看服务日志"
                fi
                show_service_logs_by_protocol
                ;;
            "")
                return
                ;;
            *)
                red "无效输入"
                sleep 1
                ;;
        esac
    done
}

# --- config detail display (merged from config_view_ops.sh) ---

show_config_details() {
    while :; do
        ui_clear
        proxy_menu_header "配置详情"
        echo "1. sing-box"
        echo "2. snell-v5"
        echo "3. shadow-tls"
        proxy_menu_rule "═"
        if ! read_prompt c_choice "选择序号(回车取消): "; then
            return
        fi
        [[ -z "$c_choice" ]] && return
        case $c_choice in
            1)
                ui_clear
                local conf_file
                conf_file="$(get_conf_file)"
                if [[ -z "$conf_file" || ! -f "$conf_file" ]]; then
                    yellow "无配置"
                    pause
                    continue
                fi

                proxy_menu_header "sing-box 配置"
                local inbound_count final_out dns_final dns_strategy summary_row
                summary_row="$(jq -r --arg sep $'\x1f' '
                    [
                        ((.inbounds // []) | length | tostring),
                        (.route.final // "🐸 direct"),
                        (.dns.final // "public4"),
                        (.dns.strategy // "unknown")
                    ] | join($sep)
                ' "$conf_file" 2>/dev/null || true)"
                if [[ -n "$summary_row" ]]; then
                    IFS=$'\x1f' read -r inbound_count final_out dns_final dns_strategy <<<"$summary_row"
                fi
                [[ "$inbound_count" =~ ^[0-9]+$ ]] || inbound_count=0
                [[ -n "$final_out" ]] || final_out="🐸 direct"
                [[ -n "$dns_final" ]] || dns_final="public4"
                [[ -n "$dns_strategy" ]] || dns_strategy="unknown"
                echo "入站数量: ${inbound_count}"
                echo "全局出口: $(routing_outbound_label "$final_out")"
                echo "DNS出口: ${dns_final}"
                echo "DNS策略: ${dns_strategy}"
                proxy_menu_divider
                print_full_singbox_config_with_compact_rules "$conf_file"
                pause
                ;;
            2)
                ui_clear
                if is_snell_configured; then
                    proxy_menu_header "snell-v5 配置 ($SNELL_CONF)"
                    cat "$SNELL_CONF"
                else
                    yellow "无 snell-v5 配置"
                fi
                pause
                ;;
            3)
                ui_clear
                local conf_file
                conf_file="$(get_conf_file)"
                if ! is_shadowtls_configured; then
                    yellow "无 shadow-tls-v3 配置"
                    pause
                    continue
                fi

                proxy_menu_header "shadow-tls-v3 配置"
                local st_line st_service st_port st_target st_backend st_sni st_pass st_state
                local printed_shadowtls=0
                while IFS= read -r st_line; do
                    [[ -n "$st_line" ]] || continue
                    IFS='|' read -r st_service st_port st_target st_backend st_sni st_pass <<< "$st_line"
                    case "$st_backend" in
                        ss|snell) ;;
                        *) continue ;;
                    esac
                    st_state="$(systemctl is-active "$st_service" 2>/dev/null || echo unknown)"
                    echo "实例: ${st_service} | 状态: ${st_state}"
                    echo "  绑定: $(shadowtls_backend_display_label "$st_backend")"
                    echo "  监听: ${st_port} -> 后端: ${st_target}"
                    echo "  SNI: ${st_sni}"
                    printed_shadowtls=1
                done < <(shadowtls_binding_lines "$conf_file")
                (( printed_shadowtls == 0 )) && yellow "未检测到绑定 SS 或 Snell 的 shadow-tls-v3 服务"
                pause
                ;;
            *)
                return
                ;;
        esac
    done
}
