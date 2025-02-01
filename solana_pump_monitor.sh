#!/bin/bash

#===========================================
# 基础配置模块
#===========================================
# Solana Pump.fun智能监控系统 v4.0
# 功能：全自动监控+市值分析+多API轮询+智能RPC管理+多通道通知

CONFIG_FILE="$HOME/.solana_pump.cfg"
LOG_FILE="$HOME/pump_monitor.log"
PY_SCRIPT="$HOME/pump_monitor.py"
RPC_FILE="$HOME/.solana_pump.rpc"
PIDFILE="/tmp/solana_pump_monitor.pid"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

#===========================================
# 配置管理模块
#===========================================
init_config() {
    echo -e "${YELLOW}>>> 配置API密钥 (支持多个，每行一个)${RESET}"
    echo -e "${YELLOW}>>> 输入完成后请按Ctrl+D结束${RESET}"
    api_keys=$(cat)
    
    # 创建默认配置
    config='{
        "api_keys": [],
        "serverchan": {
            "keys": []
        },
        "wcf": {
            "groups": []
        }
    }'
    
    # 添加API密钥
    for key in $api_keys; do
        if [ ! -z "$key" ]; then
            config=$(echo $config | jq --arg key "$key" '.api_keys += [$key]')
        fi
    done
    
    echo $config > $CONFIG_FILE
    chmod 600 $CONFIG_FILE
    echo -e "\n${GREEN}✓ 配置已保存到 $CONFIG_FILE${RESET}"
}

# 依赖安装
install_dependencies() {
    echo -e "${YELLOW}>>> 检查系统依赖...${RESET}"
    
    if command -v apt &>/dev/null; then
        PKG_MGR="apt"
        sudo apt update
    elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
    else
        echo -e "${RED}✗ 不支持的系统!${RESET}"
        exit 1
    fi

    sudo $PKG_MGR install -y python3 python3-pip jq
    pip3 install requests wcferry

    echo -e "${GREEN}✓ 依赖安装完成${RESET}"
}

#===========================================
# 通知系统模块
#===========================================
setup_notification() {
    while true; do
        echo -e "\n${YELLOW}>>> 通知设置${RESET}"
        echo "1. Server酱设置"
        echo "2. WeChatFerry设置"
        echo "3. 测试通知"
        echo "4. 返回主菜单"
        echo -n "请选择 [1-4]: "
        read choice
        
        case $choice in
            1)
                setup_serverchan
                ;;
            2)
                setup_wcf
                ;;
            3)
                test_notification
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}无效选项!${RESET}"
                ;;
        esac
    done
}

# Server酱设置
setup_serverchan() {
    while true; do
        echo -e "\n${YELLOW}>>> Server酱设置${RESET}"
        echo "1. 添加Server酱密钥"
        echo "2. 删除Server酱密钥"
        echo "3. 查看当前密钥"
        echo "4. 返回上级菜单"
        echo -n "请选择 [1-4]: "
        read choice
        
        case $choice in
            1)
                echo -e "${YELLOW}>>> 请输入Server酱密钥：${RESET}"
                read -s key
                echo
                if [ ! -z "$key" ]; then
                    config=$(cat $CONFIG_FILE)
                    config=$(echo $config | jq --arg key "$key" '.serverchan.keys += [$key]')
                    echo $config > $CONFIG_FILE
                    echo -e "${GREEN}✓ Server酱密钥已添加${RESET}"
                fi
                ;;
            2)
                config=$(cat $CONFIG_FILE)
                keys=$(echo $config | jq -r '.serverchan.keys[]')
                if [ ! -z "$keys" ]; then
                    echo -e "\n当前密钥列表："
                    i=1
                    while read -r key; do
                        echo "$i. ${key:0:8}...${key: -8}"
                        i=$((i+1))
                    done <<< "$keys"
                    
                    echo -e "\n${YELLOW}>>> 请输入要删除的密钥编号：${RESET}"
                    read num
                    if [[ $num =~ ^[0-9]+$ ]]; then
                        config=$(echo $config | jq "del(.serverchan.keys[$(($num-1))])")
                        echo $config > $CONFIG_FILE
                        echo -e "${GREEN}✓ 密钥已删除${RESET}"
                    else
                        echo -e "${RED}无效的编号${RESET}"
                    fi
                else
                    echo -e "${YELLOW}没有已保存的密钥${RESET}"
                fi
                ;;
            3)
                config=$(cat $CONFIG_FILE)
                keys=$(echo $config | jq -r '.serverchan.keys[]')
                if [ ! -z "$keys" ]; then
                    echo -e "\n当前密钥列表："
                    i=1
                    while read -r key; do
                        echo "$i. ${key:0:8}...${key: -8}"
                        i=$((i+1))
                    done <<< "$keys"
                else
                    echo -e "${YELLOW}没有已保存的密钥${RESET}"
                fi
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}无效选项!${RESET}"
                ;;
        esac
    done
}

# WeChatFerry设置
setup_wcf() {
    # 检查WeChatFerry是否已安装
    if ! python3 -c "import wcferry" 2>/dev/null; then
        echo -e "${YELLOW}>>> 正在安装WeChatFerry...${RESET}"
        pip3 install wcferry
        
        echo -e "${YELLOW}>>> 是否需要安装微信Hook工具？(y/N)：${RESET}"
        read -n 1 install_hook
        echo
        if [[ $install_hook =~ ^[Yy]$ ]]; then
            python3 -m wcferry.run
        fi
    fi
    
    while true; do
        echo -e "\n${YELLOW}>>> WeChatFerry设置${RESET}"
        echo "1. 配置目标群组"
        echo "2. 删除群组配置"
        echo "3. 查看当前配置"
        echo "4. 重启WeChatFerry"
        echo "5. 返回上级菜单"
        echo -n "请选择 [1-5]: "
        read choice
        
        case $choice in
            1)
                python3 - <<EOF
import json
from wcferry import Wcf

try:
    wcf = Wcf()
    print("\n${YELLOW}>>> 正在获取群组列表...${RESET}")
    groups = wcf.get_rooms()
    
    print("\n可用的群组：")
    for i, group in enumerate(groups, 1):
        print(f"{i}. {group['name']} ({group['wxid']})")
    
    selected = input("\n请输入要添加的群组编号（多个用逗号分隔）：")
    selected_ids = [int(x.strip()) for x in selected.split(",")]
    
    with open("$CONFIG_FILE", 'r') as f:
        config = json.load(f)
    
    for idx in selected_ids:
        if 1 <= idx <= len(groups):
            group = groups[idx-1]
            if not any(g['wxid'] == group['wxid'] for g in config['wcf']['groups']):
                config['wcf']['groups'].append({
                    'wxid': group['wxid'],
                    'name': group['name']
                })
    
    with open("$CONFIG_FILE", 'w') as f:
        json.dump(config, f, indent=4)
    
    print("\n${GREEN}✓ 群组配置已更新${RESET}")
except Exception as e:
    print(f"\n${RED}配置失败: {e}${RESET}")
EOF
                ;;
            2)
                config=$(cat $CONFIG_FILE)
                groups=$(echo $config | jq -r '.wcf.groups[]')
                if [ ! -z "$groups" ]; then
                    echo -e "\n当前群组列表："
                    i=1
                    while read -r group; do
                        name=$(echo $group | jq -r '.name')
                        wxid=$(echo $group | jq -r '.wxid')
                        echo "$i. $name ($wxid)"
                        i=$((i+1))
                    done <<< "$groups"
                    
                    echo -e "\n${YELLOW}>>> 请输入要删除的群组编号：${RESET}"
                    read num
                    if [[ $num =~ ^[0-9]+$ ]]; then
                        config=$(echo $config | jq "del(.wcf.groups[$(($num-1))])")
                        echo $config > $CONFIG_FILE
                        echo -e "${GREEN}✓ 群组已删除${RESET}"
                    else
                        echo -e "${RED}无效的编号${RESET}"
                    fi
                else
                    echo -e "${YELLOW}没有已配置的群组${RESET}"
                fi
                ;;
            3)
                config=$(cat $CONFIG_FILE)
                groups=$(echo $config | jq -r '.wcf.groups[]')
                if [ ! -z "$groups" ]; then
                    echo -e "\n当前群组列表："
                    i=1
                    while read -r group; do
                        name=$(echo $group | jq -r '.name')
                        wxid=$(echo $group | jq -r '.wxid')
                        echo "$i. $name ($wxid)"
                        i=$((i+1))
                    done <<< "$groups"
                else
                    echo -e "${YELLOW}没有已配置的群组${RESET}"
                fi
                ;;
            4)
                python3 -c "
from wcferry import Wcf
try:
    wcf = Wcf()
    wcf.cleanup()
    print('${GREEN}✓ WeChatFerry已重启${RESET}')
except Exception as e:
    print(f'${RED}重启失败: {e}${RESET}')
"
                ;;
            5)
                return
                ;;
            *)
                echo -e "${RED}无效选项!${RESET}"
                ;;
        esac
    done
}

# 测试通知
test_notification() {
    echo -e "${YELLOW}>>> 发送测试通知...${RESET}"
    python3 - <<EOF
import json
import requests
from wcferry import Wcf

def send_test_notification():
    with open("$CONFIG_FILE", 'r') as f:
        config = json.load(f)
    
    test_msg = """
🔔 通知测试
━━━━━━━━━━━━━━━━━━━━━━━━

这是一条测试消息，用于验证通知功能是否正常工作。

• Server酱
• WeChatFerry
"""
    
    # Server酱测试
    for key in config['serverchan']['keys']:
        try:
            resp = requests.post(
                f"https://sctapi.ftqq.com/{key}.send",
                data={"title": "通知测试", "desp": test_msg},
                timeout=5
            )
            if resp.status_code == 200:
                print(f"${GREEN}✓ Server酱推送成功 ({key[:8]}...{key[-8:]})${RESET}")
            else:
                print(f"${RED}✗ Server酱推送失败 ({key[:8]}...{key[-8:]})${RESET}")
        except Exception as e:
            print(f"${RED}✗ Server酱推送错误: {e}${RESET}")
    
    # WeChatFerry测试
    if config['wcf']['groups']:
        try:
            wcf = Wcf()
            for group in config['wcf']['groups']:
                try:
                    wcf.send_text(group['wxid'], test_msg)
                    print(f"${GREEN}✓ 微信推送成功 ({group['name']})${RESET}")
                except Exception as e:
                    print(f"${RED}✗ 微信推送失败 ({group['name']}): {e}${RESET}")
        except Exception as e:
            print(f"${RED}✗ WeChatFerry初始化失败: {e}${RESET}")

send_test_notification()
EOF
}

#===========================================
#===========================================
# RPC节点处理模块
#===========================================

# 状态指示图标
STATUS_OK="🟢"
STATUS_SLOW="🟡"
STATUS_ERROR="🔴"

# 节点类型标识
NODE_TYPE_OFFICIAL="[官方]"
NODE_TYPE_PUBLIC="[公共]"
NODE_TYPE_CUSTOM="[自定义]"

# 延迟阈值(毫秒)
LATENCY_GOOD=500    # 良好延迟阈值
LATENCY_WARN=1000   # 警告延迟阈值

# 默认RPC节点列表
DEFAULT_RPC_NODES=(
    "https://api.mainnet-beta.solana.com|Solana Official"
    "https://solana-api.projectserum.com|Project Serum"
    "https://rpc.ankr.com/solana|Ankr"
    "https://solana-mainnet.rpc.extrnode.com|Extrnode" 
    "https://api.mainnet.rpcpool.com|RPCPool"
    "https://api.metaplex.solana.com|Metaplex"
    "https://api.solscan.io|Solscan"
    "https://solana.public-rpc.com|GenesysGo"
    "https://ssc-dao.genesysgo.net|GenesysGo SSC"
    "https://free.rpcpool.com|RPCPool Free"
    "https://api.devnet.solana.com|Solana Devnet"
    "https://api.testnet.solana.com|Solana Testnet"
    "https://solana.getblock.io/mainnet|GetBlock"
    "https://solana-mainnet.g.alchemy.com/v2/demo|Alchemy Demo"
    "https://mainnet.helius-rpc.com/?api-key=1d8740dc-e5f4-421c-b823-e1bad1889eff|Helius"
    "https://neat-hidden-sanctuary.solana-mainnet.discover.quiknode.pro/2af5315d336f9ae920028bbb90a73b724dc1bbed|QuickNode"
    "https://solana.api.ping.pub|Ping.pub"
    "https://solana-mainnet-rpc.allthatnode.com|AllThatNode"
    "https://mainnet.rpcpool.com|RPCPool Mainnet"
    "https://api.solanium.io|Solanium"
)

# 测试RPC节点延迟和可用性
test_rpc_node() {
    local endpoint="$1"
    local provider="$2"
    local timeout=5
    
    # 构建测试请求
    local request='{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getHealth"
    }'
    
    # 测试节点
    local start_time=$(date +%s.%N)
    local response=$(curl -s -X POST -H "Content-Type: application/json" \
                    -d "$request" \
                    --connect-timeout $timeout \
                    "$endpoint" 2>/dev/null)
    local end_time=$(date +%s.%N)
    
    # 计算延迟(ms)
    local latency=$(echo "($end_time - $start_time) * 1000" | bc)
    
    # 确定状态图标和节点类型
    local status
    local type
    if [[ "$provider" == *"Official"* ]]; then
        type="$NODE_TYPE_OFFICIAL"
    elif [[ "$endpoint" == *"custom"* ]]; then
        type="$NODE_TYPE_CUSTOM"
    else
        type="$NODE_TYPE_PUBLIC"
    fi
    
    if [ ! -z "$response" ] && [[ "$response" == *"result"* ]]; then
        if (( $(echo "$latency < $LATENCY_GOOD" | bc -l) )); then
            status="$STATUS_OK"
        elif (( $(echo "$latency < $LATENCY_WARN" | bc -l) )); then
            status="$STATUS_SLOW"
        else
            status="$STATUS_ERROR"
        fi
        echo "$endpoint|$provider|$latency|$status|$type"
        return 0
    fi
    return 1
}

# 测试所有节点
test_all_nodes() {
    local input_file="$1"
    local output_file="$2"
    local total_nodes=0
    local working_nodes=0
    local good_nodes=0
    local slow_nodes=0
    
    # 清空输出文件
    > "$output_file"
    
    echo -e "\n${YELLOW}>>> 开始测试节点...${RESET}"
    
    # 读取并测试节点
    while IFS="|" read -r endpoint provider || [ -n "$endpoint" ]; do
        [ -z "$endpoint" ] && continue
        ((total_nodes++))
        echo -ne "\r测试进度: $total_nodes"
        
        if result=$(test_rpc_node "$endpoint" "$provider"); then
            echo "$result" >> "$output_file"
            ((working_nodes++))
            
            # 统计节点状态
            if [[ "$result" == *"$STATUS_OK"* ]]; then
                ((good_nodes++))
            elif [[ "$result" == *"$STATUS_SLOW"* ]]; then
                ((slow_nodes++))
            fi
        fi
    done < "$input_file"
    
    # 按延迟排序
    if [ -f "$output_file" ]; then
        sort -t"|" -k3 -n "$output_file" -o "$output_file"
    fi
    
    echo -e "\n\n${GREEN}✓ 测试完成"
    echo "总节点数: $total_nodes"
    echo "可用节点数: $working_nodes"
    echo "良好节点数: $good_nodes"
    echo "较慢节点数: $slow_nodes"
    echo -e "可用率: $(( working_nodes * 100 / total_nodes ))%${RESET}"
    
    # 显示最佳节点
    if [ $working_nodes -gt 0 ]; then
        echo -e "\n最佳节点 (延迟<${LATENCY_GOOD}ms):"
        echo "------------------------------------------------"
        head -n 5 "$output_file" | while IFS="|" read -r endpoint provider latency status type; do
            if (( $(echo "$latency < $LATENCY_GOOD" | bc -l) )); then
                printf "%-4s %-8s %7.1f  %-15s %s\n" \
                    "$status" "$type" "$latency" "$provider" "$endpoint"
            fi
        done
    fi
}

# 测试默认节点
test_default_nodes() {
    local output_file="$1"
    local temp_file="/tmp/default_nodes.txt"
    
    # 写入默认节点到临时文件
    printf "%s\n" "${DEFAULT_RPC_NODES[@]}" > "$temp_file"
    
    # 测试节点
    test_all_nodes "$temp_file" "$output_file"
    
    # 清理临时文件
    rm -f "$temp_file"
}

# 添加自定义节点
add_custom_node() {
    echo -e "${YELLOW}>>> 添加自定义RPC节点${RESET}"
    echo -n "请输入节点地址: "
    read endpoint
    echo -n "请输入节点供应商: "
    read provider
    
    if [ ! -z "$endpoint" ]; then
        echo "$endpoint|$provider" >> "$CUSTOM_NODES"
        echo -e "${GREEN}✓ 节点已添加${RESET}"
        test_all_nodes "$CUSTOM_NODES" "$RPC_FILE"
    fi
}

# RPC节点管理主函数
manage_rpc() {
    local RPC_FILE="$HOME/.solana_pump/rpc.txt"
    local CUSTOM_NODES="$HOME/.solana_pump/custom_nodes.txt"
    mkdir -p "$HOME/.solana_pump"
    
    while true; do
        echo -e "\n${YELLOW}>>> RPC节点管理${RESET}"
        echo "1. 添加自定义节点"
        echo "2. 查看当前节点"
        echo "3. 测试节点延迟"
        echo "4. 使用默认节点"
        echo "5. 删除自定义节点"
        echo "6. 返回主菜单"
        echo -n "请选择 [1-6]: "
        read choice
        
        case $choice in
            1)
                add_custom_node
                ;;
            2)
                if [ -f "$RPC_FILE" ]; then
                    echo -e "\n${YELLOW}>>> 当前RPC节点列表：${RESET}"
                    echo -e "状态 类型    延迟(ms)  供应商          节点地址"
                    echo "------------------------------------------------"
                    while IFS="|" read -r endpoint provider latency status type; do
                        printf "%-4s %-8s %7.1f  %-15s %s\n" \
                            "$status" "$type" "$latency" "$provider" "$endpoint"
                    done < "$RPC_FILE"
                else
                    echo -e "${RED}>>> RPC节点列表为空${RESET}"
                fi
                ;;
            3)
                echo -e "${YELLOW}>>> 开始测试节点延迟...${RESET}"
                if [ -f "$CUSTOM_NODES" ]; then
                    test_all_nodes "$CUSTOM_NODES" "$RPC_FILE"
                else
                    test_default_nodes "$RPC_FILE"
                fi
                ;;
            4)
                echo -e "${YELLOW}>>> 使用默认RPC节点...${RESET}"
                test_default_nodes "$RPC_FILE"
                ;;
            5)
                if [ -f "$CUSTOM_NODES" ]; then
                    echo -e "\n${YELLOW}>>> 当前自定义节点：${RESET}"
                    nl -w3 -s". " "$CUSTOM_NODES"
                    echo -n "请输入要删除的节点编号: "
                    read num
                    if [[ $num =~ ^[0-9]+$ ]]; then
                        sed -i "${num}d" "$CUSTOM_NODES"
                        echo -e "${GREEN}✓ 节点已删除${RESET}"
                        test_all_nodes "$CUSTOM_NODES" "$RPC_FILE"
                    else
                        echo -e "${RED}无效的编号${RESET}"
                    fi
                else
                    echo -e "${RED}>>> 没有自定义节点${RESET}"
                fi
                ;;
            6)
                return
                ;;
            *)
                echo -e "${RED}无效选项!${RESET}"
                ;;
        esac
    done
}

#===========================================
# Python监控核心模块
#===========================================
generate_python_script() {
    echo -e "${YELLOW}>>> 生成监控脚本...${RESET}"
    mkdir -p "$(dirname "$PY_SCRIPT")"
    
cat > "$PY_SCRIPT" << 'EOFPYTHON'
#!/usr/bin/env python3
import os
import sys
import time
import json
import logging
import asyncio
import aiohttp
import urllib3
from datetime import datetime, timezone, timedelta
from concurrent.futures import ThreadPoolExecutor
from cachetools import TTLCache
from tenacity import retry, stop_after_attempt, wait_exponential
from wcferry import Wcf

# 禁用SSL警告
urllib3.disable_warnings()

# 设置UTC+8时区
TZ = timezone(timedelta(hours=8))

class TokenMonitor:
    def __init__(self):
        # 基础配置
        self.config_file = os.path.expanduser("~/.solana_pump.cfg")
        self.rpc_file = os.path.expanduser("~/.solana_pump.rpc")
        self.watch_file = os.path.expanduser("~/.solana_pump/watch_addresses.json")
        
        # 加载配置
        self.config = self.load_config()
        self.api_keys = self.config.get('api_keys', [])
        self.current_key = 0
        
        # API请求计数器
        self.request_counts = {}
        self.last_reset = {}
        
        # 初始化缓存
        self.token_cache = TTLCache(maxsize=1000, ttl=3600)  # 1小时过期
        self.creator_cache = TTLCache(maxsize=500, ttl=1800)  # 30分钟过期
        self.block_cache = TTLCache(maxsize=100, ttl=300)    # 5分钟过期
        
        # RPC节点管理
        self.rpc_nodes = []
        self.current_rpc = None
        self.last_rpc_check = 0
        self.rpc_check_interval = 300  # 5分钟检查一次
        
        # 监控统计
        self.stats = {
            'start_time': time.time(),
            'processed_blocks': 0,
            'found_tokens': 0,
            'api_calls': 0,
            'errors': 0,
            'last_slot': 0
        }
        
        # 初始化通知系统
        self.wcf = None
        self.watch_addresses = self.load_watch_addresses()
        self.init_wcf()
        
        # 初始化API密钥
        for key in self.api_keys:
            if key.strip():
                self.request_counts[key] = 0
                self.last_reset[key] = time.time()

    def load_config(self):
        """加载配置文件"""
        try:
            with open(self.config_file) as f:
                return json.load(f)
        except Exception as e:
            logging.error(f"加载配置失败: {e}")
            return {"api_keys": [], "serverchan": {"keys": []}, "wcf": {"groups": []}}

    def load_watch_addresses(self):
        """加载监控地址"""
        try:
            with open(self.watch_file) as f:
                data = json.load(f)
                return {addr['address']: addr['note'] for addr in data.get('addresses', [])}
        except Exception as e:
            logging.error(f"加载关注地址失败: {e}")
            return {}

    def init_wcf(self):
        """初始化微信通知"""
        if self.config['wcf']['groups']:
            try:
                self.wcf = Wcf()
                logging.info("WeChatFerry初始化成功")
            except Exception as e:
                logging.error(f"WeChatFerry初始化失败: {e}")
                self.wcf = None

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def get_next_api_key(self):
        """获取下一个可用的API密钥(带重试)"""
        now = time.time()
        for key in self.api_keys:
            if not key.strip():
                continue
                
            if now - self.last_reset[key] >= 60:
                self.request_counts[key] = 0
                self.last_reset[key] = now
            
            if self.request_counts[key] < 100:
                self.request_counts[key] += 1
                return key
        
        await asyncio.sleep(1)  # 如果所有密钥都达到限制，等待1秒
        raise Exception("所有API密钥已达到限制")

    async def get_best_rpc(self):
        """获取最佳RPC节点"""
        try:
            # 定期检查RPC节点状态
            if time.time() - self.last_rpc_check > self.rpc_check_interval:
                await self.check_rpc_nodes()
            
            if self.current_rpc:
                return self.current_rpc
                
            with open(self.rpc_file) as f:
                nodes = [line.strip().split('|') for line in f]
                if not nodes:
                    raise Exception("没有可用的RPC节点")
                self.current_rpc = nodes[0][0]
                return self.current_rpc
        except Exception as e:
            logging.error(f"获取RPC节点失败: {e}")
            return "https://api.mainnet-beta.solana.com"

    async def check_rpc_nodes(self):
        """检查RPC节点状态"""
        async with aiohttp.ClientSession() as session:
            tasks = []
            with open(self.rpc_file) as f:
                nodes = [line.strip().split('|') for line in f]
                for node in nodes:
                    tasks.append(self.check_rpc_node(session, node[0]))
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
            valid_nodes = [node for node, result in zip(nodes, results) if result]
            
            if valid_nodes:
                self.current_rpc = valid_nodes[0][0]
                self.last_rpc_check = time.time()
            else:
                logging.error("没有可用的RPC节点")

    async def check_rpc_node(self, session, endpoint):
        """检查单个RPC节点"""
        try:
            async with session.post(
                endpoint,
                json={"jsonrpc":"2.0","id":1,"method":"getHealth"},
                timeout=5
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    return "result" in data
        except:
            return False
        return False

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def fetch_token_info(self, session, mint):
        """获取代币详细信息(带重试)"""
        # 检查缓存
        if mint in self.token_cache:
            return self.token_cache[mint]
            
        try:
            api_key = await self.get_next_api_key()
            headers = {"X-API-KEY": api_key}
            
            # 获取基本信息
            async with session.get(
                f"https://public-api.birdeye.so/public/token_metadata?address={mint}",
                headers=headers,
                timeout=5
            ) as resp:
                data = await resp.json()
                
                if data.get("success"):
                    token_data = data["data"]
                    
                    # 获取持有人信息
                    async with session.get(
                        f"https://public-api.birdeye.so/public/token_holders?address={mint}",
                        headers=headers,
                        timeout=5
                    ) as holders_resp:
                        holders_data = (await holders_resp.json()).get("data", [])
                    
                    # 计算持有人集中度
                    total_supply = float(token_data.get("supply", 0))
                    holder_concentration = 0
                    if holders_data and total_supply > 0:
                        top_10_holdings = sum(float(h.get("amount", 0)) for h in holders_data[:10])
                        holder_concentration = (top_10_holdings / total_supply) * 100
                    
                    token_info = {
                        "name": token_data.get("name", "Unknown"),
                        "symbol": token_data.get("symbol", ""),
                        "supply": total_supply,
                        "price": float(token_data.get("price", 0)),
                        "market_cap": float(token_data.get("mc", 0)),
                        "liquidity": float(token_data.get("liquidity", 0)),
                        "holder_count": len(holders_data),
                        "holder_concentration": holder_concentration
                    }
                    
                    # 缓存结果
                    self.token_cache[mint] = token_info
                    return token_info
                    
        except Exception as e:
            logging.error(f"获取代币信息失败: {e}")
            return {
                "name": "Unknown",
                "symbol": "",
                "supply": 0,
                "price": 0,
                "market_cap": 0,
                "liquidity": 0,
                "holder_count": 0,
                "holder_concentration": 0
            }

    async def analyze_creator_history(self, session, creator):
        """分析创建者历史"""
        # 检查缓存
        if creator in self.creator_cache:
            return self.creator_cache[creator]
            
        try:
            api_key = await self.get_next_api_key()
            headers = {"X-API-KEY": api_key}
            
            async with session.get(
                f"https://public-api.solscan.io/account/tokens?account={creator}",
                headers=headers,
                timeout=5
            ) as resp:
                tokens = await resp.json()
                
            history = []
            for token in tokens:
                mint = token.get("mint")
                if not mint:
                    continue
                    
                # 获取代币详情
                token_info = await self.fetch_token_info(session, mint)
                
                history.append({
                    "mint": mint,
                    "timestamp": token.get("timestamp", 0),
                    "max_market_cap": token_info.get("market_cap", 0),
                    "current_market_cap": token_info.get("market_cap", 0),
                    "status": "活跃" if token_info.get("market_cap", 0) > 0 else "已死"
                })
            
            # 缓存结果
            self.creator_cache[creator] = history
            return history
            
        except Exception as e:
            logging.error(f"分析创建者历史失败: {e}")
            return []

    async def analyze_creator_relations(self, session, creator):
        """分析创建者关联性"""
        try:
            # 获取钱包年龄
            async with session.get(
                f"https://public-api.solscan.io/account/{creator}",
                timeout=5
            ) as resp:
                account_data = await resp.json()
                first_tx_time = account_data.get("firstTime", time.time())
                wallet_age = (time.time() - first_tx_time) / 86400  # 转换为天数
            
            # 获取关联地址
            async with session.get(
                f"https://public-api.solscan.io/account/transactions?account={creator}&limit=50",
                timeout=5
            ) as resp:
                txs = await resp.json()
            
            related_addresses = set()
            relations = []
            watch_hits = []
            high_value_relations = []
            
            # 分析交易
            for tx in txs:
                for account in tx.get("accounts", []):
                    if account != creator:
                        related_addresses.add(account)
                        
                        # 检查是否是关注地址
                        if account in self.watch_addresses:
                            watch_hits.append({
                                "address": account,
                                "note": self.watch_addresses[account],
                                "type": "transaction",
                                "amount": float(tx.get("lamport", 0)) / 1e9,  # 转换为SOL
                                "timestamp": tx.get("blockTime", 0)
                            })
            
            # 并行分析关联地址
            tasks = []
            for address in related_addresses:
                tasks.append(self.analyze_creator_history(session, address))
            
            results = await asyncio.gather(*tasks)
            
            # 处理结果
            for address, history in zip(related_addresses, results):
                if history:
                    high_value_tokens = [
                        token for token in history 
                        if token["max_market_cap"] > 100000  # 10万美元以上视为高价值
                    ]
                    
                    if high_value_tokens:
                        high_value_relations.append({
                            "address": address,
                            "total_created": len(history),
                            "tokens": high_value_tokens
                        })
            
            return {
                "wallet_age": wallet_age,
                "is_new_wallet": wallet_age < 7,  # 小于7天视为新钱包
                "related_addresses": list(related_addresses),
                "relations": relations,
                "watch_hits": watch_hits,
                "high_value_relations": high_value_relations,
                "risk_score": self.calculate_risk_score(relations, wallet_age)
            }
        except Exception as e:
            logging.error(f"分析地址关联性失败: {e}")
            return {
                "wallet_age": 0,
                "is_new_wallet": True,
                "related_addresses": [],
                "relations": [],
                "watch_hits": [],
                "high_value_relations": [],
                "risk_score": 0
            }

    def calculate_risk_score(self, relations, wallet_age):
        """计算风险分数"""
        score = 0
        
        # 1. 钱包年龄评分 (0-25分)
        if wallet_age < 1:  # 小于1天
            score += 25
        elif wallet_age < 7:  # 小于7天
            score += 15
        elif wallet_age < 30:  # 小于30天
            score += 5
        
        # 2. 关联地址评分 (0-25分)
        unique_addresses = len(set(r["address"] for r in relations))
        if unique_addresses > 20:
            score += 25
        elif unique_addresses > 10:
            score += 15
        elif unique_addresses > 5:
            score += 5
        
        # 3. 代币创建者分析 (0-25分)
        token_creators = [r for r in relations if r["type"] == "token_creator"]
        if token_creators:
            # 计算平均成功率
            avg_success = sum(t["success_rate"] for t in token_creators) / len(token_creators)
            # 计算高价值代币数量
            high_value_count = sum(t.get("high_value_tokens", 0) for t in token_creators)
            
            if avg_success < 0.2:  # 成功率低于20%
                score += 25
            elif avg_success < 0.4:  # 成功率低于40%
                score += 15
            elif avg_success < 0.6:  # 成功率低于60%
                score += 5
            
            # 如果有高价值代币历史，降低风险分数
            if high_value_count > 0:
                score = max(0, score - 15)
        
        # 4. 交易行为评分 (0-25分)
        large_transfers = [r for r in relations if r["type"] == "transfer" and r["amount"] > 10]
        suspicious_patterns = len([t for t in large_transfers if any(
            abs(t["timestamp"] - other["timestamp"]) < 300  # 5分钟内
            for other in large_transfers
            if t != other
        )])
        
        if suspicious_patterns > 5:
            score += 25
        elif suspicious_patterns > 2:
            score += 15
        elif suspicious_patterns > 0:
            score += 5
        
        return min(score, 100)  # 最高100分

    def format_alert_message(self, data):
        """格式化警报消息"""
        creator = data["creator"]
        mint = data["mint"]
        token_info = data["token_info"]
        history = data["history"]
        relations = data["relations"]
        
        msg = f"""
🚨 新代币创建监控 (UTC+8)
━━━━━━━━━━━━━━━━━━━━━━━━

📋 基本信息:
• 代币地址: {mint}
• 创建者: {creator}
• 钱包状态: {'🆕 新钱包' if relations['is_new_wallet'] else '📅 老钱包'}
• 钱包年龄: {relations['wallet_age']:.1f} 天

💰 代币数据:
• 初始市值: ${token_info['market_cap']:,.2f}
• 代币供应量: {token_info['supply']:,.0f}
• 单价: ${token_info['price']:.8f}
• 流动性: {token_info['liquidity']:.2f} SOL
• 持有人数: {token_info['holder_count']}
• 前10持有人占比: {token_info['holder_concentration']:.1f}%"""

        # 添加关注地址信息
        if creator in self.watch_addresses:
            msg += f"\n\n⭐ 重点关注地址！\n• 备注: {self.watch_addresses[creator]}"

        # 添加风险评分
        risk_level = "高" if relations['risk_score'] >= 70 else "中" if relations['risk_score'] >= 40 else "低"
        msg += f"""

🎯 风险评估:
• 综合风险评分: {relations['risk_score']}/100
• 风险等级: {risk_level}
• 关联地址数: {len(relations['related_addresses'])}"""

        # 添加高价值关联信息
        if relations['high_value_relations']:
            msg += "\n\n💎 发现高价值关联方:"
            for relation in relations['high_value_relations'][:3]:  # 只显示前3个
                msg += f"""
• 地址: {relation['address']}
  - 创建代币总数: {relation['total_created']}
  - 高价值代币数: {len(relation['tokens'])}"""
                for token in relation['tokens'][:2]:  # 每个地址只显示前2个高价值代币
                    creation_time = datetime.fromtimestamp(token["timestamp"], tz=TZ)
                    msg += f"""
  - {token['mint']}
    创建时间: {creation_time.strftime('%Y-%m-%d %H:%M:%S')}
    最高市值: ${token['max_market_cap']:,.2f}
    当前市值: ${token['current_market_cap']:,.2f}"""

        # 添加关联的关注地址信息
        if relations['watch_hits']:
            msg += "\n\n⚠️ 发现关联的关注地址:"
            for hit in relations['watch_hits']:
                timestamp = datetime.fromtimestamp(hit["timestamp"], tz=TZ)
                msg += f"""
• {hit['address']}
  - 备注: {hit['note']}
  - 关联类型: {hit['type']}
  - 交易金额: {hit['amount']:.2f} SOL
  - 交易时间: {timestamp.strftime('%Y-%m-%d %H:%M:%S')}"""

        # 添加创建者历史记录
        if history:
            active_tokens = sum(1 for t in history if t["status"] == "活跃")
            success_rate = active_tokens / len(history) if history else 0
            msg += f"""

📜 创建者历史:
• 历史代币数: {len(history)}
• 当前活跃: {active_tokens}
• 成功率: {success_rate:.1%}

最近代币记录:"""
            for token in sorted(history, key=lambda x: x["timestamp"], reverse=True)[:3]:
                timestamp = datetime.fromtimestamp(token["timestamp"], tz=TZ)
                msg += f"""
• {token['mint']}
  - 创建时间: {timestamp.strftime('%Y-%m-%d %H:%M:%S')}
  - 最高市值: ${token['max_market_cap']:,.2f}
  - 当前市值: ${token['current_market_cap']:,.2f}
  - 当前状态: {token['status']}"""

        # 添加投资建议
        msg += "\n\n💡 投资建议:"
        if relations['is_new_wallet']:
            msg += "\n• ⚠️ 新钱包创建，需谨慎对待"
        if relations['high_value_relations']:
            msg += "\n• 🌟 发现高价值关联方，可能是成功团队新项目"
        if success_rate > 0.5:
            msg += "\n• ✅ 创建者历史表现良好"
        if relations['risk_score'] >= 70:
            msg += "\n• ❗ 高风险项目，建议谨慎"
        
        # 添加快速链接
        msg += f"""

🔗 快速链接:
• Birdeye: https://birdeye.so/token/{mint}
• Solscan: https://solscan.io/token/{mint}
• 创建者: https://solscan.io/account/{creator}

⏰ 发现时间: {datetime.now(tz=TZ).strftime('%Y-%m-%d %H:%M:%S')} (UTC+8)
"""
        return msg

    async def send_notification(self, msg):
        """发送通知"""
        # Server酱推送
        for key in self.config["serverchan"]["keys"]:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        f"https://sctapi.ftqq.com/{key}.send",
                        data={"title": "Solana新代币提醒", "desp": msg},
                        timeout=5
                    ) as resp:
                        if resp.status != 200:
                            logging.error(f"Server酱推送失败 ({key[:8]}...{key[-8:]})")
            except Exception as e:
                logging.error(f"Server酱推送失败 ({key[:8]}...{key[-8:]}): {e}")
        
        # WeChatFerry推送
        if self.wcf and self.config["wcf"]["groups"]:
            for group in self.config["wcf"]["groups"]:
                try:
                    self.wcf.send_text(group["wxid"], msg)
                except Exception as e:
                    logging.error(f"WeChatFerry推送失败 ({group['name']}): {e}")

    async def monitor(self):
        """主监控函数"""
        logging.info("监控启动...")
        self.stats['last_slot'] = 0
        PUMP_PROGRAM = "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ35MKDfgCcMKJ"
        
        async with aiohttp.ClientSession() as session:
            while True:
                try:
                    rpc = await self.get_best_rpc()
                    async with session.post(
                        rpc,
                        json={"jsonrpc":"2.0","id":1,"method":"getSlot"},
                        timeout=3
                    ) as resp:
                        current_slot = (await resp.json())["result"]
                    
                    if self.stats['last_slot'] == 0:
                        self.stats['last_slot'] = current_slot - 10
                    
                    tasks = []
                    for slot in range(self.stats['last_slot'] + 1, current_slot + 1):
                        tasks.append(self.process_block(session, slot, PUMP_PROGRAM))
                    
                    await asyncio.gather(*tasks)
                    self.stats['last_slot'] = current_slot
                    
                    await asyncio.sleep(1)
                    
                except Exception as e:
                    logging.error(f"监控循环错误: {e}")
                    await asyncio.sleep(10)

    async def process_block(self, session, slot, program_id):
        """处理单个区块"""
        try:
            rpc = await self.get_best_rpc()
            async with session.post(
                rpc,
                json={
                    "jsonrpc":"2.0",
                    "id":1,
                    "method":"getBlock",
                    "params":[slot, {"encoding":"json","transactionDetails":"full"}]
                },
                timeout=5
            ) as resp:
                block = (await resp.json()).get("result")
                
                if block and "transactions" in block:
                    for tx in block["transactions"]:
                        if program_id in tx["transaction"]["message"]["accountKeys"]:
                            accounts = tx["transaction"]["message"]["accountKeys"]
                            creator = accounts[0]
                            mint = accounts[4]
                            
                            # 并行获取所需信息
                            token_info, history, relations = await asyncio.gather(
                                self.fetch_token_info(session, mint),
                                self.analyze_creator_history(session, creator),
                                self.analyze_creator_relations(session, creator)
                            )
                            
                            alert_data = {
                                "creator": creator,
                                "mint": mint,
                                "token_info": token_info,
                                "history": history,
                                "relations": relations
                            }
                            
                            alert_msg = self.format_alert_message(alert_data)
                            logging.info("\n" + alert_msg)
                            await self.send_notification(alert_msg)
                            
                            # 更新统计信息
                            self.stats['found_tokens'] += 1
                            
                    self.stats['processed_blocks'] += 1
                    
        except Exception as e:
            logging.error(f"处理区块 {slot} 失败: {e}")
            self.stats['errors'] += 1

if __name__ == "__main__":
    # 设置日志
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('monitor.log'),
            logging.StreamHandler()
        ]
    )
    
    # 启动监控
    monitor = TokenMonitor()
    asyncio.run(monitor.monitor())
EOFPYTHON

    chmod +x "$PY_SCRIPT"
    echo -e "${GREEN}✓ 监控脚本已生成${RESET}"
}
        
#===========================================
# 主程序和菜单模块
#===========================================

# 生成Python监控脚本
generate_python_script() {
    echo -e "${YELLOW}>>> 生成监控脚本...${RESET}"
cat > "$PY_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import json
import logging
import requests
import urllib3
from datetime import datetime, timezone, timedelta
from concurrent.futures import ThreadPoolExecutor
from wcferry import Wcf

# 禁用SSL警告
urllib3.disable_warnings()

class TokenMonitor:
    def __init__(self):
        self.config_file = os.path.expanduser("~/.solana_pump.cfg")
        self.rpc_file = os.path.expanduser("~/.solana_pump.rpc")
        self.watch_file = os.path.expanduser("~/.solana_pump/watch_addresses.json")
        self.config = self.load_config()
        self.api_keys = self.config.get('api_keys', [])
        self.current_key = 0
        self.request_counts = {}
        self.last_reset = {}
        self.wcf = None
        self.watch_addresses = self.load_watch_addresses()
        self.init_wcf()
        
        # 初始化API密钥计数器
        for key in self.api_keys:
            if key.strip():
                self.request_counts[key] = 0
                self.last_reset[key] = time.time()

        # 创建线程池
        self.executor = ThreadPoolExecutor(max_workers=5)
        
        # 缓存已分析的地址
        self.address_cache = {}
        self.cache_expire = 3600  # 缓存1小时过期

    def load_config(self):
        try:
            with open(self.config_file) as f:
                return json.load(f)
        except Exception as e:
            logging.error(f"加载配置失败: {e}")
            return {"api_keys": [], "serverchan": {"keys": []}, "wcf": {"groups": []}}

    def load_watch_addresses(self):
        try:
            with open(self.watch_file) as f:
                data = json.load(f)
                return {addr['address']: addr['note'] for addr in data.get('addresses', [])}
        except Exception as e:
            logging.error(f"加载关注地址失败: {e}")
            return {}

    def init_wcf(self):
        if self.config['wcf']['groups']:
            try:
                self.wcf = Wcf()
                logging.info("WeChatFerry初始化成功")
            except Exception as e:
                logging.error(f"WeChatFerry初始化失败: {e}")
                self.wcf = None

    def get_next_api_key(self):
        """获取下一个可用的API密钥"""
        now = time.time()
        for key in self.api_keys:
            if not key.strip():
                continue
                
            if now - self.last_reset[key] >= 60:
                self.request_counts[key] = 0
                self.last_reset[key] = now
            
            if self.request_counts[key] < 100:
                self.request_counts[key] += 1
                return key
        
        raise Exception("所有API密钥已达到限制")

    def get_best_rpc(self):
        """获取最佳RPC节点"""
        try:
            with open(self.rpc_file) as f:
                nodes = [json.loads(line) for line in f]
                if not nodes:
                    raise Exception("没有可用的RPC节点")
                return nodes[0]['endpoint']
        except Exception as e:
            logging.error(f"获取RPC节点失败: {e}")
            return "https://api.mainnet-beta.solana.com"

    def fetch_token_info(self, mint):
        """获取代币详细信息"""
        try:
            headers = {"X-API-KEY": self.get_next_api_key()}
            
            # 获取基本信息
            url = f"https://public-api.birdeye.so/public/token_metadata?address={mint}"
            resp = requests.get(url, headers=headers, timeout=5)
            data = resp.json()
            
            if data.get("success"):
                token_data = data["data"]
                
                # 获取持有人信息
                holders_url = f"https://public-api.birdeye.so/public/token_holders?address={mint}"
                holders_resp = requests.get(holders_url, headers=headers, timeout=5)
                holders_data = holders_resp.json().get("data", [])
                
                # 计算持有人集中度
                total_supply = float(token_data.get("supply", 0))
                holder_concentration = 0
                if holders_data and total_supply > 0:
                    top_10_holdings = sum(float(h.get("amount", 0)) for h in holders_data[:10])
                    holder_concentration = (top_10_holdings / total_supply) * 100
                
                return {
                    "name": token_data.get("name", "Unknown"),
                    "symbol": token_data.get("symbol", "Unknown"),
                    "price": float(token_data.get("price", 0)),
                    "supply": float(token_data.get("supply", 0)),
                    "market_cap": float(token_data.get("price", 0)) * float(token_data.get("supply", 0)),
                    "liquidity": float(token_data.get("liquidity", 0)),
                    "holder_count": len(holders_data),
                    "holder_concentration": holder_concentration,
                    "verified": token_data.get("verified", False)
                }
        except Exception as e:
            logging.error(f"获取代币信息失败: {e}")
        
        return {
            "name": "Unknown",
            "symbol": "Unknown",
            "price": 0,
            "supply": 0,
            "market_cap": 0,
            "liquidity": 0,
            "holder_count": 0,
            "holder_concentration": 0,
            "verified": False
        }

    def analyze_creator_history(self, creator):
        """分析创建者历史记录"""
        # 检查缓存
        if creator in self.address_cache:
            cache_data = self.address_cache[creator]
            if time.time() - cache_data['timestamp'] < self.cache_expire:
                return cache_data['history']
        
        try:
            headers = {"X-API-KEY": self.get_next_api_key()}
            url = f"https://public-api.birdeye.so/public/address_nft_mints?address={creator}"
            resp = requests.get(url, headers=headers, timeout=5)
            data = resp.json()
            
            if data.get("success"):
                history = []
                for tx in data["data"]:
                    if "mint" in tx:
                        token_info = self.fetch_token_info(tx["mint"])
                        
                        # 获取历史最高市值
                        max_market_cap = 0
                        try:
                            history_url = f"https://public-api.birdeye.so/public/token_price_history?address={tx['mint']}"
                            history_resp = requests.get(history_url, headers=headers, timeout=5)
                            if history_resp.status_code == 200:
                                price_history = history_resp.json().get("data", [])
                                if price_history:
                                    max_price = max(float(p.get("value", 0)) for p in price_history)
                                    max_market_cap = max_price * token_info["supply"]
                        except:
                            pass

                        history.append({
                            "mint": tx["mint"],
                            "timestamp": tx["timestamp"],
                            "current_market_cap": token_info["market_cap"],
                            "max_market_cap": max_market_cap,
                            "liquidity": token_info["liquidity"],
                            "holder_count": token_info["holder_count"],
                            "holder_concentration": token_info["holder_concentration"],
                            "status": "活跃" if token_info["market_cap"] > 0 else "已退出"
                        })

                # 缓存结果
                self.address_cache[creator] = {
                    'timestamp': time.time(),
                    'history': history
                }
                return history
        except Exception as e:
            logging.error(f"获取创建者历史失败: {e}")
        
        return []

    def analyze_creator_relations(self, creator):
        """分析创建者地址关联性"""
        try:
            related_addresses = set()
            relations = []
            watch_hits = []
            high_value_relations = []
            
            # 1. 分析转账历史
            headers = {"X-API-KEY": self.get_next_api_key()}
            url = f"https://public-api.birdeye.so/public/address_activity?address={creator}"
            resp = requests.get(url, headers=headers, timeout=5)
            data = resp.json()
            
            if data.get("success"):
                # 记录地址首次交易时间
                first_tx_time = float('inf')
                for tx in data["data"]:
                    first_tx_time = min(first_tx_time, tx.get("timestamp", float('inf')))
                    
                    # 记录所有交互过的地址
                    if tx.get("from") and tx["from"] != creator:
                        related_addresses.add(tx["from"])
                        if tx["from"] in self.watch_addresses:
                            watch_hits.append({
                                'address': tx["from"],
                                'note': self.watch_addresses[tx["from"]],
                                'type': 'transfer_from',
                                'amount': tx.get("amount", 0),
                                'timestamp': tx["timestamp"]
                            })
                            
                    if tx.get("to") and tx["to"] != creator:
                        related_addresses.add(tx["to"])
                        if tx["to"] in self.watch_addresses:
                            watch_hits.append({
                                'address': tx["to"],
                                'note': self.watch_addresses[tx["to"]],
                                'type': 'transfer_to',
                                'amount': tx.get("amount", 0),
                                'timestamp': tx["timestamp"]
                            })
                        
                    # 特别关注大额转账
                    if tx.get("amount", 0) > 1:  # 1 SOL以上的转账
                        relations.append({
                            "address": tx["to"] if tx["from"] == creator else tx["from"],
                            "type": "transfer",
                            "amount": tx["amount"],
                            "timestamp": tx["timestamp"]
                        })
                
                # 计算钱包年龄（天）
                wallet_age = (time.time() - first_tx_time) / (24 * 3600) if first_tx_time != float('inf') else 0
            
            # 2. 深度分析关联地址
            for address in related_addresses:
                # 分析代币创建历史
                token_history = self.analyze_creator_history(address)
                if token_history:
                    # 找出高价值代币（最高市值超过1亿美元）
                    high_value_tokens = [t for t in token_history 
                                       if t["max_market_cap"] > 100_000_000]
                    
                    if high_value_tokens:
                        high_value_relations.append({
                            "address": address,
                            "tokens": high_value_tokens,
                            "total_created": len(token_history)
                        })
                    
                    relations.append({
                        "address": address,
                        "type": "token_creator",
                        "tokens": len(token_history),
                        "success_rate": sum(1 for t in token_history if t["status"] == "活跃") / len(token_history),
                        "high_value_tokens": len(high_value_tokens)
                    })
            
            # 3. 分析共同签名者
            with ThreadPoolExecutor(max_workers=3) as executor:
                futures = []
                for address in related_addresses:
                    futures.append(executor.submit(self._analyze_cosigners, 
                                                address, creator))
                
                for future in futures:
                    try:
                        result = future.result()
                        if result:
                            relations.extend(result)
                    except:
                        continue
            
            return {
                "wallet_age": wallet_age,
                "is_new_wallet": wallet_age < 7,  # 小于7天视为新钱包
                "related_addresses": list(related_addresses),
                "relations": relations,
                "watch_hits": watch_hits,
                "high_value_relations": high_value_relations,
                "risk_score": self.calculate_risk_score(relations, wallet_age)
            }
        except Exception as e:
            logging.error(f"分析地址关联性失败: {e}")
            return {
                "wallet_age": 0,
                "is_new_wallet": True,
                "related_addresses": [],
                "relations": [],
                "watch_hits": [],
                "high_value_relations": [],
                "risk_score": 0
            }

    def _analyze_cosigners(self, address, creator):
        """分析共同签名者（辅助函数）"""
        try:
            tx_url = f"https://public-api.solscan.io/account/transactions?account={address}"
            tx_resp = requests.get(tx_url, timeout=5)
            tx_data = tx_resp.json()
            
            cosigner_relations = []
            for tx in tx_data[:100]:  # 只看最近100笔交易
                if creator in tx.get("signatures", []):
                    cosigner_relations.append({
                        "address": address,
                        "type": "co_signer",
                        "tx_hash": tx["signature"],
                        "timestamp": tx["blockTime"]
                    })
            return cosigner_relations
        except:
            return []

    def calculate_risk_score(self, relations, wallet_age):
        """计算风险分数"""
        score = 0
        
        # 1. 钱包年龄评分 (0-25分)
        if wallet_age < 1:  # 小于1天
            score += 25
        elif wallet_age < 7:  # 小于7天
            score += 15
        elif wallet_age < 30:  # 小于30天
            score += 5
        
        # 2. 关联地址评分 (0-25分)
        unique_addresses = len(set(r["address"] for r in relations))
        if unique_addresses > 20:
            score += 25
        elif unique_addresses > 10:
            score += 15
        elif unique_addresses > 5:
            score += 5
        
        # 3. 代币创建者分析 (0-25分)
        token_creators = [r for r in relations if r["type"] == "token_creator"]
        if token_creators:
            # 计算平均成功率
            avg_success = sum(t["success_rate"] for t in token_creators) / len(token_creators)
            # 计算高价值代币数量
            high_value_count = sum(t.get("high_value_tokens", 0) for t in token_creators)
            
            if avg_success < 0.2:  # 成功率低于20%
                score += 25
            elif avg_success < 0.4:  # 成功率低于40%
                score += 15
            elif avg_success < 0.6:  # 成功率低于60%
                score += 5
            
            # 如果有高价值代币历史，降低风险分数
            if high_value_count > 0:
                score = max(0, score - 15)
        
        # 4. 交易行为评分 (0-25分)
        large_transfers = [r for r in relations if r["type"] == "transfer" and r["amount"] > 10]
        suspicious_patterns = len([t for t in large_transfers if any(
            abs(t["timestamp"] - other["timestamp"]) < 300  # 5分钟内
            for other in large_transfers
            if t != other
        )])
        
        if suspicious_patterns > 5:
            score += 25
        elif suspicious_patterns > 2:
            score += 15
        elif suspicious_patterns > 0:
            score += 5
        
        return min(score, 100)  # 最高100分

    def format_alert_message(self, data):
        """格式化警报消息"""
        creator = data["creator"]
        mint = data["mint"]
        token_info = data["token_info"]
        history = data["history"]
        relations = data["relations"]
        
        msg = f"""
🚨 新代币创建监控 (UTC+8)
━━━━━━━━━━━━━━━━━━━━━━━━

📋 基本信息:
• 代币地址: {mint}
• 创建者: {creator}
• 钱包状态: {'🆕 新钱包' if relations['is_new_wallet'] else '📅 老钱包'}
• 钱包年龄: {relations['wallet_age']:.1f} 天

💰 代币数据:
• 初始市值: ${token_info['market_cap']:,.2f}
• 代币供应量: {token_info['supply']:,.0f}
• 单价: ${token_info['price']:.8f}
• 流动性: {token_info['liquidity']:.2f} SOL
• 持有人数: {token_info['holder_count']}
• 前10持有人占比: {token_info['holder_concentration']:.1f}%"""

        # 添加关注地址信息
        if creator in self.watch_addresses:
            msg += f"\n\n⭐ 重点关注地址！\n• 备注: {self.watch_addresses[creator]}"

        # 添加风险评分
        risk_level = "高" if relations['risk_score'] >= 70 else "中" if relations['risk_score'] >= 40 else "低"
        msg += f"""

🎯 风险评估:
• 综合风险评分: {relations['risk_score']}/100
• 风险等级: {risk_level}
• 关联地址数: {len(relations['related_addresses'])}"""

        # 添加高价值关联信息
        if relations['high_value_relations']:
            msg += "\n\n💎 发现高价值关联方:"
            for relation in relations['high_value_relations'][:3]:  # 只显示前3个
                msg += f"""
• 地址: {relation['address']}
  - 创建代币总数: {relation['total_created']}
  - 高价值代币数: {len(relation['tokens'])}"""
                for token in relation['tokens'][:2]:  # 每个地址只显示前2个高价值代币
                    creation_time = datetime.fromtimestamp(token["timestamp"], tz=timezone(timedelta(hours=8)))
                    msg += f"""
  - {token['mint']}
    创建时间: {creation_time.strftime('%Y-%m-%d %H:%M:%S')}
    最高市值: ${token['max_market_cap']:,.2f}
    当前市值: ${token['current_market_cap']:,.2f}"""

        # 添加关联的关注地址信息
        if relations['watch_hits']:
            msg += "\n\n⚠️ 发现关联的关注地址:"
            for hit in relations['watch_hits']:
                timestamp = datetime.fromtimestamp(hit["timestamp"], tz=timezone(timedelta(hours=8)))
                msg += f"""
• {hit['address']}
  - 备注: {hit['note']}
  - 关联类型: {hit['type']}
  - 交易金额: {hit['amount']:.2f} SOL
  - 交易时间: {timestamp.strftime('%Y-%m-%d %H:%M:%S')}"""

        # 添加创建者历史记录
        if history:
            active_tokens = sum(1 for t in history if t["status"] == "活跃")
            success_rate = active_tokens / len(history) if history else 0
            msg += f"""

📜 创建者历史:
• 历史代币数: {len(history)}
• 当前活跃: {active_tokens}
• 成功率: {success_rate:.1%}

最近代币记录:"""
            for token in sorted(history, key=lambda x: x["timestamp"], reverse=True)[:3]:
                timestamp = datetime.fromtimestamp(token["timestamp"], tz=timezone(timedelta(hours=8)))
                msg += f"""
• {token['mint']}
  - 创建时间: {timestamp.strftime('%Y-%m-%d %H:%M:%S')}
  - 最高市值: ${token['max_market_cap']:,.2f}
  - 当前市值: ${token['current_market_cap']:,.2f}
  - 当前状态: {token['status']}"""

        # 添加投资建议
        msg += "\n\n💡 投资建议:"
        if relations['is_new_wallet']:
            msg += "\n• ⚠️ 新钱包创建，需谨慎对待"
        if relations['high_value_relations']:
            msg += "\n• 🌟 发现高价值关联方，可能是成功团队新项目"
        if success_rate > 0.5:
            msg += "\n• ✅ 创建者历史表现良好"
        if relations['risk_score'] >= 70:
            msg += "\n• ❗ 高风险项目，建议谨慎"
        
        # 添加快速链接
        msg += f"""

🔗 快速链接:
• Birdeye: https://birdeye.so/token/{mint}
• Solscan: https://solscan.io/token/{mint}
• 创建者: https://solscan.io/account/{creator}

⏰ 发现时间: {datetime.now(tz=timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M:%S')} (UTC+8)
"""
        return msg

    def send_notification(self, msg):
        """发送通知"""
        # Server酱推送
        for key in self.config["serverchan"]["keys"]:
            try:
                requests.post(
                    f"https://sctapi.ftqq.com/{key}.send",
                    data={"title": "Solana新代币提醒", "desp": msg},
                    timeout=5
                )
            except Exception as e:
                logging.error(f"Server酱推送失败 ({key[:8]}...{key[-8:]}): {e}")
        
        # WeChatFerry推送
        if self.wcf and self.config["wcf"]["groups"]:
            for group in self.config["wcf"]["groups"]:
                try:
                    self.wcf.send_text(group["wxid"], msg)
                except Exception as e:
                    logging.error(f"WeChatFerry推送失败 ({group['name']}): {e}")

    def monitor(self):
        """主监控函数"""
        logging.info("监控启动...")
        last_slot = 0
        PUMP_PROGRAM = "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ35MKDfgCcMKJ"
        
        while True:
            try:
                rpc = self.get_best_rpc()
                current_slot = requests.post(
                    rpc,
                    json={"jsonrpc":"2.0","id":1,"method":"getSlot"},
                    timeout=3
                ).json()["result"]
                
                if last_slot == 0:
                    last_slot = current_slot - 10
                
                for slot in range(last_slot + 1, current_slot + 1):
                    try:
                        block = requests.post(rpc, json={
                            "jsonrpc":"2.0",
                            "id":1,
                            "method":"getBlock",
                            "params":[slot, {"encoding":"json","transactionDetails":"full"}]
                        }, timeout=5).json().get("result")
                        
                        if block and "transactions" in block:
                            for tx in block["transactions"]:
                                if PUMP_PROGRAM in tx["transaction"]["message"]["accountKeys"]:
                                    accounts = tx["transaction"]["message"]["accountKeys"]
                                    creator = accounts[0]
                                    mint = accounts[4]
                                    
                                    token_info = self.fetch_token_info(mint)
                                    history = self.analyze_creator_history(creator)
                                    relations = self.analyze_creator_relations(creator)
                                    
                                    alert_data = {
                                        "creator": creator,
                                        "mint": mint,
                                        "token_info": token_info,
                                        "history": history,
                                        "relations": relations
                                    }
                                    
                                    alert_msg = self.format_alert_message(alert_data)
                                    logging.info("\n" + alert_msg)
                                    self.send_notification(alert_msg)
                    
                    except Exception as e:
                        logging.error(f"处理区块 {slot} 失败: {e}")
                        continue
                    
                    last_slot = slot
                    time.sleep(0.1)
                
                time.sleep(1)
            
            except Exception as e:
                logging.error(f"监控循环错误: {e}")
                time.sleep(10)

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('monitor.log'),
            logging.StreamHandler()
        ]
    )
    monitor = TokenMonitor()
    monitor.monitor()
EOF

    chmod +x "$PY_SCRIPT"
    echo -e "${GREEN}✓ 监控脚本已生成${RESET}"
}

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('monitor.log'),
            logging.StreamHandler()
        ]
    )
    monitor = TokenMonitor()
    monitor.monitor()
EOF

    chmod +x "$PY_SCRIPT"
    echo -e "${GREEN}✓ 监控脚本已生成${RESET}"
}

# 前后台控制
toggle_foreground() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}>>> 切换到前台显示...${RESET}"
            tail -f "$LOG_FILE"
        else
            echo -e "${RED}>>> 监控进程未运行${RESET}"
        fi
    else
        echo -e "${RED}>>> 监控进程未运行${RESET}"
    fi
}

# 启动监控
start_monitor() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}>>> 监控已在运行 (PID: $pid)${RESET}"
            echo -e "${YELLOW}>>> 是否切换到前台显示? (y/N)：${RESET}"
            read -n 1 show_log
            echo
            if [[ $show_log =~ ^[Yy]$ ]]; then
                toggle_foreground
            fi
            return
        fi
    fi
    
    generate_python_script
    echo -e "${GREEN}>>> 启动监控进程...${RESET}"
    nohup python3 $PY_SCRIPT > "$LOG_FILE" 2>&1 & 
    echo $! > "$PIDFILE"
    echo -e "${GREEN}>>> 监控已在后台启动 (PID: $!)${RESET}"
    echo -e "${GREEN}>>> 使用'3'选项可切换前台显示${RESET}"
}

# 主菜单
show_menu() {
    echo -e "\n${BLUE}Solana Pump监控系统 v4.0${RESET}"
    echo "1. 启动监控"
    echo "2. 配置API密钥"
    echo "3. 切换前台显示"
    echo "4. RPC节点管理"
    echo "5. 通知设置"
    echo "6. 关注地址管理"
    echo "7. 退出"
    echo -n "请选择 [1-7]: "
}

# 主程序入口
case $1 in
    "--daemon")
        generate_python_script
        exec python3 $PY_SCRIPT
        ;;
    "--start")
        install_dependencies
        start_monitor
        ;;
    *)
        install_dependencies
        while true; do
            show_menu
            read choice
            case $choice in
                1) start_monitor ;;
                2) init_config ;;
                3) toggle_foreground ;;
                4) manage_rpc ;;
                5) setup_notification ;;
                6) manage_watch_addresses ;;
                7) 
                    if [ -f "$PIDFILE" ]; then
                        pid=$(cat "$PIDFILE")
                        kill "$pid" 2>/dev/null
                        rm "$PIDFILE"
                    fi
                    exit 0 
                    ;;
                *) echo -e "${RED}无效选项!${RESET}" ;;
            esac
        done
        ;;
esac
