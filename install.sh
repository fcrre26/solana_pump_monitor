#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 服务名称
SERVICE_NAME="solana-monitor"

# 显示错误并退出
fail() {
    echo -e "${RED}[错误] $1${NC}"
    exit 1
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        fail "未找到命令: $1"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${YELLOW}=== Solana Token Monitor 管理菜单 ===${NC}"
    echo "1. 安装服务"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看服务状态"
    echo "6. 查看日志"
    echo "7. 更新程序"
    echo "8. 卸载服务"
    echo "0. 退出"
    echo
}

# 获取 GitHub Token
get_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${YELLOW}请输入你的 GitHub Token:${NC}"
        read -s GITHUB_TOKEN
        if [ -z "$GITHUB_TOKEN" ]; then
            fail "未提供 GitHub Token，无法继续"
        fi
    fi
    echo -e "${GREEN}GitHub Token 已设置${NC}"
}

# 安装服务
install_service() {
    echo -e "${YELLOW}开始安装服务...${NC}"
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then 
        fail "请使用root权限运行此脚本"
    fi

    # 检查是否已安装
    if [ -f "/usr/local/bin/solana-token-monitor" ]; then
        fail "服务已安装，请先卸载再重新安装"
    fi

    # 安装依赖
    echo "安装依赖..."
    apt-get update || fail "apt-get update 失败"
    apt-get install -y build-essential pkg-config libssl-dev curl git jq || fail "依赖安装失败"

    # 安装 Rust
    if ! command -v rustc &> /dev/null; then
        echo "安装 Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || fail "Rust 安装失败"
        source $HOME/.cargo/env || fail "无法加载 Cargo 环境"
    fi

    # 克隆项目
    INSTALL_DIR="/opt/solana-token-monitor"
    echo "克隆项目..."

    # 获取 GitHub Token
    get_github_token

    git clone https://$GITHUB_TOKEN@github.com/fcrre26/solana-token-monitor.git /tmp/solana-token-monitor || fail "项目克隆失败"
    cd /tmp/solana-token-monitor || fail "无法进入项目目录"

    # 创建服务用户
    if ! id -u solana &> /dev/null; then
        useradd -r -s /bin/false solana || fail "无法创建 solana 用户"
    fi

    # 创建目录
    mkdir -p $INSTALL_DIR/{logs,data,backup} || fail "无法创建安装目录"

    # 编译
    echo "编译项目..."
    cargo build --release || fail "项目编译失败"

    # 复制文件
    cp target/release/solana-token-monitor /usr/local/bin/ || fail "无法复制可执行文件"
    chmod +x /usr/local/bin/solana-token-monitor || fail "无法设置可执行权限"
    cp config.json $INSTALL_DIR/ || fail "无法复制配置文件"
    cp log4rs.yaml $INSTALL_DIR/ || fail "无法复制日志配置文件"

    # 设置权限
    chown -R solana:solana $INSTALL_DIR || fail "无法设置目录权限"
    chmod 640 $INSTALL_DIR/config.json || fail "无法设置配置文件权限"

    # 创建日志目录
    mkdir -p /var/log/solana-token-monitor || fail "无法创建日志目录"
    chown solana:solana /var/log/solana-token-monitor || fail "无法设置日志目录权限"

    # 安装服务
    cp solana-monitor.service /etc/systemd/system/ || fail "无法复制服务文件"
    systemctl daemon-reload || fail "无法重新加载 systemd"
    systemctl enable $SERVICE_NAME || fail "无法启用服务"

    # 清理
    cd / || fail "无法返回根目录"
    rm -rf /tmp/solana-token-monitor || fail "无法清理临时目录"

    echo -e "${GREEN}安装完成!${NC}"
}

# 启动服务
start_service() {
    echo "启动服务..."
    systemctl start $SERVICE_NAME || fail "无法启动服务"
    sleep 2
    systemctl status $SERVICE_NAME
}

# 停止服务
stop_service() {
    echo "停止服务..."
    systemctl stop $SERVICE_NAME || fail "无法停止服务"
    sleep 2
    systemctl status $SERVICE_NAME
}

# 重启服务
restart_service() {
    echo "重启服务..."
    systemctl restart $SERVICE_NAME || fail "无法重启服务"
    sleep 2
    systemctl status $SERVICE_NAME
}

# 查看状态
check_status() {
    systemctl status $SERVICE_NAME
    read -p "按回车继续..."
}

# 查看日志
view_logs() {
    echo "查看日志 (Ctrl+C 退出)..."
    journalctl -u $SERVICE_NAME -f
}

# 更新程序
update_service() {
    echo -e "${YELLOW}开始更新...${NC}"
    cd /tmp
    get_github_token
    git clone https://$GITHUB_TOKEN@github.com/fcrre26/solana-token-monitor.git || fail "项目克隆失败"
    cd solana-token-monitor
    cargo build --release || fail "项目编译失败"
    systemctl stop $SERVICE_NAME || fail "无法停止服务"
    cp target/release/solana-token-monitor /usr/local/bin/ || fail "无法复制可执行文件"
    systemctl start $SERVICE_NAME || fail "无法启动服务"
    cd /
    rm -rf /tmp/solana-token-monitor || fail "无法清理临时目录"
    echo -e "${GREEN}更新完成!${NC}"
    sleep 2
}

# 卸载服务
uninstall_service() {
    echo -e "${YELLOW}开始卸载...${NC}"
    systemctl stop $SERVICE_NAME || fail "无法停止服务"
    systemctl disable $SERVICE_NAME || fail "无法禁用服务"
    rm /etc/systemd/system/solana-monitor.service || fail "无法删除服务文件"
    rm /usr/local/bin/solana-token-monitor || fail "无法删除可执行文件"
    rm -rf /opt/solana-token-monitor || fail "无法删除安装目录"
    userdel solana || fail "无法删除 solana 用户"
    systemctl daemon-reload || fail "无法重新加载 systemd"
    echo -e "${GREEN}卸载完成!${NC}"
    sleep 2
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-8]: " choice
    case $choice in
        1) install_service ;;
        2) start_service ;;
        3) stop_service ;;
        4) restart_service ;;
        5) check_status ;;
        6) view_logs ;;
        7) update_service ;;
        8) uninstall_service ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选择${NC}" ; sleep 2 ;;
    esac
done
