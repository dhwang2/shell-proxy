# Cache utility functions for proxy install/management modules.

read_cached_value() {
    local cache_file="$1"
    [[ -s "$cache_file" ]] || return 1
    tr -d '[:space:]' < "$cache_file"
}

write_cached_value() {
    local cache_file="$1"
    local cache_value="$2"
    [[ -n "$cache_file" ]] || return 1
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null || return 1
    printf '%s\n' "$cache_value" > "$cache_file" 2>/dev/null
}

proxy_file_mtime_epoch() {
    local file="$1"
    [[ -f "$file" ]] || { echo 0; return 0; }
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0
}

read_fresh_cached_value() {
    local cache_file="$1"
    local ttl="${2:-0}"
    local now ts age

    [[ -s "$cache_file" ]] || return 1
    (( ttl > 0 )) || {
        read_cached_value "$cache_file"
        return 0
    }

    now="$(date +%s)"
    ts="$(proxy_file_mtime_epoch "$cache_file")"
    [[ "$ts" =~ ^[0-9]+$ ]] || return 1
    age=$(( now - ts ))
    (( age <= ttl )) || return 1
    read_cached_value "$cache_file"
}
