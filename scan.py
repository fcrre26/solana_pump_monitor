import sys
import subprocess
import pkg_resources
import requests
import socket
import time
import platform
import json
import os
import websocket
from typing import List, Dict, Tuple
from subprocess import Popen, PIPE

def check_and_install_dependencies():
    """检查并安装所需的依赖包"""
    required_packages = {
        'requests': 'requests',
        'websocket-client': 'websocket-client'
    }
    
    installed_packages = {pkg.key for pkg in pkg_resources.working_set}
    
    packages_to_install = []
    for package, pip_name in required_packages.items():
        if package not in installed_packages:
            packages_to_install.append(pip_name)
    
    if packages_to_install:
        print("\n[初始化] 正在安装所需依赖...")
        for package in packages_to_install:
            print(f"[安装] {package}")
            try:
                subprocess.check_call([sys.executable, "-m", "pip", "install", package])
                print(f"[完成] {package} 安装成功")
            except subprocess.CalledProcessError as e:
                print(f"[错误] 安装 {package} 失败: {e}")
                sys.exit(1)
        print("[完成] 所有依赖安装完成\n")

# ASN映射表
ASN_MAP = {
    "TERASWITCH": "397391",
    "LATITUDE-SH": "137409",
    "OVH": "16276",
    "Vultr": "20473",
    "UAB Cherry Servers": "24940",
    "Amazon AWS": "16509",
    "WEBNX": "18450",
    "LIMESTONENETWORKS": "46475",
    "PACKET": "54825",
    "Amarutu Technology Ltd": "212238",
    "IS-AS-1": "57344",
    "velia.net Internetdienste": "47447",
    "ServeTheWorld AS": "34863",
    "MEVSPACE": "211680",
    "SYNLINQ": "34927",
    "TIER-NET": "12182",
    "Latitude.sh LTDA": "137409",
    "HVC-AS": "42831",
    "Hetzner": "24940",
    "AS-30083-US-VELIA-NET": "30083"
}

# 配置文件路径
CONFIG_FILE = 'config.json'

# 默认配置
DEFAULT_CONFIG = {
    "ipinfo_token": "",
    "timeout": 2,
    "max_retries": 3
}

def load_config() -> Dict:
    """加载配置文件"""
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
    except:
        pass
    return DEFAULT_CONFIG.copy()

def save_config(config: Dict):
    """保存配置文件"""
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=4)

def load_providers() -> List[str]:
    """从文件加载服务商列表"""
    try:
        with open('providers.txt', 'r') as f:
            return [line.strip() for line in f.readlines() if line.strip()]
    except FileNotFoundError:
        return list(ASN_MAP.keys())  # 如果文件不存在，返回所有支持的服务商

def save_providers(providers: List[str]):
    """保存服务商列表到文件"""
    with open('providers.txt', 'w') as f:
        f.write('\n'.join(providers))

def get_ips(asn: str, config: Dict) -> List[str]:
    """获取指定ASN的IP列表"""
    try:
        # 使用RIPEstat API
        url = f"https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS{asn}"
        print(f"[调试] 正在请求: {url}")
        
        response = requests.get(url, timeout=10)
        print(f"[调试] 状态码: {response.status_code}")
        
        if response.status_code != 200:
            print(f"[错误] API请求失败: HTTP {response.status_code}")
            print(f"[错误] 响应内容: {response.text}")
            return []
            
        data = response.json()
        
        if not data.get("data", {}).get("prefixes"):
            print("[错误] 未找到IP前缀")
            return []
            
        # 获取所有IP前缀
        prefixes = []
        for prefix in data["data"]["prefixes"]:
            if "prefix" in prefix:
                # 取IP段的第一个IP
                ip = prefix["prefix"].split("/")[0]
                prefixes.append(ip)
        
        print(f"[信息] 找到 {len(prefixes)} 个IP前缀")
        return prefixes
        
    except requests.exceptions.Timeout:
        print(f"[错误] 请求超时")
        return []
    except requests.exceptions.RequestException as e:
        print(f"[错误] 请求异常: {e}")
        return []
    except json.JSONDecodeError:
        print(f"[错误] JSON解析失败: {response.text}")
        return []
    except Exception as e:
        print(f"[错误] 未知异常: {e}")
        return []

def is_solana_rpc(ip: str) -> bool:
    """测试IP是否是Solana RPC节点"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    try:
        result = sock.connect_ex((ip, 8899))
        sock.close()
        return result == 0
    except:
        return False
    finally:
        sock.close()

def get_ip_info(ip: str, config: Dict) -> Dict:
    """获取IP的地理位置信息"""
    try:
        # 使用免费的IP-API
        url = f"http://ip-api.com/json/{ip}"
        response = requests.get(url, timeout=5)
        data = response.json()
        
        if data.get("status") == "success":
            return {
                "city": data.get("city", "Unknown"),
                "region": data.get("regionName", "Unknown"),
                "country": data.get("country", "Unknown"),
                "org": data.get("org", "Unknown")
            }
        else:
            print(f"[错误] IP-API返回错误: {data.get('message', '未知错误')}")
            return {
                "city": "Unknown",
                "region": "Unknown",
                "country": "Unknown",
                "org": "Unknown"
            }
    except Exception as e:
        print(f"[错误] 获取IP信息失败: {e}")
        return {
            "city": "Unknown",
            "region": "Unknown",
            "country": "Unknown",
            "org": "Unknown"
        }

def get_latency(ip: str) -> float:
    """测试IP的延迟"""
    try:
        if platform.system().lower() == "windows":
            cmd = ["ping", "-n", "1", "-w", "2000", ip]
        else:
            cmd = ["ping", "-c", "1", "-W", "2", ip]
            
        process = Popen(cmd, stdout=PIPE, stderr=PIPE)
        output, _ = process.communicate()
        output = output.decode()
        
        if platform.system().lower() == "windows":
            if "平均 = " in output:
                latency = output.split("平均 = ")[-1].split("ms")[0].strip()
            elif "Average = " in output:
                latency = output.split("Average = ")[-1].split("ms")[0].strip()
            else:
                return 999.99
        else:
            if "min/avg/max" in output:
                latency = output.split("min/avg/max")[1].split("=")[1].split("/")[1].strip()
            else:
                return 999.99
                
        return float(latency)
    except:
        return 999.99

def test_http_rpc(ip: str) -> Tuple[bool, str]:
    """测试HTTP RPC连接"""
    url = f"http://{ip}:8899"
    headers = {
        "Content-Type": "application/json"
    }
    data = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getHealth"
    }
    try:
        response = requests.post(url, headers=headers, json=data, timeout=5)
        if response.status_code == 200 and "result" in response.json():
            return True, url
    except:
        pass
    return False, ""

def test_ws_rpc(ip: str) -> Tuple[bool, str]:
    """测试WebSocket RPC连接"""
    url = f"ws://{ip}:8900"
    try:
        ws = websocket.create_connection(url, timeout=5)
        data = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getHealth"
        }
        ws.send(json.dumps(data))
        result = ws.recv()
        ws.close()
        if "result" in json.loads(result):
            return True, url
    except:
        pass
    return False, ""

def save_results(results: List[Dict]):
    """保存扫描结果到文件"""
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    filename = f"solana_rpc_nodes_{timestamp}.txt"
    
    # 格式化输出
    formatted_results = []
    header = f"{'IP':<20} | {'机房':<30} | {'供应商':<15} | {'延迟(ms)':<10} | {'HTTP':<30} | {'WebSocket'}"
    separator = "-" * len(header)
    formatted_results.append(header)
    formatted_results.append(separator)
    
    for result in results:
        location = f"{result['city']}, {result['region']}, {result['country']}"
        http_url = result.get('http_url', 'N/A')
        ws_url = result.get('ws_url', 'N/A')
        line = f"{result['ip']:<20} | {location:<30} | {result['provider']:<15} | {result['latency']:<10.2f} | {http_url:<30} | {ws_url}"
        formatted_results.append(line)
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write('\n'.join(formatted_results))
        
    print(f"\n[完成] 扫描结果已保存到: {filename}")
    print("\n发现的RPC节点:")
    for line in formatted_results:
        print(line)

def show_menu():
    """显示主菜单"""
    print("\n=== Solana RPC节点扫描器 ===")
    print("1. 显示所有支持的服务商")
    print("2. 添加要扫描的服务商")
    print("3. 查看当前要扫描的服务商")
    print("4. 清空服务商列表")
    print("5. 开始扫描")
    print("6. 配置IPInfo API Token")
    print("7. 退出")
    print("========================")

def configure_ipinfo():
    """配置IPInfo API Token"""
    config = load_config()
    current_token = config.get("ipinfo_token", "")
    
    print("\n=== IPInfo API Token 配置 ===")
    if current_token:
        print(f"当前Token: {current_token[:6]}...{current_token[-4:]}")
    else:
        print("当前未设置Token")
        
    print("\n请输入新的Token (直接回车保持不变，输入'clear'清除):")
    new_token = input().strip()
    
    if new_token.lower() == "clear":
        config["ipinfo_token"] = ""
        print("\n[完成] Token已清除")
    elif new_token:
        config["ipinfo_token"] = new_token
        print("\n[完成] Token已更新")
    else:
        print("\n[取消] Token保持不变")
        
    save_config(config)

def main():
    config = load_config()
    providers = load_providers()
    total_found = 0
    
    while True:
        show_menu()
        choice = input("请选择操作 (1-7): ").strip()
        
        if choice == "1":
            print("\n支持的服务商列表:")
            for provider in ASN_MAP.keys():
                print(f"- {provider}")
                
        elif choice == "2":
            print("\n请输入服务商名称（一行一个，输入空行结束）:")
            while True:
                provider = input().strip()
                if not provider:
                    break
                if provider in ASN_MAP:
                    if provider not in providers:
                        providers.append(provider)
                    else:
                        print(f"{provider} 已在列表中")
                else:
                    print(f"不支持的服务商: {provider}")
            save_providers(providers)
            
        elif choice == "3":
            if providers:
                print("\n当前要扫描的服务商:")
                for provider in providers:
                    print(f"- {provider}")
            else:
                print("\n暂无要扫描的服务商")
                
        elif choice == "4":
            providers.clear()
            save_providers(providers)
            print("\n已清空服务商列表")
            
        elif choice == "5":
            if not providers:
                print("\n请先添加要扫描的服务商")
                continue
                
            if not config.get("ipinfo_token"):
                print("\n[警告] 未设置IPInfo API Token，可能会受到请求限制")
                print("建议先配置Token（选项6）再开始扫描")
                print("是否继续扫描？(y/N)")
                if input().lower() != 'y':
                    continue
                
            results = []
            print(f"\n[开始] 开始扫描 {len(providers)} 个服务商...")
            
            for i, provider in enumerate(providers, 1):
                print(f"\n[{i}/{len(providers)}] 正在扫描 {provider}...")
                asn = ASN_MAP[provider]
                
                print(f"[{provider}] 正在获取IP列表...")
                ips = get_ips(asn, config)
                
                if not ips:
                    print(f"[{provider}] 未获取到IP列表，跳过")
                    continue
                    
                print(f"[{provider}] 获取到 {len(ips)} 个IP，开始扫描...")
                provider_found = 0
                
                for ip in ips:
                    if is_solana_rpc(ip):
                        print(f"[发现] {provider} - {ip}:8899")
                        print(f"[测试] 正在获取节点信息...")
                        
                        ip_info = get_ip_info(ip, config)
                        latency = get_latency(ip)
                        
                        print(f"[测试] 正在测试HTTP RPC...")
                        http_success, http_url = test_http_rpc(ip)
                        
                        print(f"[测试] 正在测试WebSocket RPC...")
                        ws_success, ws_url = test_ws_rpc(ip)
                        
                        result = {
                            "ip": f"{ip}:8899",
                            "provider": provider,
                            "city": ip_info["city"],
                            "region": ip_info["region"],
                            "country": ip_info["country"],
                            "latency": latency,
                            "http_url": http_url if http_success else "不可用",
                            "ws_url": ws_url if ws_success else "不可用"
                        }
                        
                        results.append(result)
                        provider_found += 1
                        total_found += 1
                        print(f"[信息] {ip}:8899 - {ip_info['city']}, {ip_info['region']}, {ip_info['country']} - {latency:.2f}ms")
                        print(f"[信息] HTTP RPC: {result['http_url']}")
                        print(f"[信息] WebSocket RPC: {result['ws_url']}")
                
                print(f"[{provider}] 扫描完成，发现 {provider_found} 个节点")
                time.sleep(1)  # 避免请求过快
                
            if results:
                print(f"\n[统计] 共发现 {total_found} 个RPC节点")
                save_results(results)
            else:
                print("\n[完成] 未发现可用的RPC节点")
                
        elif choice == "6":
            configure_ipinfo()
            config = load_config()  # 重新加载配置
            
        elif choice == "7":
            print("\n感谢使用！")
            break
            
        else:
            print("\n无效的选择，请重试")

if __name__ == "__main__":
    check_and_install_dependencies()
    main() 
