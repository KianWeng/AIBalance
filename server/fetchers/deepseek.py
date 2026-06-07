"""DeepSeek 余额抓取器

通过 API Key 获取账户余额信息
API 文档: https://platform.deepseek.com/api-docs/

获取凭证方法：
- API Key: https://platform.deepseek.com/api_keys
"""

import requests
from datetime import datetime
from .base import BaseFetcher, BalanceInfo
from config import Config


class DeepSeekFetcher(BaseFetcher):
    service_name = "DeepSeek"
    service_id = "deepseek"

    def is_configured(self) -> bool:
        return bool(Config.DEEPSEEK_API_KEY)

    def fetch(self) -> BalanceInfo:
        if not self.is_configured():
            return self._make_error("未配置 DEEPSEEK_API_KEY")

        return self._fetch_balance()

    def _fetch_balance(self) -> BalanceInfo:
        """通过 API Key 获取余额"""
        try:
            headers = {
                "Authorization": f"Bearer {Config.DEEPSEEK_API_KEY}",
                "Content-Type": "application/json",
            }

            # DeepSeek 余额查询端点
            resp = requests.get(
                "https://api.deepseek.com/user/balance",
                headers=headers,
                timeout=15,
            )

            if resp.status_code == 401:
                return self._make_error("API Key 无效或已过期")
            if resp.status_code != 200:
                return self._make_error(f"请求失败 (HTTP {resp.status_code})")

            data = resp.json()

            # 解析余额信息
            # DeepSeek 返回格式: {"is_available": true, "balance_infos": [...]}
            balance_infos = data.get("balance_infos", [])

            total_balance_cny = 0.0
            total_balance_usd = 0.0
            used_amount = 0.0
            primary_currency = "CNY"
            primary_balance = 0.0

            for info in balance_infos:
                # currency: "CNY" 或 "USD"
                # total_balance: 总余额
                # granted_balance: 赠送余额
                # topped_up_balance: 充值余额
                currency = info.get("currency", "CNY")
                total = float(info.get("total_balance", 0))
                
                if currency == "USD":
                    total_balance_usd += total
                elif currency == "CNY":
                    total_balance_cny += total

            # 优先使用 CNY，如果没有则使用 USD
            if total_balance_cny > 0:
                primary_currency = "CNY"
                primary_balance = total_balance_cny
            elif total_balance_usd > 0:
                primary_currency = "USD"
                primary_balance = total_balance_usd

            # DeepSeek API 目前不直接返回已用金额
            # 使用 total_balance 作为 remaining，used_amount 设为 0
            # 用户可以通过查看历史账单了解详细用量
            remaining = primary_balance if primary_balance > 0 else None

            billing_period = datetime.now().strftime("%Y-%m")

            return self._make_info(
                plan_name="API",
                total_quota=primary_balance if primary_balance > 0 else None,
                used_amount=used_amount,
                billing_period=billing_period,
                currency=primary_currency,
            )

        except requests.exceptions.Timeout:
            return self._make_error("请求超时")
        except Exception as e:
            return self._make_error(f"未知错误: {str(e)}")
