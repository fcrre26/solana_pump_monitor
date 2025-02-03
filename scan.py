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
import queue
from multiprocessing import Process

# 添加颜色代码
class Colors:
    """终端颜色代码"""
    HEADER = '\033[95m'      # 紫色
    OKBLUE = '\033[94m'      # 蓝色
    OKGREEN = '\033[92m'     # 绿色
    WARNING = '\033[93m'     # 黄色
    FAIL = '\033[91m'        # 红色
    ENDC = '\033[0m'         # 结束颜色
    BOLD = '\033[1m'         # 加粗
    UNDERLINE = '\033[4m'    # 下划线

# 添加图标
class Icons:
    """ASCII图标"""
    INFO = "[i] "      # 信息
    SUCCESS = "[+] "   # 成功
    WARNING = "[!] "   # 警告
    ERROR = "[x] "     # 错误
    SCAN = "[>] "      # 扫描
    CPU = "[C] "       # CPU
    MEMORY = "[M] "    # 内存
    THREAD = "[T] "    # 线程
    SPEED = "[S] "     # 速度
    LOCATION = "[L] "  # 位置
    TIME = "[~] "      # 时间
    STATS = "[#] "     # 统计
    NODE = "[N] "      # 节点
    LATENCY = "[D] "   # 延迟
    HTTP = "[H] "      # HTTP
    WS = "[W] "        # WebSocket

class DisplayManager:
    """显示管理类，负责所有输出的格式化和美化"""
    
    @staticmethod
    def create_separator(width: int = 70) -> str:
        """创建分隔线"""
        return "-" * width
    
    @staticmethod
    def create_progress_bar(current: int, total: int, width: int = 40) -> str:
        """创建进度条"""
        progress = current / total if total > 0 else 0
        filled = int(width * progress)
        bar = "=" * filled + "-" * (width - filled)
        percentage = progress * 100
        return f"[{bar}] {current}/{total} ({percentage:.1f}%)"
    
    @staticmethod
    def create_ip_table(ip_segments: Dict[str, Dict]) -> str:
        """创建IP段统计表格"""
        # 表格边框
        table = []
        table.append("+------------+--------+--------+-----------+------------+")
        table.append("|   IP段     |  总数  |  可用  | 延迟(ms)  |   状态     |")
        table.append("+------------+--------+--------+-----------+------------+")
        
        for ip_segment, data in ip_segments.items():
            row = f"| {ip_segment:<10} | {data['total']:^6} | {data['available']:^6} | "
            row += f"{data['latency']:^9} | {data['status']:^8} |"
            table.append(row)
        
        table.append("+------------+--------+--------+-----------+------------+")
        return "\n".join(table)
    
    @staticmethod
    def create_ip_list_table(valid_ips: List[Dict]) -> str:
        """创建可用IP列表表格"""
        header = "|     IP          | 延迟(ms) |   服务商   |    机房        |         HTTP地址           |         WS地址            | 状态  |"
        separator = "-" * len(header)
        
        table = [separator, header, separator]
        
        for ip_info in valid_ips:
            latency = float(ip_info["latency"])
            status = "[+]" if latency < 200 else "[o]" if latency < 300 else "[-]"
            
            row = f"| {ip_info['ip']:<14} | {latency:^8} | {ip_info['provider']:<10} | "
            row += f"{ip_info['city']:<12} | {ip_info['http_url']:<25} | {ip_info['ws_url']:<25} | {status:^5} |"
            table.append(row)
        
        table.append(separator)
        return "\n".join(table)
    
    @staticmethod
    def print_scan_header():
        """打印扫描开始信息"""
        print("\n开始检测IP可用性...")
        print(DisplayManager.create_separator())
        print()
    
    @staticmethod
    def print_scan_progress(current_segment: str, segment_progress: Dict, total_progress: Dict):
        """打印扫描进度"""
        # 总体进度显示
        total_segments = total_progress.get('total_segments', 0)  # IP段总数
        current_segments = total_progress.get('current_segments', 0)  # 当前已扫描的IP段数
        print(f"\n总体进度: [{current_segments}/{total_segments}] 个IP段")
        print(DisplayManager.create_progress_bar(current_segments, total_segments))
        
        # 当前IP段进度
        print(f"当前检测: {current_segment}")
        print(DisplayManager.create_progress_bar(segment_progress['current'], segment_progress['total']))
        
        # CPU和内存使用情况
        cpu_usage = psutil.cpu_percent()
        memory_usage = psutil.virtual_memory().percent
        print(f"系统状态: CPU {cpu_usage}% | 内存 {memory_usage}%")
        print()
    
    @staticmethod
    def print_scan_stats(ip_segments: Dict[str, Dict], valid_ips: List[Dict]):
        """打印扫描统计信息"""
        print("当前IP段统计:")
        print(DisplayManager.create_ip_table(ip_segments))
        print(DisplayManager.create_separator())
        
        total_checked = sum(seg["total"] for seg in ip_segments.values())
        total_available = sum(seg["available"] for seg in ip_segments.values())
        success_rate = (total_available / total_checked * 100) if total_checked > 0 else 0
        
        print("实时统计:")
        print(f"- 已检测IP段: {len(ip_segments)}/3")
        print(f"- 当前成功率: {total_available}/{total_checked} ({success_rate:.1f}%)")
        
        if valid_ips:
            print("\n[发现可用IP] - 已保存到 valid_ips.txt")
            print("可用IP列表 (实时更新):")
            separator = "-" * 120
            print(separator)
            print("|     IP          | 延迟(ms) |   服务商   |    机房        |         HTTP地址           |         WS地址            | 状态  |")
            print(separator)
            
            for ip_info in valid_ips:
                latency = float(ip_info["latency"])
                status = "[+]" if latency < 200 else "[o]" if latency < 300 else "[-]"
                
                print(
                    f"| {ip_info['ip']:<14} "
                    f"| {latency:^8} "
                    f"| {ip_info['provider']:<10} "
                    f"| {ip_info['city']:<12} "
                    f"| {ip_info['http_url']:<25} "
                    f"| {ip_info['ws_url']:<25} "
                    f"| {status:^5} |"
                )
            
            print(separator)
    
    @staticmethod
    def print_scan_complete(ip_segments: Dict[str, Dict], start_time: float):
        """打印扫描完成信息"""
        print("\n[检测完成]\n")
        print("检测完成!")
        
        for ip_segment, data in ip_segments.items():
            success_rate = (data["available"] / data["total"] * 100)
            status = "优秀" if success_rate >= 70 else "良好" if success_rate >= 50 else "较差"
            print(f"{ip_segment}: {data['available']}/{data['total']} ({success_rate:.1f}%) - {status}")
        
        elapsed = time.time() - start_time
        total_ips = sum(seg["total"] for seg in ip_segments.values())
        speed = total_ips / elapsed if elapsed > 0 else 0
        
        print(f"\n总耗时: {elapsed:.1f}秒")
        print(f"检测速度: {speed:.1f} IP/s")

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

def batch_process_ips(ips: List[str]) -> List[str]:
    """批量处理IP检查，提高效率"""
    potential_ips = []
    # 增加批处理大小
    batch_size = 100  # 从20增加到100
    
    # 使用异步IO并行检查多个IP
    with ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = []
        for ip in ips:
            future = executor.submit(is_potential_rpc, ip)
            futures.append((ip, future))
        
        # 使用as_completed而不是等待所有完成
        for ip, future in futures:
            try:
                if future.result(timeout=2):  # 添加超时控制
                    potential_ips.append(ip)
            except:
                continue
    return potential_ips

def subnet_worker():
    """优化的子网扫描工作线程"""
    while not stop_event.is_set():
        try:
            subnet = subnet_queue.get_nowait()
            subnet_ips = list(subnet.hosts())
            total_ips = len(subnet_ips)
            
            # 优化采样策略
            if total_ips <= 256:
                sample_rate = 0.2  # 小子网降低到20%
            elif total_ips <= 1024:
                sample_rate = 0.1  # 中等子网降低到10%
            else:
                sample_rate = 0.05  # 大子网降低到5%
            
            # 智能选择采样点
            sample_count = max(20, int(total_ips * sample_rate))
            step = max(1, total_ips // sample_count)
            
            # 优先扫描常用端口范围
            priority_ranges = [
                (0, 10),      # 网段开始
                (245, 255),   # 网段结束
                (80, 90),     # 常用端口区域
                (8000, 8010), # 常用端口区域
            ]
            
            sample_ips = []
            for start, end in priority_ranges:
                for i in range(start, min(end, total_ips)):
                    sample_ips.append(str(subnet_ips[i]))
            
            # 在其他区域进行稀疏采样
            for i in range(0, total_ips, step):
                if not any(start <= i <= end for start, end in priority_ranges):
                    sample_ips.append(str(subnet_ips[i]))
            
            # 并行扫描采样IP
            potential_ips = batch_process_ips(sample_ips)
            
            # 发现节点时进行局部加密扫描
            if potential_ips:
                for potential_ip in potential_ips:
                    ip_obj = ipaddress.ip_address(potential_ip)
                    # 扫描前后各4个IP(从8个减少到4个)
                    for i in range(-4, 5):
                        try:
                            nearby_ip = str(ip_obj + i)
                            if ipaddress.ip_address(nearby_ip) in subnet:
                                ip_queue.put(nearby_ip)
                        except:
                            continue
            
            subnet_queue.task_done()
            
        except queue.Empty:
            break

def is_potential_rpc(ip: str) -> bool:
    """优化的RPC节点预检查"""
    try:
        # 减少超时时间
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.5)  # 从1秒减少到0.5秒
        result = sock.connect_ex((ip, 8899))
        sock.close()
        
        if result != 0:
            return False
        
        # 快速RPC检查
        try:
            response = requests.post(
                f"http://{ip}:8899",
                json={"jsonrpc": "2.0", "id": 1, "method": "getHealth"},
                headers={"Content-Type": "application/json"},
                timeout=1  # 从2秒减少到1秒
            )
            if response.status_code == 200 and "result" in response.json():
                return True
        except:
            pass
        
        return True
    except:
        return False

def get_optimal_thread_count() -> int:
    """获取优化后的线程数"""
    try:
        cpu_count = multiprocessing.cpu_count()
        available_memory = psutil.virtual_memory().available / (1024 * 1024 * 1024)
        
        # 增加基础线程数
        base_threads = cpu_count * 50  # 从20增加到50
        
        # 降低每线程内存预估
        memory_based_threads = int(available_memory * 1024 / 5)  # 从10MB降低到5MB
        
        # 提高最大线程数
        max_threads = 10000  # 从5000增加到10000
        
        optimal_threads = int(min(
            base_threads,
            memory_based_threads,
            max_threads
        ))
        
        return max(100, optimal_threads)  # 提高最小线程数
    except:
        return 500  # 提高默认线程数

def verify_worker():
    """优化的验证工作线程"""
    while not stop_event.is_set():
        try:
            # 增加批处理大小
            ips = []
            for _ in range(10):  # 从5增加到10
                try:
                    ips.append(potential_queue.get_nowait())
                except queue.Empty:
                    break
            
            if not ips:
                time.sleep(0.05)  # 减少等待时间
                continue
            
            # 并行验证IP
            with ThreadPoolExecutor(max_workers=len(ips)) as executor:
                futures = [executor.submit(scan_ip, ip, provider, config) for ip in ips]
                for ip, future in zip(ips, futures):
                    try:
                        result = future.result(timeout=3)  # 添加超时控制
                        if result:
                            verified_queue.put(result)
                            with verified_nodes_count.get_lock():
                                verified_nodes_count.value += 1
                    except:
                        pass
                    finally:
                        potential_queue.task_done()
        except:
            continue

def scan_network(network: ipaddress.IPv4Network, provider: str) -> List[str]:
    """优化的网段扫描函数"""
    verified_nodes = []
    thread_count = get_optimal_thread_count()
    config = load_config()
    
    # 计算总IP数
    total_ips = sum(1 for _ in network.hosts())
    
    # 使用新的显示管理器
    DisplayManager.print_scan_header()
    
    # IP段统计信息
    ip_segments = {
        str(network): {
            "total": total_ips,
            "available": 0,
            "latency": 0,
            "status": "scanning"
        }
    }
    
    # 打印扫描信息
    print_status(f"开始扫描网段: {network}", "scan")
    print_status(f"预计扫描IP数量: {total_ips}", "info")
    
    # 跳过IPv6网段
    if isinstance(network, ipaddress.IPv6Network):
        print_status(f"跳过IPv6网段 {network}", "warning")
        return []
    
    # 使用高效的队列
    ip_queue = Queue(maxsize=10000)
    potential_queue = Queue()
    verified_queue = Queue()
    
    # 使用原子计数器
    scanned_ips = multiprocessing.Value('i', 0)
    potential_nodes = multiprocessing.Value('i', 0)
    verified_nodes_count = multiprocessing.Value('i', 0)
    
    # 创建事件和锁
    stop_event = threading.Event()
    thread_lock = threading.Lock()
    
    def update_progress():
        """更新进度信息"""
        with scanned_ips.get_lock():
            current = scanned_ips.value
            if current % 100 == 0:  # 每扫描100个IP更新一次进度
                segment_progress = {
                    "current": current,
                    "total": total_ips
                }
                total_progress = {
                    "current": 1,
                    "total": 1,
                    "scanned": current,
                    "total_ips": total_ips
                }
                DisplayManager.print_scan_progress(str(network), segment_progress, total_progress)
                DisplayManager.print_scan_stats(ip_segments, verified_nodes)
    
    def scan_worker():
        """优化的扫描工作线程"""
        while not stop_event.is_set():
            try:
                # 批量获取IP
                ips = []
                for _ in range(20):  # 每次处理20个IP
                    try:
                        ips.append(ip_queue.get_nowait())
                    except queue.Empty:
                        break
                
                if not ips:
                    time.sleep(0.01)
                    continue
                
                # 批量处理IP
                potential_ips = batch_process_ips(ips)
                
                # 更新计数器
                with scanned_ips.get_lock():
                    scanned_ips.value += len(ips)
                with potential_nodes.get_lock():
                    potential_nodes.value += len(potential_ips)
                
                # 将潜在的RPC节点加入队列
                for ip in potential_ips:
                    potential_queue.put(ip)
                
                # 更新进度
                update_progress()
                
                # 标记任务完成
                for _ in range(len(ips)):
                    ip_queue.task_done()
                    
            except Exception as e:
                print_status(f"扫描线程异常: {e}", "error")
                continue
    
    def verify_worker():
        """优化的验证工作线程"""
        while not stop_event.is_set():
            try:
                # 批量获取待验证的IP
                ips = []
                for _ in range(5):  # 每次验证5个IP
                    try:
                        ips.append(potential_queue.get_nowait())
                    except queue.Empty:
                        break
                
                if not ips:
                    time.sleep(0.1)
                    continue
                
                # 并行验证IP
                with ThreadPoolExecutor(max_workers=len(ips)) as executor:
                    futures = [executor.submit(scan_ip, ip, provider, config) for ip in ips]
                    for ip, future in zip(ips, futures):
                        try:
                            result = future.result()
                            if result:
                                verified_queue.put(result)
                                with verified_nodes_count.get_lock():
                                    verified_nodes_count.value += 1
                                print_status(
                                    f"发现可用节点: {ip} "
                                    f"({result['city']}, {result['country']}) "
                                    f"延迟: {result['latency']:.1f}ms",
                                    "success"
                                )
                        except Exception as e:
                            print_status(f"验证节点 {ip} 失败: {e}", "error")
                        finally:
                            potential_queue.task_done()
                            
            except Exception as e:
                print_status(f"验证线程异常: {e}", "error")
                continue
    
    # 小网段完整扫描
    if network.prefixlen >= 24:
        ips = [str(ip) for ip in network.hosts()]
        print_status(f"扫描小网段 {network}，共 {len(ips)} 个IP", "scan")
        
        # 将IP加入队列
        for ip in ips:
            ip_queue.put(ip)
        
        # 启动线程
        threads = []
        
        # 启动扫描线程
        for _ in range(thread_count):
            t = threading.Thread(target=scan_worker)
            t.daemon = True
            t.start()
            threads.append(t)
        
        # 启动验证线程
        verify_thread_count = max(10, thread_count // 5)
        for _ in range(verify_thread_count):
            t = threading.Thread(target=verify_worker)
            t.daemon = True
            t.start()
            threads.append(t)
        
        # 等待完成
        ip_queue.join()
        potential_queue.join()
        
    else:
        # 大网段智能扫描
        subnets = list(network.subnets(new_prefix=24))
        print_status(f"扫描大网段 {network}，分割为 {len(subnets)} 个/24子网", "scan")
        
        # 创建子网队列
        subnet_queue = Queue()
        for subnet in subnets:
            subnet_queue.put(subnet)
        
        def subnet_worker():
            """子网扫描工作线程"""
            while not stop_event.is_set():
                try:
                    # 批量处理子网
                    subnets_to_process = []
                    for _ in range(5):
                        try:
                            subnets_to_process.append(subnet_queue.get_nowait())
                        except queue.Empty:
                            break
                    
                    if not subnets_to_process:
                        break
                    
                    for subnet in subnets_to_process:
                        # 智能采样
                        subnet_ips = list(subnet.hosts())
                        total_ips = len(subnet_ips)
                        
                        # 动态调整采样率
                        if total_ips <= 256:
                            sample_rate = 0.5  # 小子网采样50%
                        elif total_ips <= 1024:
                            sample_rate = 0.3  # 中等子网采样30%
                        else:
                            sample_rate = 0.1  # 大子网采样10%
                        
                        sample_count = max(50, int(total_ips * sample_rate))
                        step = max(1, total_ips // sample_count)
                        
                        # 智能选择采样点
                        sample_ips = []
                        for i in range(0, total_ips, step):
                            sample_ips.append(str(subnet_ips[i]))
                        
                        # 额外采样网段边界
                        if len(sample_ips) > 2:
                            sample_ips[0] = str(subnet_ips[0])  # 网段开始
                            sample_ips[-1] = str(subnet_ips[-1])  # 网段结束
                        
                        # 并行扫描采样IP
                        potential_ips = batch_process_ips(sample_ips)
                        
                        # 如果发现潜在节点，增加采样密度
                        if potential_ips:
                            print_status(f"子网 {subnet} 发现潜在节点，增加采样密度", "info")
                            # 在发现节点周围增加采样点
                            for potential_ip in potential_ips:
                                ip_obj = ipaddress.ip_address(potential_ip)
                                # 扫描前后各8个IP
                                for i in range(-8, 9):
                                    try:
                                        nearby_ip = str(ip_obj + i)
                                        if ipaddress.ip_address(nearby_ip) in subnet:
                                            ip_queue.put(nearby_ip)
                                    except:
                                        continue
                        
                        subnet_queue.task_done()
                        
                except Exception as e:
                    print_status(f"子网扫描异常: {e}", "error")
                    for _ in range(len(subnets_to_process)):
                        subnet_queue.task_done()
                    continue
        
        # 启动子网扫描线程
        subnet_threads = []
        for _ in range(thread_count):
            t = threading.Thread(target=subnet_worker)
            t.daemon = True
            t.start()
            subnet_threads.append(t)
        
        # 等待子网扫描完成
        subnet_queue.join()
    
    # 停止所有线程
    stop_event.set()
    
    # 收集结果
    while not verified_queue.empty():
        verified_nodes.append(verified_queue.get())
    
    # 打印统计信息
    print_status(f"\n扫描完成: {network}", "success")
    print_status(f"总计扫描IP: {scanned_ips.value}", "stats")
    print_status(f"发现潜在节点: {potential_nodes.value}", "stats")
    print_status(f"验证可用节点: {verified_nodes_count.value}", "stats")
    
    return verified_nodes

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
    # 测试多个RPC方法确保节点真正可用
    test_methods = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getHealth"
        },
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "getVersion"
        },
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "getSlot"
        }
    ]
    
    try:
        for method in test_methods:
            response = requests.post(url, headers=headers, json=method, timeout=5)
            if response.status_code != 200 or "result" not in response.json():
                return False, ""
        return True, url
    except:
        return False, ""

def test_ws_rpc(ip: str) -> Tuple[bool, str]:
    """测试WebSocket RPC连接"""
    url = f"ws://{ip}:8900"
    try:
        ws = websocket.create_connection(url, timeout=5)
        # 测试多个RPC方法
        test_methods = [
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getHealth"
            },
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "getVersion"
            }
        ]
        
        for method in test_methods:
            ws.send(json.dumps(method))
            result = ws.recv()
            if "result" not in json.loads(result):
                ws.close()
                return False, ""
                
        ws.close()
        return True, url
    except:
        return False, ""

def print_status(msg: str, status: str = "info", end: str = "\n"):
    """增强的状态打印函数，支持更多样式和格式"""
    status_formats = {
        "info": (Colors.OKBLUE, Icons.INFO, "信息"),
        "success": (Colors.OKGREEN, Icons.SUCCESS, "成功"),
        "warning": (Colors.WARNING, Icons.WARNING, "警告"),
        "error": (Colors.FAIL, Icons.ERROR, "错误"),
        "scan": (Colors.OKBLUE, Icons.SCAN, "扫描"),
        "system": (Colors.HEADER, Icons.CPU, "系统"),
        "thread": (Colors.OKBLUE, Icons.THREAD, "线程"),
        "stats": (Colors.OKGREEN, Icons.STATS, "统计"),
        "node": (Colors.OKGREEN, Icons.NODE, "节点"),
        "progress": (Colors.WARNING, Icons.SPEED, "进度"),
        "network": (Colors.OKBLUE, Icons.LATENCY, "网络"),
        "time": (Colors.HEADER, Icons.TIME, "时间")
    }
    
    color, icon, prefix = status_formats.get(status, (Colors.ENDC, "", ""))
    timestamp = time.strftime("%H:%M:%S")
    print(f"{color}{icon}[{timestamp}] [{prefix}] {msg}{Colors.ENDC}", end=end)

def create_progress_bar(progress: float, width: int = 50, style: str = "standard") -> str:
    """创建美观的进度条"""
    styles = {
        "standard": ("#", "-"),
        "blocks": ("█", "░"),
        "dots": ("●", "○"),
        "arrows": ("►", "─")
    }
    
    fill_char, empty_char = styles.get(style, styles["standard"])
    filled = int(width * progress)
    bar = fill_char * filled + empty_char * (width - filled)
    return f"[{bar}] {progress*100:.1f}%"

def format_table_row(data: Dict[str, str], widths: Dict[str, int], colors: Dict[str, str] = None) -> str:
    """格式化表格行，支持颜色和对齐"""
    if colors is None:
        colors = {}
    
    row = []
    for key, width in widths.items():
        value = str(data.get(key, ""))
        color = colors.get(key, Colors.ENDC)
        padding = " " * (width - len(value))
        row.append(f"{color}{value}{padding}{Colors.ENDC}")
    
    return " | ".join(row)

def save_results(results: List[Dict]):
    """增强的结果保存函数，支持更多格式和样式"""
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    filename = f"solana_rpc_nodes_{timestamp}.txt"
    
    # 计算列宽
    widths = {
        "序号": 4,
        "IP": 20,
        "延迟": 8,
        "机房": 15,
        "地区": 15,
        "国家": 10,
        "HTTP": 45,
        "WS": 45
    }
    
    # 表格样式
    table_style = "═║╔╗╚╝╠╣╦╩╬"
    h_line = table_style[0] * (sum(widths.values()) + len(widths) * 3 - 1)
    
    # 格式化输出
    formatted_results = []
    
    # 添加标题
    title = f"{Icons.STATS} === Solana RPC节点扫描结果 ==="
    formatted_results.extend([
        "",
        f"{Colors.BOLD}{title.center(len(h_line))}{Colors.ENDC}",
        f"{Icons.TIME} 扫描时间: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"{Icons.NODE} 发现节点: {len(results)} 个",
        ""
    ])
    
    # 添加表格
    formatted_results.extend([
        table_style[2] + h_line + table_style[3],
        format_table_row(widths, widths, {k: Colors.BOLD for k in widths}),
        table_style[7] + h_line + table_style[8]
    ])
    
    # 按延迟排序
    results.sort(key=lambda x: x['latency'])
    
    # 添加数据行
    for i, result in enumerate(results, 1):
        # 设置延迟颜色
        latency_color = (
            Colors.OKGREEN if result['latency'] < 100
            else Colors.WARNING if result['latency'] < 200
            else Colors.FAIL
        )
        
        row_data = {
            "序号": str(i),
            "IP": f"{result['ip']}",
            "延迟": f"{result['latency']:.1f}ms",
            "机房": result['city'][:15],
            "地区": result['region'][:15],
            "国家": result['country'][:10],
            "HTTP": result['http_url'] if result['http_url'] != "不可用" else "-",
            "WS": result['ws_url'] if result['ws_url'] != "不可用" else "-"
        }
        
        row_colors = {
            "延迟": latency_color,
            "HTTP": Colors.OKBLUE,
            "WS": Colors.OKBLUE
        }
        
        formatted_results.append(format_table_row(row_data, widths, row_colors))
    
    # 添加表格底部
    formatted_results.extend([
        table_style[4] + h_line + table_style[5],
        "",
        f"{Icons.STATS} === 详细信息 ==="
    ])
    
    # 添加详细信息
    for i, result in enumerate(results, 1):
        formatted_results.extend([
            f"\n{Icons.NODE} 节点 {i}:",
            f"{Icons.NODE} IP地址: {result['ip']}",
            f"{Icons.LATENCY} 延迟: {result['latency']:.1f}ms",
            f"{Icons.LOCATION} 位置: {result['city']}, {result['region']}, {result['country']}",
            f"{Icons.HTTP} HTTP RPC: {result['http_url']}",
            f"{Icons.WS} WebSocket: {result['ws_url']}"
        ])
    
    # 保存到文件
    with open(filename, 'w', encoding='utf-8') as f:
        f.write('\n'.join(formatted_results))
    
    # 打印结果预览
    print("\n" + "\n".join(formatted_results[:len(results) + 7]))
    print_status(f"\n完整结果已保存到: {filename}", "success")

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
    try:
        # 创建新的进程来运行扫描
        def scan_process():
            config = load_config()
            results = scan_provider(provider, config)
            if results:
                save_results(results)
            
        # 启动后台进程
        process = Process(target=scan_process)
        process.daemon = True
        process.start()
        
        # 保存进程ID到文件中以便跟踪
        with open("scan_pid.txt", "w") as f:
            f.write(str(process.pid))
            
        print(f"\n[后台] 扫描已启动，进程ID: {process.pid}")
        print("[后台] 使用选项8查看进度")
        
    except Exception as e:
        print(f"\n[错误] 启动后台扫描失败: {e}")

def show_progress():
    """显示扫描进度"""
    try:
        # 检查进程是否在运行
        if not os.path.exists("scan_pid.txt"):
            print("\n[进度] 当前没有正在进行的扫描")
            return
            
        with open("scan_pid.txt", "r") as f:
            pid = int(f.read().strip())
            
        # 检查进程是否存活
        import psutil
        try:
            process = psutil.Process(pid)
            if not process.is_running():
                raise Exception("进程已结束")
        except:
            print("\n[进度] 扫描已完成或已终止")
            if os.path.exists("scan_pid.txt"):
                os.remove("scan_pid.txt")
            return
            
        # 读取进度信息
        progress = load_progress()
        if progress:
            provider = progress.get("provider", "未知")
            scanned = progress.get("scanned", 0)
            total = progress.get("total", 0)
            found = progress.get("found", 0)
            last_update = progress.get("last_update", "未知")
            
            print(f"\n[进度] 正在扫描: {provider}")
            if total > 0:
                percentage = (scanned / total) * 100
                print(f"[进度] 已扫描: {scanned}/{total} ({percentage:.1f}%)")
            print(f"[进度] 已发现: {found} 个节点")
            print(f"[进度] 最后更新: {last_update}")
            
            # 显示系统资源使用情况
            cpu_percent = process.cpu_percent()
            memory_info = process.memory_info()
            print(f"\n[系统] CPU使用率: {cpu_percent}%")
            print(f"[系统] 内存使用: {memory_info.rss / 1024 / 1024:.1f} MB")
            
            # 显示最新的扫描日志
            if os.path.exists("scan.log"):
                print("\n最新日志:")
                with open("scan.log", "r") as f:
                    lines = f.readlines()
                    for line in lines[-5:]:  # 显示最后5行
                        print(line.strip())
        else:
            print("\n[进度] 暂无进度信息")
            
    except Exception as e:
        print(f"\n[错误] 获取进度信息失败: {e}")

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
            if http_success:  # 只有HTTP RPC可用才继续
                print(f"\n[发现] {provider} - {ip}:8899")
                print(f"[测试] 正在获取节点信息...")
                
                ip_info = get_ip_info(ip, config)
                latency = get_latency(ip)
                
                # 延迟太高的节点不要
                if latency > 500:  # 延迟超过500ms不收录
                    return None
                
                print(f"[测试] 正在测试WebSocket RPC...")
                ws_success, ws_url = test_ws_rpc(ip)
                
                # 至少HTTP或WS其中一个要可用
                if not (http_success or ws_success):
                    return None
                
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
        """更新进度信息"""
        with scanned_ips.get_lock():
            current = scanned_ips.value
            if current % 100 == 0:  # 每扫描100个IP更新一次进度
                segment_progress = {
                    "current": current,
                    "total": total_ips
                }
                total_progress = {
                    "current": 1,
                    "total": 1,
                    "scanned": current,
                    "total_ips": total_ips
                }
                DisplayManager.print_scan_progress(str(network), segment_progress, total_progress)
                DisplayManager.print_scan_stats(ip_segments, verified_nodes)
    
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
