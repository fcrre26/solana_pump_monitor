#!/bin/bash

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

# 初始化配置
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

# 通知设置
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

# RPC节点管理
# RPC节点管理
manage_rpc() {
    ANALYSIS_FILE="$HOME/.solana_pump/rpc_analysis.txt"
    mkdir -p "$HOME/.solana_pump"
    
    # 默认公共RPC节点列表
    DEFAULT_RPC_NODES='
# Solana 官方公共RPC节点
api.mainnet-beta.solana.com | 100 | Solana | Official Mainnet
api.devnet.solana.com | 100 | Solana | Official Devnet

# GenesysGo
ssc-dao.genesysgo.net | 100 | GenesysGo | US
free.rpcpool.com | 100 | GenesysGo | US

# Ankr
rpc.ankr.com/solana | 100 | Ankr | Global

# Triton
https://solana-api.projectserum.com | 100 | Project Serum | US

# QuickNode
solana-mainnet.rpc.extrnode.com | 100 | QuickNode | Global

# Alchemy
solana-mainnet.g.alchemy.com | 100 | Alchemy | Global

# Figment
solana-rpc.publicnode.com | 100 | Figment | Global

# Helius
rpc.helius.xyz | 100 | Helius | US

# RunNode
mainnet.rpcpool.com | 100 | RunNode | Global

# Serum
solana-api.projectserum.com | 100 | Serum | US

# Triton
https://rpc.solana.theindex.io | 100 | Triton | Global

# Chainstack
solana-mainnet.chainstack.com | 100 | Chainstack | Global

# BlockDaemon
mainnet.solana.blockdaemon.tech | 100 | BlockDaemon | US

# 33.cn
rpc.33.cn | 100 | 33.cn | China
rpc.33.cn:8899 | 100 | 33.cn | China

# MetaBlock
api.metablocks.world/solana | 100 | MetaBlock | Global

# Syndica
solana-mainnet.syndica.io | 100 | Syndica | Global

# NOWNodes
solana.nownodes.io | 100 | NOWNodes | Global

# GetBlock
sol.getblock.io | 100 | GetBlock | Global

# Pocket Network
solana-mainnet.gateway.pokt.network | 100 | Pocket | Global

# Blockdaemon
mainnet.solana.blockdaemon.tech | 100 | Blockdaemon | US

# Allnodes
solana.public-rpc.com | 100 | Allnodes | Global

# Solana Beach
rpc.solanabeach.io | 100 | SolanaBeach | Global

# Solflare
rpc.solflare.com | 100 | Solflare | Global

# Validators
validator.rpcpool.com | 100 | Validators | Global

# Solana FM
mainnet-beta.rpc.solanafm.com | 100 | SolanaFM | Global

# Solanium
rpc.solanium.io | 100 | Solanium | Global

# Solscan
api.solscan.io | 100 | Solscan | Global

# Raydium
raydium.rpcpool.com | 100 | Raydium | Global

# Magic Eden
rpc-mainnet.magiceden.io | 100 | MagicEden | Global

# Jupiter
rpc.jup.ag | 100 | Jupiter | Global

# Orca
api.mainnet-beta.orca.so | 100 | Orca | Global

# Marinade
rpc.marinade.finance | 100 | Marinade | Global

# Drift
solana-rpc.drift.trade | 100 | Drift | Global

# Mango
api.mngo.cloud | 100 | Mango | Global

# Metaplex
api.metaplex.solana.com | 100 | Metaplex | Global

# Phantom
solana-mainnet.phantom.tech | 100 | Phantom | Global

# Exodus
solana.exodus.com | 100 | Exodus | Global

# Slope
mainnet.rpcpool.com | 100 | Slope | Global'

    while true; do
        echo -e "\n${YELLOW}>>> RPC节点管理${RESET}"
        echo "1. 导入节点列表"
        echo "2. 查看当前节点"
        echo "3. 测试节点延迟"
        echo "4. 编辑节点列表"
        echo "5. 使用默认公共RPC"
        echo "6. 返回主菜单"
        echo -n "请选择 [1-6]: "
        read choice
                case $choice in
            1)
                echo -e "${YELLOW}>>> 请粘贴节点列表 (格式: IP | 延迟 | 供应商 | 位置)${RESET}"
                echo -e "${YELLOW}>>> 输入完成后请按Ctrl+D结束${RESET}"
                cat > "$ANALYSIS_FILE"
                
                if [ -f "$ANALYSIS_FILE" ]; then
                    # 生成处理脚本
                    cat > "$HOME/.solana_pump/process_rpc.py" << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import json
import requests
from concurrent.futures import ThreadPoolExecutor

def test_node_latency(node, timeout=3, retries=2):
    """
    测试RPC节点延迟和可用性
    返回 (延迟, 是否可用)
    """
    # 确保IP地址格式正确
    ip = node['ip'].strip()
    
    # 处理URL格式
    if ip.startswith('http://') or ip.startswith('https://'):
        endpoint = ip
    else:
        base_ip = ip.split(':')[0]  # 获取基本IP，不含端口
        if ':' not in ip:  # 如果没有指定端口
            endpoint = f"https://{base_ip}:8899"
        else:
            endpoint = f"https://{ip}"
    
    headers = {
        "Content-Type": "application/json"
    }
    
    # 测试getSlot，验证节点是否正常工作
    slot_data = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getSlot",
    }
    
    # 测试getHealth，获取延迟
    health_data = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getHealth",
    }
    
    latencies = []
    is_working = False
    
    for _ in range(retries):
        try:
            # 先测试getSlot
            response = requests.post(
                endpoint, 
                headers=headers,
                json=slot_data,
                timeout=timeout,
                verify=False
            )
            
            if response.status_code == 200:
                slot_result = response.json()
                if 'result' in slot_result:  # 确认能获取到slot
                    # 然后测试延迟
                    start_time = time.time()
                    response = requests.post(
                        endpoint, 
                        headers=headers,
                        json=health_data,
                        timeout=timeout,
                        verify=False
                    )
                    end_time = time.time()
                    
                    if response.status_code == 200:
                        latency = (end_time - start_time) * 1000
                        latencies.append(latency)
                        is_working = True
                        
        except Exception as e:
            continue
            
    return (min(latencies) if latencies else 999, is_working)

def process_rpc_list(input_file, output_file, batch_size=100):
    """分批处理RPC节点列表"""
    nodes = []
    batch = []
    batch_count = 0
    processed_ips = set()
    total_lines = 0
    valid_lines = 0
    
    print(f"\n\033[33m>>> 开始处理RPC节点列表...\033[0m")
    
    # 禁用SSL警告
    import urllib3
    urllib3.disable_warnings()
    
    # 首先计算有效行数
    with open(input_file, 'r') as f:
        for line in f:
            if line.strip() and not line.strip().startswith('#'):
                total_lines += 1
                if '|' in line:
                    valid_lines += 1
    
    print(f"\n\033[33m>>> 总行数: {total_lines}, 有效节点数: {valid_lines}\033[0m")
    
    with open(input_file, 'r') as f:
        for line in f:
            # 跳过空行和注释
            if not line.strip() or line.strip().startswith('#'):
                continue
                
            if '|' not in line:
                continue
                
            try:
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= 4:
                    ip = parts[0].strip()
                    
                    # 跳过重复IP
                    base_ip = ip.split(':')[0] if ':' in ip else ip  # 获取基本IP，不含端口
                    base_ip = base_ip.replace('https://', '').replace('http://', '')
                    if base_ip in processed_ips:
                        continue
                    processed_ips.add(base_ip)
                    
                    try:
                        reported_latency = float(parts[1].replace('ms', ''))
                    except:
                        reported_latency = 999
                    
                    node = {
                        'ip': ip,
                        'reported_latency': reported_latency,
                        'real_latency': 999,
                        'is_working': False,
                        'provider': parts[2].strip(),
                        'location': parts[3].strip() if len(parts) > 3 else 'Unknown'
                    }
                    
                    batch.append(node)
                    
                    if len(batch) >= batch_size:
                        print(f"\n\033[33m>>> 测试第 {batch_count+1} 批节点 ({len(batch)}个)... 总进度: {len(nodes)+len(batch)}/{valid_lines}\033[0m")
                        test_nodes_batch(batch)
                        nodes.extend(batch)
                        batch = []
                        batch_count += 1
                        
            except Exception as e:
                continue
    
    # 处理最后一批
    if batch:
        print(f"\n\033[33m>>> 测试最后一批节点 ({len(batch)}个)... 总进度: {len(nodes)+len(batch)}/{valid_lines}\033[0m")
        test_nodes_batch(batch)
        nodes.extend(batch)
    
    # 按实际延迟排序，但只考虑工作正常的节点
    print(f"\n\033[33m>>> 正在排序节点...\033[0m")
    nodes.sort(key=lambda x: (not x.get('is_working', False), x['real_latency']))
    
    # 只保留正常工作且延迟小于300ms的节点
    valid_nodes = [n for n in nodes if n.get('is_working', False) and n['real_latency'] < 300]
    
    # 保存到RPC文件
    print(f"\033[33m>>> 正在保存有效节点...\033[0m")
    with open(output_file, 'w') as f:
        for node in valid_nodes:
            # 构建endpoint
            ip = node['ip']
            if not (ip.startswith('http://') or ip.startswith('https://')):
                if ':' not in ip:
                    node['endpoint'] = f"https://{ip}:8899"
                else:
                    node['endpoint'] = f"https://{ip}"
            else:
                node['endpoint'] = ip
            f.write(json.dumps(node) + '\n')
    
    print(f"\n\033[32m✓ 处理完成")
    print(f"总节点数: {len(nodes)}")
    print(f"有效节点数: {len(valid_nodes)}")
    print(f"可用率: {len(valid_nodes)/len(nodes)*100:.1f}%")
    print(f"结果已保存到: {output_file}\033[0m")
    
    # 打印节点信息
    print('\n当前最快的10个RPC节点:')
    print('=' * 120)
    print(f"{'节点地址':50} | {'实测延迟':8} | {'报告延迟':8} | {'状态':6} | {'供应商':15} | {'位置':20}")
    print('-' * 120)
    for node in valid_nodes[:10]:
        status = '\033[32m可用\033[0m' if node.get('is_working', False) else '\033[31m不可用\033[0m'
        print(f"{node['ip']:50} | {node['real_latency']:6.1f}ms | {node['reported_latency']:6.1f}ms | {status:8} | {node['provider']:15} | {node['location']:20}")

def test_nodes_batch(nodes, max_workers=20):
    """并行测试节点"""
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = []
        total = len(nodes)
        working_count = 0
        
        for i, node in enumerate(nodes, 1):
            future = executor.submit(test_node_latency, node)
            futures.append((node, future))
            
        for i, (node, future) in enumerate(futures, 1):
            try:
                latency, is_working = future.result()
                node['real_latency'] = latency
                node['is_working'] = is_working
                if is_working:
                    working_count += 1
                status = '\033[32m可用\033[0m' if is_working else '\033[31m不可用\033[0m'
                print(f"\r处理: {i}/{total} | 节点: {node['ip']:50} | 延迟: {latency:6.1f}ms | 状态: {status} | 可用率: {working_count/i*100:5.1f}%", end='\n')
            except Exception as e:
                node['real_latency'] = 999
                node['is_working'] = False
                print(f"\r处理: {i}/{total} | 节点: {node['ip']:50} | 延迟: 999.0ms | 状态: \033[31m错误\033[0m | 可用率: {working_count/i*100:5.1f}%", end='\n')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 process_rpc.py input_file output_file")
        sys.exit(1)
    
    try:
        process_rpc_list(sys.argv[1], sys.argv[2])
    except Exception as e:
        print(f"\n\033[31m错误: {e}\033[0m")
        sys.exit(1)
EOF

                    chmod +x "$HOME/.solana_pump/process_rpc.py"
                    
                    # 运行处理脚本
                    "$HOME/.solana_pump/process_rpc.py" "$ANALYSIS_FILE" "$RPC_FILE"
                else
                    echo -e "${RED}>>> 节点列表文件不存在${RESET}"
                fi
                ;;
            2)
                if [ -f "$RPC_FILE" ]; then
                    echo -e "\n${YELLOW}>>> 当前RPC节点列表：${RESET}"
                    cat "$RPC_FILE"
                else
                    echo -e "${RED}>>> RPC节点列表为空${RESET}"
                fi
                ;;
            3)
                if [ -f "$RPC_FILE" ]; then
                    echo -e "${YELLOW}>>> 开始测试节点延迟...${RESET}"
                    "$HOME/.solana_pump/process_rpc.py" "$RPC_FILE" "$RPC_FILE.new"
                    if [ $? -eq 0 ]; then
                        mv "$RPC_FILE.new" "$RPC_FILE"
                    fi
                else
                    echo -e "${RED}>>> RPC节点列表为空${RESET}"
                fi
                ;;
            4)
                # 编辑节点列表
                if [ -n "$(command -v vim)" ]; then
                    vim "$ANALYSIS_FILE"
                else
                    nano "$ANALYSIS_FILE"
                fi
                ;;
            5)
                echo -e "${YELLOW}>>> 使用默认公共RPC节点...${RESET}"
                echo "$DEFAULT_RPC_NODES" > "$ANALYSIS_FILE"
                "$HOME/.solana_pump/process_rpc.py" "$ANALYSIS_FILE" "$RPC_FILE"
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

# 生成Python监控脚本
generate_python_script() {
    cat > $PY_SCRIPT << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import json
import logging
import requests
from datetime import datetime, timezone, timedelta
from concurrent.futures import ThreadPoolExecutor
from wcferry import Wcf

# 设置UTC+8时区
TZ = timezone(timedelta(hours=8))

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('monitor.log'),
        logging.StreamHandler()
    ]
)

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
        
        for key in self.api_keys:
            if key.strip():
                self.request_counts[key] = 0
                self.last_reset[key] = time.time()

    def load_config(self):
        try:
            with open(self.config_file) as f:
                return json.load(f)
        except Exception as e:
            logging.error(f"加载配置失败: {e}")
            return {"api_keys": [], "serverchan": {"keys": []}, "wcf": {"groups": []}}

    def load_watch_addresses(self):
        """加载关注地址列表"""
        try:
            with open(self.watch_file) as f:
                data = json.load(f)
                return {addr['address']: addr['note'] for addr in data.get('addresses', [])}
        except Exception as e:
            logging.error(f"加载关注地址失败: {e}")
            return {}

    def init_wcf(self):
        """初始化WeChatFerry"""
        if self.config['wcf']['groups']:
            try:
                self.wcf = Wcf()
                logging.info("WeChatFerry初始化成功")
            except Exception as e:
                logging.error(f"WeChatFerry初始化失败: {e}")
                self.wcf = None

    def get_next_api_key(self):
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
        try:
            headers = {"X-API-KEY": self.get_next_api_key()}
            url = f"https://public-api.birdeye.so/public/token_metadata?address={mint}"
            resp = requests.get(url, headers=headers, timeout=5)
            data = resp.json()
            
            if data.get("success"):
                token_data = data["data"]
                return {
                    "price": float(token_data.get("price", 0)),
                    "supply": float(token_data.get("supply", 0)),
                    "market_cap": float(token_data.get("price", 0)) * float(token_data.get("supply", 0)),
                    "liquidity": float(token_data.get("liquidity", 0))
                }
        except Exception as e:
            logging.error(f"获取代币信息失败: {e}")
        
        return {"price": 0, "supply": 0, "market_cap": 0, "liquidity": 0}

    def analyze_creator_history(self, creator):
        try:
            headers = {"X-API-KEY": self.get_next_api_key()}
            url = f"https://public-api.birdeye.so/public/address_activity?address={creator}"
            resp = requests.get(url, headers=headers, timeout=5)
            data = resp.json()
            
            if data.get("success"):
                history = []
                for tx in data["data"]:
                    if "mint" in tx:
                        token_info = self.fetch_token_info(tx["mint"])
                        history.append({
                            "mint": tx["mint"],
                            "timestamp": tx["timestamp"],
                            "market_cap": token_info["market_cap"],
                            "status": "活跃" if token_info["market_cap"] > 0 else "已退出"
                        })
                return history
        except Exception as e:
            logging.error(f"获取创建者历史失败: {e}")
        
        return []

    def analyze_creator_relations(self, creator):
        """分析创建者地址关联性"""
        try:
            related_addresses = set()
            relations = []
            watch_hits = []  # 新增：记录命中的关注地址
            
            # 1. 分析转账历史
            headers = {"X-API-KEY": self.get_next_api_key()}
            url = f"https://public-api.birdeye.so/public/address_activity?address={creator}"
            resp = requests.get(url, headers=headers, timeout=5)
            data = resp.json()
            
            if data.get("success"):
                for tx in data["data"]:
                    # 记录所有交互过的地址
                    if tx.get("from") and tx["from"] != creator:
                        related_addresses.add(tx["from"])
                        # 检查是否是关注地址
                        if tx["from"] in self.watch_addresses:
                            watch_hits.append({
                                'address': tx["from"],
                                'note': self.watch_addresses[tx["from"]],
                                'type': 'transfer_from'
                            })
                            
                    if tx.get("to") and tx["to"] != creator:
                        related_addresses.add(tx["to"])
                        # 检查是否是关注地址
                        if tx["to"] in self.watch_addresses:
                            watch_hits.append({
                                'address': tx["to"],
                                'note': self.watch_addresses[tx["to"]],
                                'type': 'transfer_to'
                            })
                        
                    # 特别关注大额转账
                    if tx.get("amount", 0) > 1:  # 1 SOL以上的转账
                        relations.append({
                            "address": tx["to"] if tx["from"] == creator else tx["from"],
                            "type": "transfer",
                            "amount": tx["amount"],
                            "timestamp": tx["timestamp"]
                        })
            
            # 2. 分析代币创建历史
            for address in related_addresses:
                token_history = self.analyze_creator_history(address)
                if token_history:
                    relations.append({
                        "address": address,
                        "type": "token_creator",
                        "tokens": len(token_history),
                        "success_rate": sum(1 for t in token_history if t["status"] == "活跃") / len(token_history)
                    })
            
            # 3. 分析共同签名者
            for address in related_addresses:
                try:
                    tx_url = f"https://public-api.solscan.io/account/transactions?account={address}"
                    tx_resp = requests.get(tx_url, timeout=5)
                    tx_data = tx_resp.json()
                    
                    for tx in tx_data[:100]:  # 只看最近100笔交易
                        if creator in tx.get("signatures", []):
                            relations.append({
                                "address": address,
                                "type": "co_signer",
                                "tx_hash": tx["signature"],
                                "timestamp": tx["blockTime"]
                            })
                except:
                    continue
            
            return {
                "related_addresses": list(related_addresses),
                "relations": relations,
                "watch_hits": watch_hits,  # 新增：返回命中的关注地址
                "risk_score": self.calculate_risk_score(relations)
            }
        except Exception as e:
            logging.error(f"分析地址关联性失败: {e}")
            return {"related_addresses": [], "relations": [], "watch_hits": [], "risk_score": 0}

    def calculate_risk_score(self, relations):
        """计算风险分数"""
        score = 0
        
        # 统计关联地址数量
        unique_addresses = len(set(r["address"] for r in relations))
        if unique_addresses > 10:
            score += 20
        
        # 分析代币创建者历史
        token_creators = [r for r in relations if r["type"] == "token_creator"]
        if token_creators:
            avg_success = sum(t["success_rate"] for t in token_creators) / len(token_creators)
            if avg_success < 0.3:  # 成功率低于30%
                score += 30
        
        # 分析大额转账
        large_transfers = [r for r in relations if r["type"] == "transfer" and r["amount"] > 10]
        if large_transfers:
            score += min(len(large_transfers) * 5, 25)
        
        # 分析共同签名
        co_signers = [r for r in relations if r["type"] == "co_signer"]
        if co_signers:
            score += min(len(co_signers) * 2, 25)
        
        return min(score, 100)  # 最高100分

    def format_alert_message(self, data):
        creator = data["creator"]
        mint = data["mint"]
        token_info = data["token_info"]
        history = data["history"]
        relations = data["relations"]
        
        active_tokens = sum(1 for t in history if t["status"] == "活跃")
        success_rate = active_tokens / len(history) if history else 0
        
        msg = f"""
🚨 新代币警报 (UTC+8)
━━━━━━━━━━━━━━━━━━━━━━━━

📋 合约地址: 
{mint}

👤 创建者地址: 
{creator}"""

        # 添加关注地址信息
        if creator in self.watch_addresses:
            msg += f"\n⭐ 重点关注地址！\n备注: {self.watch_addresses[creator]}"

        msg += f"""

💰 代币信息:
• 初始市值: ${token_info['market_cap']:,.2f}
• 代币供应量: {token_info['supply']:,.0f}
• 单价: ${token_info['price']:.8f}
• 流动性: {token_info['liquidity']:.2f} SOL

👥 地址关联分析:
• 关联地址数: {len(relations['related_addresses'])}
• 风险评分: {relations['risk_score']}/100
"""
        
        # 添加关联的关注地址信息
        if relations['watch_hits']:
            msg += "\n⚠️ 发现关联的关注地址:\n"
            for hit in relations['watch_hits']:
                msg += f"• {hit['address']}\n  备注: {hit['note']}\n  关联类型: {hit['type']}\n"
        
        # 添加重要关联信息
        important_relations = [r for r in relations['relations'] 
                             if r["type"] in ["token_creator", "co_signer"] 
                             or (r["type"] == "transfer" and r["amount"] > 10)]
        if important_relations:
            msg += "\n🔍 重要关联:\n"
            for r in sorted(important_relations, 
                           key=lambda x: x.get("timestamp", 0), 
                           reverse=True)[:3]:
                if r["type"] == "token_creator":
                    msg += f"• 关联创建者: {r['address'][:8]}...{r['address'][-6:]}\n"
                    msg += f"  - 代币数: {r['tokens']}\n"
                    msg += f"  - 成功率: {r['success_rate']:.0%}\n"
                elif r["type"] == "transfer":
                    msg += f"• 大额转账: {r['amount']} SOL\n"
                    msg += f"  - 地址: {r['address'][:8]}...{r['address'][-6:]}\n"
                elif r["type"] == "co_signer":
                    msg += f"• 共同签名: {r['address'][:8]}...{r['address'][-6:]}\n"
        
        msg += "\n📜 历史代币记录:\n"
        for token in sorted(history, key=lambda x: x["timestamp"], reverse=True)[:5]:
            timestamp = datetime.fromtimestamp(token["timestamp"], tz=TZ)
            msg += f"• {timestamp.strftime('%Y-%m-%d %H:%M:%S')} - {token['mint']}\n"
            msg += f"  - 市值: ${token['market_cap']:,.0f}\n"
            msg += f"  - 当前状态: {token['status']}\n"
        
        current_time = datetime.now(TZ).strftime('%Y-%m-%d %H:%M:%S')
        msg += f"""
⚠️ 风险提示:
• 创建者历史代币数: {len(history)}
• 成功率: {success_rate:.0%}

🔗 快速链接:
• Birdeye: https://birdeye.so/token/{mint}
• Solscan: https://solscan.io/token/{mint}

⏰ 发现时间: {current_time} (UTC+8)
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
    monitor = TokenMonitor()
    monitor.monitor()
EOF

    chmod +x $PY_SCRIPT
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

# 关注地址管理
manage_watch_addresses() {
    WATCH_FILE="$HOME/.solana_pump/watch_addresses.json"
    
    # 确保文件存在
    if [ ! -f "$WATCH_FILE" ]; then
        echo '{"addresses":[]}' > "$WATCH_FILE"
    fi
    
    while true; do
        echo -e "\n${YELLOW}>>> 关注地址管理${RESET}"
        echo "1. 添加关注地址"
        echo "2. 删除关注地址"
        echo "3. 查看关注列表"
        echo "4. 导入地址列表"
        echo "5. 返回主菜单"
        echo -n "请选择 [1-5]: "
        read choice
        
        case $choice in
            1)
                echo -e "${YELLOW}>>> 请输入要关注的地址：${RESET}"
                read address
                if [ ${#address} -eq 44 ]; then
                    echo -e "${YELLOW}>>> 请输入备注信息：${RESET}"
                    read note
                    
                    # 添加到JSON文件
                    tmp=$(mktemp)
                    jq --arg addr "$address" \
                       --arg note "$note" \
                       --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
                       '.addresses += [{"address": $addr, "note": $note, "added_time": $time}]' \
                       "$WATCH_FILE" > "$tmp" && mv "$tmp" "$WATCH_FILE"
                    
                    echo -e "${GREEN}✓ 地址已添加到关注列表${RESET}"
                else
                    echo -e "${RED}✗ 无效的Solana地址${RESET}"
                fi
                ;;
            2)
                addresses=$(jq -r '.addresses[] | "\(.address) [\(.note)]"' "$WATCH_FILE")
                if [ ! -z "$addresses" ]; then
                    echo -e "\n当前关注的地址："
                    i=1
                    while IFS= read -r line; do
                        echo "$i. $line"
                        i=$((i+1))
                    done <<< "$addresses"
                    
                    echo -e "\n${YELLOW}>>> 请输入要删除的编号：${RESET}"
                    read num
                    if [[ $num =~ ^[0-9]+$ ]]; then
                        tmp=$(mktemp)
                        jq "del(.addresses[$(($num-1))])" "$WATCH_FILE" > "$tmp" && mv "$tmp" "$WATCH_FILE"
                        echo -e "${GREEN}✓ 地址已从关注列表移除${RESET}"
                    else
                        echo -e "${RED}无效的编号${RESET}"
                    fi
                else
                    echo -e "${YELLOW}没有关注的地址${RESET}"
                fi
                ;;
            3)
                addresses=$(jq -r '.addresses[] | "\(.address) [\(.note)] - 添加时间: \(.added_time)"' "$WATCH_FILE")
                if [ ! -z "$addresses" ]; then
                    echo -e "\n当前关注的地址："
                    echo "=============================================="
                    i=1
                    while IFS= read -r line; do
                        echo "$i. $line"
                        i=$((i+1))
                    done <<< "$addresses"
                    echo "=============================================="
                else
                    echo -e "${YELLOW}没有关注的地址${RESET}"
                fi
                ;;
            4)
                echo -e "${YELLOW}>>> 请粘贴地址列表（每行格式：地址 备注），完成后按Ctrl+D：${RESET}"
                while IFS= read -r line; do
                    address=$(echo "$line" | awk '{print $1}')
                    note=$(echo "$line" | cut -d' ' -f2-)
                    if [ ${#address} -eq 44 ]; then
                        tmp=$(mktemp)
                        jq --arg addr "$address" \
                           --arg note "$note" \
                           --arg time "$(date '+%Y-%m-%d %H:%M:%S')" \
                           '.addresses += [{"address": $addr, "note": $note, "added_time": $time}]' \
                           "$WATCH_FILE" > "$tmp" && mv "$tmp" "$WATCH_FILE"
                    fi
                done
                echo -e "${GREEN}✓ 地址导入完成${RESET}"
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

show_menu() {
    echo -e "\n${BLUE}Solana Pump监控系统 v4.0${RESET}"
    echo "1. 启动监控"
    echo "2. 配置API密钥"
    echo "3. 切换前台显示"
    echo "4. RPC节点管理"
    echo "5. 通知设置"
    echo "6. 关注地址管理"  # 新增
    echo "7. 退出"
    echo -n "请选择 [1-7]: "
}

# 主程序
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
