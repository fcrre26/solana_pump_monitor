#!/bin/bash

echo "开始安装 Solana Pump Monitor..."

# 检查并安装必要的工具
if ! command -v wget &> /dev/null; then
    echo "安装 wget..."
    apt-get update
    apt-get install wget -y
fi

# 切换到root目录
cd ~

# 下载主要文件
echo "下载监控脚本..."
wget https://raw.githubusercontent.com/fcrre26/solana_pump_monitor/refs/heads/main/monitor.sh
wget https://raw.githubusercontent.com/fcrre26/solana_pump_monitor/refs/heads/main/monitor.py

# 设置执行权限
echo "设置权限..."
chmod +x monitor.sh monitor.py

# 创建必要的目录和文件
echo "创建配置目录..."
mkdir -p ~/.solana_pump
echo '{"addresses":[]}' > ~/.solana_pump/watch_addresses.json

# 配置DNS
echo "配置DNS..."
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

echo "安装完成！"
echo "现在开始运行监控程序..."

# 运行脚本
./monitor.sh
