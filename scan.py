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
import ipaddress
import threading
from queue import Queue
from concurrent.futures import ThreadPoolExecutor, as_completed
import psutil
import multiprocessing
import logging

def check_and_install_dependencies():
    """检查并安装所需的依赖包"""
    required_packages = {
        'requests': 'requests',
        'websocket-client': 'websocket-client',
        'psutil': 'psutil'
    }
    
    try:
        import pkg_resources
    except ImportError:
        print("\n[初始化] 正在安装 setuptools...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "setuptools"])
            import pkg_resources
        except Exception as e:
            print(f"[错误] 安装 setuptools 失败: {e}")
            sys.exit(1)
    
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
                # 添加 --user 参数以避免权限问题
                subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", package])
                print(f"[完成] {package} 安装成功")
            except subprocess.CalledProcessError as e:
                print(f"[错误] 安装 {package} 失败，尝试使用 sudo...")
                try:
                    subprocess.check_call(["sudo", sys.executable, "-m", "pip", "install", package])
                    print(f"[完成] {package} 安装成功")
                except:
                    print(f"[错误] 安装 {package} 失败: {e}")
                    print("[提示] 请手动执行以下命令安装依赖：")
                    print(f"sudo pip3 install {package}")
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

def is_potential_rpc(ip: str) -> bool:
    """预检查IP是否可能是RPC节点"""
    try:
        # 1. 快速TCP SYN检查
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        result = sock.connect_ex((ip, 8899))
        sock.close()
        
        # 端口不通直接返回False
        if result != 0:
            return False
            
        # 2. 快速RPC检查
        try:
            response = requests.post(
                f"http://{ip}:8899",
                json={"jsonrpc": "2.0", "id": 1, "method": "getHealth"},
                headers={"Content-Type": "application/json"},
                timeout=2
            )
            if response.status_code == 200 and "result" in response.json():
                print(f"[发现] {ip} RPC接口正常")
                return True
        except:
            pass
            
        # 3. 端口开放但RPC检查失败，返回True进行进一步检查
        print(f"[发现] {ip} 端口开放")
        return True
            
    except:
        return False

def scan_network(network: ipaddress.IPv4Network, provider: str) -> List[str]:
    """扫描单个网段"""
    potential_ips = []
    thread_count = get_optimal_thread_count()
    
    # 跳过IPv6网段
    if isinstance(network, ipaddress.IPv6Network):
        logging.info(f"[跳过] IPv6网段 {network}")
        return []
    
    # 小网段完整扫描
    if network.prefixlen >= 24:  # /24或更小的网段
        ips = [str(ip) for ip in network.hosts()]
        print(f"[扫描] 扫描小网段 {network}，共 {len(ips)} 个IP，使用 {thread_count} 个线程")
        
        # 使用线程池扫描IP
        with ThreadPoolExecutor(max_workers=thread_count) as executor:
            futures = []
            for ip in ips:
                futures.append(executor.submit(is_potential_rpc, ip))
            
            for ip, future in zip(ips, futures):
                try:
                    if future.result():
                        potential_ips.append(ip)
                        print(f"[发现] 发现潜在RPC节点: {ip}")
                except Exception as e:
                    continue
    else:
        # 大网段智能扫描
        subnets = list(network.subnets(new_prefix=24))
        print(f"[扫描] 扫描大网段 {network}，分割为 {len(subnets)} 个/24子网")
        
        # 对每个子网进行采样
        with ThreadPoolExecutor(max_workers=thread_count) as executor:
            subnet_futures = []
            for subnet in subnets:
                subnet_ips = list(subnet.hosts())
                if not subnet_ips:
                    continue
                    
                # 智能采样：每个/24网段取10个样本IP
                sample_count = min(10, len(subnet_ips))
                step = len(subnet_ips) // sample_count
                sample_ips = [str(subnet_ips[i]) for i in range(0, len(subnet_ips), step)][:sample_count]
                
                # 并行检查采样IP
                sample_futures = []
                for ip in sample_ips:
                    sample_futures.append(executor.submit(is_potential_rpc, ip))
                subnet_futures.append((subnet, sample_ips, sample_futures))
            
            # 处理采样结果
            for subnet, sample_ips, sample_futures in subnet_futures:
                found_rpc = False
                for ip, future in zip(sample_ips, sample_futures):
                    try:
                        if future.result():
                            potential_ips.append(ip)
                            found_rpc = True
                            print(f"[发现] 发现潜在RPC节点: {ip}")
                    except Exception as e:
                        continue
                
                # 如果在采样IP中发现RPC，扫描整个/24网段
                if found_rpc:
                    print(f"[扫描] 在{subnet}发现RPC节点，扫描整个子网")
                    subnet_ips = [str(ip) for ip in subnet.hosts()]
                    
                    # 并行扫描整个子网
                    full_scan_futures = []
                    for ip in subnet_ips:
                        if ip not in potential_ips:  # 跳过已知的IP
                            full_scan_futures.append(executor.submit(is_potential_rpc, ip))
                    
                    for ip, future in zip([ip for ip in subnet_ips if ip not in potential_ips], full_scan_futures):
                        try:
                            if future.result():
                                potential_ips.append(ip)
                                print(f"[发现] 发现潜在RPC节点: {ip}")
                        except Exception as e:
                            continue
    
    return potential_ips

def get_ips(asn: str, config: Dict) -> List[str]:
    """获取指定ASN的IP列表"""
    try:
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
            
        # 获取所有IP前缀并展开
        all_ips = []
        total_prefixes = len(data["data"]["prefixes"])
        ipv4_prefixes = [p for p in data["data"]["prefixes"] if ":" not in p["prefix"]]  # 过滤出IPv4前缀
        
        print(f"[信息] 找到 {len(ipv4_prefixes)} 个IPv4段，正在智能扫描...")
        for i, prefix in enumerate(ipv4_prefixes, 1):
            if "prefix" in prefix:
                try:
                    network = ipaddress.ip_network(prefix["prefix"])
                    print(f"\n[进度] 正在处理IP段 {i}/{len(ipv4_prefixes)}: {prefix['prefix']}")
                    
                    # 扫描网段
                    potential_ips = scan_network(network, asn)
                    all_ips.extend(potential_ips)
                    
                    print(f"[统计] 当前共发现 {len(all_ips)} 个潜在RPC节点")
                except Exception as e:
                    print(f"[错误] 处理IP段 {prefix['prefix']} 失败: {e}")
                    continue
        
        print(f"\n[信息] 扫描完成，共找到 {len(all_ips)} 个潜在的RPC节点")
        return all_ips
        
    except Exception as e:
        print(f"[错误] 获取IP列表失败: {e}")
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
    
    # 添加统计信息
    formatted_results.append("=== Solana RPC节点扫描结果 ===")
    formatted_results.append(f"扫描时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    formatted_results.append(f"发现节点: {len(results)} 个")
    formatted_results.append("")
    
    # 按延迟排序
    results.sort(key=lambda x: x['latency'])
    
    # 添加表头
    header = f"{'序号':<4} | {'IP':<20} | {'延迟(ms)':<8} | {'机房':<15} | {'地区':<15} | {'国家':<10} | {'HTTP地址':<45} | {'WS地址'}"
    separator = "=" * (len(header) + 20)  # 增加分隔符长度以适应链接地址
    formatted_results.append(header)
    formatted_results.append(separator)
    
    # 添加结果
    for i, result in enumerate(results, 1):
        location = f"{result['city']}"
        region = f"{result['region']}"
        country = f"{result['country']}"
        http_url = result['http_url'] if result['http_url'] != "不可用" else "-"
        ws_url = result['ws_url'] if result['ws_url'] != "不可用" else "-"
        
        line = f"{i:<4} | {result['ip']:<20} | {result['latency']:<8.1f} | {location[:15]:<15} | {region[:15]:<15} | {country[:10]:<10} | {http_url:<45} | {ws_url}"
        formatted_results.append(line)
    
    formatted_results.append(separator)
    
    # 添加详细信息
    formatted_results.append("\n=== 详细信息 ===")
    for i, result in enumerate(results, 1):
        formatted_results.append(f"\n节点 {i}:")
        formatted_results.append(f"IP地址: {result['ip']}")
        formatted_results.append(f"延迟: {result['latency']:.1f}ms")
        formatted_results.append(f"位置: {result['city']}, {result['region']}, {result['country']}")
        formatted_results.append(f"HTTP RPC: {result['http_url']}")
        formatted_results.append(f"WebSocket: {result['ws_url']}")
    
    # 保存到文件
    with open(filename, 'w', encoding='utf-8') as f:
        f.write('\n'.join(formatted_results))
        
    # 打印结果
    print("\n" + "\n".join(formatted_results[:len(results) + 7]))  # 打印表格部分
    print(f"\n[完成] 完整结果已保存到: {filename}")

def show_menu():
    """显示主菜单"""
    print("\n=== Solana RPC节点扫描器 ===")
    print("1. 显示所有支持的服务商")
    print("2. 添加要扫描的服务商")
    print("3. 查看当前要扫描的服务商")
    print("4. 清空服务商列表")
    print("5. 开始扫描")
    print("6. 快速扫描Vultr")
    print("7. 后台扫描")
    print("8. 查看扫描进度")
    print("9. 退出")
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

def save_progress(provider: str, scanned: int, total: int, found: int):
    """保存扫描进度"""
    progress = {
        "provider": provider,
        "scanned": scanned,
        "total": total,
        "found": found,
        "last_update": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    with open("scan_progress.json", "w") as f:
        json.dump(progress, f)

def load_progress() -> Dict:
    """加载扫描进度"""
    try:
        with open("scan_progress.json", "r") as f:
            return json.load(f)
    except:
        return {}

def background_scan(provider: str):
    """后台扫描函数"""
    cmd = f"nohup python3 {sys.argv[0]} --scan {provider} > scan.log 2>&1 &"
    subprocess.Popen(cmd, shell=True)
    print(f"\n[后台] 扫描已启动，使用选项8查看进度")
    print(f"[后台] 日志文件: scan.log")

def show_progress():
    """显示扫描进度"""
    progress = load_progress()
    if not progress:
        print("\n[进度] 当前没有正在进行的扫描")
        return
        
    provider = progress["provider"]
    scanned = progress["scanned"]
    total = progress["total"]
    found = progress["found"]
    last_update = progress["last_update"]
    
    print(f"\n[进度] 正在扫描: {provider}")
    print(f"[进度] 已扫描: {scanned}/{total} ({(scanned/total*100):.1f}%)")
    print(f"[进度] 已发现: {found} 个节点")
    print(f"[进度] 最后更新: {last_update}")
    
    # 显示最新的日志
    try:
        with open("scan.log", "r") as f:
            lines = f.readlines()
            if lines:
                print("\n最新日志:")
                for line in lines[-5:]:  # 显示最后5行
                    print(line.strip())
    except:
        pass

def get_optimal_thread_count() -> int:
    """获取最优线程数"""
    try:
        # 获取CPU核心数
        cpu_count = multiprocessing.cpu_count()
        # 获取可用内存(GB)
        available_memory = psutil.virtual_memory().available / (1024 * 1024 * 1024)
        
        # 基础线程数：每个CPU核心4个线程（原来是2个）
        base_threads = cpu_count * 4
        
        # 根据可用内存调整
        # 假设每个线程大约需要30MB内存（原来是50MB）
        memory_based_threads = int(available_memory * 1024 / 30)
        
        # 取较大值，允许更多线程（原来是取较小值）
        optimal_threads = max(base_threads, memory_based_threads)
        
        # 调整上下限
        # 最小10个线程（原来是5个）
        # 最大500个线程（原来是100个）
        optimal_threads = max(10, min(optimal_threads, 500))
        
        print(f"[系统] CPU核心数: {cpu_count}")
        print(f"[系统] 可用内存: {available_memory:.1f}GB")
        print(f"[系统] 最优线程数: {optimal_threads}")
        
        return optimal_threads
    except:
        # 如果无法获取系统信息，返回默认值50（原来是10）
        print("[系统] 无法获取系统信息，使用默认线程数: 50")
        return 50

def scan_ip(ip: str, provider: str, config: Dict) -> Dict:
    """扫描单个IP"""
    try:
        # 1. 检查端口是否开放
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        if sock.connect_ex((ip, 8899)) == 0:
            sock.close()
            
            # 2. 测试RPC功能
            http_success, http_url = test_http_rpc(ip)
            if http_success:
                print(f"\n[发现] {provider} - {ip}:8899")
                print(f"[测试] 正在获取节点信息...")
                
                ip_info = get_ip_info(ip, config)
                latency = get_latency(ip)
                
                print(f"[测试] 正在测试WebSocket RPC...")
                ws_success, ws_url = test_ws_rpc(ip)
                
                result = {
                    "ip": f"{ip}:8899",
                    "provider": provider,
                    "city": ip_info["city"],
                    "region": ip_info["region"],
                    "country": ip_info["country"],
                    "latency": latency,
                    "http_url": http_url,
                    "ws_url": ws_url if ws_success else "不可用"
                }
                
                print(f"[信息] {ip}:8899 - {ip_info['city']}, {ip_info['region']}, {ip_info['country']} - {latency:.2f}ms")
                print(f"[信息] HTTP RPC: {result['http_url']}")
                print(f"[信息] WebSocket RPC: {result['ws_url']}")
                return result
    except:
        pass
    return None

def scan_provider(provider: str, config: Dict) -> List[Dict]:
    """扫描单个服务商"""
    results = []
    asn = ASN_MAP[provider]
    
    print(f"\n[开始] 正在扫描 {provider}...")
    print(f"[{provider}] 正在获取IP列表...")
    potential_ips = get_ips(asn, config)
    
    if not potential_ips:
        print(f"[{provider}] 未获取到潜在RPC节点，跳过")
        return results
        
    print(f"[{provider}] 获取到 {len(potential_ips)} 个潜在RPC节点，开始详细检查...")
    total_ips = len(potential_ips)
    scanned = 0
    found = 0
    
    # 获取最优线程数
    thread_count = get_optimal_thread_count()
    print(f"[线程] 使用 {thread_count} 个线程进行扫描")
    
    # 创建进度更新线程
    progress_queue = Queue()
    stop_progress = threading.Event()
    
    def update_progress():
        while not stop_progress.is_set():
            if not progress_queue.empty():
                current = progress_queue.get()
                save_progress(provider, current, total_ips, found)
                print(f"\r[进度] 正在扫描 {current}/{total_ips} ({(current/total_ips*100):.1f}%)", end="")
            time.sleep(0.1)
    
    progress_thread = threading.Thread(target=update_progress)
    progress_thread.daemon = True
    progress_thread.start()
    
    # 使用线程池进行扫描
    with ThreadPoolExecutor(max_workers=thread_count) as executor:
        future_to_ip = {executor.submit(scan_ip, ip, provider, config): ip for ip in potential_ips}
        
        for future in as_completed(future_to_ip):
            scanned += 1
            progress_queue.put(scanned)
            
            result = future.result()
            if result:
                results.append(result)
                found += 1
                save_progress(provider, scanned, total_ips, found)
    
    # 停止进度更新线程
    stop_progress.set()
    progress_thread.join()
    
    print(f"\n[{provider}] 扫描完成，发现 {found} 个RPC节点")
    return results

def main():
    # 处理命令行参数
    if len(sys.argv) > 1 and sys.argv[1] == "--scan":
        provider = sys.argv[2]
        config = load_config()
        results = scan_provider(provider, config)
        if results:
            save_results(results)
        return

    config = load_config()
    providers = load_providers()
    total_found = 0
    
    while True:
        show_menu()
        choice = input("请选择操作 (1-9): ").strip()
        
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
                
            results = []
            print(f"\n[开始] 开始扫描 {len(providers)} 个服务商...")
            
            # 获取最优线程数（服务商扫描使用较少线程）
            thread_count = max(1, get_optimal_thread_count() // 5)
            print(f"[线程] 使用 {thread_count} 个线程扫描服务商")
            
            # 使用线程池扫描多个服务商
            with ThreadPoolExecutor(max_workers=thread_count) as executor:
                future_to_provider = {executor.submit(scan_provider, provider, config): provider for provider in providers}
                
                for future in as_completed(future_to_provider):
                    provider_results = future.result()
                    results.extend(provider_results)
                    total_found += len(provider_results)
            
            if results:
                print(f"\n[统计] 共发现 {total_found} 个RPC节点")
                save_results(results)
            else:
                print("\n[完成] 未发现可用的RPC节点")
                
        elif choice == "6":
            print("\n[快速扫描] 开始扫描Vultr...")
            results = scan_provider("Vultr", config)
            if results:
                print(f"\n[统计] 共发现 {len(results)} 个RPC节点")
                save_results(results)
            else:
                print("\n[完成] 未发现可用的RPC节点")
                
        elif choice == "7":
            print("\n请选择要后台扫描的服务商:")
            for i, provider in enumerate(ASN_MAP.keys(), 1):
                print(f"{i}. {provider}")
            print("\n输入序号或服务商名称:")
            choice = input().strip()
            
            if choice.isdigit() and 1 <= int(choice) <= len(ASN_MAP):
                provider = list(ASN_MAP.keys())[int(choice)-1]
            elif choice in ASN_MAP:
                provider = choice
            else:
                print("\n[错误] 无效的选择")
                continue
                
            background_scan(provider)
            
        elif choice == "8":
            show_progress()
            
        elif choice == "9":
            print("\n感谢使用！")
            break
            
        else:
            print("\n无效的选择，请重试")

if __name__ == "__main__":
    check_and_install_dependencies()
    main() 
