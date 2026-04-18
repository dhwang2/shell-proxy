#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$SCRIPT_DIR/env.sh" ]]; then
    source "$SCRIPT_DIR/env.sh"
elif [[ -f "/etc/shell-proxy/env.sh" ]]; then
    source "/etc/shell-proxy/env.sh"
else
    echo "错误: 未找到 env.sh"
    exit 1
fi

MODULE_DIR="$SCRIPT_DIR/modules"
if [[ ! -d "$MODULE_DIR" && -d "${WORK_DIR}/modules" ]]; then
    MODULE_DIR="${WORK_DIR}/modules"
fi
if [[ -f "${MODULE_DIR}/core/common_ops.sh" ]]; then
    # shellcheck disable=SC1090
    source "${MODULE_DIR}/core/common_ops.sh"
fi
if [[ -f "${MODULE_DIR}/core/cache_ops.sh" ]]; then
    # shellcheck disable=SC1090
    source "${MODULE_DIR}/core/cache_ops.sh"
fi
if [[ -f "${MODULE_DIR}/core/release_ops.sh" ]]; then
    # shellcheck disable=SC1090
    source "${MODULE_DIR}/core/release_ops.sh"
fi
if [[ -f "${MODULE_DIR}/core/systemd_ops.sh" ]]; then
    source "${MODULE_DIR}/core/systemd_ops.sh"
fi

if [[ "${EUID}" -ne 0 ]]; then
    red "错误: 必须使用 root 用户运行脚本更新。"
    exit 1
fi

SELF_UPDATE_CHAINLOADED="${PROXY_SELF_UPDATE_CHAINLOADED:-0}"
SELF_UPDATE_RESOLVED_REF="${PROXY_SELF_UPDATE_RESOLVED_REF:-}"
SELF_UPDATE_PRECONFIRMED="${PROXY_SELF_UPDATE_PRECONFIRMED:-0}"
SELF_UPDATE_MODE="${1:-repo}"
REPO_SOURCE_SUBDIR="app"

SPINNER_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_IDX=0
spin_tick() {
    printf '\r\033[K %s %s' "${SPINNER_CHARS[$SPINNER_IDX]}" "$1" >&2
    SPINNER_IDX=$(( (SPINNER_IDX + 1) % ${#SPINNER_CHARS[@]} ))
}
spin_clear_line() {
    printf '\r\033[K' >&2
}
spin_done() {
    spin_clear_line
    printf '\n' >&2
}

file_sha256() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | awk '{print $1}'
    else
        openssl dgst -sha256 "$f" | awk '{print $NF}'
    fi
}

format_changed_files_block() {
    local -a files=("$@")
    local rel=""
    for rel in "${files[@]}"; do
        [[ -n "$rel" ]] || continue
        printf '%s\n' "$rel"
    done
}

short_sha256() {
    local f="$1" sha=""
    [[ -f "$f" ]] || { echo "missing"; return 0; }
    sha="$(file_sha256 "$f" 2>/dev/null || true)"
    [[ -n "$sha" ]] || { echo "unknown"; return 0; }
    echo "${sha:0:12}"
}

resolve_update_source() {
    local mode="$1" repo_name="$2"
    local resolved_ref="" source_label="" source_record="" base_url=""

    case "$mode" in
        release)
            resolved_ref="$(resolve_latest_github_release_tag_cached "$repo_name" 300 2>/dev/null || true)"
            if [[ -z "$resolved_ref" ]]; then
                red "未找到可用的 RELEASE 版本"
                return 1
            fi
            base_url="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${resolved_ref}"
            source_label="${repo_name}@release (${resolved_ref})"
            source_record="release:${resolved_ref}"
            ;;
        repo|*)
            resolved_ref="${SELF_UPDATE_RESOLVED_REF:-}"
            if [[ -z "$resolved_ref" ]]; then
                resolved_ref="$(resolve_repo_branch_commit_sha_cached "$repo_name" "$BRANCH" 120 2>/dev/null || true)"
            fi
            if [[ -n "$resolved_ref" ]]; then
                base_url="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${resolved_ref}"
                source_label="${repo_name}@${BRANCH}(${resolved_ref:0:8})"
                source_record="repo:${resolved_ref}"
            else
                base_url="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}"
                source_label="${repo_name}@${BRANCH} (branch-fallback)"
                source_record=""
            fi
            ;;
    esac

    printf '%s\n%s\n%s\n%s\n' "$resolved_ref" "$source_label" "$source_record" "$base_url"
}

script_source_matches_target() {
    local current_ref="$1" target_record="$2" mode="$3" resolved_ref="$4"
    [[ -n "$current_ref" && -n "$target_record" ]] || return 1
    [[ "$current_ref" == "$target_record" ]] && return 0
    if [[ "$mode" == "repo" && -n "$resolved_ref" && "$current_ref" == "$resolved_ref" ]]; then
        return 0
    fi
    return 1
}

short_script_source_display() {
    local ref="${1:-}"
    ref="${ref#repo:}"
    ref="${ref#release:}"
    [[ -n "$ref" ]] || return 1
    printf '%s\n' "${ref:0:8}"
}

repo_source_file_rel_path() {
    local rel="${1:-}"
    [[ -n "$rel" ]] || return 1
    if [[ -n "$REPO_SOURCE_SUBDIR" ]]; then
        printf '%s/%s\n' "$REPO_SOURCE_SUBDIR" "$rel"
    else
        printf '%s\n' "$rel"
    fi
}

repo_source_tree_prefix() {
    if [[ -n "$REPO_SOURCE_SUBDIR" ]]; then
        printf '%s/\n' "$REPO_SOURCE_SUBDIR"
    else
        printf '%s' ""
    fi
}

install_proxy_command_wrapper() {
    cat > /usr/bin/sproxy <<EOF
#!/bin/bash
bash ${WORK_DIR}/management.sh "\$@"
EOF
    chmod +x /usr/bin/sproxy
}

main() {
    local repo_name="${REPO_USER}/${REPO_NAME}"
    local resolved_ref="" source_label="" source_record="" base_url="" current_ref="" ts=""
    local tmp_dir=""
    local -a curl_args=()
    local -a source_info=()
    local source_payload=""
    local preconfirmed_update="${SELF_UPDATE_PRECONFIRMED:-0}"
    local target_label=""
    local display_source_label=""

    if [[ "$SELF_UPDATE_CHAINLOADED" != "1" ]]; then
        green "正在检查脚本更新..."
    fi
    target_label="$( [[ "$SELF_UPDATE_MODE" == "release" ]] && echo "最新 RELEASE" || echo "仓库最新版" )"
    if [[ "$SELF_UPDATE_MODE" == "release" ]]; then
        local latest_release_tag=""
        latest_release_tag="$(resolve_latest_github_release_tag_cached "$repo_name" 300 2>/dev/null || true)"
        [[ -n "$latest_release_tag" ]] && write_proxy_release_tag_cache "$latest_release_tag" || true
    fi
    source_payload="$(resolve_update_source "$SELF_UPDATE_MODE" "$repo_name")" || return 1
    mapfile -t source_info <<< "$source_payload"
    resolved_ref="${source_info[0]:-}"
    source_label="${source_info[1]:-}"
    source_record="${source_info[2]:-}"
    base_url="${source_info[3]:-}"
    if [[ "$SELF_UPDATE_MODE" == "repo" && -n "$resolved_ref" ]]; then
        target_label="(${resolved_ref:0:8})"
    fi
    current_ref="$(read_script_source_ref 2>/dev/null || true)"
    ts="$(date +%s)"

    curl_args=(-fsSL)

    if [[ "$SELF_UPDATE_CHAINLOADED" != "1" ]]; then
        display_source_label="${source_label}"
        if [[ "$SELF_UPDATE_MODE" == "repo" ]]; then
            local current_short=""
            current_short="$(short_script_source_display "$current_ref" 2>/dev/null || true)"
            if [[ -n "$current_short" ]]; then
                display_source_label="(${current_short})"
            fi
        fi
        yellow "shell-proxy:${display_source_label} -> ${target_label}"
    fi
    if script_source_matches_target "$current_ref" "$source_record" "$SELF_UPDATE_MODE" "$resolved_ref"; then
        green "已是最新版本"
        return 0
    fi

    if [[ "$SELF_UPDATE_CHAINLOADED" != "1" && -n "$source_record" && -n "$current_ref" ]]; then
        if [[ ! -t 0 ]]; then
            red "当前调用不是交互式终端，无法确认脚本更新。请通过 sproxy 菜单（shell-proxy）执行脚本更新并手动确认。"
            return 11
        fi
        local yn=""
        read -r -p "发现可更新版本,是否更新? [y/N]: " yn
        [[ "${yn,,}" == "y" ]] || return 0
        preconfirmed_update=1
    fi

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "'"${tmp_dir}"'"' EXIT

    download_rel() {
        local rel="$1" out="$2"
        local source_rel=""
        source_rel="$(repo_source_file_rel_path "$rel")" || return 1
        curl "${curl_args[@]}" "${base_url}/${source_rel}?v=${ts}" -o "$out"
    }

    local remote_env="${tmp_dir}/env.sh"
    local remote_self_update="${tmp_dir}/self_update.sh"
    local -a tracked_rel_paths=()
    local -a tracked_tmp_files=()
    local -a tracked_local_files=()
    local rel_path="" tmp_path="" local_path=""

    spin_tick "下载 env.sh ..."
    download_rel "env.sh" "$remote_env" || { spin_done; red "env.sh 下载失败"; return 1; }
    # shellcheck disable=SC1090
    source "$remote_env"

    while IFS= read -r rel_path; do
        [[ -n "$rel_path" ]] || continue
        tmp_path="${tmp_dir}/${rel_path}"
        local_path="$(proxy_managed_install_path "$rel_path")"
        mkdir -p "$(dirname "$tmp_path")"
        tracked_rel_paths+=("$rel_path")
        tracked_tmp_files+=("$tmp_path")
        tracked_local_files+=("$local_path")
    done < <(proxy_managed_rel_paths)

    spin_tick "下载 self_update.sh ..."
    download_rel "self_update.sh" "$remote_self_update" || { spin_done; red "self_update.sh 下载失败"; return 1; }

    if [[ "$SELF_UPDATE_CHAINLOADED" != "1" ]]; then
        local current_self="${SELF_UPDATE_SCRIPT:-${WORK_DIR}/self_update.sh}"
        local current_sha remote_sha
        current_sha="$(file_sha256 "$current_self" 2>/dev/null || true)"
        remote_sha="$(file_sha256 "$remote_self_update" 2>/dev/null || true)"
        if [[ -n "$remote_sha" && "$remote_sha" != "$current_sha" ]]; then
            spin_done
            chmod +x "$remote_self_update"
            PROXY_SELF_UPDATE_CHAINLOADED=1 \
            PROXY_SELF_UPDATE_PRECONFIRMED="$preconfirmed_update" \
            PROXY_SELF_UPDATE_RESOLVED_REF="$resolved_ref" \
            bash "$remote_self_update" "$SELF_UPDATE_MODE"
            return $?
        fi
    fi

    # ── 增量差分：用 Trees API 获取远端 blob SHA，与本地对比，只下载变更文件 ──
    git_blob_sha1() {
        local f="$1"
        [[ -f "$f" ]] || { echo "missing"; return 0; }
        if command -v git >/dev/null 2>&1; then
            git hash-object "$f" 2>/dev/null || echo "unknown"
        else
            local sz
            sz=$(wc -c < "$f" | tr -d ' ')
            (printf "blob %d\0" "$sz"; cat "$f") | sha1sum 2>/dev/null | awk '{print $1}' || echo "unknown"
        fi
    }

    spin_tick "获取远端文件列表 ..."
    local tree_json="" tree_prefix=""
    local -a api_curl=(-fsSL -H "Accept: application/vnd.github.v3+json")
    tree_prefix="$(repo_source_tree_prefix)"
    tree_json="$(curl "${api_curl[@]}" \
        "https://api.github.com/repos/${repo_name}/git/trees/${resolved_ref}?recursive=1" 2>/dev/null || true)"

    # 构建远端 SHA 映射文件（rel_path\tblob_sha1，每行一个）。
    local remote_sha_file="${tmp_dir}/_remote_shas.tsv"
    local use_tree_diff=0
    : > "$remote_sha_file"
    if [[ -n "$tree_json" ]] && command -v jq >/dev/null 2>&1; then
        echo "$tree_json" | jq -r --arg pfx "$tree_prefix" \
            '.tree[]? | select(.type == "blob") | select(.path | startswith($pfx)) |
             ((.path | ltrimstr($pfx)) + "\t" + .sha)' > "$remote_sha_file" 2>/dev/null || true
        [[ -s "$remote_sha_file" ]] && use_tree_diff=1
    fi

    lookup_remote_sha() {
        local key="$1"
        awk -F'\t' -v k="$key" '$1 == k {print $2; exit}' "$remote_sha_file"
    }

    local -a changed_files=()
    local -a dl_rel_paths=()
    local total_managed=${#tracked_rel_paths[@]}

    if (( use_tree_diff )); then
        # 逐文件比较远端 SHA 与本地 git blob SHA。
        spin_tick "对比本地文件 0/${total_managed} ..."
        local cmp_count=0
        for idx in "${!tracked_rel_paths[@]}"; do
            local rel="${tracked_rel_paths[$idx]}"
            local local_file="${tracked_local_files[$idx]}"
            local rsha=""
            rsha="$(lookup_remote_sha "$rel")"
            local lsha=""
            if [[ -f "$local_file" ]]; then
                lsha="$(git_blob_sha1 "$local_file")"
            fi
            if [[ -z "$rsha" || "$rsha" != "$lsha" ]]; then
                dl_rel_paths+=("$rel")
                changed_files+=("$rel")
            fi
            cmp_count=$((cmp_count + 1))
            (( cmp_count % 10 == 0 )) && spin_tick "对比本地文件 ${cmp_count}/${total_managed} ..."
        done
        spin_clear_line
    else
        # Tree API 不可用，回退到下载全部文件再 SHA256 对比。
        for idx in "${!tracked_rel_paths[@]}"; do
            dl_rel_paths+=("${tracked_rel_paths[$idx]}")
        done
    fi

    if (( use_tree_diff )); then
        if (( ${#dl_rel_paths[@]} == 0 )); then
            [[ -n "$source_record" ]] && write_script_source_ref "$source_record" || true
            green "已是最新版本 (${total_managed} 文件均一致)"
            return 0
        fi
    fi

    # 下载需要更新的文件（并行）。
    local dl_count=${#dl_rel_paths[@]}
    local dl_list_file="${tmp_dir}/_download_list.txt"
    local dl_fail_file="${tmp_dir}/_download_fail"
    local dl_fail_list_file="${tmp_dir}/_download_fail_list.txt"
    : > "$dl_list_file"
    : > "$dl_fail_list_file"
    for rel in "${dl_rel_paths[@]}"; do
        printf '%s\t%s\n' "$rel" "$(repo_source_file_rel_path "$rel")" >> "$dl_list_file"
    done

    spin_tick "下载文件 0/${dl_count} ..."
    _DL_BASE_URL="$base_url" _DL_TS="$ts" _DL_TMP="$tmp_dir" _DL_FAIL_LIST="$dl_fail_list_file" \
    xargs -P 8 -I {} bash -c '
        IFS=$'\''\t'\'' read -r rel source_rel <<<"$1"
        out="${_DL_TMP}/${rel}"
        mkdir -p "$(dirname "$out")"
        curl -fsSL "${_DL_BASE_URL}/${source_rel}?v=${_DL_TS}" -o "$out" 2>/dev/null || {
            touch "${_DL_TMP}/_download_fail"
            printf "%s\n" "$rel" >> "${_DL_FAIL_LIST}"
        }
    ' _ {} < "$dl_list_file" &
    local dl_pid=$!
    local dl_done_count=0
    while kill -0 "$dl_pid" 2>/dev/null; do
        dl_done_count=0
        for rel in "${dl_rel_paths[@]}"; do
            [[ -f "${tmp_dir}/${rel}" ]] && dl_done_count=$((dl_done_count + 1))
        done
        spin_tick "下载文件 ${dl_done_count}/${dl_count} ..."
        sleep 0.3
    done
    wait "$dl_pid" 2>/dev/null || true
    spin_clear_line

    if [[ -f "$dl_fail_file" ]]; then
        if [[ -s "$dl_fail_list_file" ]]; then
            red "下载失败文件:"
            sed '/^[[:space:]]*$/d' "$dl_fail_list_file" | sort -u
        fi
        red "部分文件下载失败，请检查网络后重试。"
        return 1
    fi

    # 全量下载回退时，做 SHA256 对比找出变更文件。
    if (( ! use_tree_diff )); then
        local changed=0
        for idx in "${!tracked_rel_paths[@]}"; do
            local rel="${tracked_rel_paths[$idx]}"
            local tmp_f="${tracked_tmp_files[$idx]}"
            local local_f="${tracked_local_files[$idx]}"
            [[ -f "$tmp_f" ]] || continue
            local r_sha l_sha
            r_sha="$(file_sha256 "$tmp_f" 2>/dev/null || true)"
            l_sha=""
            [[ -f "$local_f" ]] && l_sha="$(file_sha256 "$local_f" 2>/dev/null || true)"
            if [[ -z "$l_sha" || "$r_sha" != "$l_sha" ]]; then
                changed=1
                changed_files+=("$rel")
            fi
        done
        yellow "核心对比: management.sh $(short_sha256 "${WORK_DIR}/management.sh") -> $(short_sha256 "${tmp_dir}/management.sh"), modules/core/config_ops.sh $(short_sha256 "${WORK_DIR}/modules/core/config_ops.sh") -> $(short_sha256 "${tmp_dir}/modules/core/config_ops.sh")"
    fi

    if (( ${#changed_files[@]} == 0 )); then
        [[ -n "$source_record" ]] && write_script_source_ref "$source_record" || true
        green "已是最新版本"
        return 0
    fi

    if (( preconfirmed_update == 0 )) && [[ ! -t 0 ]]; then
        red "当前调用不是交互式终端，无法确认脚本更新。请通过 sproxy 菜单（shell-proxy）执行脚本更新并手动确认。"
        return 11
    fi
    if (( preconfirmed_update == 0 )); then
        local yn=""
        read -r -p "确认更新? [y/N]: " yn
        [[ "${yn,,}" == "y" ]] || return 0
    fi

    yellow "正在更新 ${dl_count}/${total_managed} 个文件"
    format_changed_files_block "${changed_files[@]}"

    mkdir -p "${WORK_DIR}/modules" "${WORK_DIR}/systemd"
    local rel_install="" tmp_install="" local_install=""
    for rel_install in "${changed_files[@]}"; do
        tmp_install="${tmp_dir}/${rel_install}"
        local_install="$(proxy_managed_install_path "$rel_install")"
        [[ -f "$tmp_install" ]] || continue
        mkdir -p "$(dirname "$local_install")"
        install -m 0644 "$tmp_install" "$local_install"
    done
    while IFS= read -r rel_path; do
        [[ -n "$rel_path" ]] || continue
        chmod +x "$(proxy_managed_install_path "$rel_path")"
    done < <(proxy_managed_exec_rel_paths)

    install_proxy_command_wrapper || true

    if proxy_changed_rel_paths_require_menu_bundle_rebuild "${changed_files[@]}"; then
        if ! proxy_rebuild_menu_bundles "$WORK_DIR"; then
            proxy_remove_menu_bundles "$WORK_DIR" || true
            yellow "菜单 bundle 预构建失败，已回退为原始模块加载。"
        fi
    else
        yellow "本轮更新未影响菜单模块，跳过 bundle 重建。"
    fi

    if declare -F write_proxy_watchdog_unit >/dev/null 2>&1; then
        mkdir -p "$LOG_DIR" >/dev/null 2>&1 || true
        touch "$PROXY_WATCHDOG_LOG" >/dev/null 2>&1 || true
        write_proxy_watchdog_unit "$WATCHDOG_SERVICE_FILE" "/bin/bash ${WATCHDOG_SCRIPT}" "${PROXY_WATCHDOG_LOG}" || true
        systemctl daemon-reload || true
        systemctl enable --now proxy-watchdog >/dev/null 2>&1 || true
    fi

    [[ -n "$source_record" ]] && write_script_source_ref "$source_record" || true
    if [[ ! -t 0 || ! -t 1 ]]; then
        green "脚本文件已更新到 ${WORK_DIR}"
        yellow "请重新执行 sproxy 以加载新脚本。"
    fi
    return 10
}

main "$@"
