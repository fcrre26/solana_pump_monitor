#!/usr/bin/env python3
import os
import sys
import time
import json
import logging
import requests
import urllib3
import traceback
from datetime import datetime, timezone, timedelta
from concurrent.futures import ThreadPoolExecutor
from wcferry import Wcf

# 禁用SSL警告
urllib3.disable_warnings()

class TokenMonitor:
    def __init__(self):
        try:
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
            
            logging.info("TokenMonitor初始化成功")
        except Exception as e:
            logging.error(f"TokenMonitor初始化失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
            raise

    def load_config(self):
        try:
            with open(self.config_file) as f:
                config = json.load(f)
                logging.info(f"成功加载配置文件: {self.config_file}")
                return config
        except Exception as e:
            logging.error(f"加载配置失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
            return {"api_keys": [], "serverchan": {"keys": []}, "wcf": {"groups": []}}

    def load_watch_addresses(self):
        try:
            with open(self.watch_file) as f:
                data = json.load(f)
                addresses = {addr['address']: addr['note'] for addr in data.get('addresses', [])}
                logging.info(f"成功加载关注地址: {len(addresses)}个")
                return addresses
        except Exception as e:
            logging.error(f"加载关注地址失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
            return {}

    def init_wcf(self):
        if self.config['wcf']['groups']:
            try:
                self.wcf = Wcf()
                logging.info("WeChatFerry初始化成功")
            except Exception as e:
                logging.error(f"WeChatFerry初始化失败: {str(e)}")
                logging.error(f"详细错误: {traceback.format_exc()}")
                self.wcf = None

    def get_next_api_key(self):
        """获取下一个可用的API密钥"""
        try:
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
        except Exception as e:
            logging.error(f"获取API密钥失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
            raise

    def get_best_rpc(self):
        """获取最佳RPC节点"""
        # 默认RPC节点列表
        DEFAULT_NODES = [
            "https://api.mainnet-beta.solana.com",
            "https://solana-api.projectserum.com",
            "https://rpc.ankr.com/solana",
            "https://solana-mainnet.rpc.extrnode.com"
        ]
        
        try:
            # 尝试从配置文件读取
            with open(self.rpc_file) as f:
                data = f.read().strip()
                try:
                    nodes = json.loads(data)
                    if isinstance(nodes, list) and nodes:
                        logging.info(f"使用配置文件中的RPC节点: {nodes[0]['endpoint']}")
                        return nodes[0]['endpoint']
                except json.JSONDecodeError:
                    if data.startswith('https://'):
                        logging.info(f"使用配置文件中的RPC节点: {data}")
                        return data.strip()
        except Exception as e:
            logging.warning(f"读取RPC配置失败: {str(e)}")
            logging.warning(f"详细错误: {traceback.format_exc()}")
        
        # 如果配置读取失败，测试所有默认节点
        for node in DEFAULT_NODES:
            try:
                response = requests.post(
                    node,
                    json={"jsonrpc":"2.0","id":1,"method":"getHealth"},
                    timeout=3
                )
                if response.status_code == 200:
                    logging.info(f"使用可用节点: {node}")
                    return node
            except Exception as e:
                logging.warning(f"测试节点失败 {node}: {str(e)}")
                continue
        
        # 如果所有节点都失败，使用第一个默认节点
        logging.warning("所有节点不可用，使用默认节点")
        return DEFAULT_NODES[0]

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
                
                token_info = {
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
                logging.info(f"获取代币信息成功: {json.dumps(token_info, indent=2)}")
                return token_info
        except Exception as e:
            logging.error(f"获取代币信息失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
        
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
        try:
            # 检查缓存
            if creator in self.address_cache:
                cache_data = self.address_cache[creator]
                if time.time() - cache_data['timestamp'] < self.cache_expire:
                    logging.info(f"使用缓存的创建者历史: {creator}")
                    return cache_data['history']
            
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
                        except Exception as e:
                            logging.warning(f"获取价格历史失败: {str(e)}")
                        
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
                logging.info(f"分析创建者历史成功: {creator}, 发现 {len(history)} 个代币")
                return history
        except Exception as e:
            logging.error(f"分析创建者历史失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
        
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
                    except Exception as e:
                        logging.warning(f"分析共同签名者失败: {str(e)}")
                        continue
            
            result = {
                "wallet_age": wallet_age,
                "is_new_wallet": wallet_age < 7,  # 小于7天视为新钱包
                "related_addresses": list(related_addresses),
                "relations": relations,
                "watch_hits": watch_hits,
                "high_value_relations": high_value_relations,
                "risk_score": self.calculate_risk_score(relations, wallet_age)
            }
            logging.info(f"分析创建者关联性成功: {creator}")
            return result
        except Exception as e:
            logging.error(f"分析创建者关联性失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
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
        except Exception as e:
            logging.warning(f"分析共同签名者失败: {str(e)}")
            return []

    def calculate_risk_score(self, relations, wallet_age):
        """计算风险分数"""
        try:
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
        except Exception as e:
            logging.error(f"计算风险分数失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
            return 0

    def format_alert_message(self, data):
        """格式化警报消息"""
        try:
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
        except Exception as e:
            logging.error(f"格式化警报消息失败: {str(e)}")
            logging.error(f"详细错误: {traceback.format_exc()}")
            return "消息格式化失败"

    def send_notification(self, msg):
        """发送通知"""
        # Server酱推送
        for key in self.config["serverchan"]["keys"]:
            try:
                response = requests.post(
                    f"https://sctapi.ftqq.com/{key}.send",
                    data={"title": "Solana新代币提醒", "desp": msg},
                    timeout=5
                )
                if response.status_code == 200:
                    logging.info(f"Server酱推送成功 ({key[:8]}...{key[-8:]})")
                else:
                    logging.warning(f"Server酱推送失败 ({key[:8]}...{key[-8:]}): {response.text}")
            except Exception as e:
                logging.error(f"Server酱推送失败 ({key[:8]}...{key[-8:]}): {str(e)}")
                logging.error(f"详细错误: {traceback.format_exc()}")
        
        # WeChatFerry推送
        if self.wcf and self.config["wcf"]["groups"]:
            for group in self.config["wcf"]["groups"]:
                try:
                    self.wcf.send_text(group["wxid"], msg)
                    logging.info(f"WeChatFerry推送成功 ({group['name']})")
                except Exception as e:
                    logging.error(f"WeChatFerry推送失败 ({group['name']}): {str(e)}")
                    logging.error(f"详细错误: {traceback.format_exc()}")

    def monitor(self):
        """主监控函数"""
        logging.info("监控启动...")
        last_slot = 0
        PUMP_PROGRAM = "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ35MKDfgCcMKJ"
        retry_count = 0
        max_retries = 3
        
        while True:
            try:
                rpc = self.get_best_rpc()
                current_slot = None
                
                # 获取当前区块，带重试
                for _ in range(max_retries):
                    try:
                        response = requests.post(
                            rpc,
                            json={"jsonrpc":"2.0","id":1,"method":"getSlot"},
                            timeout=3
                        )
                        if response.status_code == 200:
                            current_slot = response.json()["result"]
                            break
                    except Exception as e:
                        logging.warning(f"获取区块失败，重试... ({e})")
                        time.sleep(1)
                
                if current_slot is None:
                    raise Exception("无法获取当前区块")
                
                if last_slot == 0:
                    last_slot = current_slot - 10
                
                for slot in range(last_slot + 1, current_slot + 1):
                    block = None
                    # 获取区块数据，带重试
                    for _ in range(max_retries):
                        try:
                            response = requests.post(
                                rpc,
                                json={
                                    "jsonrpc":"2.0",
                                    "id":1,
                                    "method":"getBlock",
                                    "params":[slot, {"encoding":"json","transactionDetails":"full"}]
                                },
                                timeout=5
                            )
                            if response.status_code == 200:
                                block = response.json().get("result")
                                break
                        except Exception as e:
                            logging.warning(f"获取区块 {slot} 失败，重试... ({e})")
                            time.sleep(1)
                    
                    if block and "transactions" in block:
                        logging.info(f"成功解析区块 {slot}, 交易数: {len(block['transactions'])}")
                        for tx in block["transactions"]:
                            if PUMP_PROGRAM in tx["transaction"]["message"]["accountKeys"]:
                                accounts = tx["transaction"]["message"]["accountKeys"]
                                creator = accounts[0]
                                mint = accounts[4]
                                
                                logging.info(f"发现目标交易: creator={creator}, mint={mint}")
                                token_info = self.fetch_token_info(mint)
                                logging.info(f"代币信息: {json.dumps(token_info, indent=2)}")
                                
                                if token_info["market_cap"] < 1000:
                                    logging.info(f"市值过小 (${token_info['market_cap']}), 跳过通知")
                                    continue
                                
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
                    else:
                        logging.info(f"区块 {slot} 无交易或获取失败")
                    
                    last_slot = slot
                    time.sleep(0.1)
                
                retry_count = 0  # 重置重试计数
                time.sleep(1)
                
            except Exception as e:
                retry_count += 1
                logging.error(f"监控循环错误: {str(e)}")
                logging.error(f"详细错误: {traceback.format_exc()}")
                if retry_count > max_retries:
                    logging.error("连续失败次数过多，切换RPC节点...")
                    retry_count = 0
                time.sleep(10)

if __name__ == "__main__":
    # 配置更详细的日志格式
    logging.basicConfig(
        level=logging.DEBUG,  # 改为DEBUG级别，显示更多信息
        format='%(asctime)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s',
        handlers=[
            logging.FileHandler('monitor.log'),
            logging.StreamHandler()
        ]
    )
    
    # 添加异常处理
    try:
        monitor = TokenMonitor()
        monitor.monitor()
    except Exception as e:
        logging.error(f"程序异常: {str(e)}")
        logging.error(f"详细错误: {traceback.format_exc()}")
