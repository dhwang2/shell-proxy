# Share display operations for shell-proxy management.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

SHARE_META_OPS_FILE="${SHARE_META_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/share_meta_ops.sh}"
if [[ -f "$SHARE_META_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARE_META_OPS_FILE"
fi

SUBSCRIPTION_OPS_FILE="${SUBSCRIPTION_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/subscription_ops.sh}"
SHARE_MENU_FULL_LOADED="${SHARE_MENU_FULL_LOADED:-0}"
SUBSCRIPTION_SHARE_VIEW_CACHE_TTL_SECONDS="${SUBSCRIPTION_SHARE_VIEW_CACHE_TTL_SECONDS:-2}"

subscription_share_ensure_full_support_loaded() {
    (( SHARE_MENU_FULL_LOADED == 1 )) && return 0
    if [[ "${PROXY_SHARE_MENU_BUNDLE_LOADED:-0}" == "1" ]]; then
        SHARE_MENU_FULL_LOADED=1
        return 0
    fi

    local -a module_files=(
        "modules/subscription/subscription_ops.sh"
    )

    if declare -F load_module_group >/dev/null 2>&1; then
        load_module_group "${module_files[@]}" || return 1
    else
        local module_file=""
        for module_file in "${module_files[@]}"; do
            [[ -f "${MODULE_ROOT}/${module_file}" ]] || return 1
            # shellcheck disable=SC1090
            source "${MODULE_ROOT}/${module_file}" || return 1
        done
    fi

    SHARE_MENU_FULL_LOADED=1
}

subscription_share_render_cache_dir() {
    printf '%s\n' "${CACHE_DIR}/subscription"
}

subscription_share_render_fp_file() {
    printf '%s\n' "$(subscription_share_render_cache_dir)/.render-cache.fp"
}

subscription_share_cached_fingerprint_value() {
    local file="${1:-}"
    [[ -f "$file" ]] || return 0
    tr -d '\r\n' <"$file" 2>/dev/null || true
}

render_links_pretty() {
    local text="${1:-}"
    printf '%s' "$text" | sed '/^[[:space:]]*$/d' | awk 'NR>1 {print ""} {print}'
}

surge_link_group_key() {
    local line="${1:-}"
    local name
    name="$(printf '%s' "$line" | awk -F'=' '{print $1}' | sed 's/[[:space:]]*$//')"
    name="${name%-v4}"
    name="${name%-v6}"
    name="${name%-domain}"
    printf '%s' "$name"
}

render_surge_links_compact() {
    local text="${1:-}" indent="${2:-}"
    local line key prev_key=""
    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        key="$(surge_link_group_key "$line")"
        if [[ -n "$prev_key" && "$key" != "$prev_key" ]]; then
            echo
        fi
        echo "${indent}${line}"
        prev_key="$key"
    done <<< "$text"
}

print_share_section_title() {
    local title="${1:-}" color="${2:-36;1}" indent="${3:-}"
    echo -e "${indent}\033[${color}m${title}\033[0m"
    print_share_divider "$indent"
}

print_share_divider() {
    local indent="${1:-}"
    echo "${indent}--------------------------------------------------------------------"
}

share_user_color_code() {
    local user_name="${1:-}"
    local -a palette=("33;1" "36;1" "32;1" "35;1" "34;1" "31;1")
    local checksum=0 color_index=0
    [[ -n "$user_name" ]] || { printf '%s' "${palette[0]}"; return 0; }
    checksum="$(printf '%s' "$user_name" | cksum | awk '{print $1}')"
    color_index=$(( checksum % ${#palette[@]} ))
    printf '%s' "${palette[$color_index]}"
}

print_share_user_title() {
    local user_name="${1:-}" indent="${2:-}"
    [[ -n "$user_name" ]] || return 0
    local color_code
    color_code="$(share_user_color_code "$user_name")"
    echo -e "${indent}\033[${color_code}m${user_name}\033[0m"
}

render_shadowtls_join_codes() {
    local host="${1:-}" conf_file="${2:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    is_shadowtls_configured || return 0
    subscription_share_ensure_full_support_loaded || return 1

    local line st_service st_port st_target st_backend st_sni st_pass idx=1 shown=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        IFS='|' read -r st_service st_port st_target st_backend st_sni st_pass <<< "$line"
        [[ -n "$st_port" && -n "$st_pass" && -n "$st_sni" ]] || continue
        local join_code
        join_code="$(build_shadowtls_join_code "$host" "$st_port" "$st_pass" "$st_sni")"
        echo "JOIN-${idx}: ${join_code}"
        ((idx++))
        ((shown++))
    done < <(shadowtls_binding_lines "$conf_file")

    if (( shown == 0 )); then
        yellow "当前未检测到可生成 JOIN 码的 ShadowTLS 绑定。"
    fi
}

subscription_share_view_text_file() {
    printf '%s\n' "$(subscription_share_render_cache_dir)/.share-view.txt"
}

subscription_share_view_fp_file() {
    printf '%s\n' "$(subscription_share_render_cache_dir)/.share-view.fp"
}

subscription_share_view_code_fingerprint() {
    local self_fp
    self_fp="$(calc_file_meta_signature "${BASH_SOURCE[0]}" 2>/dev/null || echo "0:0")"
    printf '%s\n' "$self_fp" | proxy_cksum_signature
}

subscription_share_view_state_fingerprint() {
    local host="${1:-}" conf_file="${2:-}" render_fp_override="${3:-}"
    local render_fp code_fp
    render_fp="$render_fp_override"
    if [[ -z "$render_fp" ]]; then
        render_fp="$(subscription_share_cached_fingerprint_value "$(subscription_share_render_fp_file)")"
    fi
    if [[ -z "$render_fp" && -n "$host" ]]; then
        subscription_share_ensure_full_support_loaded || return 1
        render_fp="$(calc_subscription_render_fingerprint "$host" "$conf_file" 2>/dev/null || true)"
    fi
    [[ -n "$render_fp" ]] || render_fp="0:0"
    code_fp="$(subscription_share_view_code_fingerprint 2>/dev/null || echo "0:0")"
    printf '%s|%s|%s\n' \
        "$render_fp" "${SHOW_JOIN_CODE:-}" "$code_fp" \
        | proxy_cksum_signature
}

subscription_share_view_cache_is_fresh() {
    local host="${1:-}" conf_file="${2:-}" render_fp_override="${3:-}"
    local text_file fp_file cached_fp expected_fp
    text_file="$(subscription_share_view_text_file)"
    fp_file="$(subscription_share_view_fp_file)"
    [[ -f "$text_file" && -f "$fp_file" ]] || return 1
    cached_fp="$(tr -d '[:space:]' <"$fp_file" 2>/dev/null || true)"
    [[ -n "$cached_fp" ]] || return 1
    expected_fp="$(subscription_share_view_state_fingerprint "$host" "$conf_file" "$render_fp_override" 2>/dev/null || true)"
    [[ -n "$expected_fp" ]] || return 1
    [[ "$cached_fp" == "$expected_fp" ]]
}

_subscription_share_render_body() {
    local host="${1:-}" conf_file="${2:-}"
    local -n _users_ref="${3:-}" _sing_ref="${4:-}" _surge_ref="${5:-}"

    local user_name idx last_idx

    print_share_section_title "[ 协议链接 ]" "36;1"
    if (( ${#_users_ref[@]} == 0 )); then
        yellow "当前无可用用户名或协议链接"
    else
        local user_sing_links
        last_idx=$(( ${#_users_ref[@]} - 1 ))
        for idx in "${!_users_ref[@]}"; do
            user_name="${_users_ref[$idx]}"
            print_share_user_title "$user_name"
            user_sing_links="${_sing_ref[$user_name]:-}"
            if [[ -n "${user_sing_links// }" ]]; then
                render_links_pretty "$user_sing_links"
            else
                yellow "  当前无可用协议链接"
            fi
            if (( idx < last_idx )); then
                print_share_divider
            fi
        done
    fi
    echo
    print_share_section_title "[ Surge 链接 ]" "35;1"
    if (( ${#_users_ref[@]} == 0 )); then
        yellow "当前无可用 Surge 协议链接"
    else
        local user_surge_links
        last_idx=$(( ${#_users_ref[@]} - 1 ))
        for idx in "${!_users_ref[@]}"; do
            user_name="${_users_ref[$idx]}"
            print_share_user_title "$user_name"
            user_surge_links="${_surge_ref[$user_name]:-}"
            if [[ -n "${user_surge_links// }" ]]; then
                render_surge_links_compact "$user_surge_links" "  "
            else
                yellow "  当前无可用 Surge 协议链接"
            fi
            if (( idx < last_idx )); then
                print_share_divider
            else
                echo
            fi
        done
    fi
    if ! surge_link_verbose_params_enabled; then
        printf '\033[90m  %s\033[0m\n' "Surge 链接已关闭可选参数显式输出（SURGE_LINK_VERBOSE_PARAMS=off）。"
    fi

    if shadowtls_join_code_enabled; then
        echo
        print_share_section_title "[ ShadowTLS JOIN 码 ]" "33;1"
        render_shadowtls_join_codes "$host" "$conf_file"
        echo
    fi
}

subscription_share_render_to_file() {
    local output_file="${1:-}" host="${2:-}" conf_file="${3:-}"
    [[ -n "$output_file" ]] || return 1
    subscription_share_ensure_full_support_loaded || return 1

    local -a share_users=()
    local -A sing_links_by_user=() surge_links_by_user=()
    mapfile -t share_users < <(sed '/^[[:space:]]*$/d' "$(subscription_render_cache_user_list_file)" 2>/dev/null || true)
    subscription_render_cache_load_user_map "$(subscription_render_cache_user_sing_map_file)" "sing_links_by_user" >/dev/null 2>&1 || true
    subscription_render_cache_load_user_map "$(subscription_render_cache_user_surge_map_file)" "surge_links_by_user" >/dev/null 2>&1 || true

    _subscription_share_render_body "$host" "$conf_file" \
        share_users sing_links_by_user surge_links_by_user >"$output_file"
}

subscription_share_view_cache_rebuild() {
    local host="${1:-}" conf_file="${2:-}" render_fp_override="${3:-}" state_fp tmp_file
    tmp_file="$(mktemp 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || tmp_file="/tmp/proxy-share-view.$$.$RANDOM"
    subscription_share_render_to_file "$tmp_file" "$host" "$conf_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    state_fp="$(subscription_share_view_state_fingerprint "$host" "$conf_file" "$render_fp_override" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"
    mkdir -p "$(dirname "$(subscription_share_view_text_file)")" >/dev/null 2>&1 || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    mv -f "$tmp_file" "$(subscription_share_view_text_file)" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    proxy_cache_write_atomic "$(subscription_share_view_fp_file)" "$state_fp" || {
        return 1
    }
}

subscription_share_render_payload_to_file() {
    local output_file="${1:-}" host="${2:-}" conf_file="${3:-}"
    local active_users_name="${4:-}" sing_map_name="${5:-}" surge_map_name="${6:-}"
    [[ -n "$output_file" && -n "$active_users_name" && -n "$sing_map_name" && -n "$surge_map_name" ]] || return 1
    subscription_share_ensure_full_support_loaded || return 1

    _subscription_share_render_body "$host" "$conf_file" \
        "$active_users_name" "$sing_map_name" "$surge_map_name" >"$output_file"
}

subscription_share_view_cache_refresh_from_payload() {
    local host="${1:-}" conf_file="${2:-}" render_fp_override="${3:-}"
    local active_users_name="${4:-}" sing_map_name="${5:-}" surge_map_name="${6:-}"
    [[ -n "$host" && -n "$active_users_name" && -n "$sing_map_name" && -n "$surge_map_name" ]] || return 1
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if subscription_share_view_cache_is_fresh "$host" "$conf_file" "$render_fp_override"; then
        return 0
    fi

    local tmp_file state_fp
    tmp_file="$(mktemp 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || tmp_file="/tmp/proxy-share-view.$$.$RANDOM"
    subscription_share_render_payload_to_file "$tmp_file" "$host" "$conf_file" \
        "$active_users_name" "$sing_map_name" "$surge_map_name" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    state_fp="$(subscription_share_view_state_fingerprint "$host" "$conf_file" "$render_fp_override" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"
    mkdir -p "$(dirname "$(subscription_share_view_text_file)")" >/dev/null 2>&1 || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    mv -f "$tmp_file" "$(subscription_share_view_text_file)" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    proxy_cache_write_atomic "$(subscription_share_view_fp_file)" "$state_fp" || return 1
}

subscription_share_view_cache_refresh_for_render() {
    local host="${1:-}" conf_file="${2:-}" render_fp_override="${3:-}"
    [[ -n "$host" ]] || return 1
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    if subscription_share_view_cache_is_fresh "$host" "$conf_file" "$render_fp_override"; then
        return 0
    fi
    subscription_share_ensure_full_support_loaded || return 1
    subscription_share_view_cache_rebuild "$host" "$conf_file" "$render_fp_override"
}

subscription_share_empty_render_fp() {
    printf '%s\n' "empty-no-protocols"
}

subscription_share_can_fast_render_empty_state() {
    local conf_file="${1:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file 2>/dev/null || true)"
    is_snell_configured && return 1
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    jq -e '
        any((.inbounds // [])[]?;
            ((.type // "") | ascii_downcase) as $type
            | ($type == "vless"
                or $type == "tuic"
                or $type == "trojan"
                or $type == "anytls"
                or $type == "shadowsocks"
                or $type == "ss"))
    ' "$conf_file" >/dev/null 2>&1 && return 1
    return 0
}

subscription_share_render_empty_view_to_file() {
    local output_file="${1:-}"
    [[ -n "$output_file" ]] || return 1
    {
        print_share_section_title "[ 协议链接 ]" "36;1"
        yellow "当前无可用用户名或协议链接"
        echo
        print_share_section_title "[ Surge 链接 ]" "35;1"
        yellow "当前无可用 Surge 协议链接"
    } >"$output_file"
}

subscription_share_empty_view_cache_rebuild() {
    local conf_file="${1:-}" tmp_file state_fp
    tmp_file="$(mktemp 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || tmp_file="/tmp/proxy-share-empty.$$.$RANDOM"
    subscription_share_render_empty_view_to_file "$tmp_file" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    state_fp="$(subscription_share_view_state_fingerprint "" "$conf_file" "$(subscription_share_empty_render_fp)" 2>/dev/null || true)"
    [[ -n "$state_fp" ]] || state_fp="0:0"
    mkdir -p "$(dirname "$(subscription_share_view_text_file)")" >/dev/null 2>&1 || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    mv -f "$tmp_file" "$(subscription_share_view_text_file)" || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    proxy_cache_write_atomic "$(subscription_share_view_fp_file)" "$state_fp" || return 1
}

manage_share() {
    ui_clear
    proxy_menu_header "订阅管理"

    local share_host="" conf_file cached_render_fp empty_render_fp
    conf_file="$(get_conf_file)"
    cached_render_fp="$(subscription_share_cached_fingerprint_value "$(subscription_share_render_fp_file)")"
    empty_render_fp="$(subscription_share_empty_render_fp)"

    if subscription_share_can_fast_render_empty_state "$conf_file"; then
        if ! subscription_share_view_cache_is_fresh "" "$conf_file" "$empty_render_fp"; then
            subscription_share_empty_view_cache_rebuild "$conf_file" || return
        fi
        if [[ -f "$(subscription_share_view_text_file)" ]]; then
            cat "$(subscription_share_view_text_file)"
        fi
        return
    fi

    share_host=$(detect_share_host)

    # Compute the live render fingerprint to detect stale cached_render_fp.
    # cached_render_fp reflects the last time the render cache was built; if the
    # underlying data (conf, user-meta) changed since then, cached_render_fp is
    # outdated.  Passing a stale value as render_fp_override to
    # subscription_share_view_cache_is_fresh causes the text-view freshness hash
    # to match its stored value even though the content is outdated, resulting in
    # the subscription view showing only the first user's links.  Using the live
    # fingerprint as override ensures the freshness check reflects actual state.
    local live_render_fp=""
    live_render_fp="$(calc_subscription_render_fingerprint "$share_host" "$conf_file" 2>/dev/null || true)"

    if ! subscription_share_view_cache_is_fresh "$share_host" "$conf_file" "${live_render_fp:-$cached_render_fp}"; then
        subscription_share_ensure_full_support_loaded || return
        sync_singbox_loaded_fingerprint_passive
        proxy_run_with_spinner "正在整理订阅视图..." \
            ensure_subscription_render_cache "_" "$share_host" "$conf_file" || return
    fi
    if [[ -f "$(subscription_share_view_text_file)" ]]; then
        cat "$(subscription_share_view_text_file)"
    else
        local render_file=""
        render_file="$(mktemp 2>/dev/null || true)"
        if [[ -z "$render_file" ]]; then
            render_file="/tmp/proxy-share-render.$$"
            : > "$render_file"
        fi
        subscription_share_ensure_full_support_loaded || { rm -f "$render_file" 2>/dev/null || true; return; }
        proxy_run_with_spinner "正在生成订阅视图..." \
            subscription_share_render_to_file "$render_file" "$share_host" "$conf_file" || {
            rm -f "$render_file" 2>/dev/null || true
            return
        }
        cat "$render_file"
        rm -f "$render_file" 2>/dev/null || true
    fi
}

# --- share link encoding, Reality key, JOIN-code (merged from share_link_ops.sh) ---

base64_no_wrap() {
    local base64_help
    base64_help=$(base64 --help 2>/dev/null || true)
    if grep -q -- '-w' <<<"$base64_help"; then
        base64 -w 0
    else
        base64 | tr -d '\n'
    fi
}

normalize_reality_key() {
    local key="${1:-}"
    key="${key//+/-}"
    key="${key//\//_}"
    key="${key//=}"
    echo "$key"
}

is_valid_reality_key() {
    local key="${1:-}"
    [[ "$key" =~ ^[A-Za-z0-9_-]{43}$ ]]
}

derive_reality_public_key_openssl() {
    local private_key="${1:-}"
    [[ -z "$private_key" ]] && return 1
    command -v openssl >/dev/null 2>&1 || return 1
    command -v xxd >/dev/null 2>&1 || return 1

    local b64="${private_key//-/+}"
    b64="${b64//_/\/}"
    local mod=$(( ${#b64} % 4 ))
    case "$mod" in
        0) ;;
        2) b64="${b64}==" ;;
        3) b64="${b64}=" ;;
        *) return 1 ;;
    esac

    local tmp_raw tmp_priv_der tmp_pub_der
    tmp_raw="$(mktemp)"
    tmp_priv_der="$(mktemp)"
    tmp_pub_der="$(mktemp)"

    if ! printf "%s" "$b64" | base64 -d >"$tmp_raw" 2>/dev/null; then
        if ! printf "%s" "$b64" | base64 --decode >"$tmp_raw" 2>/dev/null; then
            if ! printf "%s" "$b64" | base64 -D >"$tmp_raw" 2>/dev/null; then
                if ! printf "%s" "$b64" | openssl base64 -d -A >"$tmp_raw" 2>/dev/null; then
                    rm -f "$tmp_raw" "$tmp_priv_der" "$tmp_pub_der"
                    return 1
                fi
            fi
        fi
    fi

    local raw_len
    raw_len="$(wc -c <"$tmp_raw" | tr -d '[:space:]')"
    if [[ "$raw_len" != "32" ]]; then
        rm -f "$tmp_raw" "$tmp_priv_der" "$tmp_pub_der"
        return 1
    fi

    local priv_hex
    priv_hex="$(xxd -p -c 256 "$tmp_raw" | tr -d '\n')"
    printf "302e020100300506032b656e04220420%s" "$priv_hex" | xxd -r -p >"$tmp_priv_der" 2>/dev/null || {
        rm -f "$tmp_raw" "$tmp_priv_der" "$tmp_pub_der"
        return 1
    }

    openssl pkey -inform DER -in "$tmp_priv_der" -pubout -outform DER >"$tmp_pub_der" 2>/dev/null || {
        rm -f "$tmp_raw" "$tmp_priv_der" "$tmp_pub_der"
        return 1
    }

    local pub_der_hex pub_raw_hex pub_key
    pub_der_hex="$(xxd -p -c 256 "$tmp_pub_der" | tr -d '\n')"
    if [[ "${#pub_der_hex}" -lt 64 ]]; then
        rm -f "$tmp_raw" "$tmp_priv_der" "$tmp_pub_der"
        return 1
    fi

    pub_raw_hex="${pub_der_hex: -64}"
    pub_key="$(printf "%s" "$pub_raw_hex" | xxd -r -p | base64_no_wrap | tr '+/' '-_' | tr -d '=')"

    rm -f "$tmp_raw" "$tmp_priv_der" "$tmp_pub_der"
    is_valid_reality_key "$pub_key" || return 1
    echo "$pub_key"
}

generate_reality_keypair() {
    local keypair priv pub

    if [[ -x "$BIN_FILE" ]]; then
        keypair="$("$BIN_FILE" generate reality-keypair 2>/dev/null || true)"
        priv="$(echo "$keypair" | awk '/PrivateKey/{print $2; exit}')"
        pub="$(echo "$keypair" | awk '/PublicKey/{print $2; exit}')"
        priv="$(normalize_reality_key "$priv")"
        pub="$(normalize_reality_key "$pub")"
        if is_valid_reality_key "$priv" && is_valid_reality_key "$pub"; then
            echo "${priv}|${pub}"
            return 0
        fi
    fi

    if command -v openssl >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1; then
        local tmp_priv_der priv_hex
        tmp_priv_der="$(mktemp)"
        if openssl genpkey -algorithm X25519 -outform DER >"$tmp_priv_der" 2>/dev/null; then
            priv_hex="$(xxd -p -c 256 "$tmp_priv_der" | tr -d '\n')"
            if [[ "${#priv_hex}" -ge 64 ]]; then
                priv_hex="${priv_hex: -64}"
                priv="$(printf "%s" "$priv_hex" | xxd -r -p | base64_no_wrap | tr '+/' '-_' | tr -d '=')"
                pub="$(derive_reality_public_key_openssl "$priv" || true)"
                if is_valid_reality_key "$priv" && is_valid_reality_key "$pub"; then
                    rm -f "$tmp_priv_der"
                    echo "${priv}|${pub}"
                    return 0
                fi
            fi
        fi
        rm -f "$tmp_priv_der"
    fi

    return 1
}

resolve_reality_public_key() {
    local private_key="$1"
    [[ -z "$private_key" ]] && return 0

    private_key="$(normalize_reality_key "$private_key")"
    if [[ -n "${REALITY_PUBLIC_KEY_CACHE[$private_key]+_}" ]]; then
        printf '%s' "${REALITY_PUBLIC_KEY_CACHE[$private_key]}"
        return 0
    fi

    local pub=""
    if [[ -x "$BIN_FILE" ]]; then
        local flag out pri1 pub1 out2 pub2
        for flag in "--private-key" "-private-key" "--private" "-private"; do
            out="$("$BIN_FILE" generate reality-keypair "$flag" "$private_key" 2>/dev/null || true)"
            pri1="$(echo "$out" | awk '/PrivateKey/{print $2; exit}')"
            pub1="$(echo "$out" | awk '/PublicKey/{print $2; exit}')"
            pri1="$(normalize_reality_key "$pri1")"
            pub1="$(normalize_reality_key "$pub1")"

            if is_valid_reality_key "$pub1"; then
                if [[ "$pri1" == "$private_key" ]]; then
                    pub="$pub1"
                    break
                fi
                if [[ -z "$pri1" ]]; then
                    out2="$("$BIN_FILE" generate reality-keypair "$flag" "$private_key" 2>/dev/null || true)"
                    pub2="$(echo "$out2" | awk '/PublicKey/{print $2; exit}')"
                    pub2="$(normalize_reality_key "$pub2")"
                    if is_valid_reality_key "$pub2" && [[ "$pub1" == "$pub2" ]]; then
                        pub="$pub1"
                        break
                    fi
                fi
            fi
        done
    fi

    if ! is_valid_reality_key "$pub"; then
        pub="$(derive_reality_public_key_openssl "$private_key" || true)"
        pub="$(normalize_reality_key "$pub")"
    fi

    if is_valid_reality_key "$pub"; then
        REALITY_PUBLIC_KEY_CACHE["$private_key"]="$pub"
        echo "$pub"
    else
        REALITY_PUBLIC_KEY_CACHE["$private_key"]=""
    fi
}

build_shadowtls_join_code() {
    local host="${1:-}" port="${2:-}" password="${3:-}" sni="${4:-}"
    jq -nc \
        --arg server "$host" \
        --argjson port "${port:-0}" \
        --arg password "$password" \
        --arg sni "$sni" \
        '{server:$server, port:$port, password:$password, sni:$sni, version:3}' \
        | base64_no_wrap
}
