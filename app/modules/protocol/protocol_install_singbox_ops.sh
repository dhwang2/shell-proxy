# Sing-box inbound installation flow operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

CONFIG_OPS_FILE="${CONFIG_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/config_ops.sh}"
if [[ -f "$CONFIG_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_OPS_FILE"
fi

USER_MEMBERSHIP_OPS_FILE="${USER_MEMBERSHIP_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../user/user_membership_ops.sh}"
if [[ -f "$USER_MEMBERSHIP_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_MEMBERSHIP_OPS_FILE"
fi

ROUTING_AUTOCONFIG_OPS_FILE="${ROUTING_AUTOCONFIG_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../routing/routing_autoconfig_ops.sh}"
if [[ -f "$ROUTING_AUTOCONFIG_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_AUTOCONFIG_OPS_FILE"
fi

ROUTING_CORE_OPS_FILE="${ROUTING_CORE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../routing/routing_core_ops.sh}"
if [[ -f "$ROUTING_CORE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_CORE_OPS_FILE"
fi

ROUTING_OPS_FILE="${ROUTING_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_ops.sh}"
if [[ -f "$ROUTING_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_OPS_FILE"
fi

PROTOCOL_OPS_FILE="${PROTOCOL_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_ops.sh}"
if [[ -f "$PROTOCOL_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_OPS_FILE"
fi

PROTOCOL_PORT_OPS_FILE="${PROTOCOL_PORT_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_port_ops.sh}"
if [[ -f "$PROTOCOL_PORT_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_PORT_OPS_FILE"
fi

PROTOCOL_SHADOWTLS_SETUP_OPS_FILE="${PROTOCOL_SHADOWTLS_SETUP_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_shadowtls_setup_ops.sh}"
if [[ -f "$PROTOCOL_SHADOWTLS_SETUP_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_SHADOWTLS_SETUP_OPS_FILE"
fi

PROTOCOL_TLS_OPS_FILE="${PROTOCOL_TLS_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_tls_ops.sh}"
if [[ -f "$PROTOCOL_TLS_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_TLS_OPS_FILE"
fi

PROTOCOL_RUNTIME_SUPPORT_OPS_FILE="${PROTOCOL_RUNTIME_SUPPORT_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_runtime_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_SUPPORT_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_SUPPORT_OPS_FILE"
fi

SHARE_OPS_FILE="${SHARE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../subscription/share_ops.sh}"
if [[ -f "$SHARE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARE_OPS_FILE"
fi

modify_singbox_inbounds_logic() {
    local type_code=$1
    local conf_file
    conf_file=$(get_conf_file)
    if [[ -z "$conf_file" ]]; then
        red "未发现配置文件，请先重建配置。"
        return
    fi

    local selected_proto=""
    case "$type_code" in
        1) selected_proto="trojan" ;;
        2) selected_proto="vless" ;;
        3) selected_proto="tuic" ;;
        4) selected_proto="ss" ;;
        5) selected_proto="anytls" ;;
    esac
    local selected_proto_label="${selected_proto:-protocol}"

    local selected_user_name
    selected_user_name="$(proxy_user_select_name_for_protocol_action "选择用户名" "any" "$conf_file")"
    [[ -z "$selected_user_name" ]] && return
    [[ "$selected_user_name" == "__none__" ]] && { yellow "请先添加用户名"; return; }
    [[ "$selected_user_name" == "__invalid__" ]] && { red "输入无效"; return; }
    selected_user_name="$(normalize_proxy_user_name "$selected_user_name")"
    if [[ -n "$selected_proto" ]] && proxy_user_has_protocol_for_name "$selected_user_name" "$selected_proto" "any" "$conf_file"; then
        yellow "用户名 ${selected_user_name} 已拥有 ${selected_proto_label} 协议，无需重复安装。"
        return
    fi
    local target_inbound_idx
    target_inbound_idx="$(proxy_select_install_inbound_for_protocol "$conf_file" "$selected_proto")"
    [[ -z "$target_inbound_idx" ]] && return
    [[ "$target_inbound_idx" == "__invalid__" ]] && { red "输入无效"; return; }
    if [[ "$target_inbound_idx" != "__new__" ]]; then
        if proxy_append_user_to_existing_inbound "$conf_file" "$selected_proto" "$target_inbound_idx" "$selected_user_name"; then
            return
        fi
        red "复用现有 ${selected_proto_label} 入站失败"
        return
    fi

    local listen_addr
    listen_addr="$(singbox_inbound_listen_addr "$conf_file")"
    maybe_fix_bindv6only "$listen_addr"

    local cur_uuid
    cur_uuid="$(first_valid_inbound_uuid "$conf_file" 2>/dev/null || true)"
    if ! is_valid_uuid_text "$cur_uuid"; then
        cur_uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "AD3EF784-6895-48D7-82F9-0AEAC44EC4F3")"
    fi

    local new_inbound=""
    local replace_existing=0
    local replace_port=""
    local shadowtls_target_port=""
    local shadowtls_target_proto=""
    local initial_user_name=""
    local initial_user_id=""
    local random_port_range random_min_port random_max_port port_prompt
    random_port_range="$(resolve_inbound_random_port_range)"
    IFS='|' read -r random_min_port random_max_port <<< "$random_port_range"
    port_prompt="$(inbound_port_prompt_text)"

    if [[ "$type_code" == "1" ]]; then
        echo "--- 添加 trojan ---"
        local tr_build tr_lines
        tr_build="$(protocol_install_build_trojan_inbound "$conf_file" "$listen_addr" "$selected_user_name" "$random_min_port" "$port_prompt")"
        case $? in
            2) red "❌ 无法继续：trojan 必须依赖有效证书。"; return ;;
            3) red "错误: 域名无效。"; return ;;
            *) ;;
        esac
        mapfile -t tr_lines <<<"$tr_build"
        local tr_port="${tr_lines[0]}"
        [[ "${tr_lines[1]}" == "1" ]] && { replace_existing=1; replace_port="$tr_port"; }
        local tr_pass="${tr_lines[2]}"
        new_inbound="$(printf '%s\n' "${tr_lines[@]:3}")"
        if [[ -z "$new_inbound" ]]; then
            red "错误: 域名无效。"
            return
        fi
        initial_user_name="$selected_user_name"
        initial_user_id="$tr_pass"
    elif [[ "$type_code" == "2" ]]; then
        echo "--- 添加 vless reality ---"
        local v_build v_lines
        v_build="$(protocol_install_build_vless_inbound "$conf_file" "$listen_addr" "$selected_user_name" "$random_min_port" "$port_prompt" "$cur_uuid")"
        if [[ $? -ne 0 ]]; then
            red "❌ Reality 密钥生成失败，请检查 sing-box 或 openssl 环境。"
            return
        fi
        mapfile -t v_lines <<<"$v_build"
        local v_port="${v_lines[0]}"
        [[ "${v_lines[1]}" == "1" ]] && { replace_existing=1; replace_port="$v_port"; }
        initial_user_name="$selected_user_name"
        initial_user_id="$cur_uuid"
        new_inbound="$(printf '%s\n' "${v_lines[@]:3}")"
    elif [[ "$type_code" == "3" ]]; then
        echo "--- 添加 tuic v5 ---"
        local t_build t_lines
        t_build="$(protocol_install_build_tuic_inbound "$conf_file" "$listen_addr" "$selected_user_name" "$random_min_port" "$random_max_port" "$cur_uuid")"
        case $? in
            2) red "❌ 无法继续：tuic 必须依赖有效证书。"; return ;;
            *) ;;
        esac
        mapfile -t t_lines <<<"$t_build"
        local t_port="${t_lines[0]}"
        [[ "${t_lines[1]}" == "1" ]] && { replace_existing=1; replace_port="$t_port"; }
        local t_pass="${t_lines[2]}"
        initial_user_name="$selected_user_name"
        initial_user_id="$cur_uuid"
        new_inbound="$(printf '%s\n' "${t_lines[@]:3}")"
    elif [[ "$type_code" == "4" ]]; then
        echo "--- 添加 ss ---"
        local ss_build ss_lines
        ss_build="$(protocol_install_build_ss_inbound "$conf_file" "$listen_addr" "$selected_user_name" "$random_min_port" "$port_prompt")"
        case $? in
            3)
                red "仅支持 ss 2022 方法。"
                return
                ;;
            4)
                local ss_key_len
                ss_key_len="$(ss2022_key_length "2022-blake3-aes-128-gcm")"
                red "密码格式无效：需要 Base64 编码的有效 ss 2022 密钥。"
                return
                ;;
        esac
        mapfile -t ss_lines <<<"$ss_build"
        local ss_port="${ss_lines[0]}"
        [[ "${ss_lines[1]}" == "1" ]] && { replace_existing=1; replace_port="$ss_port"; }
        local ss_pass="${ss_lines[2]}"
        new_inbound="$(printf '%s\n' "${ss_lines[@]:3}")"
        if [[ -z "$new_inbound" ]]; then
            red "仅支持 ss 2022 方法。"
            return
        fi
        initial_user_name="$selected_user_name"
        initial_user_id="$ss_pass"
        shadowtls_target_port="$ss_port"
        shadowtls_target_proto="ss"
    elif [[ "$type_code" == "5" ]]; then
        echo "--- 添加 anytls ---"
        local a_build a_lines
        a_build="$(protocol_install_build_anytls_inbound "$conf_file" "$listen_addr" "$selected_user_name" "$random_min_port" "$port_prompt")"
        case $? in
            2) red "❌ 无法继续：anytls 必须依赖有效证书。"; return ;;
            *) ;;
        esac
        mapfile -t a_lines <<<"$a_build"
        local a_port="${a_lines[0]}"
        [[ "${a_lines[1]}" == "1" ]] && { replace_existing=1; replace_port="$a_port"; }
        local a_pass="${a_lines[2]}"
        initial_user_name="$selected_user_name"
        initial_user_id="$a_pass"
        new_inbound="$(printf '%s\n' "${a_lines[@]:3}")"
    fi

    if [[ -n "$new_inbound" ]]; then
        backup_conf_file "$conf_file"
        local tmp_json
        tmp_json=$(mktemp)
        local new_inbound_json
        new_inbound_json="$(echo "$new_inbound" | jq -c '.' 2>/dev/null || true)"
        if [[ -z "$new_inbound_json" ]]; then
            rm -f "$tmp_json"
            red "内部错误：生成入站配置失败（JSON 无效）。"
            return
        fi
        protocol_install_apply_new_inbound_change() {
            local route_sync_required=0
            if [[ "$replace_existing" -eq 1 && -n "$replace_port" ]]; then
                if ! [[ "$replace_port" =~ ^[0-9]+$ ]]; then
                    rm -f "$tmp_json"
                    red "内部错误：覆盖端口非法（$replace_port）。"
                    return 1
                fi
                local replaced_count
                replaced_count=$(jq -r --arg p "$replace_port" '[.inbounds[]? | select((.listen_port // 0 | tostring) == $p)] | length' "$conf_file" 2>/dev/null || echo 0)
                jq --arg p "$replace_port" --argjson new "$new_inbound_json" '
                    .inbounds = ((.inbounds // []) | map(select((.listen_port // 0 | tostring) != $p)) + [$new])
                ' "$conf_file" > "$tmp_json"
                [[ "$replaced_count" =~ ^[0-9]+$ ]] || replaced_count=0
                (( replaced_count > 0 )) && yellow "已覆盖端口 ${replace_port} 上的 ${replaced_count} 条入站配置。"
            else
                jq --argjson new "$new_inbound_json" '.inbounds = ((.inbounds // []) + [$new])' "$conf_file" > "$tmp_json"
            fi

            if [[ ! -s "$tmp_json" ]]; then
                red "配置更新失败"
                return 1
            fi

            mv "$tmp_json" "$conf_file"
            if [[ -n "$initial_user_id" && -n "$initial_user_name" ]]; then
                local initial_proto initial_tag initial_key inherited_template_id=""
                case "$type_code" in
                    1) initial_proto="trojan" ;;
                    2) initial_proto="vless" ;;
                    3) initial_proto="tuic" ;;
                    4) initial_proto="ss" ;;
                    5) initial_proto="anytls" ;;
                    *) initial_proto="" ;;
                esac
                initial_tag="$(jq -r '.tag // empty' <<<"$new_inbound_json" 2>/dev/null || true)"
                if [[ -n "$initial_proto" && -n "$initial_tag" ]]; then
                    initial_key="$(make_user_key "$initial_proto" "$initial_tag" "$initial_user_id")"
                    if declare -F routing_user_requires_route_sync_after_protocol_add >/dev/null 2>&1; then
                        routing_user_requires_route_sync_after_protocol_add "$initial_user_name" "$initial_key" "$conf_file" && route_sync_required=1 || route_sync_required=0
                    fi
                    if declare -F proxy_user_inherit_template_id_for_key >/dev/null 2>&1; then
                        inherited_template_id="$(proxy_user_inherit_template_id_for_key "$initial_user_name" "$initial_key" "$conf_file" 2>/dev/null || true)"
                    fi
                    if protocol_install_session_active; then
                        protocol_install_session_queue_membership "$initial_user_name" "$initial_key" "$inherited_template_id" "$route_sync_required" "$conf_file" || true
                    elif declare -F proxy_user_meta_apply_protocol_membership >/dev/null 2>&1; then
                        proxy_user_meta_apply_protocol_membership "$initial_user_name" "$initial_key" "$inherited_template_id" >/dev/null 2>&1 || true
                    else
                        proxy_user_group_add "$initial_user_name" >/dev/null 2>&1 || true
                        proxy_user_meta_set_name "$initial_key" "$initial_user_name" >/dev/null 2>&1 || true
                        proxy_user_inherit_template_for_key "$initial_user_name" "$initial_key" "$conf_file" || true
                    fi
                fi
            fi
            if ! protocol_install_session_active; then
                (( route_sync_required == 1 )) && sync_user_template_route_rules "$conf_file" >/dev/null 2>&1 || true
            fi
            if protocol_install_session_active; then
                protocol_install_apply_singbox_change
                green “添加成功，已复用配置。”
            else
                green "添加成功！重启 sing-box..."
                protocol_install_apply_singbox_change
            fi
            return 0
        }

        if declare -F proxy_run_with_spinner_compact >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
            protocol_install_apply_new_inbound_change_with_spinner() {
                protocol_install_apply_new_inbound_change
            }
            if ! proxy_run_with_spinner_compact "正在写入协议配置..." protocol_install_apply_new_inbound_change_with_spinner; then
                return
            fi
        else
            if ! protocol_install_apply_new_inbound_change; then
                return
            fi
        fi

        # `proxy_run_with_spinner_compact` runs the wrapped function in a background
        # process, so any prompt inside that function would block on /dev/tty while
        # the spinner keeps overwriting the terminal. Keep the optional ShadowTLS
        # setup outside the spinner to avoid hidden interactive waits.
        if [[ "$shadowtls_target_proto" == "ss" && -n "$shadowtls_target_port" ]]; then
            local ss_st_enable=""
            if ! read_prompt ss_st_enable "是否配置 shadow-tls-v3 保护此 ss 端口? [y/N]: "; then
                ss_st_enable=""
            fi
            if [[ "${ss_st_enable,,}" == "y" ]]; then
                configure_shadowtls_for_target "$shadowtls_target_port" "ss" || true
            fi
        fi
    fi
}

# --- sing-box inbound build helpers (merged from protocol_install_singbox_build_ops.sh) ---

protocol_install_tls_domain_default() {
    local default_domain="yourdomain.com"
    if [[ -f "${WORK_DIR}/.domain" ]]; then
        default_domain="$(cat "${WORK_DIR}/.domain")"
    elif [[ -d "${WORK_DIR}/caddy/certificates" ]]; then
        local detected_domain
        detected_domain="$(resolve_tls_server_domain_default 2>/dev/null || true)"
        [[ -n "$detected_domain" ]] && default_domain="$detected_domain"
    fi
    printf '%s\n' "$default_domain"
}

protocol_install_require_tls_cert() {
    local domain="$1"
    local cert_path="" key_path="" cert_pair=""
    if is_valid_domain_name "$domain"; then
        echo "$domain" > "${WORK_DIR}/.domain"
    fi
    cert_pair="$(resolve_caddy_tls_cert_pair "$domain" 2>/dev/null || true)"
    if [[ -n "$cert_pair" ]]; then
        IFS='|' read -r cert_path key_path <<<"$cert_pair"
    fi

    if [[ ! -f "$cert_path" ]]; then
        yellow "⚠️ 未检测到证书，准备通过 caddy 自动申请..." >&2
        local auto_cert=""
        if ! read_prompt auto_cert "是否立即启动 caddy 并申请证书? [y/N]: "; then
            auto_cert=""
        fi
        if [[ "${auto_cert,,}" == "y" ]]; then
            cert_path="${WORK_DIR}/caddy/certificates/pending/${domain}.crt"
            setup_caddy_sub "" "$domain" || return 1
            wait_for_tls_certificate_file "$cert_path" 60 || return 1
            cert_pair="$(resolve_caddy_tls_cert_pair "$domain" 2>/dev/null || true)"
            [[ -n "$cert_pair" ]] || return 1
            IFS='|' read -r cert_path key_path <<<"$cert_pair"
        else
            return 2
        fi
    fi

    printf '%s|%s\n' "$cert_path" "$key_path"
}

protocol_install_build_trojan_inbound() {
    local conf_file="$1" listen_addr="$2" selected_user_name="$3" random_min_port="$4" port_prompt="$5"
    local tr_port tr_pick tr_domain input_domain cert_pair cert_path key_path tr_pass

    tr_port="$(gen_preferred_inbound_port "trojan" "$conf_file")"
    [[ -z "$tr_port" ]] && tr_port="$random_min_port"
    tr_pick="$(pick_singbox_port_with_override "$conf_file" "$tr_port" "$port_prompt")"
    tr_port="${tr_pick%%|*}"

    tr_domain="$(protocol_install_tls_domain_default)"
    if ! read_prompt input_domain "域名 (需与 caddy 一致) [默认: ${tr_domain}]: "; then
        input_domain=""
    fi
    tr_domain="${input_domain:-$tr_domain}"
    if ! is_valid_domain_name "$tr_domain"; then
        return 3
    fi

    cert_pair="$(protocol_install_require_tls_cert "$tr_domain")" || return $?
    IFS='|' read -r cert_path key_path <<<"$cert_pair"

    tr_pass="$(gen_rand_alnum 16)"
    cat <<EOF
${tr_port}
${tr_pick##*|}
${tr_pass}
{
  "type": "trojan",
  "tag": "trojan_${tr_port}",
  "listen": "${listen_addr}",
  "listen_port": ${tr_port},
  "users": [{"name": "${selected_user_name}", "password": "${tr_pass}"}],
  "tls": {
    "enabled": true,
    "server_name": "${tr_domain}",
    "alpn": ["h2", "http/1.1"],
    "certificate_path": "${cert_path}",
    "key_path": "${key_path}"
  }
}
EOF
}

protocol_install_build_vless_inbound() {
    local conf_file="$1" listen_addr="$2" selected_user_name="$3" random_min_port="$4" port_prompt="$5" cur_uuid="$6"
    local v_port v_pick v_sni input_sni keypair v_priv v_pub v_sid

    v_port="$(gen_preferred_inbound_port "vless" "$conf_file")"
    [[ -z "$v_port" ]] && v_port="$random_min_port"
    v_pick="$(pick_singbox_port_with_override "$conf_file" "$v_port" "$port_prompt")"
    v_port="${v_pick%%|*}"

    v_sni="$(pick_decoy_sni_domain)"
    if ! read_prompt input_sni "伪装域名 [默认: $v_sni]: "; then
        input_sni=""
    fi
    v_sni=${input_sni:-$v_sni}

    keypair="$(generate_reality_keypair 2>/dev/null || true)"
    IFS='|' read -r v_priv v_pub <<<"$keypair"
    if ! is_valid_reality_key "$v_priv"; then
        return 1
    fi
    v_sid=$(openssl rand -hex 8)

    cat <<EOF
${v_port}
${v_pick##*|}
${cur_uuid}
{
  "type": "vless",
  "tag": "vless_reality_${v_port}",
  "listen": "${listen_addr}",
  "listen_port": ${v_port},
  "users": [{"name": "${selected_user_name}", "uuid": "${cur_uuid}", "flow": "xtls-rprx-vision"}],
  "tls": {
    "enabled": true,
    "server_name": "${v_sni}",
    "reality": {
      "enabled": true,
      "handshake": {"server": "${v_sni}", "server_port": 443},
      "private_key": "${v_priv}",
      "short_id": ["${v_sid}"]
    }
  }
}
EOF
}

protocol_install_build_tuic_inbound() {
    local conf_file="$1" listen_addr="$2" selected_user_name="$3" random_min_port="$4" random_max_port="$5" cur_uuid="$6"
    local t_port t_pick t_domain input_domain cert_pair cert_path key_path t_pass

    t_port="$(gen_preferred_inbound_port "tuic" "$conf_file")"
    [[ -z "$t_port" ]] && t_port="$random_min_port"
    t_pick="$(pick_singbox_port_with_override "$conf_file" "$t_port" "监听端口(默认随机 ${random_min_port}-${random_max_port})")"
    t_port="${t_pick%%|*}"

    t_domain="$(protocol_install_tls_domain_default)"
    if ! read_prompt input_domain "域名 (需与 caddy 一致) [默认: $t_domain]: "; then
        input_domain=""
    fi
    t_domain=${input_domain:-$t_domain}

    cert_pair="$(protocol_install_require_tls_cert "$t_domain")" || return $?
    IFS='|' read -r cert_path key_path <<<"$cert_pair"

    t_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    cat <<EOF
${t_port}
${t_pick##*|}
${t_pass}
{
  "type": "tuic",
  "tag": "tuic5_${t_port}",
  "listen": "${listen_addr}",
  "listen_port": ${t_port},
  "users": [{"name": "${selected_user_name}", "uuid": "${cur_uuid}", "password": "${t_pass}"}],
  "congestion_control": "bbr",
  "tls": {
    "enabled": true,
    "server_name": "${t_domain}",
    "alpn": ["h3"],
    "certificate_path": "${cert_path}",
    "key_path": "${key_path}"
  }
}
EOF
}

protocol_install_build_ss_inbound() {
    local conf_file="$1" listen_addr="$2" selected_user_name="$3" random_min_port="$4" port_prompt="$5"
    local ss_port ss_pick ss_method input_method ss_pass input_pass

    ss_port="$(gen_preferred_inbound_port "ss" "$conf_file")"
    [[ -z "$ss_port" ]] && ss_port="$random_min_port"
    ss_pick="$(pick_singbox_port_with_override "$conf_file" "$ss_port" "$port_prompt")"
    ss_port="${ss_pick%%|*}"
    ss_method="2022-blake3-aes-128-gcm"
    if ! read_prompt input_method "加密方式 [默认: $ss_method，可选: 2022-blake3-aes-128-gcm/2022-blake3-aes-256-gcm/2022-blake3-chacha20-poly1305]: "; then
        input_method=""
    fi
    ss_method=${input_method:-$ss_method}
    if ! is_ss2022_method "$ss_method"; then
        return 3
    fi
    ss_pass="$(gen_ss_password_by_method "$ss_method")"
    if ! read_prompt input_pass "密码 [默认随机]: "; then
        input_pass=""
    fi
    ss_pass=${input_pass:-$ss_pass}
    if ! validate_ss_password_for_method "$ss_method" "$ss_pass"; then
        return 4
    fi

    cat <<EOF
${ss_port}
${ss_pick##*|}
${ss_pass}
{
  "type": "shadowsocks",
  "tag": "ss_${ss_port}",
  "listen": "${listen_addr}",
  "listen_port": ${ss_port},
  "name": "${selected_user_name}",
  "method": "${ss_method}",
  "password": "${ss_pass}"
}
EOF
}

protocol_install_build_anytls_inbound() {
    local conf_file="$1" listen_addr="$2" selected_user_name="$3" random_min_port="$4" port_prompt="$5"
    local a_port a_pick a_pass input_pass a_domain input_domain cert_pair cert_path key_path

    a_port="$(gen_preferred_inbound_port "anytls" "$conf_file")"
    [[ -z "$a_port" ]] && a_port="$random_min_port"
    a_pick="$(pick_singbox_port_with_override "$conf_file" "$a_port" "$port_prompt")"
    a_port="${a_pick%%|*}"

    a_pass="$(gen_rand_alnum 16)"
    if ! read_prompt input_pass "密码 [默认随机]: "; then
        input_pass=""
    fi
    a_pass=${input_pass:-$a_pass}

    a_domain="$(protocol_install_tls_domain_default)"
    if ! read_prompt input_domain "域名 (需与 caddy 一致) [默认: $a_domain]: "; then
        input_domain=""
    fi
    a_domain=${input_domain:-$a_domain}

    cert_pair="$(protocol_install_require_tls_cert "$a_domain")" || return $?
    IFS='|' read -r cert_path key_path <<<"$cert_pair"

    cat <<EOF
${a_port}
${a_pick##*|}
${a_pass}
{
  "type": "anytls",
  "tag": "anytls_${a_port}",
  "listen": "${listen_addr}",
  "listen_port": ${a_port},
  "users": [{"name": "${selected_user_name}", "password": "${a_pass}"}],
  "tls": {
    "enabled": true,
    "server_name": "${a_domain}",
    "certificate_path": "${cert_path}",
    "key_path": "${key_path}"
  }
}
EOF
}

# --- protocol install session/support helpers (merged from protocol_install_support_ops.sh) ---

PROTOCOL_INSTALL_SESSION_ACTIVE="${PROTOCOL_INSTALL_SESSION_ACTIVE:-0}"
PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART="${PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART:-0}"
PROTOCOL_INSTALL_PENDING_SNELL_RESTART="${PROTOCOL_INSTALL_PENDING_SNELL_RESTART:-0}"
PROTOCOL_INSTALL_PENDING_USER_MEMBERSHIP_TEXT="${PROTOCOL_INSTALL_PENDING_USER_MEMBERSHIP_TEXT:-}"
PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_REQUIRED="${PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_REQUIRED:-0}"
PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_CONF_FILE="${PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_CONF_FILE:-}"
PROTOCOL_INSTALL_SESSION_DIR="${PROTOCOL_INSTALL_SESSION_DIR:-}"

protocol_install_session_dir() {
    if [[ -n "${PROTOCOL_INSTALL_SESSION_DIR:-}" ]]; then
        printf '%s\n' "$PROTOCOL_INSTALL_SESSION_DIR"
        return 0
    fi
    printf '%s\n' "${TEMP_DIR:-/tmp/shell-proxy}/install-session"
}

protocol_install_session_services_file() {
    printf '%s/services.txt\n' "$(protocol_install_session_dir)"
}

protocol_install_session_membership_file() {
    printf '%s/membership.tsv\n' "$(protocol_install_session_dir)"
}

protocol_install_session_route_sync_file() {
    printf '%s/route-sync.txt\n' "$(protocol_install_session_dir)"
}

protocol_install_session_active() {
    [[ "${PROTOCOL_INSTALL_SESSION_ACTIVE:-0}" == "1" ]]
}

protocol_install_session_begin() {
    local session_dir
    PROTOCOL_INSTALL_SESSION_ACTIVE=1
    PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART=0
    PROTOCOL_INSTALL_PENDING_SNELL_RESTART=0
    PROTOCOL_INSTALL_PENDING_USER_MEMBERSHIP_TEXT=""
    PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_REQUIRED=0
    PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_CONF_FILE=""
    session_dir="$(protocol_install_session_dir)"
    PROTOCOL_INSTALL_SESSION_DIR="$session_dir"
    mkdir -p "$session_dir" >/dev/null 2>&1 || true
    : >"$(protocol_install_session_services_file)"
    : >"$(protocol_install_session_membership_file)"
    : >"$(protocol_install_session_route_sync_file)"
}

protocol_install_session_has_pending_changes() {
    local services_file
    services_file="$(protocol_install_session_services_file)"
    if (( ${PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART:-0} == 1 || ${PROTOCOL_INSTALL_PENDING_SNELL_RESTART:-0} == 1 )); then
        return 0
    fi
    [[ -s "$services_file" ]]
}

protocol_install_session_pending_summary() {
    local -a items=()
    local services_file service=""
    (( ${PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART:-0} == 1 )) && items+=("sing-box")
    (( ${PROTOCOL_INSTALL_PENDING_SNELL_RESTART:-0} == 1 )) && items+=("snell-v5")
    services_file="$(protocol_install_session_services_file)"
    if [[ -f "$services_file" ]]; then
        while IFS= read -r service; do
            [[ -n "$service" ]] || continue
            items+=("$service")
        done < "$services_file"
    fi
    if (( ${#items[@]} > 0 )); then
        printf '%s\n' "${items[@]}" | awk '!seen[$0]++' | paste -sd' ' -
        return 0
    fi
    printf '%s' "${items[*]}"
}

protocol_install_session_mark_service_dirty() {
    local service="${1:-}" services_file
    case "$service" in
        sing-box) PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART=1 ;;
        snell-v5) PROTOCOL_INSTALL_PENDING_SNELL_RESTART=1 ;;
        *) return 1 ;;
    esac
    if protocol_install_session_active; then
        services_file="$(protocol_install_session_services_file)"
        mkdir -p "$(dirname "$services_file")" >/dev/null 2>&1 || true
        printf '%s\n' "$service" >>"$services_file"
    fi
}

protocol_install_restart_singbox_now() {
    restart_singbox_if_present
}

protocol_install_restart_snell_now() {
    systemctl enable snell-v5 2>/dev/null || true
    systemctl restart snell-v5
    check_service_result "snell-v5" "重启"
}

protocol_install_apply_singbox_change() {
    if protocol_install_session_active; then
        protocol_install_session_mark_service_dirty "sing-box"
        return 0
    fi
    protocol_install_restart_singbox_now
}

protocol_install_apply_snell_change() {
    if protocol_install_session_active; then
        protocol_install_session_mark_service_dirty "snell-v5"
        return 0
    fi
    protocol_install_restart_snell_now
}

protocol_install_session_queue_membership() {
    local target_name="${1:-}" key="${2:-}" template_id="${3:-}" route_sync_required="${4:-0}" conf_file="${5:-}"
    local membership_file route_sync_file
    proxy_is_blank_string "$target_name" && return 1
    target_name="$(normalize_proxy_user_name "$target_name")"
    [[ -n "$target_name" && -n "$key" ]] || return 1
    PROTOCOL_INSTALL_PENDING_USER_MEMBERSHIP_TEXT+="${target_name}"$'\t'"${key}"$'\t'"${template_id}"$'\n'
    membership_file="$(protocol_install_session_membership_file)"
    mkdir -p "$(dirname "$membership_file")" >/dev/null 2>&1 || true
    printf '%s\t%s\t%s\n' "$target_name" "$key" "$template_id" >>"$membership_file"
    if [[ "$route_sync_required" == "1" && -n "$conf_file" && -f "$conf_file" ]]; then
        PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_REQUIRED=1
        PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_CONF_FILE="$conf_file"
        route_sync_file="$(protocol_install_session_route_sync_file)"
        printf '%s\n' "$conf_file" >"$route_sync_file"
    fi
}

protocol_install_session_apply_pending_metadata() {
    local records_file conf_file route_sync_file membership_file
    records_file="$(mktemp)"
    membership_file="$(protocol_install_session_membership_file)"
    route_sync_file="$(protocol_install_session_route_sync_file)"
    if [[ -n "${PROTOCOL_INSTALL_PENDING_USER_MEMBERSHIP_TEXT:-}" ]]; then
        printf '%s' "${PROTOCOL_INSTALL_PENDING_USER_MEMBERSHIP_TEXT:-}" >>"$records_file"
    fi
    if [[ -f "$membership_file" ]]; then
        cat "$membership_file" >>"$records_file"
    fi
    if [[ ! -s "$records_file" ]]; then
        rm -f "$records_file"
    else
        awk 'NF && !seen[$0]++' "$records_file" >"${records_file}.dedup"
        mv -f "${records_file}.dedup" "$records_file"
    fi

    if [[ -s "$records_file" ]]; then
        if declare -F proxy_user_meta_apply_protocol_memberships_batch >/dev/null 2>&1; then
            proxy_user_meta_apply_protocol_memberships_batch "$records_file" >/dev/null 2>&1 || true
        else
            local target_name key template_id
            while IFS=$'\t' read -r target_name key template_id; do
                [[ -n "$target_name" && -n "$key" ]] || continue
                proxy_user_meta_apply_protocol_membership "$target_name" "$key" "$template_id" >/dev/null 2>&1 || true
            done < "$records_file"
        fi
    fi
    rm -f "$records_file"
    PROTOCOL_INSTALL_PENDING_USER_MEMBERSHIP_TEXT=""

    if (( ${PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_REQUIRED:-0} == 1 )); then
        conf_file="${PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_CONF_FILE:-}"
        if [[ -n "$conf_file" && -f "$conf_file" ]]; then
            yellow "正在同步路由规则..."
            sync_user_template_route_rules "$conf_file" >/dev/null 2>&1 || true
        fi
    elif [[ -f "$route_sync_file" ]]; then
        conf_file="$(tail -n1 "$route_sync_file" 2>/dev/null || true)"
        if [[ -n "$conf_file" && -f "$conf_file" ]]; then
            yellow "正在同步路由规则..."
            sync_user_template_route_rules "$conf_file" >/dev/null 2>&1 || true
        fi
    fi
    PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_REQUIRED=0
    PROTOCOL_INSTALL_PENDING_ROUTE_SYNC_CONF_FILE=""
    : >"$membership_file"
    : >"$route_sync_file"
}

_protocol_install_session_flush_inner() {
    protocol_install_session_apply_pending_metadata
    if (( ${PROTOCOL_INSTALL_PENDING_SNELL_RESTART:-0} == 1 )); then
        protocol_install_restart_snell_now
    fi
    if (( ${PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART:-0} == 1 )); then
        protocol_install_restart_singbox_now
    fi
}

protocol_install_session_flush_now() {
    if ! protocol_install_session_has_pending_changes; then
        return 1
    fi

    if declare -F proxy_run_with_spinner_fg >/dev/null 2>&1; then
        proxy_run_with_spinner_fg "正在应用新配置文件..." _protocol_install_session_flush_inner
    else
        yellow "正在应用新配置文件..."
        _protocol_install_session_flush_inner
    fi

    PROTOCOL_INSTALL_PENDING_SINGBOX_RESTART=0
    PROTOCOL_INSTALL_PENDING_SNELL_RESTART=0
    return 0
}

protocol_install_session_flush() {
    if ! protocol_install_session_has_pending_changes; then
        return 1
    fi

    # flush_now uses proxy_run_with_spinner_fg which runs the spinner in a
    # background process and work in the foreground, preserving variable state.
    protocol_install_session_flush_now
}

protocol_install_session_end() {
    local flushed=1
    protocol_install_session_flush || flushed=$?
    PROTOCOL_INSTALL_SESSION_ACTIVE=0
    if [[ -n "${PROTOCOL_INSTALL_SESSION_DIR:-}" && -d "${PROTOCOL_INSTALL_SESSION_DIR:-}" ]]; then
        rm -rf "${PROTOCOL_INSTALL_SESSION_DIR}" >/dev/null 2>&1 || true
    fi
    PROTOCOL_INSTALL_SESSION_DIR=""
    return "$flushed"
}

proxy_select_install_inbound_for_protocol() {
    local conf_file="${1:-}" proto="${2:-}"
    [[ -n "$proto" ]] || { echo "__new__"; return 0; }

    local rows=()
    mapfile -t rows < <(proxy_collect_inbound_rows_by_protocol "$conf_file" "$proto")
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "__new__"
        return 0
    fi

    if [[ ${#rows[@]} -eq 1 ]]; then
        local auto_idx auto_tag auto_port _auto_desc
        IFS=$'\t' read -r auto_idx auto_tag auto_port _auto_desc <<<"${rows[0]}"
        printf '复用已有 %s 入站: %s 端口 %s\n' "$(proxy_user_protocol_label "$proto")" "$auto_tag" "$auto_port" >&2
        echo "$auto_idx"
        return 0
    fi

    echo >&2
    echo "选择 $(proxy_user_protocol_label "$proto") 入站" >&2
    local idx=1 row inbound_idx tag port desc
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r inbound_idx tag port desc <<<"$row"
        printf '%d. tag=%s | 端口=%s | %s\n' "$idx" "$tag" "$port" "$desc" >&2
        ((idx++))
    done
    echo "0. 新建独立入站" >&2

    if ! read_prompt pick "选择序号(回车默认复用第1个): "; then
        echo ""
        return
    fi
    if [[ -z "$pick" ]]; then
        IFS=$'\t' read -r inbound_idx _tag _port _desc <<<"${rows[0]}"
        echo "$inbound_idx"
        return 0
    fi
    if [[ "$pick" == "0" ]]; then
        echo "__new__"
        return 0
    fi
    if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > ${#rows[@]} )); then
        echo "__invalid__"
        return
    fi
    IFS=$'\t' read -r inbound_idx _tag _port _desc <<<"${rows[$((pick-1))]}"
    echo "$inbound_idx"
}

proxy_append_user_to_existing_inbound() {
    local conf_file="${1:-}" proto="${2:-}" idx="${3:-}" target_name="${4:-}"
    [[ -n "$conf_file" && -f "$conf_file" && -n "$proto" && "$idx" =~ ^[0-9]+$ && -n "$target_name" ]] || return 1

    local tmp_json created_user_id="" target_tag="" target_port=""
    target_name="$(normalize_proxy_user_name "$target_name")"
    target_tag="$(jq -r --argjson i "$idx" '.inbounds[$i].tag // ("inbound_" + ($i|tostring))' "$conf_file" 2>/dev/null || true)"
    target_port="$(jq -r --argjson i "$idx" '.inbounds[$i].listen_port // ""' "$conf_file" 2>/dev/null || true)"
    tmp_json="$(mktemp)"

    case "$proto" in
        vless)
            local new_uuid input_uuid
            new_uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
            if ! read_prompt input_uuid "uuid [回车随机]: "; then
                rm -f "$tmp_json"
                return 1
            fi
            new_uuid="${input_uuid:-$new_uuid}"
            created_user_id="$new_uuid"
            jq --argjson i "$idx" --arg u "$new_uuid" --arg n "$target_name" '
                .inbounds[$i] |= (
                    .users = (
                        (if (.users | type) == "array" then .users
                         elif (.users | type) == "object" then [.users]
                         elif (.uuid? != null) then [{name:(.name // ""), uuid:(.uuid // .id // ""), flow:(.flow // "xtls-rprx-vision")}]
                         else [] end)
                        + [{name:$n, uuid:$u, flow:(((if (.users | type) == "array" then .users[0].flow else null end) // .flow // "xtls-rprx-vision"))}]
                    )
                    | del(.uuid, .id, .name, .flow)
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        tuic)
            local new_uuid new_pass input_uuid input_pass
            new_uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
            new_pass="$(gen_rand_alnum 16)"
            if ! read_prompt input_uuid "uuid [回车随机]: "; then
                rm -f "$tmp_json"
                return 1
            fi
            new_uuid="${input_uuid:-$new_uuid}"
            if ! read_prompt input_pass "password [回车随机]: "; then
                rm -f "$tmp_json"
                return 1
            fi
            new_pass="${input_pass:-$new_pass}"
            created_user_id="$new_uuid"
            jq --argjson i "$idx" --arg u "$new_uuid" --arg p "$new_pass" --arg n "$target_name" '
                .inbounds[$i] |= (
                    .users = (
                        (if (.users | type) == "array" then .users
                         elif (.users | type) == "object" then [.users]
                         elif (.uuid? != null and .password? != null) then [{name:(.name // ""), uuid:(.uuid // .id // ""), password:(.password // "")}]
                         else [] end)
                        + [{name:$n, uuid:$u, password:$p}]
                    )
                    | del(.uuid, .id, .name, .password)
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        trojan)
            local new_pass input_pass
            new_pass="$(gen_rand_alnum 16)"
            if ! read_prompt input_pass "password [回车随机]: "; then
                rm -f "$tmp_json"
                return 1
            fi
            new_pass="${input_pass:-$new_pass}"
            created_user_id="$new_pass"
            jq --argjson i "$idx" --arg p "$new_pass" --arg n "$target_name" '
                .inbounds[$i] |= (
                    .users = (
                        (if (.users | type) == "array" then .users
                         elif (.users | type) == "object" then [.users]
                         elif (.password? != null) then [{name:(.name // ""), password:(.password // "")}]
                         else [] end)
                        + [{name:$n, password:$p}]
                    )
                    | del(.name, .password)
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        anytls)
            local new_pass input_pass
            new_pass="$(gen_rand_alnum 16)"
            if ! read_prompt input_pass "密码 [回车随机]: "; then
                rm -f "$tmp_json"
                return 1
            fi
            new_pass="${input_pass:-$new_pass}"
            created_user_id="$new_pass"
            jq --argjson i "$idx" --arg p "$new_pass" --arg n "$target_name" '
                .inbounds[$i] |= (
                    .users = (
                        (if (.users | type) == "array" then .users
                         elif (.users | type) == "object" then [.users]
                         elif (.password? != null) then [{name:(.name // ""), password:(.password // "")}]
                         else [] end)
                        + [{name:$n, password:$p}]
                    )
                    | del(.name, .password)
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        ss)
            local ss_method new_pass input_pass
            ss_method="$(jq -r --argjson i "$idx" '.inbounds[$i].method // "2022-blake3-aes-128-gcm"' "$conf_file" 2>/dev/null)"
            [[ -n "$ss_method" && "$ss_method" != "null" ]] || ss_method="2022-blake3-aes-128-gcm"
            new_pass="$(gen_ss_password_by_method "$ss_method")"
            if ! read_prompt input_pass "密码 [回车随机]: "; then
                rm -f "$tmp_json"
                return 1
            fi
            new_pass="${input_pass:-$new_pass}"
            if ! validate_ss_password_for_method "$ss_method" "$new_pass"; then
                local ss_key_len
                ss_key_len="$(ss2022_key_length "$ss_method")"
                red "密码格式无效：${ss_method} 需要 Base64 编码的 ${ss_key_len} 字节密钥。"
                rm -f "$tmp_json"
                return 1
            fi
            created_user_id="$new_pass"
            jq --argjson i "$idx" --arg m "$ss_method" --arg p "$new_pass" --arg n "$target_name" '
                .inbounds[$i] |= (
                    .method = (.method // $m)
                    | .users = (
                        (if (.users | type) == "array" then .users
                         elif (.users | type) == "object" then [.users]
                         elif (.password? != null) then [{name:(.name // ""), password:(.password // "")}]
                         else [] end)
                        + [{name:$n, password:$p}]
                    )
                    | .users |= map(select((.password // "") != ""))
                    | del(.name)
                )
            ' "$conf_file" > "$tmp_json" 2>/dev/null || true
            ;;
        *)
            rm -f "$tmp_json"
            return 1
            ;;
    esac

    if [[ ! -s "$tmp_json" ]] || ! jq . "$tmp_json" >/dev/null 2>&1; then
        rm -f "$tmp_json"
        return 1
    fi

    protocol_append_existing_user_apply_change() {
        local route_sync_required=0
        backup_conf_file "$conf_file"
        mv "$tmp_json" "$conf_file"
        if [[ -n "$created_user_id" && -n "$target_tag" ]]; then
            local created_key inherited_template_id=""
            created_key="$(make_user_key "$proto" "$target_tag" "$created_user_id")"
            if declare -F routing_user_requires_route_sync_after_protocol_add >/dev/null 2>&1; then
                routing_user_requires_route_sync_after_protocol_add "$target_name" "$created_key" "$conf_file" && route_sync_required=1 || route_sync_required=0
            fi
            if declare -F proxy_user_inherit_template_id_for_key >/dev/null 2>&1; then
                inherited_template_id="$(proxy_user_inherit_template_id_for_key "$target_name" "$created_key" "$conf_file" 2>/dev/null || true)"
            fi
            if protocol_install_session_active; then
                protocol_install_session_queue_membership "$target_name" "$created_key" "$inherited_template_id" "$route_sync_required" "$conf_file" || true
            elif declare -F proxy_user_meta_apply_protocol_membership >/dev/null 2>&1; then
                proxy_user_meta_apply_protocol_membership "$target_name" "$created_key" "$inherited_template_id" >/dev/null 2>&1 || true
            else
                proxy_user_group_add "$target_name" >/dev/null 2>&1 || true
                proxy_user_meta_set_name "$created_key" "$target_name" >/dev/null 2>&1 || true
                proxy_user_inherit_template_for_key "$target_name" "$created_key" "$conf_file" || true
            fi
        fi
        if ! protocol_install_session_active; then
            (( route_sync_required == 1 )) && sync_user_template_route_rules "$conf_file" >/dev/null 2>&1 || true
        fi
        protocol_install_apply_singbox_change
    }

    if declare -F proxy_run_with_spinner_compact >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        proxy_run_with_spinner_compact "正在写入复用配置..." protocol_append_existing_user_apply_change || return 1
    else
        protocol_append_existing_user_apply_change || return 1
    fi

    local proto_label
    proto_label="$(proxy_user_protocol_label "$proto")"
    green "已为用户名 ${target_name} 复用 ${proto_label} 入站: 端口 ${target_port:--}"
    return 0
}

# --- protocol install menu (merged from protocol_install_ops.sh) ---

protocol_install_get_occupied_ports_fast() {
    local conf_file="${1:-}"
    local occupied_ports=""

    if declare -F protocol_menu_cache_read_occupied_ports >/dev/null 2>&1; then
        occupied_ports="$(protocol_menu_cache_read_occupied_ports 2>/dev/null || true)"
    fi

    if [[ -z "$occupied_ports" && -n "${PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE:-}" ]]; then
        occupied_ports="${PROXY_PROTOCOL_OCCUPIED_PORTS_CACHE}"
    fi

    if declare -F protocol_menu_cache_schedule_rebuild_if_stale >/dev/null 2>&1; then
        protocol_menu_cache_schedule_rebuild_if_stale "$conf_file" >/dev/null 2>&1 || true
    elif declare -F protocol_menu_cache_schedule_rebuild >/dev/null 2>&1; then
        protocol_menu_cache_schedule_rebuild "$conf_file" >/dev/null 2>&1 || true
    fi

    if [[ -z "$occupied_ports" ]]; then
        printf '%s' ""
        return 0
    fi
    printf '%s' "$occupied_ports"
}

add_protocol() {
    local range random_min_port random_max_port tls_common ss_common snell_common summary_ports
    local conf_file occupied_ports
    local compact_port_summary
    local proto_type session_rc
    local C_RESET=$'\033[0m'
    local C_META=$'\033[90m'
    local C_OCCUPIED=$'\033[9;31m'

    protocol_install_session_begin
    while :; do
        ui_clear
        proxy_menu_header "添加协议(退出统一生效)"

        range="$(resolve_inbound_random_port_range)"
        IFS='|' read -r random_min_port random_max_port <<< "$range"
        tls_common="$(common_ports_for_proto "trojan")"
        ss_common="$(common_ports_for_proto "ss")"
        snell_common="$(common_ports_for_proto "snell")"

        conf_file="$(get_conf_file 2>/dev/null || true)"
        occupied_ports="$(protocol_install_get_occupied_ports_fast "$conf_file")"

        summary_ports="${tls_common} ${ss_common} ${snell_common}"
        compact_port_summary="$(render_compact_port_summary_with_usage \
            "$summary_ports" "$occupied_ports" "$random_min_port" "$random_max_port" "$C_META" "$C_OCCUPIED")"

        echo -e "(${compact_port_summary})"
        echo "  1. ss"
        echo "  2. vless"
        echo "  3. tuic"
        echo "  4. trojan"
        echo "  5. anytls"
        echo "  6. snell-v5"
        proxy_menu_rule "═"
        if ! read_prompt proto_type "选择(回车返回): "; then
            break
        fi
        [[ -z "$proto_type" ]] && break

        case $proto_type in
            1) modify_singbox_inbounds_logic 4 ;;
            2) modify_singbox_inbounds_logic 2 ;;
            3) modify_singbox_inbounds_logic 3 ;;
            4) modify_singbox_inbounds_logic 1 ;;
            5) modify_singbox_inbounds_logic 5 ;;
            6) modify_snell_config ;;
            *)
                red "无效输入"
                sleep 1
                continue
                ;;
        esac

        if declare -F protocol_menu_cache_schedule_rebuild >/dev/null 2>&1; then
            protocol_menu_cache_schedule_rebuild "$conf_file"
        fi
    done

    session_rc=0
    protocol_install_session_end || session_rc=$?
}

# --- snell installation flow helpers (merged from protocol_install_snell_ops.sh) ---

modify_snell_config() {
    ui_clear
    proxy_menu_header "配置 snell-v5"
    local has_conf="no"
    [[ -f "$SNELL_CONF" ]] && has_conf="yes"

    local random_port_range random_min_port random_max_port conf_file_for_port
    random_port_range="$(resolve_inbound_random_port_range)"
    IFS='|' read -r random_min_port random_max_port <<< "$random_port_range"
    conf_file_for_port="$(get_conf_file)"

    local current_listen current_port current_psk current_udp current_obfs current_ipv6
    current_listen=$(grep "^listen" "$SNELL_CONF" 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ')
    current_port=$(echo "$current_listen" | awk -F':' '{print $NF}')
    current_psk=$(grep "^psk" "$SNELL_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    current_udp=$(grep "^udp" "$SNELL_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    current_obfs=$(grep "^obfs" "$SNELL_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    current_ipv6=$(grep "^ipv6" "$SNELL_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' ')

    local selected_user_name
    selected_user_name="$(proxy_user_select_name_for_protocol_action "选择用户名" "any" "$conf_file_for_port")"
    [[ -z "$selected_user_name" ]] && return
    [[ "$selected_user_name" == "__none__" ]] && { yellow "请先添加用户名"; return; }
    [[ "$selected_user_name" == "__invalid__" ]] && { red "输入无效"; return; }
    selected_user_name="$(normalize_proxy_user_name "$selected_user_name")"

    if [[ "$has_conf" == "yes" ]]; then
        yellow "🔔 提示: snell-v5 当前为单实例模式；再次添加不会新建第 2 个节点，而是覆盖现有 snell-v5。若需继续，请先删除现有 snell-v5。"
        [[ -z "$current_port" ]] && current_port="14443"
    else
        current_port="$(gen_preferred_inbound_port "snell" "$conf_file_for_port")"
        [[ -z "$current_port" ]] && current_port="$random_min_port"
    fi
    [[ -z "$current_udp" ]] && current_udp="true"
    [[ -z "$current_obfs" ]] && current_obfs="off"
    [[ -z "$current_ipv6" ]] && current_ipv6="false"

    if [[ "$has_conf" == "no" ]]; then
        yellow "当前未配置 snell-v5，将按你的输入创建配置。"
    fi

    local new_port new_psk
    while :; do
        local input_port
        if [[ "$has_conf" == "yes" ]]; then
            if ! read_prompt input_port "监听端口 [当前: $current_port]: "; then
                input_port=""
            fi
            new_port=${input_port:-$current_port}
        else
            if ! read_prompt input_port "监听端口 [默认优先常用端口/随机 ${random_min_port}-${random_max_port}: $current_port]: "; then
                input_port=""
            fi
            new_port=${input_port:-$current_port}
        fi

        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
            red "错误: 端口无效，请输入 1-65535。"
            continue
        fi

        if [[ "$has_conf" == "yes" && "$new_port" == "$current_port" ]]; then
            break
        fi

        if [[ -n "$conf_file_for_port" && -f "$conf_file_for_port" ]]; then
            if jq -e --argjson p "$new_port" '.inbounds[]? | select((.listen_port // 0) == $p)' "$conf_file_for_port" >/dev/null 2>&1; then
                red "错误: 端口 ${new_port} 已被 sing-box 入站占用。"
                continue
            fi
        fi

        local protocol_conflicts
        protocol_conflicts="$(list_non_inbound_protocol_port_conflicts "$new_port" "$conf_file_for_port")"
        if [[ -n "${protocol_conflicts// }" ]]; then
            red "错误: 端口 ${new_port} 已被其他协议占用："
            while IFS= read -r line; do
                [[ -n "$line" ]] && echo "  - ${line}"
            done <<< "$protocol_conflicts"
            continue
        fi

        if declare -F check_port >/dev/null 2>&1; then
            if ! check_port "$new_port"; then
                red "错误: 端口 ${new_port} 已被占用。"
                continue
            fi
        elif ss -tuln 2>/dev/null | grep -q ":${new_port} "; then
            red "错误: 端口 ${new_port} 已被占用。"
            continue
        fi
        break
    done

    if [[ "$has_conf" == "yes" ]]; then
        if ! read_prompt new_psk "PSK 密钥 [当前: ${current_psk:-未设置}]: "; then
            new_psk=""
        fi
        if [[ -z "${new_psk:-}" ]]; then
            new_psk=${current_psk:-$(gen_rand_alnum 16)}
        fi
    else
        if ! read_prompt new_psk "PSK 密钥 [默认随机]: "; then
            new_psk=""
        fi
        new_psk=${new_psk:-$(gen_rand_alnum 16)}
    fi

    local cur_ipv6_yn="n"; [[ "$current_ipv6" == "true" ]] && cur_ipv6_yn="y"
    echo -e "\n\033[33m提示: 开启 IPv6 (:::) 通常可同时支持 IPv4 和 IPv6 访问。\033[0m"
    if ! read_prompt new_ipv6_yn "开启双栈? [y/n, 当前: $cur_ipv6_yn]: "; then
        new_ipv6_yn=""
    fi
    if [[ "${new_ipv6_yn:-$cur_ipv6_yn}" == "y" ]]; then
        new_ipv6="true"; new_listen=":::${new_port}"
    else
        new_ipv6="false"; new_listen="0.0.0.0:${new_port}"
    fi

    local cur_udp_yn="n"; [[ "$current_udp" == "true" ]] && cur_udp_yn="y"
    if ! read_prompt new_udp_yn "开启 UDP? [y/n, 当前: $cur_udp_yn]: "; then
        new_udp_yn=""
    fi
    if [[ "${new_udp_yn:-$cur_udp_yn}" == "y" ]]; then new_udp="true"; else new_udp="false"; fi

    echo "混淆模式: [1. off | 2. http | 3. tls]"
    local obfs_choice=""
    if ! read_prompt obfs_choice "选择 [当前: $current_obfs]: "; then
        obfs_choice=""
    fi
    local new_obfs=""
    case $obfs_choice in 1) new_obfs="off" ;; 2) new_obfs="http" ;; 3) new_obfs="tls" ;; *) new_obfs="$current_obfs" ;; esac

    cat > "$SNELL_CONF" <<EOF
[snell-server]
listen = ${new_listen}
psk = ${new_psk}
ipv6 = ${new_ipv6}
obfs = ${new_obfs}
udp = ${new_udp}
EOF
    protocol_install_finalize_snell_config() {
        local snell_key
        snell_key="$(proxy_user_key "snell" "snell-v5" "$new_psk")"
        if protocol_install_session_active; then
            protocol_install_session_queue_membership "$selected_user_name" "$snell_key" "" "0" "$conf_file_for_port" || true
        elif declare -F proxy_user_meta_apply_protocol_membership >/dev/null 2>&1; then
            proxy_user_meta_apply_protocol_membership "$selected_user_name" "$snell_key" "" >/dev/null 2>&1 || true
        else
            proxy_user_group_add "$selected_user_name" >/dev/null 2>&1 || true
            proxy_user_meta_set_name "$snell_key" "$selected_user_name" >/dev/null 2>&1 || true
        fi

        if [[ "$has_conf" == "yes" && -n "$current_port" && "$new_port" != "$current_port" ]]; then
            local old_target_services
            old_target_services="$(shadowtls_service_names_by_backend_target_port "snell" "$current_port" "$conf_file_for_port" 2>/dev/null || true)"
            if [[ -n "${old_target_services// }" ]]; then
                local stale_count
                stale_count="$(printf '%s\n' "$old_target_services" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
                disable_shadowtls_services_from_list "$old_target_services" || true
                yellow "已下线 ${stale_count} 个仍指向旧端口 ${current_port} 的 snell shadow-tls-v3 绑定。"
            fi
        fi
    }

    if declare -F proxy_run_with_spinner_compact >/dev/null 2>&1 && proxy_prompt_tty_available 2>/dev/null; then
        proxy_run_with_spinner_compact "正在写入 snell 配置..." protocol_install_finalize_snell_config || {
            red "snell-v5 配置写入失败"
            return
        }
    else
        protocol_install_finalize_snell_config || {
            red "snell-v5 配置写入失败"
            return
        }
    fi

    local st_enable=""
    if ! read_prompt st_enable "是否配置 shadow-tls-v3 保护此端口? [y/n]: "; then
        st_enable=""
    fi
    if [[ "${st_enable,,}" == "y" ]]; then
        configure_shadowtls_for_target "$new_port" "snell" || true
    fi
    if protocol_install_session_active; then
        protocol_install_apply_snell_change
        green "snell-v5 配置已写入。"
        yellow "退出“安装协议”菜单后将统一重启 snell-v5。"
    else
        protocol_install_apply_snell_change
    fi
}
