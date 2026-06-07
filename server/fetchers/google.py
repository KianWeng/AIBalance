"""Google (Gemini / AI Studio) 余额抓取器

通过 Google AI Studio 的 API Key 获取 Gemini API 用量。
Google AI Studio 目前对大部分用户免费，但有速率限制。

获取 API Key 方法：
1. 访问 https://aistudio.google.com/apikey
2. 点击 "Create API Key" 或复制已有的 Key
"""

import requests
from datetime import datetime
from .base import BaseFetcher, BalanceInfo
from config import Config


class GoogleFetcher(BaseFetcher):
    service_name = "Gemini"
    service_id = "google"

    def is_configured(self) -> bool:
        return bool(Config.GOOGLE_API_KEY)

    def fetch(self) -> BalanceInfo:
        if not self.is_configured():
            return self._make_error("未配置 GOOGLE_API_KEY")

        try:
            # 方式 1: 通过 Generative Language API 获取使用情况
            # 注意：Google 目前没有直接的 usage/billing API for AI Studio
            # 我们用一个轻量调用来验证 Key 是否有效，并获取模型信息

            # 验证 API Key 是否有效
            validate_resp = requests.get(
                "https://generativelanguage.googleapis.com/v1beta/models",
                params={"key": Config.GOOGLE_API_KEY},
                timeout=15,
            )

            if validate_resp.status_code == 400:
                error_data = validate_resp.json()
                if "API key not valid" in str(error_data):
                    return self._make_error("API Key 无效")
                return self._make_error(f"API 错误: {error_data.get('error', {}).get('message', 'unknown')}")

            if validate_resp.status_code == 403:
                return self._make_error("API Key 权限不足")

            if validate_resp.status_code != 200:
                return self._make_error(f"请求失败 (HTTP {validate_resp.status_code})")

            models_data = validate_resp.json()
            model_count = len(models_data.get("models", []))

            # Google AI Studio 目前是免费使用的，没有美元额度概念
            # 但有 RPM (requests per minute) 和 TPM (tokens per minute) 限制
            # 我们展示 Key 状态和可用模型数量
            now = datetime.now()

            info = self._make_info(
                plan_name="AI Studio (Free)",
                total_quota=None,
                used_amount=0,
                billing_period=now.strftime("%Y-%m"),
            )

            # 附加信息：可用模型数量
            if model_count > 0:
                info.plan_name = f"AI Studio ({model_count} models)"

            return info

        except requests.exceptions.Timeout:
            return self._make_error("请求超时")
        except Exception as e:
            return self._make_error(f"未知错误: {str(e)}")
