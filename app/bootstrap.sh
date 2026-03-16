#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# shell-proxy 公开仓库引导安装脚本
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/dhwang2/shell-proxy/main/app/bootstrap.sh | bash

REPO_USER="dhwang2"
REPO_NAME="shell-proxy"
BRANCH="main"
REPO_SOURCE_SUBDIR="app"

red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }

echo "================================================="
echo "   shell-proxy 自动化部署"
echo "================================================="

INSTALL_DIR="/tmp/proxy-install"
ARCHIVE_FILE="${INSTALL_DIR}/proxy-install.tar.gz"
INSTALL_SRC_DIR=""

cleanup() {
    cd / >/dev/null 2>&1 || true
    rm -rf "$INSTALL_DIR"
}
trap cleanup EXIT

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

download_file() {
    local url="$1" out="$2"
    local http_code="" attempt=1 max_attempts=4
    local -a curl_args=(
        -s
        -w "%{http_code}"
        --connect-timeout 10
        --retry 2
        --retry-all-errors
        -L
        -o "$out"
    )
    curl_args+=("$url")

    while (( attempt <= max_attempts )); do
        http_code="$(curl "${curl_args[@]}" || true)"
        if [[ "$http_code" == "200" ]]; then
            return 0
        fi
        if (( attempt < max_attempts )); then
            yellow "下载重试($attempt/$max_attempts): $url [HTTP ${http_code:-000}]"
            sleep 1
        fi
        ((attempt++))
    done

    red "下载失败: $url"
    red "HTTP 状态码: ${http_code:-000}"
    if [[ -s "$out" ]]; then
        echo "服务器返回内容:"
        cat "$out"
    fi
    return 1
}

resolve_repo_ref() {
    local api_url="https://api.github.com/repos/${REPO_USER}/${REPO_NAME}/commits/${BRANCH}"
    local response=""
    response="$(curl -fsSL "$api_url" 2>/dev/null || true)"
    printf '%s\n' "$response" | sed -n 's/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' | head -n 1
}

download_repo_archive() {
    local repo_ref="$1" out="$2"
    local archive_url="https://api.github.com/repos/${REPO_USER}/${REPO_NAME}/tarball/${repo_ref}"
    download_file "$archive_url" "$out"
}

extract_install_tree() {
    local archive_file="$1" extract_dir="$2" extracted_root=""
    rm -rf "$extract_dir/extracted"
    mkdir -p "$extract_dir/extracted"
    tar -xzf "$archive_file" -C "$extract_dir/extracted"
    extracted_root="$(find "$extract_dir/extracted" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [[ -n "$extracted_root" && -d "$extracted_root" ]] || return 1
    if [[ -n "$REPO_SOURCE_SUBDIR" && -d "$extracted_root/$REPO_SOURCE_SUBDIR" ]]; then
        INSTALL_SRC_DIR="$extracted_root/$REPO_SOURCE_SUBDIR"
    else
        INSTALL_SRC_DIR="$extracted_root"
    fi
    [[ -f "$INSTALL_SRC_DIR/install.sh" ]] || return 1
    return 0
}

echo "正在准备安装源:${REPO_USER}/${REPO_NAME}@${BRANCH}"
REPO_REF="$(resolve_repo_ref)"
if [[ -n "$REPO_REF" ]]; then
    green "正在准备安装源:${REPO_USER}/${REPO_NAME}@${BRANCH} (${REPO_REF:0:12})"
else
    red "解析仓库提交失败: ${REPO_USER}/${REPO_NAME}@${BRANCH}"
    exit 1
fi

green "正在拉取安装归档和依赖..."
download_repo_archive "$REPO_REF" "$ARCHIVE_FILE" || exit 1
extract_install_tree "$ARCHIVE_FILE" "$INSTALL_DIR" || {
    red "解压安装包失败"
    exit 1
}

chmod +x "$INSTALL_SRC_DIR/install.sh"
cd "$INSTALL_SRC_DIR"
if ! PROXY_INSTALL_BOOTSTRAP_REF="${REPO_REF}" PROXY_INSTALL_BOOTSTRAP_SOURCE_DIR="$INSTALL_SRC_DIR" bash install.sh; then
    red "安装失败，请根据上方日志排查。"
    exit 1
fi
