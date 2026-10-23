#!/bin/bash
# ==============================================
# 一键部署脚本 | 改编自 ellermister/mtproxy.sh
# 兼容：有systemd（真机） / 无systemd（docker容器）Debian/Ubuntu
# 【修复版】彻底消除 timedatectl / systemctl 不存在时报错
# ==============================================

# =====================【改这里：项目基础信息】=====================
SCRIPT_NAME="myweb"
SERVICE_NAME="myweb"
BIN_NAME="myweb"
BIN_RELEASE_URL="https://github.com/xxx/xxx/releases/download/v1.0.0/myweb-linux-amd64"
CONFIG_FILE="/etc/${SERVICE_NAME}/config.conf"
INSTALL_DIR="/usr/local/${SERVICE_NAME}"
PID_FILE="${INSTALL_DIR}/${SERVICE_NAME}.pid"
LOG_FILE="${INSTALL_DIR}/${SERVICE_NAME}.log"
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

# 时间同步：修复！不存在timedatectl时一行都不执行
check_time() {
    info "检测系统时间同步状态"
    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true
        sleep 1
        TIME_SYNC=$(timedatectl | grep "System clock synchronized:" | awk '{print $4}')
        if [[ "${TIME_SYNC}" != "yes" ]]; then
            warn "时间同步暂时未就绪，若后续下载失败请手动校准时间"
        else
            info "系统时间同步正常"
        fi
    else
        warn "当前环境无 timedatectl，跳过时间同步检测（容器环境），校时命令示例：date -s '2026-10-23 15:00:00'"
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

# 生成systemd服务单元（仅在确认有systemctl的时候才调用！）
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

# ============ 启动逻辑：自动分支 ============
start() {
    check_root
    if command -v systemctl &>/dev/null; then
        info "检测到 systemd 环境，生成服务单元"
        gen_systemd
        systemctl start ${SERVICE_NAME}
        sleep 0.5
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            info "${SERVICE_NAME} 启动成功（systemd）"
        else
            error "${SERVICE_NAME} 启动失败，请查看日志：journalctl -u ${SERVICE_NAME}"
        fi
    else
        # 无systemd容器环境：nohup后台
        if [[ -f ${PID_FILE} ]]; then
            local oldpid=$(cat ${PID_FILE})
            if kill -0 ${oldpid} 2>/dev/null; then
                warn "程序已经在运行，pid: ${oldpid}"
                return
            fi
            rm -f ${PID_FILE}
        fi
        info "使用 nohup 后台启动（无systemd容器环境）"
        nohup ${INSTALL_DIR}/${BIN_NAME} -c ${CONFIG_FILE} > ${LOG_FILE} 2>&1 &
        echo $! > ${PID_FILE}
        sleep 0.5
        info "${SERVICE_NAME} 启动成功，pid=$(cat ${PID_FILE})，日志：${LOG_FILE}"
    fi
}

# 停止
stop() {
    check_root
    if command -v systemctl &>/dev/null; then
        systemctl stop ${SERVICE_NAME}
        info "${SERVICE_NAME} 已停止（systemd）"
    else
        if [[ -f ${PID_FILE} ]]; then
            local pid=$(cat ${PID_FILE})
            if kill -0 ${pid} 2>/dev/null; then
                kill ${pid}
                sleep 0.3
                kill -0 ${pid} 2>/dev/null && kill -9 ${pid}
            fi
            rm -f ${PID_FILE}
            info "${SERVICE_NAME} 已停止"
        else
            warn "没有找到运行pid"
        fi
    fi
}

# 重启
restart() {
    check_root
    stop
    sleep 0.5
    start
}

# 状态查看
status() {
    check_root
    if command -v systemctl &>/dev/null; then
        systemctl status ${SERVICE_NAME}
    else
        if [[ -f ${PID_FILE} ]]; then
            local pid=$(cat ${PID_FILE})
            if kill -0 ${pid} 2>/dev/null; then
                info "运行中，pid: ${pid}"
            else
                warn "pid文件存在，但进程已经退出"
                rm -f ${PID_FILE}
            fi
        else
            warn "程序未运行"
        fi
    fi
}

# 安装流程【重点：安装阶段不再碰systemd！】
install() {
    check_root
    check_arch
    check_time
    download_bin
    gen_config
    info "安装完成！"
    info "启动命令：$0 start"
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
    stop
    if command -v systemctl &>/dev/null; then
        systemctl disable ${SERVICE_NAME}
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        systemctl daemon-reload
    fi
    rm -rf ${INSTALL_DIR}
    rm -f ${CONFIG_FILE}
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
