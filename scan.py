import requests
import socket
import time
from typing import List, Dict

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

def load_providers() -> List[str]:
    """从文件加载服务商列表"""
    try:
        with open('providers.txt', 'r') as f:
            return [line.strip() for line in f.readlines() if line.strip()]
    except FileNotFoundError:
        return []

def save_providers(providers: List[str]):
    """保存服务商列表到文件"""
    with open('providers.txt', 'w') as f:
        f.write('\n'.join(providers))

def get_ips(asn: str) -> List[str]:
    """获取指定ASN的IP列表"""
    try:
        url = f"https://ipinfo.io/AS{asn}/json"
        headers = {"Accept": "application/json"}
        response = requests.get(url, headers=headers)
        data = response.json()
        if "prefixes" in data:
            return [prefix["netblock"].split("/")[0] for prefix in data["prefixes"]]
        return []
    except Exception as e:
        print(f"获取IP列表出错: {e}")
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

def save_results(results: List[str]):
    """保存扫描结果到文件"""
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    filename = f"solana_rpc_nodes_{timestamp}.txt"
    with open(filename, 'w') as f:
        f.write('\n'.join(results))
    print(f"\n结果已保存到: {filename}")

def show_menu():
    """显示主菜单"""
    print("\n=== Solana RPC节点扫描器 ===")
    print("1. 显示所有支持的服务商")
    print("2. 添加要扫描的服务商")
    print("3. 查看当前要扫描的服务商")
    print("4. 清空服务商列表")
    print("5. 开始扫描")
    print("6. 退出")
    print("========================")

def main():
    providers = load_providers()
    
    while True:
        show_menu()
        choice = input("请选择操作 (1-6): ").strip()
        
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
            print("\n开始扫描...")
            for provider in providers:
                print(f"\n正在扫描 {provider}...")
                asn = ASN_MAP[provider]
                ips = get_ips(asn)
                for ip in ips:
                    if is_solana_rpc(ip):
                        result = f"{provider} - {ip}:8899"
                        results.append(result)
                        print(f"发现RPC节点: {result}")
                time.sleep(1)  # 避免请求过快
                
            if results:
                save_results(results)
            else:
                print("\n未发现可用的RPC节点")
                
        elif choice == "6":
            print("\n感谢使用！")
            break
            
        else:
            print("\n无效的选择，请重试")

if __name__ == "__main__":
    main() 
