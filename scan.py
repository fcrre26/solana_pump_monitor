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
from typing import List, Dict, Tuple, Optional
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
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import asyncio
from collections import OrderedDict
import random
from collections import defaultdict
from collections import Counter
from tabulate import tabulate

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
        'psutil': 'psutil',
        'urllib3': 'urllib3',
        'ipinfo': 'ipinfo',  # 新增IPinfo官方库
        'tabulate': 'tabulate'  # 新增表格依赖
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
                # 添加--user参数以避免权限问题
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
    "max_retries": 3,
    "max_threads": 1000,  # 最大线程数
    "batch_size": 100,     # 批处理大小
    "strict_mode": True    # 严格检查模式
}

def load_config() -> Dict:
    """加载配置文件"""
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
                # 转换内存单位
                if 'hyper_mode' in config:
                    config['hyper_mode']['max_memory_usage'] = parse_memory(
                        config['hyper_mode']['max_memory_usage']
                    )
                return config
    except:
        pass
    return DEFAULT_CONFIG.copy()

def parse_memory(mem_str: str) -> int:
    """将内存字符串转换为MB"""
    units = {"K": 1, "M": 1024, "G": 1024**2, "T": 1024**3}
    unit = mem_str[-1]
    return int(float(mem_str[:-1]) * units[unit])

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
    """优化后的线程数计算"""
    cpu_count = os.cpu_count() or 8
    return min(cpu_count * 1000, 10000)  # 提升到10000线程

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

class DynamicThreadPool:
    """动态调整的线程池"""
    def __init__(self, max_workers=None):
        self.max_workers = max_workers or (os.cpu_count() * 50)
        self.executor = ThreadPoolExecutor(max_workers=self.max_workers)
        self._adjust_interval = 5  # 每5秒调整一次
        self._last_adjust = time.time()
        
    def adjust_pool(self, qsize):
        """根据队列长度动态调整线程数"""
        if time.time() - self._last_adjust > self._adjust_interval:
            new_size = min(
                self.max_workers,
                max(50, int(qsize * 0.2))  # 根据队列长度动态调整
            )
            if new_size != self.executor._max_workers:
                self.executor._max_workers = new_size
                print_status(f"动态调整线程数为 {new_size}", "thread")
            self._last_adjust = time.time()

class GeoCache:
    """地理位置信息缓存"""
    def __init__(self, max_size=1000):
        self.cache = OrderedDict()
        self.max_size = max_size
        
    def get(self, ip: str) -> Optional[Dict]:
        if ip in self.cache:
            self.cache.move_to_end(ip)
            return self.cache[ip]
        return None
        
    def set(self, ip: str, info: Dict):
        if ip in self.cache:
            self.cache.move_to_end(ip)
        else:
            self.cache[ip] = info
            if len(self.cache) > self.max_size:
                self.cache.popitem(last=False)

# 在全局初始化
GEO_CACHE = GeoCache()

def scan_network(network: ipaddress.IPv4Network, provider: str) -> List[str]:
    """扫描IPv4网段"""
    # 强制转换为IPv4Network类型
    if not isinstance(network, ipaddress.IPv4Network):
        print_status(f"跳过非IPv4网段 {network}", "warning")
        return []
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
        """内存优化版扫描线程"""
        batch_size = 1000  # 增大批处理量
        while True:
            batch = []
            try:
                for _ in range(batch_size):
                    batch.append(ip_queue.get_nowait())
                    except queue.Empty:
                if batch:
                    process_batch(batch)  # 批量处理
                    time.sleep(0.01)
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

class ASNCache:
    def __init__(self, ttl=3600*24):  # 延长缓存时间
        self.cache = OrderedDict()
        self.max_size = 1000000  # 增大缓存容量
        self.ttl = ttl

# 全局初始化
ASN_CACHE = ASNCache()

def get_asn_prefixes(asn: str) -> List[str]:
    """带缓存的ASN前缀获取"""
    if cached := ASN_CACHE.get(asn):
        return cached
        
    # 原有API调用逻辑...
    ASN_CACHE.set(asn, prefixes)
    return prefixes

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
    """获取IP详细信息（优先使用IPinfo）"""
    try:
        # 验证是否为合法IPv4地址
        ipaddress.IPv4Address(ip)
    except:
        return {"city": "Invalid", "region": "Invalid", "country": "Invalid", "datacenter": "Unknown"}
    
    # 优先使用IPinfo
    if token := config.get("ipinfo_token"):
        try:
            url = f"https://ipinfo.io/{ip}/json?token={token}"
            response = requests.get(url, timeout=3)
            data = response.json()
            
            return {
                "city": data.get("city", "Unknown"),
                "region": data.get("region", "Unknown"),
                "country": data.get("country", "Unknown"),
                "datacenter": data.get("org", "").split()[1] if " " in data.get("org", "") else "Unknown"
            }
        except:
            pass
    
    # 回退到免费API（仅基本地理信息）
    try:
        url = f"http://ip-api.com/json/{ip}"
        response = requests.get(url, timeout=5)
        data = response.json()
        
            return {
                "city": data.get("city", "Unknown"),
                "region": data.get("regionName", "Unknown"),
                "country": data.get("country", "Unknown"),
            "datacenter": "Unknown"
        }
    except:
        return {"city": "Unknown", "region": "Unknown", "country": "Unknown", "datacenter": "Unknown"}

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
    """保存为表格格式"""
    with open("scan_results.txt", "w") as f:
        f.write(f"=== 扫描结果 {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")
        f.write(f"总节点数: {len(results)}\n\n")
        
        # 表格数据
        headers = ["IP", "延迟(ms)", "机房", "地区", "国家", "HTTP地址", "WS地址"]
        rows = []
        for res in sorted(results, key=lambda x: x['latency']):
            rows.append([
                res['ip'],
                f"{res['latency']:.1f}",
                res['city'],
                res['region'],
                res['country'],
                res['http_url'],
                res['ws_url']
            ])
        
        f.write(tabulate(rows, headers, tablefmt="grid"))
        
        # 统计信息
        f.write("\n\n=== 统计信息 ===\n")
        avg_latency = sum(r['latency'] for r in results) / len(results)
        f.write(f"平均延迟: {avg_latency:.1f}ms\n")
        # 更多统计...

def show_menu():
    """显示主菜单"""
    menu = f"""
{Colors.OKGREEN}=== Solana RPC节点扫描器 ==={Colors.ENDC}
1. 显示所有支持的服务商    2. 添加扫描服务商
3. 查看当前服务商列表      4. 清空服务商列表
5. 开始全面扫描           6. 快速扫描Vultr
7. 后台扫描模式           8. 查看扫描进度
9. 配置IPinfo API         0. 退出程序
{Colors.OKGREEN}============================{Colors.ENDC}
    """
    print(menu)

def configure_ipinfo():
    """配置IPInfo API Token"""
    config = load_config()
    current_token = config.get("ipinfo_token", "")
    
    print("\n=== IPInfo API Token 配置 ===")
    print("1. 访问 https://ipinfo.io/ 注册获取API Token")
    print("2. 免费套餐每月5万次请求（足够使用）")
    if current_token:
        print(f"\n当前已配置Token: {current_token[:6]}...{current_token[-4:]}")
    else:
        print("\n当前未配置Token，使用免费IP-API（精度较低）")
        
    print("\n请输入新的Token（直接回车保持当前状态）：")
    new_token = input().strip()
    
    if new_token:
        config["ipinfo_token"] = new_token
        save_config(config)
        print("Token配置成功！")
    else:
        print("保持当前配置")

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
    """改进的后台扫描函数"""
    try:
        def scan_process():
            # 创建新的进程组
            os.setpgrp()
            
            # 重定向输出到日志文件
            with open("scan.log", "a") as log_file:
                sys.stdout = log_file
                sys.stderr = log_file
                
            config = load_config()
            results = scan_provider(provider, config)
            if results:
                save_results(results)
            
        # 使用start_new_session创建独立进程组
        process = Process(target=scan_process, daemon=True)
        process.start()
        
        # 保存进程组ID
        with open("scan_pid.txt", "w") as f:
            f.write(str(process.pid))  # 注意：这里实际应该保存进程组ID
            
        print(f"\n[后台] 扫描已启动，进程组ID: {process.pid}")
        
    except Exception as e:
        print(f"\n[错误] 启动后台扫描失败: {e}")

def show_progress(total_segments: int, current_segment: int,
                 total_ips: int, scanned_ips: int):
    """改进的进度条显示"""
    # IP段进度
    seg_width = 50
    seg_filled = int(current_segment / total_segments * seg_width)
    seg_bar = '#' * seg_filled + '-' * (seg_width - seg_filled)
    
    # IP进度 
    ip_width = 50
    ip_filled = int(scanned_ips / total_ips * ip_width)
    ip_bar = '#' * ip_filled + '-' * (ip_width - ip_filled)
    
    print(f"\n{Colors.OKBLUE}[总进度] {current_segment}/{total_segments}段")
    print(f"[{seg_bar}]")
    print(f"[IP进度] {scanned_ips}/{total_ips} ({scanned_ips/total_ips:.1%})")
    print(f"[{ip_bar}]{Colors.ENDC}")

class ScanStats:
    """扫描统计信息"""
    def __init__(self):
        self.total_scanned = 0
        self.port_open = 0
        self.http_failed = 0
        self.ws_failed = 0
        self.high_latency = 0
        self.sync_failed = 0
        self.valid_nodes = 0

def init_config():
    """初始化配置文件"""
    config_path = os.path.join(os.path.dirname(__file__), 'config.json')
    if not os.path.exists(config_path):
        default_config = {
            "ipinfo_token": "",
            "timeout": 1.5,
            "max_retries": 2,
            "max_threads": 10000,
            "batch_size": 1000,
            "strict_mode": False,
            "hyper_mode": {
                "enable": True,
                "max_memory_usage": "28G",
                "network_buffer_size": "2G",
                "ip_cache_size": 1000000,
                "result_buffer": 50000
            },
            "performance": {
                "port_scan_timeout": 0.3,
                "rpc_check_timeout": 0.8,
                "geo_cache_ttl": 86400
            }
        }
        with open(config_path, 'w') as f:
            json.dump(default_config, f, indent=4)
        print(f"已自动生成配置文件: {config_path}")

def main():
    init_config()  # 新增初始化
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
    
    global_stats = ScanStats()
    
    while True:
        show_menu()
        choice = input("请选择操作 (0-9): ").strip()
        
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
                show_final_stats(results)
                save_results(results)
            else:
                print("\n[完成] 未发现可用的RPC节点")
                
        elif choice == "6":
            print("\n[快速扫描] 开始扫描Vultr...")
            results = scan_provider("Vultr", config)
            if results:
                print(f"\n[统计] 共发现 {len(results)} 个RPC节点")
                show_final_stats(results)
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
            configure_ipinfo()
            
        elif choice == "0":
            print("\n感谢使用！")
            break
            
        else:
            print("\n无效的选择，请重试")

def optimized_scan_ip(ip: str, provider: str, config: Dict) -> Optional[Dict]:
    """优化后的扫描流程"""
    try:
        # 第一阶段：快速检查
        if not is_port_open(ip, 8899):
            return None
        
        # 第二阶段：基础验证
        http_url = f"http://{ip}:8899"
        if not enhanced_health_check(http_url):
            return None
        
        # 第三阶段：性能检查
        latency = get_latency(ip)
        if latency > 300:  # 300ms以上直接丢弃
            return None
        
        # 第四阶段：详细验证
        if not check_sync_status(http_url):
            return None
        
        # 通过所有检查后获取位置信息
        ip_info = get_ip_info(ip, config)
        
        # 构建结果
        result = {
            "ip": f"{ip}:8899",
            "provider": provider,
            "latency": latency,
            **ip_info,
            "last_checked": time.strftime("%Y-%m-%d %H:%M:%S")
        }
        
        return result
        
    except Exception as e:
        return None

def scan_ip(ip: str, provider: str, config: Dict, stats: ScanStats) -> Dict:
    """扫描单个IP并记录统计信息"""
    try:
        stats.total_scanned += 1
        
        # 端口检查
        if not is_port_open(ip, 8899):
            return None
        stats.port_open += 1
        
        # HTTP检查
        http_ok, http_url = test_http_rpc(ip)
        if not http_ok:
            stats.http_failed += 1
            return None
            
        # 延迟检查
        latency = get_latency(ip)
        if latency > 500:  # 500ms以上过滤
            stats.high_latency += 1
            return None
            
        # 同步状态检查
        if not check_sync_status(http_url):
            stats.sync_failed += 1
            return None
            
        # WebSocket检查
        ws_ok, ws_url = test_ws_rpc(ip)
        if not ws_ok:
            stats.ws_failed += 1
            
        stats.valid_nodes += 1
        return {
            "ip": f"{ip}:8899",
            "provider": provider,
            "city": get_ip_info(ip, config)["city"],
            "region": get_ip_info(ip, config)["region"],
            "country": get_ip_info(ip, config)["country"],
            "latency": latency,
            "http_url": http_url if http_ok else "不可用",
            "ws_url": ws_url if ws_ok else "不可用",
            "last_checked": time.strftime("%Y-%m-%d %H:%M:%S")
        }
        
    except Exception as e:
        return None

def scan_provider(provider: str, config: Dict) -> List[Dict]:
    stats = ScanStats()
    
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
    
    # 创建进度跟踪器
    tracker = ProgressTracker(total_segments=len(potential_ips), total_ips=len(potential_ips))
    recent_nodes = []
    
    # 启动进度更新线程
    def update_progress():
        while not stop_event.is_set():
            show_enhanced_progress(tracker, recent_nodes)
            time.sleep(1)  # 每秒刷新一次
    
    progress_thread = threading.Thread(target=update_progress)
    progress_thread.start()
    
    # 使用线程池进行扫描
    with ThreadPoolExecutor(max_workers=thread_count) as executor:
        futures = {executor.submit(scan_ip, ip, provider, config, stats): ip for ip in potential_ips}
        
        for future in as_completed(futures):
            scanned += 1
            tracker.update_ips(1)
            result = future.result()
            if result:
                recent_nodes.append(result)
                on_node_found(result)
    
    # 停止进度线程
    stop_event.set()
    progress_thread.join()
    
    print(f"\n[{provider}] 扫描完成，发现 {found} 个RPC节点")
    show_scan_stats(stats)
    
    if results:
        show_final_stats(results)
        save_results(results)
    
    return results

class RealtimeSaver:
    """实时保存器"""
    def __init__(self):
        self.lock = threading.Lock()
        self.file = open("results.txt", "a")
        
    def save(self, result: dict):
        """实时保存表格数据"""
        table = tabulate([result.values()], headers=result.keys(), tablefmt="grid")
        self.file.write(table + "\n")  # 保留表格格式保存
            
    def __del__(self):
        self.file.close()

# 在全局初始化
realtime_saver = RealtimeSaver()

# 在发现节点时调用
def on_node_found(result: dict):
    print_realtime_result(result)
    realtime_saver.save(result)

def print_realtime_result(result: dict):
    """即时打印发现节点"""
    table = [[
        result['ip'],
        f"{result['latency']}ms",
        result['city'],
        result['region'],
        result['country'],
        result['http_url'],
        result['ws_url']
    ]]
    headers = ["IP", "延迟", "机房", "地区", "国家", "HTTP地址", "WS地址"]
    print(f"\n{Colors.OKGREEN}新节点发现!{Colors.ENDC}")
    print(tabulate(table, headers, tablefmt="grid"))

class ProgressTracker:
    """进度跟踪器"""
    def __init__(self, total_segments: int, total_ips: int):
        self.start_time = time.time()
        self.total_segments = total_segments
        self.total_ips = total_ips
        self.scanned_segments = 0
        self.scanned_ips = 0
        self.lock = threading.Lock()
        
    def update_segment(self):
        """更新已扫描段数"""
        with self.lock:
            self.scanned_segments += 1
            
    def update_ips(self, count: int):
        """更新已扫描IP数"""
        with self.lock:
            self.scanned_ips += count
            
    def get_progress(self) -> dict:
        """获取当前进度数据"""
        elapsed = time.time() - self.start_time
        seg_progress = self.scanned_segments / self.total_segments if self.total_segments else 0
        ip_progress = self.scanned_ips / self.total_ips if self.total_ips else 0
        
        # 计算剩余时间
        remaining_time = 0
        if ip_progress > 0.01:  # 避免除零错误
            remaining_time = (elapsed / ip_progress) * (1 - ip_progress)
            
        return {
            "segments": f"{self.scanned_segments}/{self.total_segments}",
            "ips": f"{self.scanned_ips}/{self.total_ips}",
            "elapsed": self.format_time(elapsed),
            "remaining": self.format_time(remaining_time),
            "seg_progress": seg_progress,
            "ip_progress": ip_progress
        }
    
    @staticmethod
    def format_time(seconds: float) -> str:
        """将秒转换为时间格式"""
        if seconds < 60:
            return f"{int(seconds)}秒"
        elif seconds < 3600:
            return f"{int(seconds//60)}分{int(seconds%60)}秒"
        else:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            return f"{hours}小时{minutes}分"

def show_enhanced_progress(tracker: ProgressTracker, recent_nodes: List[Dict]):
    """优化后的进度显示（不覆盖节点信息）"""
    # 使用ANSI控制码只更新进度部分
    print("\033[7A")  # 上移7行（根据进度显示行数调整）
    # ... 输出进度信息 ...
    print("\033[K"*7)  # 清除剩余行

if __name__ == "__main__":
    main() 
