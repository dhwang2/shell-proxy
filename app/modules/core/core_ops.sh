# Core version and update menu operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

SERVICE_OPS_FILE="${SERVICE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../service/service_ops.sh}"
if [[ -f "$SERVICE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SERVICE_OPS_FILE"
fi

manage_core() {
    while :; do
        ui_clear
        proxy_menu_header "内核管理"
        echo "1. 查看版本"
        echo "2. 检查更新"
        echo "3. 执行更新"
        proxy_menu_rule "═"
        echo
        if ! read_prompt choice "选择序号(回车取消): "; then
            return
        fi
        [[ -z "$choice" ]] && return
        case $choice in
            1)
                echo
                local v
                v="$(current_singbox_version)"; [[ -n "$v" ]] && print_kv "sing-box" "v${v}" "\033[32m" || print_kv "sing-box" "missing" "\033[31m"
                v="$(current_snell_version)"; [[ -n "$v" ]] && print_kv "snell-v5" "v${v}" "\033[32m" || print_kv "snell-v5" "missing" "\033[31m"
                v="$(current_shadowtls_version)"; [[ -n "$v" ]] && print_kv "${SHADOWTLS_DISPLAY_NAME}" "v${v}" "\033[32m" || print_kv "${SHADOWTLS_DISPLAY_NAME}" "missing" "\033[31m"
                v="$(current_caddy_version)"; [[ -n "$v" ]] && print_kv "caddy" "v${v}" "\033[32m" || print_kv "caddy" "missing" "\033[31m"
                pause
                ;;
            2)
                echo
                local cur latest
                cur="$(current_singbox_version)"; latest="$(github_latest_release_version "SagerNet/sing-box")"
                if [[ -z "$cur" ]]; then
                    print_kv "sing-box" "missing" "\033[31m"
                elif [[ -n "$latest" ]] && version_gt "$latest" "$cur"; then
                    print_kv "sing-box" "v${cur} -> v${latest} (可更新)" "\033[33m"
                else
                    print_kv "sing-box" "v${cur} (最新)" "\033[32m"
                fi
                cur="$(current_shadowtls_version)"; latest="$(github_latest_release_version "ihciah/shadow-tls")"
                if [[ -z "$cur" ]]; then
                    print_kv "${SHADOWTLS_DISPLAY_NAME}" "missing" "\033[31m"
                elif [[ -n "$latest" ]] && version_gt "$latest" "$cur"; then
                    print_kv "${SHADOWTLS_DISPLAY_NAME}" "v${cur} -> v${latest} (可更新)" "\033[33m"
                else
                    print_kv "${SHADOWTLS_DISPLAY_NAME}" "v${cur} (最新)" "\033[32m"
                fi
                cur="$(current_caddy_version)"; latest="$(github_latest_release_version "caddyserver/caddy" "$(caddy_version_cache_file)" "${CADDY_DEFAULT_VERSION}")"
                if [[ -z "$cur" ]]; then
                    print_kv "caddy" "missing" "\033[31m"
                elif [[ -n "$latest" ]] && version_gt "$latest" "$cur"; then
                    print_kv "caddy" "v${cur} -> v${latest} (可更新)" "\033[33m"
                else
                    print_kv "caddy" "v${cur} (最新)" "\033[32m"
                fi
                echo
                yellow "提示: snell 的更新不由此菜单自动处理。"
                pause
                ;;
            3)
                echo
                local cur_s latest_s cur_st latest_st cur_c latest_c need=0
                cur_s="$(current_singbox_version)"; latest_s="$(github_latest_release_version "SagerNet/sing-box")"
                cur_st="$(current_shadowtls_version)"; latest_st="$(github_latest_release_version "ihciah/shadow-tls")"
                cur_c="$(current_caddy_version)"; latest_c="$(github_latest_release_version "caddyserver/caddy" "$(caddy_version_cache_file)" "${CADDY_DEFAULT_VERSION}")"
                if [[ -n "$cur_s" && -n "$latest_s" ]] && version_gt "$latest_s" "$cur_s"; then need=1; fi
                if [[ -n "$cur_st" && -n "$latest_st" ]] && version_gt "$latest_st" "$cur_st"; then need=1; fi
                if [[ -n "$cur_c" && -n "$latest_c" ]] && version_gt "$latest_c" "$cur_c"; then need=1; fi
                if [[ "$need" -eq 0 ]]; then
                    green "已是最新版本"
                    pause
                    continue
                fi
                read -p "发现可更新版本，确认更新? [y/N]: " yn
                [[ "${yn,,}" != "y" ]] && continue
                if [[ -n "$cur_s" && -n "$latest_s" ]] && version_gt "$latest_s" "$cur_s"; then
                    yellow "更新 sing-box -> v${latest_s} ..."
                    update_singbox_core "$latest_s" && green "sing-box 更新成功" || red "sing-box 更新失败"
                fi
                if [[ -n "$cur_st" && -n "$latest_st" ]] && version_gt "$latest_st" "$cur_st"; then
                    yellow "更新 ${SHADOWTLS_DISPLAY_NAME} -> v${latest_st} ..."
                    update_shadowtls_core "$latest_st" && green "${SHADOWTLS_DISPLAY_NAME} 更新成功" || red "${SHADOWTLS_DISPLAY_NAME} 更新失败"
                fi
                if [[ -n "$cur_c" && -n "$latest_c" ]] && version_gt "$latest_c" "$cur_c"; then
                    yellow "更新 caddy -> v${latest_c} ..."
                    update_caddy_core "$latest_c" && green "caddy 更新成功" || red "caddy 更新失败"
                fi
                pause
                ;;
            *) return ;;
        esac
    done
}
