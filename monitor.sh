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
BOLD='\033[1m'
RESET='\033[0m'

#===========================================
# 配置管理模块
#===========================================
# 环境状态文件
ENV_STATE_FILE="$HOME/.solana_pump/env_state"

# 检查环境状态
check_env_state() {
    if [ -f "$ENV_STATE_FILE" ]; then
        return 0
    fi
    return 1
}

# API密钥配置
init_config() {
    echo -e "${YELLOW}${BOLD}>>> 配置API密钥 (支持多个，每行一个)${RESET}"
    echo -e "${YELLOW}${BOLD}>>> 输入完成后请按Ctrl+D结束${RESET}"
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
    echo -e "\n${GREEN}${BOLD}✓ 配置已保存到 $CONFIG_FILE${RESET}"
}

# 依赖安装
install_dependencies() {
    # 如果环境状态文件存在，直接返回
    if check_env_state; then
        return 0
    fi

    echo -e "\n${YELLOW}${BOLD}>>> 首次运行需要检查环境${RESET}"
    echo -e "${BOLD}1. 检查并安装依赖${RESET}"
    echo -e "${BOLD}2. 跳过检查（如果确定环境已准备好）${RESET}"
    echo -n "请选择 [1-2]: "
    read choice

    case $choice in
        1)
            echo -e "${YELLOW}${BOLD}>>> 开始安装依赖...${RESET}"
            if command -v apt &>/dev/null; then
                PKG_MGR="apt"
                sudo apt update
            elif command -v yum &>/dev/null; then
                PKG_MGR="yum"
            else
                echo -e "${RED}${BOLD}✗ 不支持的系统!${RESET}"
                exit 1
            fi

            sudo $PKG_MGR install -y python3 python3-pip jq bc curl
            pip3 install requests wcferry

            # 创建环境状态文件
            mkdir -p "$(dirname "$ENV_STATE_FILE")"
            touch "$ENV_STATE_FILE"
            
            echo -e "${GREEN}${BOLD}✓ 依赖安装完成${RESET}"
            ;;
        2)
            echo -e "${YELLOW}${BOLD}>>> 跳过环境检查${RESET}"
            # 创建环境状态文件
            mkdir -p "$(dirname "$ENV_STATE_FILE")"
            touch "$ENV_STATE_FILE"
            ;;
        *)
            echo -e "${RED}${BOLD}无效选项!${RESET}"
            exit 1
            ;;
    esac
}

# 环境管理
manage_environment() {
    while true; do
        echo -e "\n${YELLOW}${BOLD}>>> 环境管理${RESET}"
        echo -e "${BOLD}1. 检查环境状态${RESET}"
        echo -e "${BOLD}2. 重新安装依赖${RESET}"
        echo -e "${BOLD}3. 清除环境状态${RESET}"
        echo -e "${BOLD}4. 返回主菜单${RESET}"
        echo -n "请选择 [1-4]: "
        read choice

        case $choice in
            1)
                if check_env_state; then
                    echo -e "${GREEN}${BOLD}✓ 环境已配置${RESET}"
                else
                    echo -e "${YELLOW}${BOLD}环境未配置${RESET}"
                fi
                ;;
            2)
                rm -f "$ENV_STATE_FILE"
                install_dependencies
                ;;
            3)
                rm -f "$ENV_STATE_FILE"
                echo -e "${GREEN}${BOLD}✓ 环境状态已清除${RESET}"
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}${BOLD}无效选项!${RESET}"
                ;;
        esac
    done
}

#===========================================
# 通知系统模块
#===========================================
setup_notification() {
    while true; do
        echo -e "\n${YELLOW}${BOLD}>>> 通知设置${RESET}"
        echo -e "${BOLD}1. Server酱设置${RESET}"
        echo -e "${BOLD}2. WeChatFerry设置${RESET}"
        echo -e "${BOLD}3. 测试通知${RESET}"
        echo -e "${BOLD}4. 返回主菜单${RESET}"
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
                echo -e "${RED}${BOLD}无效选项!${RESET}"
                ;;
        esac
    done
}

# Server酱设置
setup_serverchan() {
    while true; do
        echo -e "\n${YELLOW}${BOLD}>>> Server酱设置${RESET}"
        echo -e "${BOLD}1. 添加Server酱密钥${RESET}"
        echo -e "${BOLD}2. 删除Server酱密钥${RESET}"
        echo -e "${BOLD}3. 查看当前密钥${RESET}"
        echo -e "${BOLD}4. 返回上级菜单${RESET}"
        echo -n "请选择 [1-4]: "
        read choice
        
        case $choice in
            1)
                echo -e "${YELLOW}${BOLD}>>> 请输入Server酱密钥：${RESET}"
                read -s key
                echo
                if [ ! -z "$key" ]; then
                    config=$(cat $CONFIG_FILE)
                    config=$(echo $config | jq --arg key "$key" '.serverchan.keys += [$key]')
                    echo $config > $CONFIG_FILE
                    echo -e "${GREEN}${BOLD}✓ Server酱密钥已添加${RESET}"
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
                    
                    echo -e "\n${YELLOW}${BOLD}>>> 请输入要删除的密钥编号：${RESET}"
                    read num
                    if [[ $num =~ ^[0-9]+$ ]]; then
                        config=$(echo $config | jq "del(.serverchan.keys[$(($num-1))])")
                        echo $config > $CONFIG_FILE
                        echo -e "${GREEN}${BOLD}✓ 密钥已删除${RESET}"
                    else
                        echo -e "${RED}${BOLD}无效的编号${RESET}"
                    fi
                else
                    echo -e "${YELLOW}${BOLD}没有已保存的密钥${RESET}"
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
                    echo -e "${YELLOW}${BOLD}没有已保存的密钥${RESET}"
                fi
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}${BOLD}无效选项!${RESET}"
                ;;
        esac
    done
}

# WeChatFerry设置
setup_wcf() {
    # 检查WeChatFerry是否已安装
    if ! python3 -c "import wcferry" 2>/dev/null; then
        echo -e "${YELLOW}${BOLD}>>> 正在安装WeChatFerry...${RESET}"
        pip3 install wcferry
        
        echo -e "${YELLOW}${BOLD}>>> 是否需要安装微信Hook工具？(y/N)：${RESET}"
        read -n 1 install_hook
        echo
        if [[ $install_hook =~ ^[Yy]$ ]]; then
            python3 -m wcferry.run
        fi
    fi
    
    while true; do
        echo -e "\n${YELLOW}${BOLD}>>> WeChatFerry设置${RESET}"
        echo -e "${BOLD}1. 配置目标群组${RESET}"
        echo -e "${BOLD}2. 删除群组配置${RESET}"
        echo -e "${BOLD}3. 查看当前配置${RESET}"
        echo -e "${BOLD}4. 重启WeChatFerry${RESET}"
        echo -e "${BOLD}5. 返回上级菜单${RESET}"
        echo -n "请选择 [1-5]: "
        read choice
        
        case $choice in
            1)
                python3 - <<EOF
import json
from wcferry import Wcf

try:
    wcf = Wcf()
    print("\n${YELLOW}${BOLD}>>> 正在获取群组列表...${RESET}")
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
    
    print("\n${GREEN}${BOLD}✓ 群组配置已更新${RESET}")
except Exception as e:
    print(f"\n${RED}${BOLD}配置失败: {e}${RESET}")
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
                    
                    echo -e "\n${YELLOW}${BOLD}>>> 请输入要删除的群组编号：${RESET}"
                    read num
                    if [[ $num =~ ^[0-9]+$ ]]; then
                        config=$(echo $config | jq "del(.wcf.groups[$(($num-1))])")
                        echo $config > $CONFIG_FILE
                        echo -e "${GREEN}${BOLD}✓ 群组已删除${RESET}"
                    else
                        echo -e "${RED}${BOLD}无效的编号${RESET}"
                    fi
                else
                    echo -e "${YELLOW}${BOLD}没有已配置的群组${RESET}"
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
                    echo -e "${YELLOW}${BOLD}没有已配置的群组${RESET}"
                fi
                ;;
            4)
                python3 -c "
from wcferry import Wcf
try:
    wcf = Wcf()
    wcf.cleanup()
    print('${GREEN}${BOLD}✓ WeChatFerry已重启${RESET}')
except Exception as e:
    print(f'${RED}${BOLD}重启失败: {e}${RESET}')
"
                ;;
            5)
                return
                ;;
            *)
                echo -e "${RED}${BOLD}无效选项!${RESET}"
                ;;
        esac
    done
}

# 测试通知
test_notification() {
    echo -e "${YELLOW}${BOLD}>>> 发送测试通知...${RESET}"
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

这是一条测试消息,用于验证通知功能是否正常工作。

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
                print(f"${GREEN}${BOLD}✓ Server酱推送成功 ({key[:8]}...{key[-8:]})${RESET}")
            else:
                print(f"${RED}${BOLD}✗ Server酱推送失败 ({key[:8]}...{key[-8:]})${RESET}")
        except Exception as e:
            print(f"${RED}${BOLD}✗ Server酱推送错误: {e}${RESET}")
    
    # WeChatFerry测试
    if config['wcf']['groups']:
        try:
            wcf = Wcf()
            for group in config['wcf']['groups']:
                try:
                    wcf.send_text(group['wxid'], test_msg)
                    print(f"${GREEN}${BOLD}✓ 微信推送成功 ({group['name']})${RESET}")
                except Exception as e:
                    print(f"${RED}${BOLD}✗ 微信推送失败 ({group['name']}): {e}${RESET}")
        except Exception as e:
            print(f"${RED}${BOLD}✗ WeChatFerry初始化失败: {e}${RESET}")

send_test_notification()
EOF
}

#===========================================
# 关注地址管理模块
#===========================================
manage_watch_addresses() {
    local WATCH_DIR="$HOME/.solana_pump"
    local WATCH_FILE="$WATCH_DIR/watch_addresses.json"
    
    # 创建目录和文件（如果不存在）
    mkdir -p "$WATCH_DIR"
    if [ ! -f "$WATCH_FILE" ]; then
        echo '{"addresses":[]}' > "$WATCH_FILE"
    fi
    
    while true; do
        echo -e "\n${YELLOW}${BOLD}>>> 关注地址管理${RESET}"
        echo -e "${BOLD}1. 添加关注地址${RESET}"
        echo -e "${BOLD}2. 删除关注地址${RESET}"
        echo -e "${BOLD}3. 查看当前地址${RESET}"
        echo -e "${BOLD}4. 返回主菜单${RESET}"
        echo -n "请选择 [1-4]: "
        read choice
        
        case $choice in
            1)
                echo -e "\n${YELLOW}${BOLD}>>> 添加关注地址${RESET}"
                echo -n "请输入Solana地址: "
                read address
                echo -n "请输入备注信息: "
                read note
                
                if [ ! -z "$address" ]; then
                    # 检查地址格式
                    if [[ ! "$address" =~ ^[1-9A-HJ-NP-Za-km-z]{32,44}$ ]]; then
                        echo -e "${RED}${BOLD}无效的Solana地址格式${RESET}"
                        continue
                    fi
                    
                    # 添加地址
                    tmp=$(mktemp)
                    jq --arg addr "$address" --arg note "$note" \
                        '.addresses += [{"address": $addr, "note": $note}]' \
                        "$WATCH_FILE" > "$tmp" && mv "$tmp" "$WATCH_FILE"
                    
                    echo -e "${GREEN}${BOLD}✓ 地址已添加${RESET}"
                fi
                ;;
            2)
                addresses=$(jq -r '.addresses[] | "\(.address) (\(.note))"' "$WATCH_FILE")
                if [ ! -z "$addresses" ]; then
                    echo -e "\n当前关注地址："
                    i=1
                    while IFS= read -r line; do
                        echo "$i. $line"
                        i=$((i+1))
                    done <<< "$addresses"
                    
                    echo -e "\n${YELLOW}${BOLD}>>> 请输入要删除的地址编号：${RESET}"
                    read num
                    if [[ $num =~ ^[0-9]+$ ]]; then
                        tmp=$(mktemp)
                        jq "del(.addresses[$(($num-1))])" "$WATCH_FILE" > "$tmp" \
                            && mv "$tmp" "$WATCH_FILE"
                        echo -e "${GREEN}${BOLD}✓ 地址已删除${RESET}"
                    else
                        echo -e "${RED}${BOLD}无效的编号${RESET}"
                    fi
                else
                    echo -e "${YELLOW}${BOLD}没有已添加的关注地址${RESET}"
                fi
                ;;
            3)
                addresses=$(jq -r '.addresses[] | "\(.address) (\(.note))"' "$WATCH_FILE")
                if [ ! -z "$addresses" ]; then
                    echo -e "\n当前关注地址："
                    i=1
                    while IFS= read -r line; do
                        echo "$i. $line"
                        i=$((i+1))
                    done <<< "$addresses"
                else
                    echo -e "${YELLOW}${BOLD}没有已添加的关注地址${RESET}"
                fi
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}${BOLD}无效选项!${RESET}"
                ;;
        esac
    done
}

#===========================================
# RPC节点处理模块
#===========================================
# 全局配置
RPC_DIR="$HOME/.solana_pump"
RPC_FILE="$RPC_DIR/rpc_list.txt"
CUSTOM_NODES="$RPC_DIR/custom_nodes.txt"
PYTHON_RPC="$HOME/.solana_pump.rpc"

# 状态指示图标
STATUS_OK="[OK]"
STATUS_SLOW="[!!]"
STATUS_ERROR="[XX]"

# 延迟阈值(毫秒)
LATENCY_GOOD=100    # 良好延迟阈值
LATENCY_WARN=500    # 警告延迟阈值

# 默认RPC节点列表
DEFAULT_RPC_NODES=(
    "https://api.mainnet-beta.solana.com"
    "https://solana-api.projectserum.com"
    "https://rpc.ankr.com/solana"
    "https://solana-mainnet.rpc.extrnode.com"
    "https://api.mainnet.rpcpool.com"
    "https://api.metaplex.solana.com"
    "https://api.solscan.io"
    "https://solana.public-rpc.com"
)

# 初始化RPC配置
init_rpc_config() {
    mkdir -p "$RPC_DIR"
    touch "$RPC_FILE"
    touch "$CUSTOM_NODES"
    
    # 确保Python RPC配置文件存在
    if [ ! -f "$PYTHON_RPC" ]; then
        echo "https://api.mainnet-beta.solana.com" > "$PYTHON_RPC"
    fi
}

# 测试单个RPC节点
test_rpc_node() {
    local endpoint="$1"
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
    
    # 验证响应
    if [ ! -z "$response" ] && [[ "$response" == *"result"* ]]; then
        local status
        if (( $(echo "$latency < $LATENCY_GOOD" | bc -l) )); then
            status="$STATUS_OK"
        elif (( $(echo "$latency < $LATENCY_WARN" | bc -l) )); then
            status="$STATUS_SLOW"
        else
            status="$STATUS_ERROR"
        fi
        echo "$endpoint|$latency|$status"
        return 0
    fi
    return 1
}

# 测试所有节点
test_all_nodes() {
    local temp_file="$RPC_DIR/temp_results.txt"
    > "$temp_file"
    
    echo -e "\n${YELLOW}${BOLD}>>> 开始测试节点...${RESET}"
    local total=0
    local success=0
    
    # 测试默认节点
    for endpoint in "${DEFAULT_RPC_NODES[@]}"; do
        ((total++))
        echo -ne "\r测试进度: $total"
        if result=$(test_rpc_node "$endpoint"); then
            echo "$result" >> "$temp_file"
            ((success++))
        fi
    done
    
    # 测试自定义节点
    if [ -f "$CUSTOM_NODES" ]; then
        while read -r endpoint; do
            [ -z "$endpoint" ] && continue
            ((total++))
            echo -ne "\r测试进度: $total"
            if result=$(test_rpc_node "$endpoint"); then
                echo "$result" >> "$temp_file"
                ((success++))
            fi
        done < "$CUSTOM_NODES"
    fi
    
    # 按延迟排序并保存结果
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        sort -t"|" -k2 -n "$temp_file" -o "$RPC_FILE"
        
        # 提取最佳节点并保存为单独的URL
        best_node=$(head -n 1 "$RPC_FILE" | cut -d"|" -f1)
        echo "$best_node" > "$PYTHON_RPC"
        
        # 同时保存完整的节点信息
        nodes=$(awk -F"|" '{print "{\"endpoint\": \""$1"\", \"latency\": "$2"}"}' "$RPC_FILE" | jq -s '.')
        echo "$nodes" > "$RPC_DIR/full_rpc_info.json"
    else
        # 如果没有可用节点，使用默认节点
        echo "https://api.mainnet-beta.solana.com" > "$PYTHON_RPC"
    fi
    
    rm -f "$temp_file"
    
    echo -e "\n\n${GREEN}${BOLD}✓ 测试完成"
    echo "总节点数: $total"
    echo "可用节点数: $success"
    echo -e "可用率: $(( success * 100 / total ))%${RESET}"
    
    # 显示最佳节点
    if [ -f "$RPC_FILE" ] && [ -s "$RPC_FILE" ]; then
        echo -e "\n最佳节点 (延迟<${LATENCY_GOOD}ms):"
        echo "------------------------------------------------"
        head -n 5 "$RPC_FILE" | while IFS="|" read -r endpoint latency status; do
            printf "%-4s %7.1f ms  %s\n" "$status" "$latency" "$endpoint"
        done
    fi
}

# 添加自定义节点
add_custom_node() {
    echo -e "${YELLOW}${BOLD}>>> 添加自定义RPC节点${RESET}"
    echo -n "请输入节点地址: "
    read endpoint
    
    if [ ! -z "$endpoint" ]; then
        # 验证节点格式
        if [[ ! "$endpoint" =~ ^https?:// ]]; then
            echo -e "${RED}${BOLD}错误: 无效的节点地址格式，必须以 http:// 或 https:// 开头${RESET}"
            return 1
        fi
        
        # 检查是否已存在
        if grep -q "^$endpoint$" "$CUSTOM_NODES" 2>/dev/null; then
            echo -e "${YELLOW}${BOLD}该节点已存在${RESET}"
            return 1
        fi
        
        # 测试节点连接
        echo -e "${YELLOW}${BOLD}正在测试节点连接...${RESET}"
        if result=$(test_rpc_node "$endpoint"); then
            echo "$endpoint" >> "$CUSTOM_NODES"
            echo -e "${GREEN}${BOLD}✓ 节点已添加并测试通过${RESET}"
            test_all_nodes
        else
            echo -e "${RED}${BOLD}✗ 节点连接测试失败${RESET}"
            return 1
        fi
    fi
}

# 删除自定义节点
delete_custom_node() {
    if [ ! -f "$CUSTOM_NODES" ] || [ ! -s "$CUSTOM_NODES" ]; then
        echo -e "${RED}${BOLD}>>> 没有自定义节点${RESET}"
        return 1
    fi
    
    echo -e "\n${YELLOW}${BOLD}>>> 当前自定义节点：${RESET}"
    nl -w3 -s". " "$CUSTOM_NODES"
    echo -n "请输入要删除的节点编号 (输入 0 取消): "
    read num
    
    if [ "$num" = "0" ]; then
        echo -e "${YELLOW}${BOLD}已取消删除${RESET}"
        return 0
    fi
    
    if [[ $num =~ ^[0-9]+$ ]]; then
        local total_lines=$(wc -l < "$CUSTOM_NODES")
        if [ "$num" -le "$total_lines" ]; then
            local node_to_delete=$(sed "${num}!d" "$CUSTOM_NODES")
            sed -i "${num}d" "$CUSTOM_NODES"
            echo -e "${GREEN}${BOLD}✓ 已删除节点: $node_to_delete${RESET}"
            test_all_nodes
        else
            echo -e "${RED}${BOLD}错误: 无效的节点编号${RESET}"
            return 1
        fi
    else
        echo -e "${RED}${BOLD}错误: 请输入有效的数字${RESET}"
        return 1
    fi
}

# 查看当前节点
view_current_nodes() {
    echo -e "\n${YELLOW}${BOLD}>>> RPC节点状态：${RESET}"
    
    # 显示当前使用的节点
    if [ -f "$PYTHON_RPC" ]; then
        local current_node=$(cat "$PYTHON_RPC")
        echo -e "\n${GREEN}${BOLD}当前使用的节点:${RESET}"
        echo "$current_node"
    fi
    
    # 显示所有节点列表
    if [ -f "$RPC_FILE" ] && [ -s "$RPC_FILE" ]; then
        echo -e "\n所有可用节点:"
        echo -e "状态   延迟(ms)  节点地址"
        echo "------------------------------------------------"
        while IFS="|" read -r endpoint latency status; do
            printf "%-4s %7.1f ms  %s\n" "$status" "$latency" "$endpoint"
        done < "$RPC_FILE"
    else
        echo -e "${YELLOW}${BOLD}>>> 没有测试过的节点记录${RESET}"
    fi
    
    # 显示自定义节点
    if [ -f "$CUSTOM_NODES" ] && [ -s "$CUSTOM_NODES" ]; then
        echo -e "\n自定义节点列表:"
        nl -w3 -s". " "$CUSTOM_NODES"
    fi
}

# RPC节点管理主函数
manage_rpc() {
    # 确保配置已初始化
    init_rpc_config
    
    while true; do
        echo -e "\n${YELLOW}${BOLD}>>> RPC节点管理${RESET}"
        echo -e "${BOLD}1. 添加自定义节点${RESET}"
        echo -e "${BOLD}2. 查看当前节点${RESET}"
        echo -e "${BOLD}3. 测试节点延迟${RESET}"
        echo -e "${BOLD}4. 使用默认节点${RESET}"
        echo -e "${BOLD}5. 删除自定义节点${RESET}"
        echo -e "${BOLD}6. 返回主菜单${RESET}"
        echo -n "请选择 [1-6]: "
        read choice
        
        case $choice in
            1)
                add_custom_node
                ;;
            2)
                view_current_nodes
                ;;
            3)
                test_all_nodes
                ;;
            4)
                echo -e "${YELLOW}${BOLD}>>> 使用默认RPC节点...${RESET}"
                test_all_nodes
                ;;
            5)
                delete_custom_node
                ;;
            6)
                return
                ;;
            *)
                echo -e "${RED}${BOLD}无效选项!${RESET}"
                ;;
        esac
    done
}

#===========================================
# 主程序和菜单模块
#===========================================

# 生成Python监控脚本
generate_python_script() {
    echo -e "${YELLOW}${BOLD}>>> 生成监控脚本...${RESET}"
    cp ./monitor.py "$PY_SCRIPT"
    chmod +x "$PY_SCRIPT"
    echo -e "${GREEN}${BOLD}✓ 监控脚本已生成${RESET}"
}

# 前后台控制
toggle_foreground() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}${BOLD}>>> 切换到前台显示...${RESET}"
            tail -f "$LOG_FILE"
        else
            echo -e "${RED}${BOLD}>>> 监控进程未运行${RESET}"
        fi
    else
        echo -e "${RED}${BOLD}>>> 监控进程未运行${RESET}"
    fi
}

# 启动监控
start_monitor() {
    # 检查RPC配置
    if [ ! -f "$PYTHON_RPC" ] || [ ! -s "$PYTHON_RPC" ]; then
        echo -e "${YELLOW}${BOLD}>>> RPC配置不存在或为空，执行RPC测试...${RESET}"
        test_all_nodes
    fi
    
    # 验证RPC配置
    if [ ! -f "$PYTHON_RPC" ] || [ ! -s "$PYTHON_RPC" ]; then
        echo -e "${RED}${BOLD}>>> RPC配置失败，无法启动监控${RESET}"
        return 1
    fi
    
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}${BOLD}>>> 监控已在运行 (PID: $pid)${RESET}"
            echo -e "${YELLOW}${BOLD}>>> 是否切换到前台显示? (y/N)：${RESET}"
            read -n 1 show_log
            echo
            if [[ $show_log =~ ^[Yy]$ ]]; then
                toggle_foreground
            fi
            return
        fi
    fi
    
    generate_python_script
    echo -e "${GREEN}${BOLD}>>> 启动监控进程...${RESET}"
    nohup python3 "$PY_SCRIPT" > "$LOG_FILE" 2>&1 & 
    echo $! > "$PIDFILE"
    echo -e "${GREEN}${BOLD}>>> 监控已在后台启动 (PID: $!)${RESET}"
    echo -e "${GREEN}${BOLD}>>> 使用'3'选项可切换前台显示${RESET}"
}

# 主菜单
show_menu() {
    echo -e "\n${BLUE}${BOLD}Solana Pump监控系统 v4.0${RESET}"
    echo -e "${BOLD}1. 启动监控${RESET}"
    echo -e "${BOLD}2. 配置API密钥${RESET}"
    echo -e "${BOLD}3. 切换前台显示${RESET}"
    echo -e "${BOLD}4. RPC节点管理${RESET}"
    echo -e "${BOLD}5. 通知设置${RESET}"
    echo -e "${BOLD}6. 关注地址管理${RESET}"
    echo -e "${BOLD}7. 环境管理${RESET}"
    echo -e "${BOLD}8. 退出${RESET}"
    echo -n "请选择 [1-8]: "
}

# 主程序入口
case $1 in
    "--daemon")
        generate_python_script
        exec python3 "$PY_SCRIPT"
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
                7) manage_environment ;;
                8) 
                    if [ -f "$PIDFILE" ]; then
                        pid=$(cat "$PIDFILE")
                        kill "$pid" 2>/dev/null
                        rm "$PIDFILE"
                    fi
                    exit 0 
                    ;;
                *) echo -e "${RED}${BOLD}无效选项!${RESET}" ;;
            esac
        done
        ;;
esac

    
    
