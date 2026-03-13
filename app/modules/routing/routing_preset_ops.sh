# Routing preset metadata, ruleset synchronization, and rule build support operations.

COMMON_OPS_FILE="${COMMON_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../core/common_ops.sh}"
if [[ -f "$COMMON_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_OPS_FILE"
fi

ROUTING_AUTOCONFIG_OPS_FILE="${ROUTING_AUTOCONFIG_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_autoconfig_ops.sh}"
if [[ -f "$ROUTING_AUTOCONFIG_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_AUTOCONFIG_OPS_FILE"
fi

ROUTING_OPS_FILE="${ROUTING_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/routing_ops.sh}"
if [[ -f "$ROUTING_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTING_OPS_FILE"
fi

ROUTING_PRESET_FIELD_SEP=$'\x1f'

if ! declare -p ROUTING_BUILD_RULES_RESULT_CACHE 2>/dev/null | grep -q 'declare -A'; then
    declare -gA ROUTING_BUILD_RULES_RESULT_CACHE=()
fi
ROUTING_BUILD_RULES_RESULT_CACHE_FP="${ROUTING_BUILD_RULES_RESULT_CACHE_FP:-}"

routing_build_rules_cache_dir() {
    echo "${CACHE_DIR}/routing/build-rules"
}

routing_build_rules_cache_write_atomic() {
    local path="${1:-}" content="${2-}" tmp_file
    [[ -n "$path" ]] || return 1
    mkdir -p "$(dirname "$path")" >/dev/null 2>&1 || return 1
    tmp_file="$(mktemp)"
    printf '%s' "$content" >"$tmp_file"
    mv -f "$tmp_file" "$path"
}

routing_build_rules_cache_file_for_key() {
    local prefix="${1:-}" raw_key="${2:-}" cache_key
    [[ -n "$prefix" ]] || return 1
    cache_key="$(printf '%s' "${prefix}|${raw_key}" | cksum 2>/dev/null | awk '{print $1"-"$2}')"
    printf '%s\n' "$(routing_build_rules_cache_dir)/${prefix}-${cache_key}.cache"
}

routing_build_rules_ruleset_tags_cache_file() {
    local conf_file="${1:-}"
    routing_build_rules_cache_file_for_key "ruleset-tags" "$conf_file"
}

routing_build_rules_result_cache_file() {
    local cache_key="${1:-}"
    routing_build_rules_cache_file_for_key "result" "$cache_key"
}

routing_collect_conf_ruleset_tag_lines() {
    local conf_file="${1:-}" conf_fp cache_file cached_fp tag_lines=""
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0

    conf_fp="$(calc_file_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    cache_file="$(routing_build_rules_ruleset_tags_cache_file "$conf_file" 2>/dev/null || true)"
    if [[ -n "$cache_file" && -f "$cache_file" ]]; then
        IFS= read -r cached_fp <"$cache_file"
        if [[ -n "$cached_fp" && "$cached_fp" == "$conf_fp" ]]; then
            tail -n +2 "$cache_file" 2>/dev/null || true
            return 0
        fi
    fi

    tag_lines="$(jq -r '.route.rule_set[]?.tag // empty | select(length > 0)' "$conf_file" 2>/dev/null | sort -u || true)"
    routing_build_rules_cache_write_atomic "$cache_file" "$(printf '%s\n%s' "$conf_fp" "$tag_lines")" >/dev/null 2>&1 || true
    [[ -n "$tag_lines" ]] && printf '%s\n' "$tag_lines"
}

routing_conf_ruleset_fingerprint() {
    local conf_file="${1:-}" tag_lines
    [[ -n "$conf_file" && -f "$conf_file" ]] || { echo "0:0"; return 0; }
    tag_lines="$(routing_collect_conf_ruleset_tag_lines "$conf_file" 2>/dev/null || true)"
    printf '%s' "$tag_lines" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

routing_build_rules_cache_refresh_if_needed() {
    local conf_file="${1:-}" ruleset_fp
    ruleset_fp="$(routing_conf_ruleset_fingerprint "$conf_file" 2>/dev/null || echo "0:0")"
    [[ -n "$ruleset_fp" ]] || ruleset_fp="0:0"
    if [[ "$ROUTING_BUILD_RULES_RESULT_CACHE_FP" != "$ruleset_fp" ]]; then
        ROUTING_BUILD_RULES_RESULT_CACHE=()
        ROUTING_BUILD_RULES_RESULT_CACHE_FP="$ruleset_fp"
    fi
    printf '%s\n' "$ruleset_fp"
}

routing_state_json_fingerprint() {
    local state_json="${1:-[]}"
    printf '%s' "$state_json" | cksum 2>/dev/null | awk '{print $1":"$2}'
}

routing_trim_token() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

routing_json_array_from_lines() {
    local lines="${1:-}" line out="[" first=1
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if (( first == 0 )); then
            out+=","
        fi
        first=0
        out+="\"$(routing_json_escape_string "$line")\""
    done <<<"$lines"
    out+="]"
    printf '%s\n' "$out"
}

routing_json_escape_string() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

routing_print_route_rule_with_rule_set() {
    local outbound="${1:-}" tag="${2:-}"
    printf '{"rule_set":["%s"],"action":"route","outbound":"%s"}\n' \
        "$(routing_json_escape_string "$tag")" \
        "$(routing_json_escape_string "$outbound")"
}

routing_print_route_rule_with_domain_suffix() {
    local outbound="${1:-}" domain_suffix_json="${2:-[]}"
    printf '{"domain_suffix":%s,"action":"route","outbound":"%s"}\n' \
        "${domain_suffix_json:-[]}" \
        "$(routing_json_escape_string "$outbound")"
}

routing_print_route_rule_all() {
    local outbound="${1:-}"
    printf '{"action":"route","outbound":"%s"}\n' "$(routing_json_escape_string "$outbound")"
}

routing_state_entry_rows() {
    local state_json="${1:-[]}"
    jq -r --arg sep "$ROUTING_PRESET_FIELD_SEP" '
        .[]?
        | [(.type // ""), (.outbound // ""), (.domains // "")]
        | join($sep)
    ' <<<"${state_json:-[]}" 2>/dev/null
}

routing_add_unique_tag() {
    local tag="${1:-}" seen_name="$2" geosite_name="$3" other_name="$4" geoip_name="$5"
    [[ -n "$tag" ]] || return 0

    local -n seen_ref="$seen_name"
    local -n geosite_ref="$geosite_name"
    local -n other_ref="$other_name"
    local -n geoip_ref="$geoip_name"

    [[ -n "${seen_ref[$tag]+x}" ]] && return 0
    seen_ref["$tag"]=1

    case "$tag" in
        geosite-*) geosite_ref+=("$tag") ;;
        geoip-*) geoip_ref+=("$tag") ;;
        *) other_ref+=("$tag") ;;
    esac
}

routing_collect_conf_ruleset_tags() {
    local conf_file="$1" assoc_name="$2"
    local -n assoc_ref="$assoc_name"
    local tag=""
    assoc_ref=()
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        assoc_ref["$tag"]=1
    done < <(routing_collect_conf_ruleset_tag_lines "$conf_file")
}

routing_preset_label() {
    local t="$1"
    case "$t" in
        openai) echo "OpenAI/ChatGPT" ;;
        anthropic) echo "Anthropic/Claude" ;;
        google) echo "Google" ;;
        netflix) echo "Netflix" ;;
        disney) echo "Disney+" ;;
        mytvsuper) echo "MyTVSuper" ;;
        youtube) echo "YouTube" ;;
        spotify) echo "Spotify" ;;
        tiktok) echo "TikTok" ;;
        telegram) echo "Telegram" ;;
        twitter) echo "Twitter/X" ;;
        whatsapp) echo "WhatsApp" ;;
        facebook) echo "Facebook" ;;
        discord) echo "Discord" ;;
        instagram) echo "Instagram" ;;
        reddit) echo "Reddit" ;;
        linkedin) echo "LinkedIn" ;;
        paypal) echo "PayPal" ;;
        microsoft) echo "Microsoft" ;;
        xai) echo "xAI/Grok" ;;
        meta) echo "Meta" ;;
        messenger) echo "Messenger" ;;
        github) echo "GitHub" ;;
        ads) echo "广告屏蔽" ;;
        ai-intl) echo "AI服务(国际)" ;;
        custom) echo "自定义" ;;
        all) echo "所有流量" ;;
        *) echo "$t" ;;
    esac
}

routing_preset_label_colored() {
    local t="$1"
    local label
    label="$(routing_preset_label "$t")"
    case "$t" in
        openai|anthropic|ai-intl) routing_colorize "35;1" "$label" ;;
        google|youtube|github|netflix|disney|mytvsuper|spotify|tiktok|microsoft|paypal) routing_colorize "34;1" "$label" ;;
        telegram|twitter|whatsapp|facebook|discord|instagram|reddit|linkedin|meta|messenger) routing_colorize "33;1" "$label" ;;
        xai) routing_colorize "35;1" "$label" ;;
        ads) routing_colorize "31;1" "$label" ;;
        custom) routing_colorize "37;1" "$label" ;;
        all) routing_colorize "31;1" "$label" ;;
        *) routing_colorize "37;1" "$label" ;;
    esac
}

routing_preset_meta() {
    local t="$1"
    case "$t" in
        openai) echo "geosite-openai|openai.com,chatgpt.com,oaistatic.com" ;;
        anthropic) echo "geosite-anthropic|anthropic.com,claude.ai" ;;
        google) echo "geosite-google|google.com,gstatic.com,googleapis.com,googlevideo.com|geoip-google" ;;
        netflix) echo "geosite-netflix|netflix.com,nflxvideo.net,nflximg.net,nflxso.net,nflxext.com|geoip-netflix" ;;
        disney) echo "geosite-disney|disneyplus.com,dssott.com,bamgrid.com,disney.com" ;;
        mytvsuper) echo "geosite-mytvsuper|mytvsuper.com,tvb.com" ;;
        youtube) echo "geosite-youtube|youtube.com,youtu.be,googlevideo.com" ;;
        spotify) echo "geosite-spotify|spotify.com,scdn.co,spotifycdn.com" ;;
        tiktok) echo "geosite-tiktok|tiktok.com,tiktokv.com,tiktokcdn.com" ;;
        telegram) echo "geosite-telegram|telegram.org,t.me|geoip-telegram" ;;
        twitter) echo "geosite-twitter|twitter.com,x.com,twimg.com|geoip-twitter" ;;
        whatsapp) echo "geosite-whatsapp|whatsapp.com,whatsapp.net" ;;
        facebook) echo "geosite-facebook|facebook.com,fbcdn.net,messenger.com|geoip-facebook" ;;
        discord) echo "geosite-discord|discord.com,discord.gg,discordapp.com,discordapp.net" ;;
        instagram) echo "geosite-instagram|instagram.com,cdninstagram.com" ;;
        reddit) echo "geosite-reddit|reddit.com,redd.it,redditmedia.com" ;;
        linkedin) echo "geosite-linkedin|linkedin.com,licdn.com" ;;
        paypal) echo "geosite-paypal|paypal.com,paypalobjects.com" ;;
        microsoft) echo "geosite-microsoft|microsoft.com,live.com,outlook.com,office.com,msauth.net,msftauth.net" ;;
        xai) echo "geosite-xai|x.ai,grok.com" ;;
        meta) echo "geosite-meta|meta.com,fb.com" ;;
        messenger) echo "geosite-messenger|messenger.com,m.me" ;;
        github) echo "geosite-github|github.com,githubusercontent.com" ;;
        ads) echo "geosite-category-ads-all|doubleclick.net,googlesyndication.com,googleadservices.com,adservice.google.com,googletagmanager.com" ;;
        ai-intl) echo "geosite-category-ai-!cn|openai.com,anthropic.com,claude.ai,chatgpt.com|geoip-ai" ;;
        *) echo "" ;;
    esac
}

routing_required_ruleset_tags_from_state() {
    local state_json="${1:-[]}"
    local row="" t="" out="" domains="" meta="" tag="" ip_tag="" token="" mapped=""
    local tag_lines=""
    declare -A seen_tags=()
    local -a geosite_tags=() other_tags=() geoip_tags=()

    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS="$ROUTING_PRESET_FIELD_SEP" read -r t out domains <<<"$row"
        case "$t" in
            ""|all)
                continue
                ;;
            custom)
                [[ -z "$domains" ]] && continue
                local -a _parts
                IFS=',' read -r -a _parts <<<"$domains"
                for token in "${_parts[@]}"; do
                    token="$(routing_trim_token "$token")"
                    [[ -z "$token" ]] && continue
                    mapped=""
                    case "$token" in
                        geosite:*)
                            mapped="geosite-${token#geosite:}"
                            ;;
                        geoip:*)
                            mapped="geoip-${token#geoip:}"
                            ;;
                    esac
                    routing_add_unique_tag "$mapped" seen_tags geosite_tags other_tags geoip_tags
                done
                ;;
            *)
                meta="$(routing_preset_meta "$t")"
                [[ -z "$meta" ]] && continue
                IFS='|' read -r tag _ ip_tag <<< "$meta"
                routing_add_unique_tag "$tag" seen_tags geosite_tags other_tags geoip_tags
                routing_add_unique_tag "$ip_tag" seen_tags geosite_tags other_tags geoip_tags
                ;;
        esac
    done < <(routing_state_entry_rows "$state_json")

    local _tag
    for _tag in "${geosite_tags[@]}" "${other_tags[@]}" "${geoip_tags[@]}"; do
        [[ -n "$_tag" ]] || continue
        tag_lines+="${_tag}"$'\n'
    done

    routing_json_array_from_lines "$tag_lines" | jq -c '
        unique
        | (
            map(select(startswith("geosite-")))
            + map(select((startswith("geosite-") or startswith("geoip-")) | not))
            + map(select(startswith("geoip-")))
          )
    ' 2>/dev/null || echo "[]"
}

routing_sync_required_rule_sets() {
    local conf_file="$1" state_json="${2:-[]}"
    [[ -n "$conf_file" && -f "$conf_file" ]] || return 1

    local required_tags catalog_json tmp_json
    required_tags="$(routing_required_ruleset_tags_from_state "$state_json")"
    [[ -z "$required_tags" ]] && required_tags="[]"
    catalog_json="$(auto_rule_set_catalog_json)"
    [[ -z "$catalog_json" ]] && catalog_json="[]"

    tmp_json="$(mktemp)"
    jq --argjson required "$required_tags" --argjson catalog "$catalog_json" '
        .route = (.route // {})
        | .route.rule_set = (
            (
              ((.route.rule_set // []) as $current
              | (
                  $current
                  | map(
                      . as $item
                      | if ((($item.type? // "") != "") or (($item.url? // "") != "") or (($item.path? // "") != "")) then
                          $item
                        else
                          ([ $catalog[]? | select(.tag == ($item.tag // "")) ] | .[0]) // empty
                        end
                    )
                ) as $normalized
              | reduce ($required[]?) as $tag ($normalized;
                    if ([ .[]?.tag ] | index($tag)) != null then
                        .
                    else
                        . + ([ $catalog[]? | select(.tag == $tag) ] | .[0:1])
                    end
                )
              )
              | unique_by(.tag)
            )
            | (
                map(select((.tag // "") | startswith("geosite-")))
                + map(select((.tag // "") as $t | (($t | startswith("geosite-")) or ($t | startswith("geoip-"))) | not))
                + map(select((.tag // "") | startswith("geoip-")))
              )
          )
    ' "$conf_file" > "$tmp_json" 2>/dev/null || true

    if [[ -s "$tmp_json" ]] && jq . "$tmp_json" >/dev/null 2>&1; then
        if ! cmp -s "$tmp_json" "$conf_file"; then
            mv "$tmp_json" "$conf_file"
            return 10
        fi
        rm -f "$tmp_json"
        return 0
    fi

    rm -f "$tmp_json"
    return 1
}

routing_conf_has_ruleset_tag() {
    local conf_file="$1" tag="$2"
    [[ -n "$conf_file" && -f "$conf_file" && -n "$tag" ]] || return 1
    jq -e --arg tag "$tag" '.route.rule_set[]? | select(.tag == $tag)' "$conf_file" >/dev/null 2>&1
}

routing_build_custom_rule() {
    local outbound="$1" domains="$2"
    local ds_lines="" dk_lines="" ip_lines=""
    local token part

    IFS=',' read -r -a parts <<<"$domains"
    for part in "${parts[@]}"; do
        token="$(routing_trim_token "$part")"
        [[ -z "$token" ]] && continue

        case "$token" in
            keyword:*)
                dk_lines+="${token#keyword:}"$'\n'
                ;;
            geosite:*|geoip:*)
                dk_lines+="$token"$'\n'
                ;;
            *:*)
                if [[ "$token" == */* ]]; then
                    ip_lines+="$token"$'\n'
                elif [[ "$token" =~ ^[0-9a-fA-F:]+$ ]]; then
                    ip_lines+="${token}/128"$'\n'
                else
                    token="${token#.}"
                    ds_lines+="$token"$'\n'
                fi
                ;;
            *)
                if [[ "$token" =~ ^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
                    if [[ "$token" == */* ]]; then
                        ip_lines+="$token"$'\n'
                    else
                        ip_lines+="${token}/32"$'\n'
                    fi
                elif [[ "$token" == *"/"* && "$token" =~ ^[0-9./]+$ ]]; then
                    ip_lines+="$token"$'\n'
                elif [[ "$token" == *"."* ]]; then
                    token="${token#.}"
                    ds_lines+="$token"$'\n'
                else
                    dk_lines+="$token"$'\n'
                fi
                ;;
        esac
    done

    [[ -n "$ds_lines$dk_lines$ip_lines" ]] || { echo ""; return 0; }

    local ds_json dk_json ip_json out_json rule_json
    ds_json="$(routing_json_array_from_lines "$ds_lines")"
    dk_json="$(routing_json_array_from_lines "$dk_lines")"
    ip_json="$(routing_json_array_from_lines "$ip_lines")"
    [[ -n "$ds_json" ]] || ds_json="[]"
    [[ -n "$dk_json" ]] || dk_json="[]"
    [[ -n "$ip_json" ]] || ip_json="[]"

    out_json="$(routing_json_escape_string "$outbound")"
    rule_json="{\"action\":\"route\",\"outbound\":\"${out_json}\""
    if [[ "$ds_json" != "[]" ]]; then
        rule_json+=",\"domain_suffix\":${ds_json}"
    fi
    if [[ "$dk_json" != "[]" ]]; then
        rule_json+=",\"domain_keyword\":${dk_json}"
    fi
    if [[ "$ip_json" != "[]" ]]; then
        rule_json+=",\"ip_cidr\":${ip_json}"
    fi
    rule_json+="}"
    printf '%s\n' "$rule_json"
}

routing_build_rule_objects_from_fields() {
    local t="$1" out="$2" domains="$3" conf_file="${4:-}" ruleset_tags_name="${5:-}"
    [[ -n "$t" && -n "$out" ]] || return 0

    if [[ "$t" == "all" ]]; then
        routing_print_route_rule_all "$out"
        return 0
    fi

    if [[ "$t" == "custom" ]]; then
        local custom_rule
        custom_rule="$(routing_build_custom_rule "$out" "$domains")"
        if [[ -n "$custom_rule" && "$custom_rule" != "null" ]]; then
            printf '%s\n' "$custom_rule"
        fi
        return 0
    fi

    local meta tag fallback ip_tag ds_json geosite_ok geoip_ok
    meta="$(routing_preset_meta "$t")"
    [[ -n "$meta" ]] || return 0
    IFS='|' read -r tag fallback ip_tag <<< "$meta"

    geosite_ok=0
    geoip_ok=0
    if [[ -n "$ruleset_tags_name" ]]; then
        local -n ruleset_tags_ref="$ruleset_tags_name"
        [[ -n "$tag" && -n "${ruleset_tags_ref[$tag]+x}" ]] && geosite_ok=1
        [[ -n "$ip_tag" && -n "${ruleset_tags_ref[$ip_tag]+x}" ]] && geoip_ok=1
    else
        [[ -n "$tag" ]] && routing_conf_has_ruleset_tag "$conf_file" "$tag" && geosite_ok=1
        [[ -n "$ip_tag" ]] && routing_conf_has_ruleset_tag "$conf_file" "$ip_tag" && geoip_ok=1
    fi

    if (( geosite_ok == 1 )); then
        routing_print_route_rule_with_rule_set "$out" "$tag"
    fi
    if (( geoip_ok == 1 )); then
        routing_print_route_rule_with_rule_set "$out" "$ip_tag"
    fi
    if (( geosite_ok == 1 || geoip_ok == 1 )); then
        return 0
    fi

    ds_json="$(routing_json_array_from_lines "$(printf '%s' "$fallback" | tr ',' '\n')")"
    routing_print_route_rule_with_domain_suffix "$out" "$ds_json"
}

routing_build_rules_from_state() {
    local state_json="${1:-[]}" conf_file="$2"
    local row="" t="" out="" domains="" tmp_rules=""
    local ruleset_fp state_fp cache_key compiled_rules cache_file
    declare -A ruleset_tags=()

    ruleset_fp="$(routing_build_rules_cache_refresh_if_needed "$conf_file" 2>/dev/null || echo "0:0")"
    state_fp="$(routing_state_json_fingerprint "$state_json" 2>/dev/null || echo "0:0")"
    cache_key="${ruleset_fp}|${state_fp}"
    if [[ -n "${ROUTING_BUILD_RULES_RESULT_CACHE[$cache_key]+x}" ]]; then
        printf '%s\n' "${ROUTING_BUILD_RULES_RESULT_CACHE[$cache_key]}"
        return 0
    fi
    cache_file="$(routing_build_rules_result_cache_file "$cache_key" 2>/dev/null || true)"
    if [[ -n "$cache_file" && -f "$cache_file" ]]; then
        compiled_rules="$(cat "$cache_file" 2>/dev/null || true)"
        if [[ -n "$compiled_rules" ]]; then
            ROUTING_BUILD_RULES_RESULT_CACHE["$cache_key"]="$compiled_rules"
            printf '%s\n' "$compiled_rules"
            return 0
        fi
    fi

    tmp_rules="$(mktemp)"
    routing_collect_conf_ruleset_tags "$conf_file" ruleset_tags

    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        IFS="$ROUTING_PRESET_FIELD_SEP" read -r t out domains <<<"$row"
        [[ -n "$t" && -n "$out" ]] || continue
        routing_build_rule_objects_from_fields "$t" "$out" "$domains" "$conf_file" ruleset_tags >> "$tmp_rules"
    done < <(routing_state_entry_rows "$state_json")

    if [[ ! -s "$tmp_rules" ]]; then
        rm -f "$tmp_rules"
        ROUTING_BUILD_RULES_RESULT_CACHE["$cache_key"]="[]"
        echo "[]"
        return 0
    fi

    compiled_rules="$(jq -s -c '
        def is_geosite_rule:
            ((.rule_set? // null) | type) == "array"
            and ((.rule_set | length) > 0)
            and all(.rule_set[]; startswith("geosite-"));
        def is_geoip_rule:
            ((.rule_set? // null) | type) == "array"
            and ((.rule_set | length) > 0)
            and all(.rule_set[]; startswith("geoip-"));
        def is_domain_match_rule:
            ((.rule_set? // null) | type) != "array"
            and (
                has("domain")
                or has("domain_suffix")
                or has("domain_keyword")
                or has("domain_regex")
            );
        def uniq_preserve:
            reduce .[] as $x ([]; if index($x) == null then . + [$x] else . end);
        def merge_by_outbound:
            reduce .[] as $r ([]; 
                if ([ .[]?.outbound ] | index($r.outbound)) == null then
                    . + [$r]
                else
                    map(
                        if .outbound == $r.outbound then
                            .rule_set = (((.rule_set // []) + ($r.rule_set // [])) | uniq_preserve)
                        else
                            .
                        end
                    )
                end
            );
        (map(select(is_domain_match_rule))) as $dm
        |
        (map(select(is_geosite_rule)) | merge_by_outbound) as $gs
        | (map(select(is_geoip_rule)) | merge_by_outbound) as $gi
        | (map(select((is_domain_match_rule or is_geosite_rule or is_geoip_rule) | not))) as $other
        | ($dm + $gs + $gi + $other)
    ' "$tmp_rules" 2>/dev/null || cat "$tmp_rules")"
    rm -f "$tmp_rules"

    [[ -n "$compiled_rules" ]] || compiled_rules="[]"
    ROUTING_BUILD_RULES_RESULT_CACHE["$cache_key"]="$compiled_rules"
    routing_build_rules_cache_write_atomic "$cache_file" "$compiled_rules" >/dev/null 2>&1 || true
    printf '%s\n' "$compiled_rules"
}
