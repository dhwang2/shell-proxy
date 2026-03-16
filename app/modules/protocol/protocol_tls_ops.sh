# Protocol TLS domain, certificate, and decoy SNI operations.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

SHARE_META_OPS_FILE="${SHARE_META_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../subscription/share_meta_ops.sh}"
if [[ -f "$SHARE_META_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARE_META_OPS_FILE"
fi

PROTOCOL_RUNTIME_OPS_FILE="${PROTOCOL_RUNTIME_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocol_runtime_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_OPS_FILE"
fi
if ! declare -F install_caddy >/dev/null 2>&1; then
    PROTOCOL_RUNTIME_OPS_FILE="${WORK_DIR:-/etc/shell-proxy}/modules/protocol/protocol_runtime_ops.sh"
    if [[ -f "$PROTOCOL_RUNTIME_OPS_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$PROTOCOL_RUNTIME_OPS_FILE"
    fi
fi

SYSTEMD_OPS_FILE="${SYSTEMD_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/systemd_ops.sh}"
if [[ -f "$SYSTEMD_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SYSTEMD_OPS_FILE"
fi

TLS_PUBLIC_IP_CACHE_TTL="${TLS_PUBLIC_IP_CACHE_TTL:-120}"
TLS_DOMAIN_DNS_CACHE_TTL="${TLS_DOMAIN_DNS_CACHE_TTL:-60}"

tls_cache_dir() {
    echo "${CACHE_DIR}/tls"
}

tls_domain_cache_key() {
    local domain="${1:-}"
    printf '%s' "$domain" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/_/g'
}

tls_public_ip_cache_file() {
    local family="${1:-v4}"
    echo "$(tls_cache_dir)/public-ip-${family}"
}

tls_domain_dns_cache_file() {
    local family="${1:-a}"
    local domain="${2:-}"
    echo "$(tls_cache_dir)/dns-${family}-$(tls_domain_cache_key "$domain")"
}

tls_cache_file_is_fresh() {
    local cache_file="$1"
    local ttl="${2:-0}"
    local now ts age
    [[ -f "$cache_file" ]] || return 1
    (( ttl > 0 )) || return 0
    now="$(date +%s)"
    ts="$(proxy_file_mtime_epoch "$cache_file" 2>/dev/null || echo 0)"
    [[ "$ts" =~ ^[0-9]+$ ]] || return 1
    age=$(( now - ts ))
    (( age <= ttl ))
}

tls_cache_read_multiline() {
    local cache_file="$1"
    local ttl="${2:-0}"
    tls_cache_file_is_fresh "$cache_file" "$ttl" || return 1
    cat "$cache_file" 2>/dev/null
}

tls_cache_write_multiline() {
    local cache_file="$1"
    shift
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null || return 1
    printf '%s\n' "$@" > "$cache_file" 2>/dev/null
}

pick_random_value() {
    local -a values=("$@")
    local count=${#values[@]}
    (( count > 0 )) || return 1

    local idx=0
    if command -v shuf >/dev/null 2>&1; then
        idx="$(shuf -i 0-$((count - 1)) -n 1 2>/dev/null || echo 0)"
    else
        idx=$((RANDOM % count))
    fi
    echo "${values[$idx]}"
}

shadowtls_domain_used() {
    local domain="${1:-}"
    [[ -n "$domain" && -f "$SHADOWTLS_SNI_USED_FILE" ]] || return 1
    grep -Fxqi "$domain" "$SHADOWTLS_SNI_USED_FILE"
}

remember_shadowtls_sni_domain() {
    local domain="${1:-}"
    [[ -n "$domain" ]] || return 1

    mkdir -p "$(dirname "$SHADOWTLS_SNI_USED_FILE")"
    touch "$SHADOWTLS_SNI_USED_FILE"
    if ! shadowtls_domain_used "$domain"; then
        printf '%s\n' "$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')" >> "$SHADOWTLS_SNI_USED_FILE"
    fi
}

pick_decoy_sni_domain() {
    local -a apple_pool=(
        "books.apple.com"
        "store.apple.com"
        "developer.apple.com"
        "support.apple.com"
        "music.apple.com"
        "tv.apple.com"
        "apps.apple.com"
        "www.apple.com"
    )
    local -a microsoft_pool=(
        "learn.microsoft.com"
        "support.microsoft.com"
        "account.microsoft.com"
        "login.microsoftonline.com"
        "www.microsoft.com"
        "www.office.com"
        "www.bing.com"
    )
    local -a fallback_pool=(
        "www.cloudflare.com"
        "store.steampowered.com"
        "www.paypal.com"
    )

    local -a unused_apple=()
    local -a unused_microsoft=()
    local -a unused_fallback=()
    local domain
    for domain in "${apple_pool[@]}"; do
        shadowtls_domain_used "$domain" || unused_apple+=("$domain")
    done
    for domain in "${microsoft_pool[@]}"; do
        shadowtls_domain_used "$domain" || unused_microsoft+=("$domain")
    done
    for domain in "${fallback_pool[@]}"; do
        shadowtls_domain_used "$domain" || unused_fallback+=("$domain")
    done

    if ((${#unused_apple[@]} > 0)); then
        pick_random_value "${unused_apple[@]}"
        return 0
    fi
    if ((${#unused_microsoft[@]} > 0)); then
        pick_random_value "${unused_microsoft[@]}"
        return 0
    fi
    if ((${#unused_fallback[@]} > 0)); then
        pick_random_value "${unused_fallback[@]}"
        return 0
    fi

    pick_random_value "${apple_pool[@]}" "${microsoft_pool[@]}" "${fallback_pool[@]}"
}

is_valid_domain_name() {
    local value="${1:-}"
    [[ -n "$value" ]] || return 1
    [[ "$value" =~ : ]] && return 1
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 1
    [[ "$value" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "$value" == *.* ]] || return 1
    [[ "$value" != .* && "$value" != *. ]] || return 1
    return 0
}

resolve_tls_server_domain_default() {
    local domain=""

    if [[ -f "${WORK_DIR}/.domain" ]]; then
        domain="$(cat "${WORK_DIR}/.domain" 2>/dev/null | tr -d '[:space:]')"
        if is_valid_domain_name "$domain"; then
            echo "$domain"
            return 0
        fi
    fi

    if [[ -d "${WORK_DIR}/caddy/certificates" ]]; then
        local cert_domain
        cert_domain="$(find "${WORK_DIR}/caddy/certificates" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | head -n 1 | xargs -n1 basename 2>/dev/null | tr -d '[:space:]')"
        if is_valid_domain_name "$cert_domain"; then
            echo "$cert_domain"
            return 0
        fi
    fi

    domain="$(detect_share_host 2>/dev/null | tr -d '[:space:]')"
    if is_valid_domain_name "$domain"; then
        echo "$domain"
        return 0
    fi

    echo ""
    return 1
}

resolve_caddy_tls_cert_pair() {
    local domain="${1:-}"
    local cert_file key_file
    [[ -n "$domain" ]] || return 1
    [[ -d "${WORK_DIR}/caddy/certificates" ]] || return 1

    while IFS= read -r cert_file; do
        [[ -n "$cert_file" ]] || continue
        key_file="${cert_file%.crt}.key"
        if [[ -f "$cert_file" && -f "$key_file" ]]; then
            printf '%s|%s\n' "$cert_file" "$key_file"
            return 0
        fi
    done < <(find "${WORK_DIR}/caddy/certificates" -maxdepth 4 -type f -path "*/${domain}/${domain}.crt" 2>/dev/null | sort)

    return 1
}

resolve_domain_a_records_for_tls() {
    local domain="${1:-}"
    local cache_file="" cached=""
    [[ -n "$domain" ]] || return 0
    cache_file="$(tls_domain_dns_cache_file a "$domain")"
    cached="$(tls_cache_read_multiline "$cache_file" "$TLS_DOMAIN_DNS_CACHE_TTL" 2>/dev/null || true)"
    if [[ -n "$cached" ]]; then
        [[ "$cached" == "__empty__" ]] || printf '%s\n' "$cached"
        return 0
    fi
    if command -v getent >/dev/null 2>&1; then
        cached="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sed '/^[[:space:]]*$/d' | sort -u || true)"
        if [[ -n "$cached" ]]; then
            tls_cache_write_multiline "$cache_file" "$cached" >/dev/null 2>&1 || true
            printf '%s\n' "$cached"
        else
            tls_cache_write_multiline "$cache_file" "__empty__" >/dev/null 2>&1 || true
        fi
        return 0
    fi
    if command -v dig >/dev/null 2>&1; then
        cached="$(dig +short A "$domain" 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u || true)"
        if [[ -n "$cached" ]]; then
            tls_cache_write_multiline "$cache_file" "$cached" >/dev/null 2>&1 || true
            printf '%s\n' "$cached"
        else
            tls_cache_write_multiline "$cache_file" "__empty__" >/dev/null 2>&1 || true
        fi
    fi
}

resolve_domain_aaaa_records_for_tls() {
    local domain="${1:-}"
    local cache_file="" cached=""
    [[ -n "$domain" ]] || return 0
    cache_file="$(tls_domain_dns_cache_file aaaa "$domain")"
    cached="$(tls_cache_read_multiline "$cache_file" "$TLS_DOMAIN_DNS_CACHE_TTL" 2>/dev/null || true)"
    if [[ -n "$cached" ]]; then
        [[ "$cached" == "__empty__" ]] || printf '%s\n' "$cached"
        return 0
    fi
    if command -v getent >/dev/null 2>&1; then
        cached="$(getent ahostsv6 "$domain" 2>/dev/null | awk '{print $1}' | sed '/^[[:space:]]*$/d' | sort -u || true)"
        if [[ -n "$cached" ]]; then
            tls_cache_write_multiline "$cache_file" "$cached" >/dev/null 2>&1 || true
            printf '%s\n' "$cached"
        else
            tls_cache_write_multiline "$cache_file" "__empty__" >/dev/null 2>&1 || true
        fi
        return 0
    fi
    if command -v dig >/dev/null 2>&1; then
        cached="$(dig +short AAAA "$domain" 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u || true)"
        if [[ -n "$cached" ]]; then
            tls_cache_write_multiline "$cache_file" "$cached" >/dev/null 2>&1 || true
            printf '%s\n' "$cached"
        else
            tls_cache_write_multiline "$cache_file" "__empty__" >/dev/null 2>&1 || true
        fi
    fi
}

detect_local_public_ipv4_for_tls() {
    local ip=""
    ip="$(read_fresh_cached_value "$(tls_public_ip_cache_file v4)" "$TLS_PUBLIC_IP_CACHE_TTL" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
        [[ "$ip" == "__none__" ]] || printf '%s' "$ip"
        return 0
    fi
    ip="$(curl -4 -s --connect-timeout 2 --max-time 3 https://api.ipify.org 2>/dev/null || true)"
    [[ -n "$ip" ]] || ip="$(curl -4 -s --connect-timeout 2 --max-time 3 https://ipv4.icanhazip.com 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
    if [[ -n "$ip" ]]; then
        write_cached_value "$(tls_public_ip_cache_file v4)" "$ip" || true
        printf '%s' "$ip"
    else
        write_cached_value "$(tls_public_ip_cache_file v4)" "__none__" || true
    fi
}

detect_local_public_ipv6_for_tls() {
    local ip=""
    if [[ "$(detect_server_ip_stack 2>/dev/null || echo ipv4)" == "ipv4" ]]; then
        return 0
    fi
    if ! ip -6 route show default 2>/dev/null | grep -q .; then
        return 0
    fi
    ip="$(read_fresh_cached_value "$(tls_public_ip_cache_file v6)" "$TLS_PUBLIC_IP_CACHE_TTL" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
        [[ "$ip" == "__none__" ]] || printf '%s' "$ip"
        return 0
    fi
    ip="$(curl -6 -s --connect-timeout 2 --max-time 3 https://api64.ipify.org 2>/dev/null || true)"
    [[ -n "$ip" ]] || ip="$(curl -6 -s --connect-timeout 2 --max-time 3 https://icanhazip.com 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
    if [[ -n "$ip" ]]; then
        write_cached_value "$(tls_public_ip_cache_file v6)" "$ip" || true
        printf '%s' "$ip"
    else
        write_cached_value "$(tls_public_ip_cache_file v6)" "__none__" || true
    fi
}

domain_points_to_this_server_for_tls() {
    local domain="${1:-}"
    local local_v4="" local_v6="" has_record=1
    local -a domain_v4s=() domain_v6s=()
    [[ -n "$domain" ]] || return 0

    # ����ִ�� DNS �����͹��� IP ̽�⣬���ٴ��еȴ���
    local _tmp_v4s _tmp_v6s _tmp_lip4 _tmp_lip6
    _tmp_v4s="$(mktemp)" _tmp_v6s="$(mktemp)" _tmp_lip4="$(mktemp)" _tmp_lip6="$(mktemp)"
    local _pid_v4s _pid_v6s _pid_lip4 _pid_lip6

    (resolve_domain_a_records_for_tls "$domain" > "$_tmp_v4s" 2>/dev/null) & _pid_v4s=$!
    (resolve_domain_aaaa_records_for_tls "$domain" > "$_tmp_v6s" 2>/dev/null) & _pid_v6s=$!
    (detect_local_public_ipv4_for_tls > "$_tmp_lip4" 2>/dev/null) & _pid_lip4=$!
    (detect_local_public_ipv6_for_tls > "$_tmp_lip6" 2>/dev/null) & _pid_lip6=$!

    wait "$_pid_v4s" 2>/dev/null || true
    wait "$_pid_v6s" 2>/dev/null || true
    wait "$_pid_lip4" 2>/dev/null || true
    wait "$_pid_lip6" 2>/dev/null || true

    mapfile -t domain_v4s < "$_tmp_v4s"
    mapfile -t domain_v6s < "$_tmp_v6s"
    local_v4="$(cat "$_tmp_lip4" 2>/dev/null || true)"
    local_v6="$(cat "$_tmp_lip6" 2>/dev/null || true)"
    rm -f "$_tmp_v4s" "$_tmp_v6s" "$_tmp_lip4" "$_tmp_lip6" 2>/dev/null || true

    (( ${#domain_v4s[@]} > 0 || ${#domain_v6s[@]} > 0 )) || has_record=0
    (( has_record == 1 )) || return 1

    if [[ -z "$local_v4" && -z "$local_v6" ]]; then
        return 0
    fi

    local ip
    if [[ -n "$local_v4" ]]; then
        for ip in "${domain_v4s[@]}"; do
            [[ "$ip" == "$local_v4" ]] && return 0
        done
    fi
    if [[ -n "$local_v6" ]]; then
        for ip in "${domain_v6s[@]}"; do
            [[ "$ip" == "$local_v6" ]] && return 0
        done
    fi

    return 1
}

# --- certificate entry helpers (merged from protocol_certificate_ops.sh) ---

setup_caddy_sub() {
    local _unused_uuid="$1"
    local preferred_domain="${2:-}"
    local default_domain="" caddy_domain="" caddy_email=""

    if ! declare -F install_caddy >/dev/null 2>&1; then
        red "证书入口初始化失败：未加载 install_caddy 依赖。请先执行 11) 脚本更新。" >&2
        return 1
    fi
    install_caddy || return

    preferred_domain="$(printf '%s' "$preferred_domain" | tr -d '[:space:]')"
    if [[ -n "$preferred_domain" ]]; then
        default_domain="$preferred_domain"
    elif [[ -f "${WORK_DIR}/.domain" ]]; then
        default_domain="$(cat "${WORK_DIR}/.domain" | tr -d '[:space:]')"
    fi
    [[ -z "$default_domain" ]] && default_domain="yourdomain.com"

    if [[ -n "$preferred_domain" ]]; then
        caddy_domain="$preferred_domain"
    else
        echo >&2
        read -p "域名[默认: $default_domain]: " caddy_domain
        caddy_domain="${caddy_domain:-$default_domain}"
        caddy_domain="$(printf '%s' "$caddy_domain" | tr -d '[:space:]')"
    fi

    echo "$caddy_domain" > "${WORK_DIR}/.domain"

    if [[ "$caddy_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        yellow "警告: 输入的是 IP，caddy 将无法申请证书 (https 需要域名)。" >&2
    fi
    if ! domain_points_to_this_server_for_tls "$caddy_domain"; then
        red "证书申请前检查失败：域名当前未解析到本机。请先更新 A/AAAA 记录，再重试。" >&2
        return 1
    fi

    local default_email="user@example.com"
    read -p "邮箱[默认: $default_email]: " caddy_email
    caddy_email=${caddy_email:-"$default_email"}

    pkill -f "python3 -m http.server" 2>/dev/null

    local pid_18443=""
    if command -v ss &>/dev/null; then
        pid_18443=$(ss -lntp | grep :18443 | awk -F'pid=' '{print $2}' | awk -F',' '{print $1}')
    elif command -v netstat &>/dev/null; then
        pid_18443=$(netstat -lntp | grep :18443 | awk '{print $NF}' | cut -d/ -f1)
    fi

    if [[ -n "$pid_18443" ]]; then
        yellow "检测到 18443 端口占用 (PID: $pid_18443)，正在清理..." >&2
        kill -9 "$pid_18443" 2>/dev/null
    fi

    mkdir -p "${WORK_DIR}/caddy" "${LOG_DIR}"

    cat > "$CADDY_FILE" <<EOF
{
    email $caddy_email
    auto_https disable_redirects
}

$caddy_domain:18443 {
    handle {
        reverse_proxy https://www.bing.com {
            header_up Host {upstream_hostport}
        }
    }
}
EOF

    write_caddy_sub_unit "$CADDY_SERVICE_FILE" \
        "$CADDY_BIN run --environ --config $CADDY_FILE" \
        "$CADDY_BIN reload --config $CADDY_FILE"

    systemctl daemon-reload
    systemctl enable caddy-sub >/dev/null 2>&1 || true
    systemctl restart caddy-sub

    local service_wait=0
    for service_wait in {1..10}; do
        if systemctl is-active --quiet caddy-sub; then
            return 0
        fi
        sleep 0.2
    done

    red "证书入口启动失败，请检查 caddy 日志。" >&2
    if ss -tuln | grep -q ":18443 "; then
        red "诊断: 18443 端口仍被占用。" >&2
    fi
    return 1
}

wait_for_tls_certificate_file() {
    local cert_path="${1:-}"
    local timeout="${2:-120}"
    local remaining domain cert_pair interval elapsed
    remaining="$timeout"
    interval=1
    elapsed=0
    [[ -n "$cert_path" ]] || return 1
    domain="$(basename "${cert_path%.crt}")"

    local -a _spin=("${_PROXY_SPIN_FRAMES[@]}")
    local spin_idx=0

    yellow "证书入口已启动，证书申请中..." >&2
    while (( remaining > 0 )); do
        if [[ -f "$cert_path" ]]; then
            printf '\r\033[K' >&2
            green "✅ 证书申请成功 (耗时 ${elapsed}s)" >&2
            return 0
        fi
        cert_pair="$(resolve_caddy_tls_cert_pair "$domain" 2>/dev/null || true)"
        if [[ -n "$cert_pair" ]]; then
            printf '\r\033[K' >&2
            green "✅ 证书申请成功 (耗时 ${elapsed}s)" >&2
            return 0
        fi
        printf '\r\033[K'"${_PROXY_SPIN_COLOR}"'%s\033[0m 等待证书签发... %ds/%ds' "${_spin[$spin_idx]}" "$elapsed" "$timeout" >&2
        spin_idx=$(( (spin_idx + 1) % ${#_spin[@]} ))
        sleep "$interval"
        ((elapsed+=interval))
        ((remaining-=interval))
    done

    printf '\r\033[K' >&2
    red "❌ 证书申请超时 (${timeout}s)，请检查域名解析、80 端口和 caddy 日志。" >&2
    return 1
}
