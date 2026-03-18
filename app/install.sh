#!/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# 安装脚本 (由 bootstrap.sh 引导调用)

# 加载环境
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/modules/core/release_ops.sh"
source "$(dirname "$0")/modules/core/systemd_ops.sh"

REPO_SOURCE_SUBDIR="app"

on_error() {
    local line_no="${1:-unknown}"
    local cmd="${2:-unknown}"
    red "安装失败: line=${line_no}, cmd=${cmd}"
}

trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        red "缺少依赖命令: $cmd"
        exit 1
    fi
}

download_file() {
    local url="$1"
    local output="$2"
    curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 10 \
        --output "$output" "$url"
}

prepare_temp_dir() {
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        red "错误: 必须使用 root 用户运行此脚本！\n"
        exit 1
    fi
}

check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    else
        release="linux"
    fi
    
    # 检查架构
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) red "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
}

install_dependencies() {
    if [[ "${release}" == "centos" ]]; then
        yum install -y tar jq curl unzip ca-certificates
    else
        apt-get update
        apt-get install -y tar jq curl unzip ca-certificates
    fi
    require_cmd curl
    require_cmd jq
    require_cmd tar
    require_cmd unzip
}

get_latest_version() {
    resolve_latest_github_release_version "SagerNet/sing-box" "${CACHE_DIR}/sing-box/latest-version" "1.10.0"
}

install_singbox_core() {
    local version=$(get_latest_version)
    green "安装 sing-box v${version}..."
    
    prepare_temp_dir
    mkdir -p "$BIN_DIR" "$CONF_DIR" "$LOG_DIR"
    
    local filename="sing-box-${version}-linux-${ARCH}.tar.gz"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${filename}"
    
    download_file "$download_url" "${TEMP_DIR}/${filename}"
    tar -zxf "${TEMP_DIR}/${filename}" -C "$TEMP_DIR"
    local extracted_bin
    extracted_bin="$(find "$TEMP_DIR" -name sing-box -type f | head -n 1)"
    if [[ -z "$extracted_bin" || ! -f "$extracted_bin" ]]; then
        red "未找到 sing-box 可执行文件，安装中止"
        return 1
    fi
    
    install -m 755 "$extracted_bin" "$BIN_FILE"
    rm -rf "$TEMP_DIR"
}

install_snell() {
    local version="5.0.1"
    green "安装 snell-v5 v${version}..."
    
    prepare_temp_dir
    mkdir -p "$BIN_DIR"
    
    local snell_arch="${ARCH}"
    [[ "${ARCH}" == "arm64" ]] && snell_arch="aarch64"

    local filename="snell-server-v${version}-linux-${snell_arch}.zip"
    local download_url="https://dl.nssurge.com/snell/${filename}"
    
    download_file "$download_url" "${TEMP_DIR}/${filename}"
    unzip -o "${TEMP_DIR}/${filename}" -d "$TEMP_DIR"
    if [[ ! -f "${TEMP_DIR}/snell-server" ]]; then
        red "未找到 snell-server 可执行文件，安装中止"
        return 1
    fi
    
    install -m 755 "${TEMP_DIR}/snell-server" "$SNELL_BIN"
    rm -rf "$TEMP_DIR"
}

install_shadowtls() {
    green "安装 shadow-tls-v3..."
    # 获取最新版
    local st_version
    st_version="$(curl -fsSL "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//')" || true
    st_version=${st_version:-0.2.25}
    
    local st_arch="x86_64-unknown-linux-musl"
    [[ "${ARCH}" == "arm64" ]] && st_arch="aarch64-unknown-linux-musl"
    
    # 修正: shadow-tls-v3 提供的是直接二进制文件，不是压缩包
    local filename="shadow-tls-${st_arch}"
    local download_url="https://github.com/ihciah/shadow-tls/releases/download/v${st_version}/${filename}"
    
    prepare_temp_dir
    download_file "$download_url" "${TEMP_DIR}/${filename}"
    
    if [[ ! -f "${TEMP_DIR}/${filename}" ]]; then
        red "错误: 下载 shadow-tls 失败"
        return 1
    fi
    
    install -m 755 "${TEMP_DIR}/${filename}" "$ST_BIN"
    rm -rf "$TEMP_DIR"
}

install_caddy() {
    green "安装 caddy..."
    local version fallback_version archive_path
    version="$(resolve_caddy_release_version)"
    fallback_version="${CADDY_DEFAULT_VERSION}"

    mkdir -p "$BIN_DIR" "$LOG_DIR" "$WORK_DIR/caddy"

    prepare_temp_dir
    archive_path="${TEMP_DIR}/caddy.tar.gz"

    if ! download_caddy_release_archive "$version" "$ARCH" "$archive_path"; then
        if [[ "$version" != "$fallback_version" ]]; then
            yellow "caddy 最新版本下载失败，回退到 v${fallback_version} 重试..."
            version="$fallback_version"
            download_caddy_release_archive "$version" "$ARCH" "$archive_path" || {
                red "caddy 下载失败"
                return 1
            }
        else
            red "caddy 下载失败"
            return 1
        fi
    fi

    if [[ -f "$archive_path" ]]; then
        tar -zxf "$archive_path" -C "$(dirname "$CADDY_BIN")" caddy >/dev/null 2>&1
        rm -f "$archive_path"
        chmod +x "$CADDY_BIN"
        if ! "$CADDY_BIN" version >/dev/null 2>&1; then
            red "caddy 安装失败"
            return 1
        fi
    else
        red "caddy 下载失败"
        return 1
    fi
}

create_services() {
    mkdir -p "$LOG_DIR" "$WORK_DIR/caddy"
    touch \
        "$SINGBOX_SERVICE_LOG" \
        "$SNELL_SERVICE_LOG" \
        "$SHADOWTLS_SERVICE_LOG" \
        "$CADDY_SUB_SERVICE_LOG" \
        "$PROXY_SCRIPT_LOG" \
        "$PROXY_WATCHDOG_LOG" \
        >/dev/null 2>&1 || true

    write_singbox_unit "$SERVICE_FILE" "${BIN_FILE} run -C ${CONF_DIR}"
    write_snell_unit "$SNELL_SERVICE_FILE" "${SNELL_BIN} -c ${SNELL_CONF}"
    # 如果已存在可用的 shadow-tls-v3 配置，避免安装流程覆盖现网参数。
    if [[ -f "$ST_SERVICE_FILE" ]] && grep -q "server --listen" "$ST_SERVICE_FILE"; then
        yellow "检测到已配置的 shadow-tls-v3 unit，保留现有配置。"
    else
        write_shadowtls_unit "$ST_SERVICE_FILE" "/bin/false"
    fi
    write_proxy_watchdog_unit "$WATCHDOG_SERVICE_FILE" "/bin/bash ${WATCHDOG_SCRIPT}" "${PROXY_WATCHDOG_LOG}"

    systemctl daemon-reload
    # 默认不启用服务：避免未完成协议配置就自动启动导致失败或产生“默认配置”误解。
}

install_control_script() {
    mkdir -p "$WORK_DIR" "${WORK_DIR}/modules" "${WORK_DIR}/systemd"
    local repo_ref="" repo_name="${REPO_USER}/${REPO_NAME}"
    local rel_path="" dest_path="" install_src_dir="" source_path="" source_real="" dest_real=""
    repo_ref="${PROXY_INSTALL_BOOTSTRAP_REF:-}"
    install_src_dir="${PROXY_INSTALL_BOOTSTRAP_SOURCE_DIR:-}"
    if [[ -z "$repo_ref" || -z "$install_src_dir" || ! -d "$install_src_dir" || ! -f "$install_src_dir/env.sh" ]]; then
        install_src_dir="$(dirname "$0")"
        repo_ref=""
    fi
    while IFS= read -r rel_path; do
        [[ -n "$rel_path" ]] || continue
        source_path="${install_src_dir}/${rel_path}"
        dest_path="$(proxy_managed_install_path "$rel_path")"
        mkdir -p "$(dirname "$dest_path")"
        source_real="$(cd "$(dirname "$source_path")" 2>/dev/null && pwd -P)/$(basename "$source_path")"
        dest_real="$(cd "$(dirname "$dest_path")" 2>/dev/null && pwd -P)/$(basename "$dest_path")"
        if [[ "$source_real" == "$dest_real" ]]; then
            continue
        fi
        install -m 0644 "$source_path" "$dest_path"
    done < <(proxy_managed_rel_paths)
    [[ -n "$repo_ref" ]] && write_script_source_ref "$repo_ref" || true
    while IFS= read -r rel_path; do
        [[ -n "$rel_path" ]] || continue
        chmod +x "$(proxy_managed_install_path "$rel_path")"
    done < <(proxy_managed_exec_rel_paths)

    cat > /usr/bin/sproxy <<EOF
#!/bin/bash
bash ${WORK_DIR}/management.sh "\$@"
EOF
    chmod +x /usr/bin/sproxy
    rm -f /usr/bin/proxy

    if ! proxy_rebuild_menu_bundles "$WORK_DIR"; then
        proxy_remove_menu_bundles "$WORK_DIR" || true
        yellow "菜单 bundle 预构建失败，将回退为原始模块加载。"
    fi
}

main() {
    check_root
    check_sys
    install_dependencies
    install_singbox_core
    install_snell
    install_shadowtls
    install_caddy
    create_services
    install_control_script
    systemctl enable --now proxy-watchdog >/dev/null 2>&1 || yellow "watchdog 启动失败，可后续手动执行: systemctl restart proxy-watchdog"
    
    green "安装完成！"
    sleep 1
    if [[ -t 0 && -t 1 ]]; then
        sproxy menu
    else
        yellow "检测到非交互终端，已跳过菜单。快捷指令(shell-proxy): sproxy"
    fi
}

main
