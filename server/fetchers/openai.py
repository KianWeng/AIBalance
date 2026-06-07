"""OpenAI (Codex / ChatGPT) 余额抓取器

支持两种方式获取余额：
1. API Key → 通过 api.openai.com/dashboard/billing 获取 API 用量
2. Session Token → 通过 platform.openai.com 获取详细用量（包括 ChatGPT Plus）

获取凭证方法：
- API Key: https://platform.openai.com/api-keys
- Session Token: 登录 platform.openai.com → DevTools → Application → Cookies → __Secure-next-auth.session-token
"""

import requests
from datetime import datetime, timedelta
from .base import BaseFetcher, BalanceInfo
from config import Config


class OpenAIFetcher(BaseFetcher):
    service_name = "OpenAI"
    service_id = "openai"

    def is_configured(self) -> bool:
        return bool(Config.OPENAI_API_KEY or Config.OPENAI_SESSION_TOKEN)

    def fetch(self) -> BalanceInfo:
        if not self.is_configured():
            return self._make_error("未配置 OPENAI_API_KEY 或 OPENAI_SESSION_TOKEN")

        # 优先使用 API Key
        if Config.OPENAI_API_KEY:
            return self._fetch_via_api_key()
        else:
            return self._fetch_via_session()

    def _fetch_via_api_key(self) -> BalanceInfo:
        """通过 API Key 获取用量 - 适用于 API / Codex 用户"""
        try:
            headers = {
                "Authorization": f"Bearer {Config.OPENAI_API_KEY}",
            }

            # 获取当前计费周期的用量
            # OpenAI 的 billing 端点 - 计算当前月份的开始和结束时间戳
            now = datetime.now()
            start_date = now.replace(day=1)
            end_date = (start_date + timedelta(days=32)).replace(day=1)

            start_ts = int(start_date.timestamp())
            end_ts = int(end_date.timestamp())

            # 获取用量
            usage_resp = requests.get(
                f"https://api.openai.com/dashboard/billing/usage",
                headers=headers,
                params={"start_date": start_date.isoformat()[:10], "end_date": end_date.isoformat()[:10]},
                timeout=15,
            )

            if usage_resp.status_code == 401:
                return self._make_error("API Key 无效或已过期")
            if usage_resp.status_code != 200:
                return self._make_error(f"请求失败 (HTTP {usage_resp.status_code})")

            usage_data = usage_resp.json()

            # OpenAI 返回的金额单位是 cents（分），需要除以 100
            used_cents = usage_data.get("total_usage", 0)
            used = used_cents / 100.0

            # 获取额度上限
            credit_resp = requests.get(
                "https://api.openai.com/dashboard/billing/credit_grants",
                headers=headers,
                timeout=15,
            )

            total = None
            remaining = None
            if credit_resp.status_code == 200:
                credit_data = credit_resp.json()
                total_granted = credit_data.get("total_granted", 0)
                total_used = credit_data.get("total_used", 0)
                total_available = credit_data.get("total_available", 0)
                if total_granted > 0:
                    total = total_granted
                    remaining = total_available
                    used = total_used

            billing_period = now.strftime("%Y-%m")

            return self._make_info(
                plan_name="API",
                total_quota=total,
                used_amount=used,
                billing_period=billing_period,
            )

        except requests.exceptions.Timeout:
            return self._make_error("请求超时")
        except Exception as e:
            return self._make_error(f"未知错误: {str(e)}")

    def _fetch_via_session(self) -> BalanceInfo:
        """通过 Session Token 获取用量 - 可获取 ChatGPT Plus 等信息"""
        try:
            headers = {
                "Cookie": f"__Secure-next-auth.session-token={Config.OPENAI_SESSION_TOKEN}",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
                "Accept": "application/json",
            }

            # 获取账户信息
            resp = requests.get(
                "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27",
                headers=headers,
                timeout=15,
            )

            if resp.status_code == 401:
                return self._make_error("Session Token 已过期，请重新登录")
            if resp.status_code != 200:
                return self._make_error(f"请求失败 (HTTP {resp.status_code})")

            data = resp.json()
            accounts = data.get("accounts", {})

            # 解析账户类型
            plan = "Free"
            for acc_id, acc_data in accounts.items():
                account_type = acc_data.get("account", {}).get("plan_type", "free")
                if account_type in ("plus", "team", "enterprise"):
                    plan = account_type.capitalize()
                    break

            # Session 方式无法精确获取用量，返回基本信息
            return self._make_info(
                plan_name=plan,
                total_quota=None,  # ChatGPT Plus 没有明确的美元额度
                used_amount=0,
                billing_period="monthly",
            )

        except Exception as e:
            return self._make_error(f"未知错误: {str(e)}")
