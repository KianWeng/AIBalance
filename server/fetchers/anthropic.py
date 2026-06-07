"""Anthropic (Claude) 余额抓取器

通过 console.anthropic.com 的 session cookie 获取用量信息。
Anthropic 没有公开的用量 API，所以需要通过浏览器 Cookie 访问内部接口。

获取 Cookie 方法：
1. 登录 https://console.anthropic.com
2. 打开 DevTools (F12) → Application → Cookies
3. 复制所有 Cookie 值（或至少 __Host-next-auth.session-token）
"""

import requests
from datetime import datetime
from .base import BaseFetcher, BalanceInfo
from config import Config


class AnthropicFetcher(BaseFetcher):
    service_name = "Claude"
    service_id = "anthropic"

    def is_configured(self) -> bool:
        return bool(Config.ANTHROPIC_SESSION_COOKIE)

    def fetch(self) -> BalanceInfo:
        if not self.is_configured():
            return self._make_error("未配置 ANTHROPIC_SESSION_COOKIE")

        try:
            # Anthropic Console 内部 API - 获取用量信息
            # 注意：这个端点可能随 Anthropic 前端更新而变化
            headers = {
                "Cookie": Config.ANTHROPIC_SESSION_COOKIE,
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
                "Accept": "application/json",
                "Referer": "https://console.anthropic.com/settings/usage",
            }

            # 尝试获取使用量数据
            resp = requests.get(
                "https://api.anthropic.com/v1/usage",
                headers=headers,
                timeout=15,
            )

            # 如果 v1/usage 不可用，尝试 console 内部端点
            if resp.status_code != 200:
                resp = requests.get(
                    "https://console.anthropic.com/api/settings/usage",
                    headers=headers,
                    timeout=15,
                )

            if resp.status_code == 401:
                return self._make_error("Cookie 已过期，请重新登录获取")
            if resp.status_code != 200:
                return self._make_error(f"请求失败 (HTTP {resp.status_code})")

            data = resp.json()

            # 解析用量数据 - 根据 Anthropic 的实际返回格式调整
            # 以下为常见返回结构的解析逻辑
            used = 0.0
            total = None
            plan = "API"

            if "usage" in data:
                usage_data = data["usage"]
                used = usage_data.get("total_cost", 0)
                total = usage_data.get("budget_limit", None)
                plan = usage_data.get("plan", "API")
            elif "total_cost" in data:
                used = data["total_cost"]
                total = data.get("budget_limit", None)
            elif "credits" in data:
                credits = data["credits"]
                used = credits.get("used", 0)
                total = credits.get("total", None)
                remaining = credits.get("remaining", None)
                if total and remaining:
                    used = total - remaining

            # 确定当前计费周期
            now = datetime.now()
            billing_period = now.strftime("%Y-%m")

            return self._make_info(
                plan_name=plan,
                total_quota=total,
                used_amount=used,
                billing_period=billing_period,
            )

        except requests.exceptions.Timeout:
            return self._make_error("请求超时")
        except requests.exceptions.ConnectionError:
            return self._make_error("网络连接失败")
        except Exception as e:
            return self._make_error(f"未知错误: {str(e)}")
