#!/bin/bash
# ==============================================
# 一键部署脚本 | 改编自 ellermister/mtproxy.sh
# 适配 Debian / Ubuntu
# Author: Modified
# ==============================================

# =====================【改这里：项目基础信息】=====================
SCRIPT_NAME="myweb"
SERVICE_NAME="myweb"
BIN_NAME="myweb"
BIN_RELEASE_URL="https://github.com/xxx/xxx/releases/download/v1.0.0/myweb-linux-amd64"
CONFIG_FILE="/etc/${SERVICE_NAME}/config.conf"
INSTALL_DIR="/usr/local/${SERVICE_NAME}"
# =================================================================

# 颜色定义（和原版mtproxy.sh保持一致）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO] $*${NC}"
}
warn() {
    echo -e "${YELLOW}[WARN] $*${NC}"
}
error() {
    echo -e "${RED}[ERROR] $*${NC}"
}

# 必须root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 用户执行脚本"
        exit 1
    fi
}

# 检测系统架构
check_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            BIN_ARCH="amd64"
            ;;
        aarch64)
            BIN_ARCH="arm64"
            ;;
        *)
            error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    info "检测架构: ${BIN_ARCH}"
}

# 时间同步（替换原版ntpdate，兼容新版Debian）
check_time() {
    info "检测系统时间同步状态"
    timedatectl set-ntp true
    sleep 1
    TIME_SYNC=$(timedatectl | grep "System clock synchronized:" | awk '{print $4}')
    if [[ "${TIME_SYNC}" != "yes" ]]; then
        warn "时间同步暂时未就绪，若后续下载失败请手动校准时间：timedatectl set-timezone Asia/Shanghai"
    else
        info "系统时间同步正常"
    fi
}

# 下载二进制
download_bin() {
    mkdir -p ${INSTALL_DIR}
    local BIN_FULL_URL=${BIN_RELEASE_URL}
    info "开始下载程序: ${BIN_FULL_URL}"
    if ! curl -L --progress-bar -o ${INSTALL_DIR}/${BIN_NAME} ${BIN_FULL_URL}; then
        error "二进制文件下载失败，请检查网络/下载地址"
        exit 1
    fi
    chmod +x ${INSTALL_DIR}/${BIN_NAME}
    info "二进制下载 + 授权完成"
}

# 生成默认配置文件【改这里：你的配置模板】
gen_config() {
    mkdir -p $(dirname ${CONFIG_FILE})
    if [[ ! -f ${CONFIG_FILE} ]]; then
        cat > ${CONFIG_FILE} << EOF
# myweb 配置文件
listen = ":8080"
debug = false
EOF
        info "已生成默认配置文件：${CONFIG_FILE}"
    else
        warn "配置文件已存在，跳过生成"
    fi
}

# 生成systemd服务单元
gen_systemd() {
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=${SERVICE_NAME} web service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${BIN_NAME} -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# 安装流程
install() {
    check_root
    check_arch
    check_time
    download_bin
    gen_config
    gen_systemd
    info "安装完成！"
    info "启动命令：$0 start"
}

# 启动
start() {
    check_root
    systemctl start ${SERVICE_NAME}
    sleep 0.5
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        info "${SERVICE_NAME} 启动成功"
    else
        error "${SERVICE_NAME} 启动失败，请查看日志：journalctl -u ${SERVICE_NAME}"
    fi
}

# 停止
stop() {
    check_root
    systemctl stop ${SERVICE_NAME}
    info "${SERVICE_NAME} 已停止"
}

# 重启
restart() {
    check_root
    systemctl restart ${SERVICE_NAME}
    info "${SERVICE_NAME} 已重启"
}

# 状态
status() {
    check_root
    systemctl status ${SERVICE_NAME}
}

# 卸载
uninstall() {
    check_root
    warn "即将卸载，是否继续？[y/N]"
    read -r ans
    if [[ "${ans}" != "y" && "${ans}" != "Y" ]]; then
        info "取消卸载"
        exit 0
    fi
    systemctl stop ${SERVICE_NAME}
    systemctl disable ${SERVICE_NAME}
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    rm -rf ${INSTALL_DIR}
    rm -f ${CONFIG_FILE}
    systemctl daemon-reload
    info "卸载完成"
}

# 主菜单
menu() {
    echo "====================================="
    echo "          ${SCRIPT_NAME} 一键脚本"
    echo "====================================="
    echo "  1. 安装"
    echo "  2. 启动"
    echo "  3. 停止"
    echo "  4. 重启"
    echo "  5. 查看状态"
    echo "  6. 卸载"
    echo "====================================="
    read -p "请输入选择: " opt
    case ${opt} in
        1) install ;;
        2) start ;;
        3) stop ;;
        4) restart ;;
        5) status ;;
        6) uninstall ;;
        *) error "输入错误" ;;
    esac
}

# 参数入口
case "$1" in
    install) install ;;
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    status) status ;;
    uninstall) uninstall ;;
    *) menu ;;
esac
