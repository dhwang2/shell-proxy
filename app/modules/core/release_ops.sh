# Release/cache resolution helpers for install, self-update, and runtime update checks.

RELEASE_CACHE_OPS_FILE="${RELEASE_CACHE_OPS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cache_ops.sh}"
if [[ -f "$RELEASE_CACHE_OPS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$RELEASE_CACHE_OPS_FILE"
fi

read_script_source_ref() {
    read_cached_value "$SCRIPT_SOURCE_REF_FILE"
}

write_script_source_ref() {
    local ref="${1:-}"
    [[ -n "$ref" ]] || return 1
    write_cached_value "$SCRIPT_SOURCE_REF_FILE" "$ref"
}

read_proxy_release_tag_cache() {
    read_cached_value "$PROXY_RELEASE_TAG_CACHE_FILE"
}

write_proxy_release_tag_cache() {
    local tag="${1:-}"
    [[ -n "$tag" ]] || return 1
    write_cached_value "$PROXY_RELEASE_TAG_CACHE_FILE" "$tag"
}

read_proxy_repo_commit_cache() {
    read_cached_value "$PROXY_REPO_COMMIT_CACHE_FILE"
}

write_proxy_repo_commit_cache() {
    local commit_sha="${1:-}"
    [[ -n "$commit_sha" ]] || return 1
    write_cached_value "$PROXY_REPO_COMMIT_CACHE_FILE" "$commit_sha"
}

github_api_branch_commit_sha() {
    local repo="$1"
    local branch="$2"
    local connect_timeout="${3:-10}"
    local retry_count="${4:-2}"
    local retry_delay="${5:-1}"

    curl -fsSL --connect-timeout "$connect_timeout" --max-time "$(( connect_timeout * 2 ))" --retry "$retry_count" --retry-delay "$retry_delay" \
        "https://api.github.com/repos/${repo}/branches/${branch}" 2>/dev/null \
        | jq -r '.commit.sha // empty' 2>/dev/null
}

github_api_latest_release_tag() {
    local repo="$1"
    local connect_timeout="${2:-10}"
    local retry_count="${3:-2}"
    local retry_delay="${4:-1}"

    curl -fsSL --connect-timeout "$connect_timeout" --max-time "$(( connect_timeout * 2 ))" --retry "$retry_count" --retry-delay "$retry_delay" \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null
}

github_api_latest_release_version() {
    local repo="$1"
    github_api_latest_release_tag "$repo" | sed 's/^v//'
}

github_redirect_latest_release_tag() {
    local repo="$1"
    local connect_timeout="${2:-10}"
    local retry_count="${3:-2}"
    local retry_delay="${4:-1}"
    curl -fsSLI --connect-timeout "$connect_timeout" --max-time "$(( connect_timeout * 2 ))" --retry "$retry_count" --retry-delay "$retry_delay" \
        -o /dev/null -w '%{url_effective}' \
        "https://github.com/${repo}/releases/latest" 2>/dev/null \
        | sed -nE 's#.*/releases/tag/([^/?]+).*#\1#p'
}

github_redirect_latest_release_version() {
    local repo="$1"
    github_redirect_latest_release_tag "$repo" | sed 's/^v//'
}

resolve_repo_branch_commit_sha_cached() {
    local repo="$1"
    local branch="$2"
    local ttl="${3:-$PROXY_REPO_COMMIT_CACHE_TTL}"
    local commit_sha=""

    commit_sha="$(read_fresh_cached_value "$PROXY_REPO_COMMIT_CACHE_FILE" "$ttl" 2>/dev/null || true)"
    if [[ -n "$commit_sha" ]]; then
        echo "$commit_sha"
        return 0
    fi

    commit_sha="$(github_api_branch_commit_sha "$repo" "$branch" 3 1 1 2>/dev/null || true)"
    if [[ -n "$commit_sha" ]]; then
        write_proxy_repo_commit_cache "$commit_sha" || true
        echo "$commit_sha"
        return 0
    fi

    read_proxy_repo_commit_cache 2>/dev/null || true
}

resolve_latest_github_release_tag_cached() {
    local repo="$1"
    local ttl="${2:-$PROXY_RELEASE_TAG_CACHE_TTL}"
    local tag=""

    tag="$(read_fresh_cached_value "$PROXY_RELEASE_TAG_CACHE_FILE" "$ttl" 2>/dev/null || true)"
    if [[ -n "$tag" ]]; then
        echo "$tag"
        return 0
    fi

    tag="$(github_api_latest_release_tag "$repo" 3 1 1 2>/dev/null || true)"
    if [[ -z "$tag" ]]; then
        tag="$(github_redirect_latest_release_tag "$repo" 3 1 1 2>/dev/null || true)"
    fi
    if [[ -n "$tag" ]]; then
        write_proxy_release_tag_cache "$tag" || true
        echo "$tag"
        return 0
    fi

    read_proxy_release_tag_cache 2>/dev/null || true
}

resolve_latest_github_release_version() {
    local repo="$1"
    local cache_file="${2:-}"
    local fallback_version="${3:-}"
    local version=""

    version="$(github_api_latest_release_version "$repo")" || true
    if [[ -z "$version" ]]; then
        version="$(github_redirect_latest_release_version "$repo")" || true
    fi
    if [[ -n "$version" ]]; then
        [[ -n "$cache_file" ]] && write_cached_value "$cache_file" "$version" || true
        echo "$version"
        return 0
    fi

    if [[ -n "$cache_file" ]]; then
        version="$(read_cached_value "$cache_file")" || true
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    echo "$fallback_version"
}

caddy_version_cache_file() {
    echo "${CADDY_CACHE_DIR}/latest-version"
}

resolve_caddy_release_version() {
    resolve_latest_github_release_version "caddyserver/caddy" "$(caddy_version_cache_file)" "${CADDY_DEFAULT_VERSION}"
}

download_caddy_release_archive() {
    local version="$1"
    local arch="$2"
    local output_path="$3"
    local filename="caddy_${version}_linux_${arch}.tar.gz"
    local cache_path="${CADDY_CACHE_DIR}/${filename}"
    local url="https://github.com/caddyserver/caddy/releases/download/v${version}/${filename}"

    mkdir -p "$(dirname "$output_path")" || return 1
    mkdir -p "${CADDY_CACHE_DIR}" 2>/dev/null || true

    if [[ -s "$cache_path" ]]; then
        cp -f "$cache_path" "$output_path"
        return 0
    fi

    if curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 10 \
        --output "$output_path" "$url"; then
        cp -f "$output_path" "$cache_path" 2>/dev/null || true
        write_cached_value "$(caddy_version_cache_file)" "$version" || true
        return 0
    fi

    if [[ -s "$cache_path" ]]; then
        cp -f "$cache_path" "$output_path"
        return 0
    fi

    return 1
}
