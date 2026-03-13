# Bundle build and rebuild helpers for shell-proxy management.

proxy_remove_menu_bundles_impl() {
    local root_dir="${1:-$WORK_DIR}" group="" rel_path="" target_path=""
    while IFS= read -r group; do
        [[ -n "$group" ]] || continue
        rel_path="$(proxy_bundle_rel_path "$group" 2>/dev/null || true)"
        [[ -n "$rel_path" ]] || continue
        target_path="${root_dir}/${rel_path}"
        rm -f "$target_path" 2>/dev/null || true
    done < <(proxy_bundle_group_names)
    rmdir "${root_dir}/bundles" >/dev/null 2>&1 || true
}

proxy_rebuild_menu_bundle_impl() {
    local root_dir="${1:-$WORK_DIR}" group="${2:-}" rel_path="" target_path="" tmp_path="" bundle_shell=""
    local timeout_bin="" timeout_seconds=""
    [[ -n "$group" ]] || return 1
    rel_path="$(proxy_bundle_rel_path "$group" 2>/dev/null || true)"
    [[ -n "$rel_path" ]] || return 1
    target_path="${root_dir}/${rel_path}"
    mkdir -p "$(dirname "$target_path")" >/dev/null 2>&1 || return 1
    tmp_path="$(mktemp)"
    bundle_shell="${BASH:-bash}"
    timeout_seconds="${PROXY_BUNDLE_BUILD_TIMEOUT_SECONDS:-15}"
    [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || timeout_seconds=15
    if command -v timeout >/dev/null 2>&1; then
        timeout_bin="timeout"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_bin="gtimeout"
    fi

    if [[ -n "$timeout_bin" ]]; then
        if ! PROXY_BUNDLE_ROOT_DIR="$root_dir" PROXY_BUNDLE_GROUP_NAME="$group" "$timeout_bin" "$timeout_seconds" "$bundle_shell" >"$tmp_path" <<'EOF'
set -Eeuo pipefail
IFS=$'\n\t'

if ! declare -p PROXY_BUNDLE_SOURCED_FILE_GUARD 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_BUNDLE_SOURCED_FILE_GUARD=()
fi

proxy_bundle_source_guard_key() {
    local target="${1:-}" abs_target="" resolved_dir=""
    [[ -n "$target" ]] || return 1
    if [[ "$target" != /* ]]; then
        abs_target="${PWD}/${target}"
    else
        abs_target="$target"
    fi
    resolved_dir="$(cd "$(dirname "$abs_target")" 2>/dev/null && pwd -P)" || resolved_dir=""
    if [[ -n "$resolved_dir" ]]; then
        printf '%s/%s\n' "$resolved_dir" "$(basename "$abs_target")"
        return 0
    fi
    printf '%s\n' "$abs_target"
}

source() {
    local target="${1:-}" key="" rc=0
    if [[ -z "$target" ]]; then
        builtin source "$@"
        return $?
    fi
    key="$(proxy_bundle_source_guard_key "$target" 2>/dev/null || printf '%s\n' "$target")"
    if [[ -n "${PROXY_BUNDLE_SOURCED_FILE_GUARD[$key]+x}" ]]; then
        return 0
    fi
    PROXY_BUNDLE_SOURCED_FILE_GUARD["$key"]=1
    builtin source "$@"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        unset 'PROXY_BUNDLE_SOURCED_FILE_GUARD[$key]'
    fi
    return "$rc"
}

__bundle_root="${PROXY_BUNDLE_ROOT_DIR:?}"
__bundle_group="${PROXY_BUNDLE_GROUP_NAME:?}"

source "${__bundle_root}/env.sh"
MODULE_DIR="${__bundle_root}/modules"

if [[ "${__bundle_group}" != "base" ]]; then
    mapfile -t __bundle_base_modules < <(proxy_base_module_rel_paths)
    for __bundle_rel in "${__bundle_base_modules[@]}"; do
        source "${__bundle_root}/${__bundle_rel}"
    done
fi

mapfile -t __bundle_before_funcs < <(compgen -A function | LC_ALL=C sort)
mapfile -t __bundle_before_vars < <(compgen -v | LC_ALL=C sort)
mapfile -t __bundle_group_modules < <(proxy_bundle_source_module_rel_paths "${__bundle_group}")

for __bundle_rel in "${__bundle_group_modules[@]}"; do
    [[ -f "${__bundle_root}/${__bundle_rel}" ]] || {
        echo "missing bundle source: ${__bundle_rel}" >&2
        exit 1
    }
    source "${__bundle_root}/${__bundle_rel}"
done

mapfile -t __bundle_after_funcs < <(compgen -A function | LC_ALL=C sort)
mapfile -t __bundle_after_vars < <(compgen -v | LC_ALL=C sort)

printf '#!/bin/bash\n'
printf '# Prebuilt shell-proxy menu bundle: %s\n' "${__bundle_group}"
printf '# Generated during install/self-update. Do not edit manually.\n\n'

while IFS= read -r __bundle_name; do
    __bundle_decl=""
    case "${__bundle_name}" in
        BASH*|DIRSTACK|EUID|GROUPS|HISTCMD|HOSTNAME|HOSTTYPE|IFS|LINENO|MACHTYPE|OLDPWD|OPTERR|OPTIND|OSTYPE|PATH|PIPESTATUS|PPID|PWD|RANDOM|SECONDS|SHELLOPTS|SHLVL|UID|_)
            continue
            ;;
        __bundle_*)
            continue
            ;;
    esac
    __bundle_decl="$(declare -p "${__bundle_name}" 2>/dev/null || true)"
    [[ -n "${__bundle_decl}" ]] || continue
    printf '%s\n' "${__bundle_decl/#declare /declare -g }"
done < <(
    comm -13 \
        <(printf '%s\n' "${__bundle_before_vars[@]}") \
        <(printf '%s\n' "${__bundle_after_vars[@]}")
)

while IFS= read -r __bundle_line; do
    [[ -n "${__bundle_line}" ]] || continue
    printf '%s\n' "${__bundle_line}"
done < <(proxy_bundle_prelude_lines "${__bundle_group}")

printf '\n'

while IFS= read -r __bundle_name; do
    [[ -n "${__bundle_name}" ]] || continue
    declare -f "${__bundle_name}"
    printf '\n'
done < <(
    comm -13 \
        <(printf '%s\n' "${__bundle_before_funcs[@]}") \
        <(printf '%s\n' "${__bundle_after_funcs[@]}")
)
EOF
        then
            rm -f "$tmp_path" 2>/dev/null || true
            return 1
        fi
    else
        if ! PROXY_BUNDLE_ROOT_DIR="$root_dir" PROXY_BUNDLE_GROUP_NAME="$group" "$bundle_shell" >"$tmp_path" <<'EOF'
set -Eeuo pipefail
IFS=$'\n\t'

if ! declare -p PROXY_BUNDLE_SOURCED_FILE_GUARD 2>/dev/null | grep -q 'declare -A'; then
    declare -gA PROXY_BUNDLE_SOURCED_FILE_GUARD=()
fi

proxy_bundle_source_guard_key() {
    local target="${1:-}" abs_target="" resolved_dir=""
    [[ -n "$target" ]] || return 1
    if [[ "$target" != /* ]]; then
        abs_target="${PWD}/${target}"
    else
        abs_target="$target"
    fi
    resolved_dir="$(cd "$(dirname "$abs_target")" 2>/dev/null && pwd -P)" || resolved_dir=""
    if [[ -n "$resolved_dir" ]]; then
        printf '%s/%s\n' "$resolved_dir" "$(basename "$abs_target")"
        return 0
    fi
    printf '%s\n' "$abs_target"
}

source() {
    local target="${1:-}" key="" rc=0
    if [[ -z "$target" ]]; then
        builtin source "$@"
        return $?
    fi
    key="$(proxy_bundle_source_guard_key "$target" 2>/dev/null || printf '%s\n' "$target")"
    if [[ -n "${PROXY_BUNDLE_SOURCED_FILE_GUARD[$key]+x}" ]]; then
        return 0
    fi
    PROXY_BUNDLE_SOURCED_FILE_GUARD["$key"]=1
    builtin source "$@"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        unset 'PROXY_BUNDLE_SOURCED_FILE_GUARD[$key]'
    fi
    return "$rc"
}

__bundle_root="${PROXY_BUNDLE_ROOT_DIR:?}"
__bundle_group="${PROXY_BUNDLE_GROUP_NAME:?}"

source "${__bundle_root}/env.sh"
MODULE_DIR="${__bundle_root}/modules"

if [[ "${__bundle_group}" != "base" ]]; then
    mapfile -t __bundle_base_modules < <(proxy_base_module_rel_paths)
    for __bundle_rel in "${__bundle_base_modules[@]}"; do
        source "${__bundle_root}/${__bundle_rel}"
    done
fi

mapfile -t __bundle_before_funcs < <(compgen -A function | LC_ALL=C sort)
mapfile -t __bundle_before_vars < <(compgen -v | LC_ALL=C sort)
mapfile -t __bundle_group_modules < <(proxy_bundle_source_module_rel_paths "${__bundle_group}")

for __bundle_rel in "${__bundle_group_modules[@]}"; do
    [[ -f "${__bundle_root}/${__bundle_rel}" ]] || {
        echo "missing bundle source: ${__bundle_rel}" >&2
        exit 1
    }
    source "${__bundle_root}/${__bundle_rel}"
done

mapfile -t __bundle_after_funcs < <(compgen -A function | LC_ALL=C sort)
mapfile -t __bundle_after_vars < <(compgen -v | LC_ALL=C sort)

printf '#!/bin/bash\n'
printf '# Prebuilt shell-proxy menu bundle: %s\n' "${__bundle_group}"
printf '# Generated during install/self-update. Do not edit manually.\n\n'

while IFS= read -r __bundle_name; do
    __bundle_decl=""
    case "${__bundle_name}" in
        BASH*|DIRSTACK|EUID|GROUPS|HISTCMD|HOSTNAME|HOSTTYPE|IFS|LINENO|MACHTYPE|OLDPWD|OPTERR|OPTIND|OSTYPE|PATH|PIPESTATUS|PPID|PWD|RANDOM|SECONDS|SHELLOPTS|SHLVL|UID|_)
            continue
            ;;
        __bundle_*)
            continue
            ;;
    esac
    __bundle_decl="$(declare -p "${__bundle_name}" 2>/dev/null || true)"
    [[ -n "${__bundle_decl}" ]] || continue
    printf '%s\n' "${__bundle_decl/#declare /declare -g }"
done < <(
    comm -13 \
        <(printf '%s\n' "${__bundle_before_vars[@]}") \
        <(printf '%s\n' "${__bundle_after_vars[@]}")
)

while IFS= read -r __bundle_line; do
    [[ -n "${__bundle_line}" ]] || continue
    printf '%s\n' "${__bundle_line}"
done < <(proxy_bundle_prelude_lines "${__bundle_group}")

printf '\n'

while IFS= read -r __bundle_name; do
    [[ -n "${__bundle_name}" ]] || continue
    declare -f "${__bundle_name}"
    printf '\n'
done < <(
    comm -13 \
        <(printf '%s\n' "${__bundle_before_funcs[@]}") \
        <(printf '%s\n' "${__bundle_after_funcs[@]}")
)
EOF
        then
            rm -f "$tmp_path" 2>/dev/null || true
            return 1
        fi
    fi

    if ! "$bundle_shell" -n "$tmp_path" >/dev/null 2>&1; then
        rm -f "$tmp_path" 2>/dev/null || true
        return 1
    fi

    install -m 0644 "$tmp_path" "$target_path"
    rm -f "$tmp_path" 2>/dev/null || true
}

proxy_rebuild_menu_bundles_impl() {
    local root_dir="${1:-$WORK_DIR}" group=""
    while IFS= read -r group; do
        [[ -n "$group" ]] || continue
        proxy_rebuild_menu_bundle_impl "$root_dir" "$group" || return 1
    done < <(proxy_bundle_group_names)
}
