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
manage_rpc() {
    # 首先确保目录存在
    mkdir -p "$HOME/.solana_pump"
    
    # 创建分析文件（如果不存在）
    ANALYSIS_FILE="$HOME/.solana_pump/detailed_analysis.txt"
    touch "$ANALYSIS_FILE"
    
    # 确保Python依赖已安装
    pip3 install requests urllib3 >/dev/null 2>&1
    
    while true; do
        echo -e "\n${YELLOW}>>> RPC节点管理${RESET}"
        echo "1. 导入RPC节点列表"
        echo "2. 查看当前节点"
        echo "3. 测试节点延迟"
        echo "4. 编辑节点列表"
        echo "5. 返回主菜单"
        echo -n "请选择 [1-5]: "
        read choice
        
        case $choice in
            1)
                echo -e "${YELLOW}>>> 请粘贴RPC节点列表到 $ANALYSIS_FILE${RESET}"
                echo -e "${YELLOW}>>> 完成后按任意键继续...${RESET}"
                read -n 1
                
                if [ -f "$ANALYSIS_FILE" ]; then
                    # 确保目录存在
                    mkdir -p "$(dirname "$RPC_FILE")"
                    
                    # 生成Python处理脚本
                    cat > "$HOME/.solana_pump/process_rpc.py" << 'EOF'
#!/usr/bin/env python3
import sys
import json
import time
import requests
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta

# 设置UTC+8时区
TZ = timezone(timedelta(hours=8))

def test_node_latency(node, timeout=3, retries=2):
    """
    测试RPC节点延迟
    - timeout: 请求超时时间
    - retries: 重试次数
    返回最小延迟
    """
    endpoint = f"https://{node['ip'].strip()}:8899"
    headers = {
        "Content-Type": "application/json"
    }
    data = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getHealth",
    }
    
    latencies = []
    for _ in range(retries):
        try:
            start_time = time.time()
            response = requests.post(
                endpoint, 
                headers=headers,
                json=data,
                timeout=timeout,
                verify=False  # 忽略SSL证书验证
            )
            end_time = time.time()
            
            if response.status_code == 200:
                latency = (end_time - start_time) * 1000  # 转换为毫秒
                latencies.append(latency)
        except Exception as e:
            continue
            
    return min(latencies) if latencies else 999

def test_nodes_batch(nodes, max_workers=20):
    """
    并行测试一批节点
    - nodes: 节点列表
    - max_workers: 最大并行数
    """
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = []
        total = len(nodes)
        
        for i, node in enumerate(nodes, 1):
            future = executor.submit(test_node_latency, node)
            futures.append((node, future))
            print(f"\r测试进度: {i}/{total}", end='')
        
        print()  # 换行
        
        for node, future in futures:
            try:
                node['real_latency'] = future.result()
            except Exception as e:
                node['real_latency'] = 999

def process_rpc_list(input_file, output_file, batch_size=100):
    """分批处理RPC节点列表"""
    nodes = []
    batch = []
    batch_count = 0
    
    print(f"\n\033[33m>>> 开始处理RPC节点列表...\033[0m")
    
    # 禁用SSL警告
    import urllib3
    urllib3.disable_warnings()
    
    with open(input_file, 'r') as f:
        for line in f:
            if '|' not in line or '===' in line or '---' in line:
                continue
                
            try:
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= 4:
                    try:
                        reported_latency = float(parts[2].replace('ms', ''))
                    except:
                        reported_latency = 999
                    
                    node = {
                        'ip': parts[1].strip(),
                        'reported_latency': reported_latency,
                        'real_latency': 999,
                        'provider': parts[3].strip(),
                        'location': parts[4].strip() if len(parts) > 4 else 'Unknown',
                        'endpoint': f"https://{parts[1].strip()}:8899"
                    }
                    
                    batch.append(node)
                    
                    if len(batch) >= batch_size:
                        print(f"\n\033[33m>>> 测试第 {batch_count+1} 批节点 ({len(batch)}个)...\033[0m")
                        test_nodes_batch(batch)
                        nodes.extend(batch)
                        batch = []
                        batch_count += 1
                        
            except Exception as e:
                continue
    
    # 处理最后一批
    if batch:
        print(f"\n\033[33m>>> 测试最后一批节点 ({len(batch)}个)...\033[0m")
        test_nodes_batch(batch)
        nodes.extend(batch)
    
    # 按实际延迟排序
    print(f"\n\033[33m>>> 正在排序节点...\033[0m")
    nodes.sort(key=lambda x: x['real_latency'])
    
    # 只保留延迟小于300ms的节点
    valid_nodes = [n for n in nodes if n['real_latency'] < 300]
    
    # 保存到RPC文件
    print(f"\033[33m>>> 正在保存有效节点...\033[0m")
    with open(output_file, 'w') as f:
        for node in valid_nodes:
            f.write(json.dumps(node) + '\n')
    
    print(f"\n\033[32m✓ {len(valid_nodes)} 个有效节点已保存到 {output_file}\033[0m")
    
    # 打印节点信息
    print('\n当前最快的10个RPC节点:')
    print('=' * 100)
    print(f"{'IP地址':15} | {'实测延迟':8} | {'报告延迟':8} | {'供应商':15} | {'位置':30}")
    print('-' * 100)
    for node in valid_nodes[:10]:
        print(f"{node['ip']:15} | {node['real_latency']:6.1f}ms | {node['reported_latency']:6.1f}ms | {node['provider']:15} | {node['location']:30}")

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
        self.config = self.load_config()
        self.api_keys = self.config.get('api_keys', [])
        self.current_key = 0
        self.request_counts = {}
        self.last_reset = {}
        self.wcf = None
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
                    if tx.get("to") and tx["to"] != creator:
                        related_addresses.add(tx["to"])
                        
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
                "risk_score": self.calculate_risk_score(relations)
            }
        except Exception as e:
            logging.error(f"分析地址关联性失败: {e}")
            return {"related_addresses": [], "relations": [], "risk_score": 0}

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
{creator}

💰 代币信息:
• 初始市值: ${token_info['market_cap']:,.2f}
• 代币供应量: {token_info['supply']:,.0f}
• 单价: ${token_info['price']:.8f}
• 流动性: {token_info['liquidity']:.2f} SOL

👥 地址关联分析:
• 关联地址数: {len(relations['related_addresses'])}
• 风险评分: {relations['risk_score']}/100
"""
        
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

# 主菜单
show_menu() {
    echo -e "\n${BLUE}Solana Pump监控系统 v4.0${RESET}"
    echo "1. 启动监控"
    echo "2. 配置API密钥"
    echo "3. 切换前台显示"
    echo "4. RPC节点管理"
    echo "5. 通知设置"
    echo "6. 退出"
    echo -n "请选择 [1-6]: "
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
                6) 
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
                    
