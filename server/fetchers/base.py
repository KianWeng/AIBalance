"""余额抓取器 - 基类"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict
from typing import Optional
from datetime import datetime


@dataclass
class BalanceInfo:
    """单个服务的余额信息"""
    service_name: str          # 服务名称，如 "Claude"
    service_id: str            # 服务标识，如 "anthropic"
    plan_name: str             # 套餐名称，如 "Pro", "API"
    total_quota: Optional[float]   # 总额度（美元），None 表示不限额
    used_amount: float         # 已用金额（美元）
    remaining: Optional[float]     # 剩余额度（美元），None 表示不限额
    currency: str              # 货币单位，默认 "USD"
    billing_period: str        # 计费周期，如 "monthly", "2024-01"
    usage_percentage: float    # 使用百分比 0-100
    last_updated: str          # 最后更新时间 ISO 格式
    status: str                # "active", "expired", "error"
    error_message: str         # 错误信息，正常时为空
    extra: Optional[dict] = None   # 附加数据 (如 Cursor token/模型明细)

    def to_dict(self) -> dict:
        return asdict(self)


class BaseFetcher(ABC):
    """所有余额抓取器的基类"""

    service_name: str = ""
    service_id: str = ""

    @abstractmethod
    def is_configured(self) -> bool:
        """检查是否已配置所需的凭证"""
        pass

    @abstractmethod
    def fetch(self) -> BalanceInfo:
        """抓取余额信息"""
        pass

    def _make_error(self, message: str) -> BalanceInfo:
        """构造错误状态的 BalanceInfo"""
        return BalanceInfo(
            service_name=self.service_name,
            service_id=self.service_id,
            plan_name="Unknown",
            total_quota=None,
            used_amount=0,
            remaining=None,
            currency="USD",
            billing_period="",
            usage_percentage=0,
            last_updated=datetime.now().isoformat(),
            status="error",
            error_message=message,
        )

    def _make_info(
        self,
        plan_name: str,
        total_quota: Optional[float],
        used_amount: float,
        billing_period: str = "monthly",
        currency: str = "USD",
    ) -> BalanceInfo:
        """构造正常的 BalanceInfo"""
        remaining = None
        usage_pct = 0.0
        if total_quota is not None and total_quota > 0:
            remaining = max(0, total_quota - used_amount)
            usage_pct = min(100, (used_amount / total_quota) * 100)

        return BalanceInfo(
            service_name=self.service_name,
            service_id=self.service_id,
            plan_name=plan_name,
            total_quota=total_quota,
            used_amount=round(used_amount, 2),
            remaining=round(remaining, 2) if remaining is not None else None,
            currency=currency,
            billing_period=billing_period,
            usage_percentage=round(usage_pct, 1),
            last_updated=datetime.now().isoformat(),
            status="active",
            error_message="",
        )
