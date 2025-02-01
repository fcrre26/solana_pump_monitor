#!/bin/bash

# Solana Pump.fun智能监控系统 v3.0
# 功能：全自动监控+市值分析+多API轮询+智能RPC管理

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
    
    echo -e "${YELLOW}>>> 是否配置微信通知? (y/N)：${RESET}"
    read -n 1 setup_wechat
    echo
    
    if [[ $setup_wechat =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}>>> 请输入Server酱密钥：${RESET}"
        read -s SENDKEY
        echo "SENDKEY='$SENDKEY'" > $CONFIG_FILE
    else
        echo "SENDKEY=''" > $CONFIG_FILE
    fi
    
    echo "API_KEYS='$api_keys'" >> $CONFIG_FILE
    chmod 600 $CONFIG_FILE
    echo -e "\n${GREEN}✓ 配置已保存到 $CONFIG_FILE${RESET}"
}

# 微信通知设置
setup_wechat() {
    echo -e "${YELLOW}>>> 微信通知设置${RESET}"
    echo "1. 开启微信通知"
    echo "2. 关闭微信通知"
    echo "3. 更新Server酱密钥"
    echo "4. 返回主菜单"
    echo -n "请选择 [1-4]: "
    read choice

    case $choice in
        1|3)
            echo -e "${YELLOW}>>> 请输入Server酱密钥：${RESET}"
            read -s SENDKEY
            echo
            if [ -f "$CONFIG_FILE" ]; then
                API_KEYS=$(grep "API_KEYS" "$CONFIG_FILE" || echo "API_KEYS=''")
                echo "$API_KEYS" > "$CONFIG_FILE"
                echo "SENDKEY='$SENDKEY'" >> "$CONFIG_FILE"
            else
                echo "API_KEYS=''" > "$CONFIG_FILE"
                echo "SENDKEY='$SENDKEY'" >> "$CONFIG_FILE"
            fi
            chmod 600 "$CONFIG_FILE"
            echo -e "${GREEN}✓ 微信通知已开启${RESET}"
            ;;
        2)
            if [ -f "$CONFIG_FILE" ]; then
                API_KEYS=$(grep "API_KEYS" "$CONFIG_FILE" || echo "API_KEYS=''")
                echo "$API_KEYS" > "$CONFIG_FILE"
                echo "SENDKEY=''" >> "$CONFIG_FILE"
            fi
            chmod 600 "$CONFIG_FILE"
            echo -e "${GREEN}✓ 微信通知已关闭${RESET}"
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选项!${RESET}"
            ;;
    esac
}

# RPC节点管理
manage_rpc() {
    echo -e "${YELLOW}>>> RPC节点管理${RESET}"
    echo "1. 导入RPC节点列表"
    echo "2. 查看当前节点"
    echo "3. 测试节点延迟"
    echo "4. 返回主菜单"
    echo -n "请选择 [1-4]: "
    read choice

    case $choice in
        1)
            echo -e "${YELLOW}>>> 请粘贴RPC节点列表 (完成后按Ctrl+D)：${RESET}"
            node_data=$(cat)
            python3 -c "
import sys, json, time, logging
from datetime import datetime, timezone, timedelta

# 设置UTC+8时区
TZ = timezone(timedelta(hours=8))

logging.basicConfig(level=logging.INFO)

class RPCManager:
    def __init__(self):
        self.rpc_nodes = []
        self.config_file = '$RPC_FILE'

    def parse_rpc_list(self, data):
        nodes = []
        for line in data.split('\n'):
            if '|' not in line or '===' in line:
                continue
            try:
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= 4:
                    latency = float(parts[2].replace('ms', ''))
                    node = {
                        'ip': parts[1],
                        'latency': latency,
                        'provider': parts[3],
                        'location': parts[4] if len(parts) > 4 else 'Unknown',
                        'endpoint': f'https://{parts[1].strip()}:8899'
                    }
                    nodes.append(node)
            except Exception as e:
                logging.error(f'解析节点数据失败: {line} - {str(e)}')
                continue
        nodes.sort(key=lambda x: x['latency'])
        return nodes

    def add_nodes(self, data):
        new_nodes = self.parse_rpc_list(data)
        if not new_nodes:
            logging.error('没有解析到有效的节点数据')
            return False
        valid_nodes = [n for n in new_nodes if n['latency'] < 300]
        if not valid_nodes:
            logging.error('没有找到延迟合格的节点')
            return False
        self.rpc_nodes = valid_nodes
        self.save_nodes()
        logging.info(f'已添加 {len(valid_nodes)} 个有效节点')
        self.print_nodes()
        return True

    def save_nodes(self):
        try:
            with open(self.config_file, 'w') as f:
                for node in self.rpc_nodes:
                    f.write(json.dumps(node) + '\n')
            logging.info(f'节点信息已保存到 {self.config_file}')
        except Exception as e:
            logging.error(f'保存节点信息失败: {str(e)}')

    def print_nodes(self):
        print('\n当前RPC节点列表:')
        print('=' * 80)
        print(f\"{'IP地址':15} | {'延迟':7} | {'供应商':15} | {'位置':30}\")
        print('-' * 80)
        for node in self.rpc_nodes:
            print(f\"{node['ip']:15} | {node['latency']:5.1f}ms | {node['provider']:15} | {node['location']:30}\")

manager = RPCManager()
manager.add_nodes('''$node_data''')" || echo -e "${RED}处理节点数据失败${RESET}"
            ;;
        2)
            if [ -f "$RPC_FILE" ]; then
                echo -e "${GREEN}当前RPC节点列表：${RESET}"
                python3 -c "
import json
with open('$RPC_FILE') as f:
    print('=' * 80)
    print(f\"{'IP地址':15} | {'延迟':7} | {'供应商':15} | {'位置':30}\")
    print('-' * 80)
    for line in f:
        node = json.loads(line)
        print(f\"{node['ip']:15} | {node['latency']:5.1f}ms | {node['provider']:15} | {node['location']:30}\")
"
            else
                echo -e "${RED}未找到RPC节点配置文件${RESET}"
            fi
            ;;
        3)
            if [ -f "$RPC_FILE" ]; then
                echo -e "${YELLOW}>>> 测试节点延迟...${RESET}"
                python3 -c "
import json, requests, time
with open('$RPC_FILE', 'r') as f:
    nodes = [json.loads(line) for line in f]

for node in nodes:
    try:
        start = time.time()
        resp = requests.post(
            node['endpoint'],
            json={'jsonrpc':'2.0','id':1,'method':'getHealth'},
            timeout=3
        )
        latency = (time.time() - start) * 1000
        status = '✓' if resp.status_code == 200 else '✗'
        print(f\"{status} {node['ip']:15} | {latency:5.1f}ms\")
    except:
        print(f\"✗ {node['ip']:15} | 超时\")
"
            else
                echo -e "${RED}未找到RPC节点配置文件${RESET}"
            fi
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选项!${RESET}"
            ;;
    esac
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
        self.api_keys = []
        self.current_key = 0
        self.request_counts = {}
        self.last_reset = {}
        self.load_config()

    def load_config(self):
        try:
            with open(self.config_file) as f:
                config = {}
                for line in f:
                    if '=' in line:
                        key, val = line.strip().split('=', 1)
                        config[key] = val.strip("'")
                
                self.api_keys = config.get('API_KEYS', '').split('\n')
                self.sendkey = config.get('SENDKEY', '')
                
                for key in self.api_keys:
                    if key.strip():
                        self.request_counts[key] = 0
                        self.last_reset[key] = time.time()
        except Exception as e:
            logging.error(f"加载配置失败: {e}")
            sys.exit(1)

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
                tokens = []
                for activity in data["data"]:
                    if activity.get("type") == "token_creation":
                        token_info = self.fetch_token_info(activity["mint"])
                        tokens.append({
                            "mint": activity["mint"],
                            "timestamp": activity["timestamp"],
                            "market_cap": token_info["market_cap"],
                            "status": "活跃" if token_info["liquidity"] > 0 else "已退出"
                        })
                return tokens
        except Exception as e:
            logging.error(f"分析创建者历史失败: {e}")
        return []

    def format_alert_message(self, data):
        creator = data["creator"]
        mint = data["mint"]
        token_info = data["token_info"]
        history = data["history"]
        
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

📜 历史代币记录:
"""
        
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

    def send_alert(self, msg):
        if self.sendkey:
            try:
                requests.post(
                    f"https://sctapi.ftqq.com/{self.sendkey}.send",
                    data={"title": "Solana新代币提醒", "desp": msg},
                    timeout=5
                )
            except Exception as e:
                logging.error(f"发送提醒失败: {e}")

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
                        block = requests.post(rpc, {
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
                                    
                                    alert_data = {
                                        "creator": creator,
                                        "mint": mint,
                                        "token_info": token_info,
                                        "history": history
                                    }
                                    
                                    alert_msg = self.format_alert_message(alert_data)
                                    logging.info("\n" + alert_msg)
                                    self.send_alert(alert_msg)
                    
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
    pip3 install requests

    echo -e "${GREEN}✓ 依赖安装完成${RESET}"
}

# 主菜单
show_menu() {
    echo -e "\n${BLUE}Solana Pump监控系统 v3.0${RESET}"
    echo "1. 启动监控"
    echo "2. 配置API密钥"
    echo "3. 切换前台显示"
    echo "4. RPC节点管理"
    echo "5. 微信通知设置"
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
                5) setup_wechat ;;
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
