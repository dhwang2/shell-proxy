# Subscription target detection and render-context operations for shell-proxy management.

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

USER_MEMBERSHIP_OPS_FILE="${USER_MEMBERSHIP_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../user/user_membership_ops.sh}"
if [[ -f "$USER_MEMBERSHIP_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$USER_MEMBERSHIP_OPS_FILE"
fi

PROTOCOL_RUNTIME_OPS_FILE="${PROTOCOL_RUNTIME_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../protocol/protocol_runtime_ops.sh}"
if [[ -f "$PROTOCOL_RUNTIME_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PROTOCOL_RUNTIME_OPS_FILE"
fi

normalize_ip_literal() {
    local raw="${1:-}"
    raw="$(printf '%s' "$raw" | tr -d '\r' | tr -d '\n' | tr -d ' ')"
    raw="${raw#[}"
    raw="${raw%]}"
    raw="${raw%%/*}"
    raw="${raw%%%*}"
    echo "$raw"
}

if ! declare -F is_ipv4_literal >/dev/null 2>&1; then
    is_ipv4_literal() {
        local ip="${1:-}"
        [[ -n "$ip" ]] || return 1
        [[ "$ip" == *:* ]] && return 1

        local o1 o2 o3 o4 extra
        IFS='.' read -r o1 o2 o3 o4 extra <<<"$ip"
        [[ -n "$o1" && -n "$o2" && -n "$o3" && -n "$o4" && -z "$extra" ]] || return 1

        local octet
        for octet in "$o1" "$o2" "$o3" "$o4"; do
            [[ "$octet" =~ ^[0-9]+$ ]] || return 1
            (( octet >= 0 && octet <= 255 )) || return 1
        done
        return 0
    }
fi

if ! declare -F is_public_ipv4_literal >/dev/null 2>&1; then
    is_public_ipv4_literal() {
        local ip="${1:-}"
        is_ipv4_literal "$ip" || return 1

        local o1 o2 o3 o4
        IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

        if (( o1 == 0 || o1 == 10 || o1 == 127 )); then
            return 1
        fi
        if (( o1 == 100 && o2 >= 64 && o2 <= 127 )); then
            return 1
        fi
        if (( o1 == 169 && o2 == 254 )); then
            return 1
        fi
        if (( o1 == 172 && o2 >= 16 && o2 <= 31 )); then
            return 1
        fi
        if (( o1 == 192 && o2 == 168 )); then
            return 1
        fi
        if (( o1 == 198 && (o2 == 18 || o2 == 19) )); then
            return 1
        fi
        if (( o1 >= 224 )); then
            return 1
        fi
        if (( o1 == 255 && o2 == 255 && o3 == 255 && o4 == 255 )); then
            return 1
        fi

        return 0
    }
fi

is_ipv6_literal() {
    local ip
    ip="$(normalize_ip_literal "${1:-}")"
    [[ -n "$ip" && "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1

    local dcolon_count
    dcolon_count="$(awk -v s="$ip" 'BEGIN{print gsub(/::/, "", s)}')"
    [[ -n "$dcolon_count" ]] || return 1
    (( dcolon_count <= 1 )) || return 1
    return 0
}

is_shareable_ipv6_literal() {
    local ip lower
    ip="$(normalize_ip_literal "${1:-}")"
    is_ipv6_literal "$ip" || return 1

    lower="$(printf '%s' "$ip" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        ::|::1|::ffff:*|0:0:0:0:0:ffff:*|fe80:*|fc*|fd*)
            return 1
            ;;
    esac
    return 0
}

ensure_subscription_target_cache_maps() {
    if ! declare -p SUBSCRIPTION_IP_DETECT_CACHE 2>/dev/null | grep -q 'declare -A'; then
        declare -gA SUBSCRIPTION_IP_DETECT_CACHE=()
    fi
    if ! declare -p SUBSCRIPTION_DOMAIN_RESOLVE_CACHE 2>/dev/null | grep -q 'declare -A'; then
        declare -gA SUBSCRIPTION_DOMAIN_RESOLVE_CACHE=()
    fi
    SUBSCRIPTION_TARGET_CACHE_INIT=1
}

subscription_target_cache_dir() {
    local base_dir
    if declare -F subscription_render_cache_dir >/dev/null 2>&1; then
        base_dir="$(subscription_render_cache_dir)"
    else
        base_dir="${CACHE_DIR:-${WORK_DIR:-/etc/shell-proxy}/cache}/subscription"
    fi
    printf '%s\n' "${base_dir}/targets"
}

subscription_target_cache_ttl_seconds() {
    printf '%s\n' "${SUBSCRIPTION_TARGET_CACHE_TTL_SECONDS:-3600}"
}

subscription_target_cache_file() {
    local cache_key="${1:-}" cache_id
    [[ -n "$cache_key" ]] || return 1
    cache_id="$(printf '%s' "$cache_key" | cksum 2>/dev/null | awk '{print $1"-"$2}')"
    [[ -n "$cache_id" ]] || return 1
    printf '%s/.%s.cache\n' "$(subscription_target_cache_dir)" "$cache_id"
}

subscription_target_cache_read() {
    local cache_key="${1:-}" output_var="${2:-}" cache_file cached_at cached_value now ttl
    [[ -n "$cache_key" && -n "$output_var" ]] || return 1

    cache_file="$(subscription_target_cache_file "$cache_key" 2>/dev/null || true)"
    [[ -n "$cache_file" && -f "$cache_file" ]] || return 1

    IFS=$'\t' read -r cached_at cached_value <"$cache_file" || return 1
    [[ "$cached_at" =~ ^[0-9]+$ ]] || return 1
    ttl="$(subscription_target_cache_ttl_seconds 2>/dev/null || true)"
    [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=3600
    now="$(date +%s)"
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    (( now - cached_at <= ttl )) || return 1

    if [[ "$cached_value" == "__none__" ]]; then
        printf -v "$output_var" '%s' ""
    else
        printf -v "$output_var" '%s' "$cached_value"
    fi
    return 0
}

subscription_target_cache_write() {
    local cache_key="${1:-}" cache_value="${2-}" cache_dir cache_file tmp_file now stored_value
    [[ -n "$cache_key" ]] || return 1

    cache_dir="$(subscription_target_cache_dir)"
    cache_file="$(subscription_target_cache_file "$cache_key" 2>/dev/null || true)"
    [[ -n "$cache_file" ]] || return 1
    mkdir -p "$cache_dir" >/dev/null 2>&1 || return 1

    now="$(date +%s)"
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    stored_value="${cache_value:-__none__}"
    tmp_file="$(mktemp)"
    printf '%s\t%s\n' "$now" "$stored_value" >"$tmp_file"
    mv -f "$tmp_file" "$cache_file"
}

subscription_target_cache_write_atomic() {
    local path="${1:-}" content="${2-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

detect_server_ipv4_for_subscription() {
    local cache_key="server_ipv4" cached_ip=""
    if [[ -z "${SUBSCRIPTION_TARGET_CACHE_INIT:-}" ]] \
        || ! declare -p SUBSCRIPTION_IP_DETECT_CACHE 2>/dev/null | grep -q 'declare -A' \
        || ! declare -p SUBSCRIPTION_DOMAIN_RESOLVE_CACHE 2>/dev/null | grep -q 'declare -A'; then
        ensure_subscription_target_cache_maps
    fi
    if [[ -n "${SUBSCRIPTION_IP_DETECT_CACHE[$cache_key]+_}" ]]; then
        cached_ip="${SUBSCRIPTION_IP_DETECT_CACHE[$cache_key]}"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi
    if subscription_target_cache_read "$cache_key" cached_ip; then
        SUBSCRIPTION_IP_DETECT_CACHE["$cache_key"]="$cached_ip"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi

    local ip=""

    if command -v ip >/dev/null 2>&1; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
        ip="$(normalize_ip_literal "$ip")"
        if ! is_public_ipv4_literal "$ip"; then
            ip="$(ip -o -4 addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}')"
            ip="$(normalize_ip_literal "$ip")"
        fi
    fi

    if ! is_public_ipv4_literal "$ip" && command -v curl >/dev/null 2>&1; then
        ip="$(curl -4 -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || true)"
        ip="$(normalize_ip_literal "$ip")"
    fi
    if ! is_public_ipv4_literal "$ip" && command -v curl >/dev/null 2>&1; then
        ip="$(curl -s4 --connect-timeout 2 icanhazip.com 2>/dev/null || true)"
        ip="$(normalize_ip_literal "$ip")"
    fi

    if is_public_ipv4_literal "$ip"; then
        SUBSCRIPTION_IP_DETECT_CACHE["$cache_key"]="$ip"
        subscription_target_cache_write "$cache_key" "$ip" >/dev/null 2>&1 || true
        echo "$ip"
    else
        SUBSCRIPTION_IP_DETECT_CACHE["$cache_key"]=""
        subscription_target_cache_write "$cache_key" "" >/dev/null 2>&1 || true
    fi
}

detect_server_ipv6_for_subscription() {
    local cache_key="server_ipv6" cached_ip=""
    local stack_mode=""
    if [[ -z "${SUBSCRIPTION_TARGET_CACHE_INIT:-}" ]] \
        || ! declare -p SUBSCRIPTION_IP_DETECT_CACHE 2>/dev/null | grep -q 'declare -A' \
        || ! declare -p SUBSCRIPTION_DOMAIN_RESOLVE_CACHE 2>/dev/null | grep -q 'declare -A'; then
        ensure_subscription_target_cache_maps
    fi
    if [[ -n "${SUBSCRIPTION_IP_DETECT_CACHE[$cache_key]+_}" ]]; then
        cached_ip="${SUBSCRIPTION_IP_DETECT_CACHE[$cache_key]}"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi
    if subscription_target_cache_read "$cache_key" cached_ip; then
        SUBSCRIPTION_IP_DETECT_CACHE["$cache_key"]="$cached_ip"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi

    stack_mode="$(detect_server_ip_stack 2>/dev/null || echo ipv4)"
    if [[ "$stack_mode" != "ipv6" && "$stack_mode" != "dualstack" ]]; then
        SUBSCRIPTION_IP_DETECT_CACHE["$cache_key"]=""
        subscription_target_cache_write "$cache_key" "" >/dev/null 2>&1 || true
        return 0
    fi

    local ip=""

    if command -v ip >/dev/null 2>&1; then
        ip="$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
        ip="$(normalize_ip_literal "$ip")"
        if ! is_shareable_ipv6_literal "$ip"; then
            ip="$(ip -o -6 addr show scope global 2>/dev/null | awk '$4 !~ /^fe80:/ {split($4, a, "/"); print a[1]; exit}')"
            ip="$(normalize_ip_literal "$ip")"
        fi
    fi

    if ! is_shareable_ipv6_literal "$ip" && command -v curl >/dev/null 2>&1; then
        ip="$(curl -6 -s --connect-timeout 2 https://api64.ipify.org 2>/dev/null || true)"
        ip="$(normalize_ip_literal "$ip")"
    fi
    if ! is_shareable_ipv6_literal "$ip" && command -v curl >/dev/null 2>&1; then
        ip="$(curl -s6 --connect-timeout 2 icanhazip.com 2>/dev/null || true)"
        ip="$(normalize_ip_literal "$ip")"
    fi

    if is_shareable_ipv6_literal "$ip"; then
        SUBSCRIPTION_IP_DETECT_CACHE["$cache_key"]="$ip"
        subscription_target_cache_write "$cache_key" "$ip" >/dev/null 2>&1 || true
        echo "$ip"
    else
        SUBSCRIPTION_IP_DETECT_CACHE["$cache_key"]=""
        subscription_target_cache_write "$cache_key" "" >/dev/null 2>&1 || true
    fi
}

resolve_domain_ipv4_for_subscription() {
    local host="${1:-}"
    host="$(printf '%s' "$host" | tr -d '\r' | tr -d '\n' | tr -d ' ')"
    [[ -n "$host" ]] || return 0
    local cache_key="ipv4|${host}" cached_ip=""
    if [[ -z "${SUBSCRIPTION_TARGET_CACHE_INIT:-}" ]] \
        || ! declare -p SUBSCRIPTION_IP_DETECT_CACHE 2>/dev/null | grep -q 'declare -A' \
        || ! declare -p SUBSCRIPTION_DOMAIN_RESOLVE_CACHE 2>/dev/null | grep -q 'declare -A'; then
        ensure_subscription_target_cache_maps
    fi
    if [[ -n "${SUBSCRIPTION_DOMAIN_RESOLVE_CACHE[$cache_key]+_}" ]]; then
        cached_ip="${SUBSCRIPTION_DOMAIN_RESOLVE_CACHE[$cache_key]}"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi
    if subscription_target_cache_read "resolve|${cache_key}" cached_ip; then
        SUBSCRIPTION_DOMAIN_RESOLVE_CACHE["$cache_key"]="$cached_ip"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi
    command -v getent >/dev/null 2>&1 || return 0

    local ip
    ip="$(getent ahostsv4 "$host" 2>/dev/null | awk '$1 ~ /^[0-9.]+$/ {print $1; exit}')"
    ip="$(normalize_ip_literal "$ip")"
    if is_ipv4_literal "$ip"; then
        SUBSCRIPTION_DOMAIN_RESOLVE_CACHE["$cache_key"]="$ip"
        subscription_target_cache_write "resolve|${cache_key}" "$ip" >/dev/null 2>&1 || true
        echo "$ip"
    else
        SUBSCRIPTION_DOMAIN_RESOLVE_CACHE["$cache_key"]=""
        subscription_target_cache_write "resolve|${cache_key}" "" >/dev/null 2>&1 || true
    fi
}

resolve_domain_ipv6_for_subscription() {
    local host="${1:-}"
    host="$(printf '%s' "$host" | tr -d '\r' | tr -d '\n' | tr -d ' ')"
    [[ -n "$host" ]] || return 0
    local stack_mode=""
    stack_mode="$(detect_server_ip_stack 2>/dev/null || echo ipv4)"
    if [[ "$stack_mode" != "ipv6" && "$stack_mode" != "dualstack" ]]; then
        return 0
    fi
    local cache_key="ipv6|${host}" cached_ip=""
    if [[ -z "${SUBSCRIPTION_TARGET_CACHE_INIT:-}" ]] \
        || ! declare -p SUBSCRIPTION_IP_DETECT_CACHE 2>/dev/null | grep -q 'declare -A' \
        || ! declare -p SUBSCRIPTION_DOMAIN_RESOLVE_CACHE 2>/dev/null | grep -q 'declare -A'; then
        ensure_subscription_target_cache_maps
    fi
    if [[ -n "${SUBSCRIPTION_DOMAIN_RESOLVE_CACHE[$cache_key]+_}" ]]; then
        cached_ip="${SUBSCRIPTION_DOMAIN_RESOLVE_CACHE[$cache_key]}"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi
    if subscription_target_cache_read "resolve|${cache_key}" cached_ip; then
        SUBSCRIPTION_DOMAIN_RESOLVE_CACHE["$cache_key"]="$cached_ip"
        [[ -n "$cached_ip" ]] && echo "$cached_ip"
        return 0
    fi
    command -v getent >/dev/null 2>&1 || return 0

    local ip
    ip="$(getent ahostsv6 "$host" 2>/dev/null | awk '$1 ~ /:/ && $1 !~ /^fe80:/ {print $1; exit}')"
    ip="$(normalize_ip_literal "$ip")"
    if is_shareable_ipv6_literal "$ip"; then
        SUBSCRIPTION_DOMAIN_RESOLVE_CACHE["$cache_key"]="$ip"
        subscription_target_cache_write "resolve|${cache_key}" "$ip" >/dev/null 2>&1 || true
        echo "$ip"
    else
        SUBSCRIPTION_DOMAIN_RESOLVE_CACHE["$cache_key"]=""
        subscription_target_cache_write "resolve|${cache_key}" "" >/dev/null 2>&1 || true
    fi
}

detect_surge_link_targets_uncached() {
    local host="${1:-}"
    local mode="${2:-ip}"
    local host_literal ipv4 ipv6 output=""

    host_literal="$(normalize_ip_literal "$host")"

    if [[ "$mode" == "domain" ]]; then
        local domain_candidate=""
        if is_valid_domain_name "$host"; then
            domain_candidate="$host"
        elif is_valid_domain_name "$host_literal"; then
            domain_candidate="$host_literal"
        else
            domain_candidate="$(resolve_tls_server_domain_default 2>/dev/null || true)"
        fi
        domain_candidate="$(printf '%s' "$domain_candidate" | tr -d '\r' | tr -d '\n' | tr -d ' ')"
        if is_valid_domain_name "$domain_candidate"; then
            echo "domain|${domain_candidate}"
        fi
        return 0
    fi

    if is_ipv4_literal "$host_literal"; then
        ipv4="$host_literal"
    elif [[ -n "$host" ]]; then
        ipv4="$(resolve_domain_ipv4_for_subscription "$host" 2>/dev/null || true)"
    fi

    if ! is_public_ipv4_literal "$ipv4"; then
        ipv4="$(detect_server_ipv4_for_subscription 2>/dev/null || true)"
    fi
    ipv6="$(detect_server_ipv6_for_subscription 2>/dev/null || true)"

    if ! is_shareable_ipv6_literal "$ipv6"; then
        if is_shareable_ipv6_literal "$host_literal"; then
            ipv6="$host_literal"
        elif [[ -n "$host" ]]; then
            ipv6="$(resolve_domain_ipv6_for_subscription "$host" 2>/dev/null || true)"
        fi
    fi

    if is_public_ipv4_literal "$ipv4"; then
        output+="ipv4|${ipv4}"$'\n'
    fi
    if is_shareable_ipv6_literal "$ipv6"; then
        output+="ipv6|${ipv6}"$'\n'
    fi

    printf '%s' "$output" | awk 'NF && !seen[$0]++'
}

detect_surge_link_targets_pair_uncached() {
    local host="${1:-}"
    local host_literal ipv4="" ipv6="" ip_output="" ip_clean=""

    host_literal="$(normalize_ip_literal "$host")"

    if is_ipv4_literal "$host_literal"; then
        ipv4="$host_literal"
    elif [[ -n "$host" ]]; then
        ipv4="$(resolve_domain_ipv4_for_subscription "$host" 2>/dev/null || true)"
    fi

    if ! is_public_ipv4_literal "$ipv4"; then
        ipv4="$(detect_server_ipv4_for_subscription 2>/dev/null || true)"
    fi
    ipv6="$(detect_server_ipv6_for_subscription 2>/dev/null || true)"

    if ! is_shareable_ipv6_literal "$ipv6"; then
        if is_shareable_ipv6_literal "$host_literal"; then
            ipv6="$host_literal"
        elif [[ -n "$host" ]]; then
            ipv6="$(resolve_domain_ipv6_for_subscription "$host" 2>/dev/null || true)"
        fi
    fi

    if is_public_ipv4_literal "$ipv4"; then
        ip_output+="ipv4|${ipv4}"$'\n'
    fi
    if is_shareable_ipv6_literal "$ipv6"; then
        ip_output+="ipv6|${ipv6}"$'\n'
    fi

    ip_clean="$(printf '%s' "$ip_output" | awk 'NF && !seen[$0]++')"
    SUBSCRIPTION_RENDER_CONTEXT_SURGE_IP_TARGETS="${ip_clean:-}"
}

subscription_render_snapshot_rows_uncached() {
    local conf_file="${1:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0

    jq -r '
        def tag_for($entry):
            $entry.value.tag // ("inbound_" + ($entry.key | tostring));
        def user_list($in):
            if ($in.users | type) == "array" then $in.users
            elif ($in.users | type) == "object" then [$in.users]
            else []
            end;
        def row($proto; $tag; $port; $sni; $priv; $sid; $alpn; $method; $user_id; $secret; $flow; $name):
            [
                $proto,
                ($tag // ""),
                (($port // "") | tostring),
                ($sni // ""),
                ($priv // ""),
                ($sid // ""),
                ($alpn // ""),
                ($method // ""),
                ($user_id // ""),
                ($secret // ""),
                ($flow // ""),
                ($name // "")
            ] | join("\u001f");

        .inbounds
        | to_entries[]?
        | . as $entry
        | ($entry.value // {}) as $in
        | (($in.type // "") | ascii_downcase) as $type
        | if $type == "vless" then
            (
                (user_list($in)[]?
                    | select((.uuid // .id // empty) != "")
                    | row(
                        "vless";
                        tag_for($entry);
                        $in.listen_port;
                        ($in.tls.server_name // "");
                        ($in.tls.reality.private_key // "");
                        ($in.tls.reality.short_id[0] // "");
                        "";
                        "";
                        (.uuid // .id // "");
                        "";
                        (.flow // "xtls-rprx-vision");
                        (.name // "")
                    )
                ),
                (
                    if (($in.users | type) == "null" and (($in.uuid // $in.id // empty) != "")) then
                        row(
                            "vless";
                            tag_for($entry);
                            $in.listen_port;
                            ($in.tls.server_name // "");
                            ($in.tls.reality.private_key // "");
                            ($in.tls.reality.short_id[0] // "");
                            "";
                            "";
                            ($in.uuid // $in.id // "");
                            "";
                            ($in.flow // "xtls-rprx-vision");
                            ($in.name // "")
                        )
                    else
                        empty
                    end
                )
            )
          elif $type == "tuic" then
            (
                (user_list($in)[]?
                    | select((.uuid // .id // empty) != "" and (.password // empty) != "")
                    | row(
                        "tuic";
                        tag_for($entry);
                        $in.listen_port;
                        ($in.tls.server_name // "");
                        "";
                        "";
                        "";
                        "";
                        (.uuid // .id // "");
                        (.password // "");
                        "";
                        (.name // "")
                    )
                ),
                (
                    if (($in.users | type) == "null" and (($in.uuid // $in.id // empty) != "") and (($in.password // empty) != "")) then
                        row(
                            "tuic";
                            tag_for($entry);
                            $in.listen_port;
                            ($in.tls.server_name // "");
                            "";
                            "";
                            "";
                            "";
                            ($in.uuid // $in.id // "");
                            ($in.password // "");
                            "";
                            ($in.name // "")
                        )
                    else
                        empty
                    end
                )
            )
          elif ($type == "trojan" or $type == "anytls") then
            (
                if ($in.users | type) == "array" then
                    $in.users
                elif ($in.users | type) == "object" then
                    [$in.users]
                elif (($in.password // empty) != "") then
                    [{name:($in.name // ""), password:($in.password // "")}]
                else
                    []
                end
            )
            | .[]?
            | select((.password // empty) != "")
            | row(
                $type;
                tag_for($entry);
                $in.listen_port;
                ($in.tls.server_name // "");
                "";
                "";
                (
                    if $type == "trojan" then
                        (($in.tls.alpn // ["h2", "http/1.1"]) | if type == "array" then join(",") else tostring end)
                    else
                        ""
                    end
                );
                "";
                (.password // "");
                (.password // "");
                "";
                (.name // "")
            )
          elif ($type == "shadowsocks" or $type == "ss") then
            (
                if ($in.users | type) == "array" then
                    $in.users
                elif ($in.users | type) == "object" then
                    [$in.users]
                elif (($in.password // empty) != "") then
                    [{name:($in.name // ""), method:($in.method // ""), password:($in.password // "")}]
                else
                    []
                end
            )
            | .[]?
            | select((.password // empty) != "")
            | row(
                "ss";
                tag_for($entry);
                $in.listen_port;
                "";
                "";
                "";
                "";
                (.method // ($in.method // ""));
                (.password // "");
                (.password // "");
                "";
                (.name // "")
            )
          else
            empty
          end
    ' "$conf_file" 2>/dev/null || true
}

subscription_render_snapshot_rows() {
    local proto="${1:-}"
    local conf_file="${2:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"

    local rows=""
    if (( SUBSCRIPTION_RENDER_CONTEXT_ACTIVE == 1 )) \
        && [[ "$conf_file" == "$SUBSCRIPTION_RENDER_CONTEXT_CONF" ]]; then
        rows="${SUBSCRIPTION_RENDER_CONTEXT_SNAPSHOT_ROWS:-}"
    else
        rows="$(subscription_render_snapshot_rows_uncached "$conf_file" 2>/dev/null || true)"
    fi

    [[ -n "$rows" ]] || return 0
    if [[ -z "$proto" ]]; then
        printf '%s\n' "$rows"
        return 0
    fi
    awk -F "$(printf '\037')" -v target_proto="$proto" 'target_proto == "" || $1 == target_proto' <<< "$rows"
}

subscription_render_context_begin() {
    local host="${1:-}"
    local conf_file="${2:-}"
    [[ -z "$conf_file" ]] && conf_file="$(get_conf_file)"

    SUBSCRIPTION_RENDER_CONTEXT_ACTIVE=0
    SUBSCRIPTION_RENDER_CONTEXT_HOST="$host"
    SUBSCRIPTION_RENDER_CONTEXT_CONF="$conf_file"
    SUBSCRIPTION_RENDER_CONTEXT_NODE_NAME="$(detect_share_node_name 2>/dev/null || true)"
    SUBSCRIPTION_RENDER_CONTEXT_SURGE_IP_TARGETS=""
    detect_surge_link_targets_pair_uncached "$host" 2>/dev/null || true
    SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_BINDINGS="$(shadowtls_binding_lines_uncached "$conf_file" 2>/dev/null || true)"
    SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_TARGET_KEYS="$(printf '%s\n' "$SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_BINDINGS" \
        | awk -F'|' 'NF >= 4 && $3 ~ /^[0-9]+$/ && $4 != "" {print $4 "|" $3}')"
    if [[ -n "$conf_file" && -f "$conf_file" ]]; then
        SUBSCRIPTION_RENDER_CONTEXT_SNAPSHOT_ROWS="$(subscription_render_snapshot_rows_uncached "$conf_file" 2>/dev/null || true)"
    else
        SUBSCRIPTION_RENDER_CONTEXT_SNAPSHOT_ROWS=""
    fi
    SUBSCRIPTION_RENDER_CONTEXT_VLESS_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_TUIC_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_TROJAN_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_ANYTLS_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_SS_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_ACTIVE=1
}

subscription_render_context_end() {
    SUBSCRIPTION_RENDER_CONTEXT_ACTIVE=0
    SUBSCRIPTION_RENDER_CONTEXT_HOST=""
    SUBSCRIPTION_RENDER_CONTEXT_CONF=""
    SUBSCRIPTION_RENDER_CONTEXT_NODE_NAME=""
    SUBSCRIPTION_RENDER_CONTEXT_SURGE_IP_TARGETS=""
    SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_BINDINGS=""
    SUBSCRIPTION_RENDER_CONTEXT_SHADOWTLS_TARGET_KEYS=""
    SUBSCRIPTION_RENDER_CONTEXT_SNAPSHOT_ROWS=""
    SUBSCRIPTION_RENDER_CONTEXT_VLESS_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_TUIC_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_TROJAN_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_ANYTLS_INBOUNDS=""
    SUBSCRIPTION_RENDER_CONTEXT_SS_INBOUNDS=""
}

# --- Surge subscription link generation (merged from subscription_surge_ops.sh) ---

surge_target_suffix() {
    case "${1:-}" in
        ipv6) echo "v6" ;;
        domain) echo "domain" ;;
        *) echo "v4" ;;
    esac
}

surge_append_links_for_targets() {
    local output_var="${1:-}" families_name="${2:-}" hosts_name="${3:-}"
    local name_prefix="${4:-}" user_suffix="${5:-}" proto_label="${6:-}" port="${7:-}" extra="${8:-}"
    [[ -n "$output_var" && -n "$families_name" && -n "$hosts_name" ]] || return 0

    local -n families_ref="$families_name"
    local -n hosts_ref="$hosts_name"
    local current="" target_idx target_family target_host target_suffix
    current="${!output_var}"

    for target_idx in "${!hosts_ref[@]}"; do
        target_family="${families_ref[$target_idx]}"
        target_host="${hosts_ref[$target_idx]}"
        target_suffix="$(surge_target_suffix "$target_family")"
        current+="${name_prefix}-${target_suffix}-${user_suffix} = ${proto_label}, ${target_host}, ${port}${extra}"$'\n'
    done

    printf -v "$output_var" '%s' "$current"
}

surge_append_links_for_targets_with_user_buckets() {
    local output_var="${1:-}" map_name="${2:-}" families_name="${3:-}" hosts_name="${4:-}"
    local name_prefix="${5:-}" user_suffix="${6:-}" proto_label="${7:-}" port="${8:-}" extra="${9:-}"
    [[ -n "$output_var" && -n "$map_name" ]] || return 0

    surge_append_links_for_targets "$output_var" "$families_name" "$hosts_name" "$name_prefix" "$user_suffix" "$proto_label" "$port" "$extra"

    local -n output_ref="$output_var"
    local -n map_ref="$map_name"
    local -n families_ref="$families_name"
    local -n hosts_ref="$hosts_name"
    local target_idx target_family target_host target_suffix line
    for target_idx in "${!hosts_ref[@]}"; do
        target_family="${families_ref[$target_idx]}"
        target_host="${hosts_ref[$target_idx]}"
        target_suffix="$(surge_target_suffix "$target_family")"
        line="${name_prefix}-${target_suffix}-${user_suffix} = ${proto_label}, ${target_host}, ${port}${extra}"
        map_ref["$user_suffix"]+="${line}"$'\n'
    done
}

subscription_link_user_bucket_key() {
    local proto="${1:-}" in_tag="${2:-}" user_id="${3:-}" raw_name="${4:-}"
    local suffix=""
    if declare -F proxy_user_share_suffix_cached >/dev/null 2>&1; then
        suffix="$(proxy_user_share_suffix_cached "$proto" "$in_tag" "$user_id" "$raw_name" 2>/dev/null || true)"
    else
        suffix="$(proxy_user_share_suffix "$proto" "$in_tag" "$user_id" "$raw_name" 2>/dev/null || true)"
    fi
    if [[ -z "$suffix" ]]; then
        if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
            suffix="$(proxy_user_link_name_cached "$proto" "$in_tag" "$user_id" "$raw_name" 2>/dev/null || true)"
        else
            suffix="$(proxy_user_link_name "$proto" "$in_tag" "$user_id" "$raw_name" 2>/dev/null || true)"
        fi
        suffix="$(normalize_proxy_user_name "$suffix")"
    fi
    [[ -n "$suffix" ]] || suffix="$(normalize_proxy_user_name "$DEFAULT_PROXY_USER_NAME")"
    printf '%s\n' "$suffix"
}

subscription_build_link_payload() {
    local host="${1:-}" conf_file="${2:-}" link_mode="${3:-default}" target_user="${4:-}"
    local sing_map_name="${5:-}" surge_ip_map_name="${6:-}"
    local sing_var_name="${7:-}" surge_ip_var_name="${8:-}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local -n sing_map_ref="$sing_map_name"
    local -n surge_ip_map_ref="$surge_ip_map_name"
    local -n sing_out_ref="$sing_var_name"
    local -n surge_ip_out_ref="$surge_ip_var_name"

    local snapshot_rows="" ss_snapshot_rows="" node_name uri_host
    local hide_shadow_bound_direct=0
    local filter_all=0
    local opt_udp="" opt_reuse="" opt_tfo=""
    local -a ip_families=() ip_hosts=()
    local target_line target_family target_host

    sing_out_ref=""
    surge_ip_out_ref=""

    node_name="$(detect_share_node_name)"
    uri_host="$(format_share_uri_host "$host" 2>/dev/null || echo "$host")"
    [[ "$link_mode" == "subscription" ]] && hide_shadow_bound_direct=1
    [[ -z "$target_user" ]] && filter_all=1

    if surge_link_verbose_params_enabled; then
        opt_udp=", udp-relay=true"
        opt_reuse=", reuse=true"
        opt_tfo=", tfo=true"
    fi

    while IFS= read -r target_line; do
        [[ -n "$target_line" ]] || continue
        IFS='|' read -r target_family target_host <<< "$target_line"
        [[ -n "$target_family" && -n "$target_host" ]] || continue
        ip_families+=("$target_family")
        ip_hosts+=("$target_host")
    done <<< "${SUBSCRIPTION_RENDER_CONTEXT_SURGE_IP_TARGETS:-}"

    snapshot_rows="$(subscription_render_snapshot_rows "" "$conf_file" 2>/dev/null || true)"
    [[ -n "$snapshot_rows" ]] || snapshot_rows=""
    ss_snapshot_rows="$(awk -F "$(printf '\037')" '$1 == "ss"' <<< "$snapshot_rows")"

    if declare -F proxy_user_display_name_cache_refresh >/dev/null 2>&1; then
        proxy_user_display_name_cache_refresh
    fi

    local proto in_tag port sni _priv _sid alpn method user_id secret _flow raw_name
    while IFS=$'\037' read -r proto in_tag port sni _priv _sid alpn method user_id secret _flow raw_name; do
        [[ -n "$proto" ]] || continue
        case "$proto" in
            vless)
                [[ -n "$user_id" && -n "$port" ]] || continue
                if (( filter_all == 0 )); then
                    proxy_user_matches_filter "vless" "$in_tag" "$user_id" "$raw_name" "$target_user" || continue
                fi
                local v_user_suffix v_pub v_query v_line
                v_user_suffix="$(subscription_link_user_bucket_key "vless" "$in_tag" "$user_id" "$raw_name")"
                v_pub="$(resolve_reality_public_key "$_priv")"
                v_query="encryption=none&security=reality&type=tcp&sni=${sni}&fp=chrome&flow=${_flow}"
                [[ -n "$v_pub" ]] && v_query="${v_query}&pbk=${v_pub}"
                [[ -n "$_sid" ]] && v_query="${v_query}&sid=${_sid}"
                v_line="vless://${user_id}@${uri_host}:${port}?${v_query}#${node_name}_vless_${port}_${v_user_suffix}"
                sing_out_ref+="${v_line}"$'\n'
                sing_map_ref["$v_user_suffix"]+="${v_line}"$'\n'
                ;;
            tuic)
                [[ -n "$user_id" && -n "$secret" && -n "$port" ]] || continue
                if (( filter_all == 0 )); then
                    proxy_user_matches_filter "tuic" "$in_tag" "$user_id" "$raw_name" "$target_user" || continue
                fi
                local t_user_suffix t_line t_user_name t_uuid_fmt t_extra
                t_user_suffix="$(subscription_link_user_bucket_key "tuic" "$in_tag" "$user_id" "$raw_name")"
                t_line="tuic://${user_id}:${secret}@${uri_host}:${port}?congestion_control=bbr&alpn=h3&sni=${sni}&udp_relay_mode=native&allow_insecure=1#${node_name}_tuic_${port}_${t_user_suffix}"
                sing_out_ref+="${t_line}"$'\n'
                sing_map_ref["$t_user_suffix"]+="${t_line}"$'\n'
                if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
                    t_user_name="$(proxy_user_link_name_cached "tuic" "$in_tag" "$user_id" "$raw_name")"
                else
                    t_user_name="$(proxy_user_link_name "tuic" "$in_tag" "$user_id" "$raw_name")"
                fi
                t_uuid_fmt="$user_id"
                if is_valid_uuid_text "$user_id"; then
                    t_uuid_fmt="$(printf '%s' "$user_id" | tr '[:lower:]' '[:upper:]')"
                fi
                t_extra=", password=${secret}, uuid=${t_uuid_fmt}, alpn=h3, sni=${sni}, skip-cert-verify=false, congestion-controller=bbr${opt_udp}"
                surge_append_links_for_targets_with_user_buckets surge_ip_out_ref surge_ip_map_ref ip_families ip_hosts "${node_name}-tuic" "$t_user_name" "tuic-v5" "$port" "$t_extra"
                ;;
            trojan)
                [[ -n "$secret" && -n "$port" ]] || continue
                if (( filter_all == 0 )); then
                    proxy_user_matches_filter "trojan" "$in_tag" "$user_id" "$raw_name" "$target_user" || continue
                fi
                local tr_user_suffix tr_line tr_user_name tr_extra tr_alpn_opt tr_alpn_first alpn_item
                tr_user_suffix="$(subscription_link_user_bucket_key "trojan" "$in_tag" "$user_id" "$raw_name")"
                tr_line="trojan://${secret}@${uri_host}:${port}?security=tls&sni=${sni}&type=tcp#${node_name}_trojan_${port}_${tr_user_suffix}"
                if [[ -n "$alpn" ]]; then
                    tr_line="trojan://${secret}@${uri_host}:${port}?security=tls&sni=${sni}&type=tcp&alpn=${alpn}#${node_name}_trojan_${port}_${tr_user_suffix}"
                fi
                sing_out_ref+="${tr_line}"$'\n'
                sing_map_ref["$tr_user_suffix"]+="${tr_line}"$'\n'
                if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
                    tr_user_name="$(proxy_user_link_name_cached "trojan" "$in_tag" "$user_id" "$raw_name")"
                else
                    tr_user_name="$(proxy_user_link_name "trojan" "$in_tag" "$user_id" "$raw_name")"
                fi
                tr_alpn_first=""
                if [[ -n "$alpn" ]]; then
                    IFS=',' read -r -a _surge_alpn_items <<< "$alpn"
                    for alpn_item in "${_surge_alpn_items[@]}"; do
                        alpn_item="${alpn_item//[[:space:]]/}"
                        [[ -n "$alpn_item" ]] || continue
                        tr_alpn_first="$alpn_item"
                        break
                    done
                fi
                [[ -n "$tr_alpn_first" ]] && tr_alpn_opt=", alpn=${tr_alpn_first}" || tr_alpn_opt=""
                tr_extra=", password=${secret}, sni=${sni}${tr_alpn_opt}, skip-cert-verify=false${opt_udp}"
                surge_append_links_for_targets_with_user_buckets surge_ip_out_ref surge_ip_map_ref ip_families ip_hosts "${node_name}-trojan" "$tr_user_name" "trojan" "$port" "$tr_extra"
                ;;
            anytls)
                [[ -n "$secret" && -n "$port" ]] || continue
                if (( filter_all == 0 )); then
                    proxy_user_matches_filter "anytls" "$in_tag" "$user_id" "$raw_name" "$target_user" || continue
                fi
                local a_user_suffix a_line a_user_name a_extra
                a_user_suffix="$(subscription_link_user_bucket_key "anytls" "$in_tag" "$user_id" "$raw_name")"
                a_line="anytls://${secret}@${uri_host}:${port}?sni=${sni}#${node_name}_anytls_${port}_${a_user_suffix}"
                sing_out_ref+="${a_line}"$'\n'
                sing_map_ref["$a_user_suffix"]+="${a_line}"$'\n'
                if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
                    a_user_name="$(proxy_user_link_name_cached "anytls" "$in_tag" "$user_id" "$raw_name")"
                else
                    a_user_name="$(proxy_user_link_name "anytls" "$in_tag" "$user_id" "$raw_name")"
                fi
                a_extra=", password=${secret}, sni=${sni}, skip-cert-verify=false${opt_reuse}"
                surge_append_links_for_targets_with_user_buckets surge_ip_out_ref surge_ip_map_ref ip_families ip_hosts "${node_name}-anytls" "$a_user_name" "anytls" "$port" "$a_extra"
                ;;
            ss)
                [[ -n "$method" && -n "$secret" && -n "$port" ]] || continue
                if (( filter_all == 0 )); then
                    proxy_user_matches_filter "ss" "$in_tag" "$user_id" "$raw_name" "$target_user" || continue
                fi
                local ss_user_suffix ss_auth ss_line ss_user_name ss_pass_literal ss_extra
                ss_user_suffix="$(subscription_link_user_bucket_key "ss" "$in_tag" "$user_id" "$raw_name")"
                ss_auth="$(printf "%s" "${method}:${secret}" | base64_no_wrap | tr '+/' '-_' | tr -d '=')"
                ss_line="ss://${ss_auth}@${uri_host}:${port}#${node_name}_ss_${port}_${ss_user_suffix}"
                sing_out_ref+="${ss_line}"$'\n'
                sing_map_ref["$ss_user_suffix"]+="${ss_line}"$'\n'
                if (( hide_shadow_bound_direct == 1 )) && shadowtls_binding_exists_for_backend_target "ss" "$port" "$conf_file"; then
                    continue
                fi
                if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
                    ss_user_name="$(proxy_user_link_name_cached "ss" "$in_tag" "$user_id" "$raw_name")"
                else
                    ss_user_name="$(proxy_user_link_name "ss" "$in_tag" "$user_id" "$raw_name")"
                fi
                ss_pass_literal="$(printf '%s' "$secret" | sed 's/\\/\\\\/g; s/"/\\"/g')"
                ss_extra=", encrypt-method=${method}, password=\"${ss_pass_literal}\"${opt_udp}"
                surge_append_links_for_targets_with_user_buckets surge_ip_out_ref surge_ip_map_ref ip_families ip_hosts "${node_name}-ss" "$ss_user_name" "ss" "$port" "$ss_extra"
                ;;
        esac
    done <<< "$snapshot_rows"

    if [[ -f "$SNELL_CONF" ]]; then
        local s_port s_psk s_user_name s_extra
        s_port=$(grep "^listen" "$SNELL_CONF" | awk -F':' '{print $NF}')
        s_psk=$(grep "^psk" "$SNELL_CONF" | cut -d= -f2 | tr -d ' ')
        if (( filter_all == 0 )); then
            proxy_user_matches_filter "snell" "snell-v5" "$s_psk" "" "$target_user" || s_psk=""
        fi
        if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
            s_user_name="$(proxy_user_link_name_cached "snell" "snell-v5" "$s_psk" "")"
        else
            s_user_name="$(proxy_user_link_name "snell" "snell-v5" "$s_psk" "")"
        fi
        if [[ -n "$s_psk" ]] && { ! (( hide_shadow_bound_direct == 1 )) || ! shadowtls_binding_exists_for_backend_target "snell" "$s_port" "$conf_file"; }; then
            s_extra=", psk=${s_psk}, version=5${opt_reuse}${opt_tfo}"
            surge_append_links_for_targets_with_user_buckets surge_ip_out_ref surge_ip_map_ref ip_families ip_hosts "${node_name}-snell-v5" "$s_user_name" "snell" "$s_port" "$s_extra"
        fi
    fi

    if is_shadowtls_configured; then
        local st_line st_service st_port st_target st_backend st_sni st_pass st_version
        while IFS= read -r st_line; do
            [[ -n "$st_line" ]] || continue
            IFS='|' read -r st_service st_port st_target st_backend st_sni st_pass <<< "$st_line"
            [[ "$st_port" =~ ^[0-9]+$ ]] || continue
            [[ "$st_target" =~ ^[0-9]+$ ]] || continue
            [[ -n "$st_sni" && -n "$st_pass" ]] || continue
            st_version="$(shadowtls_protocol_version "$st_service" 2>/dev/null || true)"
            [[ "$st_version" =~ ^[23]$ ]] || st_version="2"

            if [[ "$st_backend" == "snell" && -f "$SNELL_CONF" ]]; then
                local snell_psk snell_user_name snell_extra
                snell_psk=$(grep "^psk" "$SNELL_CONF" | cut -d= -f2 | tr -d ' ')
                [[ -n "$snell_psk" ]] || continue
                if (( filter_all == 0 )); then
                    proxy_user_matches_filter "snell" "snell-v5" "$snell_psk" "" "$target_user" || continue
                fi
                if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
                    snell_user_name="$(proxy_user_link_name_cached "snell" "snell-v5" "$snell_psk" "")"
                else
                    snell_user_name="$(proxy_user_link_name "snell" "snell-v5" "$snell_psk" "")"
                fi
                snell_extra=", psk=${snell_psk}, version=5${opt_reuse}${opt_tfo}, shadow-tls-password=${st_pass}, shadow-tls-sni=${st_sni}, shadow-tls-version=${st_version}"
                surge_append_links_for_targets_with_user_buckets surge_ip_out_ref surge_ip_map_ref ip_families ip_hosts "${node_name}-snell-v5-st" "$snell_user_name" "snell" "$st_port" "$snell_extra"
                continue
            fi

            if [[ "$st_backend" == "ss" && -n "$ss_snapshot_rows" ]]; then
                local proto in_tag port sni _priv _sid alpn ss_method ss_user_id ss_passwd _flow ss_name
                while IFS=$'\037' read -r proto in_tag port sni _priv _sid alpn ss_method ss_user_id ss_passwd _flow ss_name; do
                    [[ "$proto" == "ss" && "$port" == "$st_target" && -n "$ss_method" && -n "$ss_passwd" ]] || continue
                    if (( filter_all == 0 )); then
                        proxy_user_matches_filter "ss" "ss_${st_target}" "$ss_user_id" "$ss_name" "$target_user" || continue
                    fi
                    local ss_user_name ss_passwd_literal ss_extra
                    if declare -F proxy_user_link_name_cached >/dev/null 2>&1; then
                        ss_user_name="$(proxy_user_link_name_cached "ss" "ss_${st_target}" "$ss_user_id" "$ss_name")"
                    else
                        ss_user_name="$(proxy_user_link_name "ss" "ss_${st_target}" "$ss_user_id" "$ss_name")"
                    fi
                    ss_passwd_literal="$(printf '%s' "$ss_passwd" | sed 's/\\/\\\\/g; s/"/\\"/g')"
                    ss_extra=", encrypt-method=${ss_method}, password=\"${ss_passwd_literal}\", shadow-tls-password=${st_pass}, shadow-tls-sni=${st_sni}, shadow-tls-version=${st_version}${opt_udp}"
                    surge_append_links_for_targets_with_user_buckets surge_ip_out_ref surge_ip_map_ref ip_families ip_hosts "${node_name}-ss-st" "$ss_user_name" "ss" "$st_port" "$ss_extra"
                done <<< "$ss_snapshot_rows"
            fi
        done < <(shadowtls_binding_lines "$conf_file")
    fi
}
