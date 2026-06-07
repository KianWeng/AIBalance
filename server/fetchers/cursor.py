"""Cursor 余额抓取器

通过 Cursor 桌面端的 accessToken (JWT) 直接调用 gRPC-web API 获取用量数据。
自动从本地 Cursor 应用的 state.vscdb 读取 accessToken，无需额外配置。

API 端点：api2.cursor.sh (gRPC-web)
  - DashboardService/GetPlanInfo              → 计划信息
  - DashboardService/GetCurrentBillingCycle   → 计费周期
  - DashboardService/GetAggregatedUsageEvents → 用量汇总 (tokens / cost)
"""

import sqlite3
import struct
import requests
from pathlib import Path
from datetime import datetime
from .base import BaseFetcher, BalanceInfo
from config import Config


class CursorFetcher(BaseFetcher):
    service_name = "Cursor"
    service_id = "cursor"

    GRPC_BASE = "https://api2.cursor.sh/aiserver.v1"

    def is_configured(self) -> bool:
        return bool(
            Config.CURSOR_ACCESS_TOKEN
            or self._read_local_token()
        )

    # ======================== 本地数据读取 ========================

    @staticmethod
    def _db_path() -> Path:
        return (
            Path.home()
            / "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        )

    def _read_local_state(self, key: str) -> str:
        """从 Cursor 的 state.vscdb 读取指定 key"""
        db = self._db_path()
        if not db.exists():
            return ""
        try:
            conn = sqlite3.connect(str(db))
            row = conn.execute(
                "SELECT value FROM ItemTable WHERE key=?", (key,)
            ).fetchone()
            conn.close()
            return row[0] if row else ""
        except Exception:
            return ""

    def _read_local_token(self) -> str:
        return self._read_local_state("cursorAuth/accessToken")

    def _read_local_plan(self) -> str:
        return self._read_local_state("cursorAuth/stripeMembershipType")

    def _read_local_email(self) -> str:
        return self._read_local_state("cursorAuth/cachedEmail")

    @property
    def _token(self) -> str:
        return Config.CURSOR_ACCESS_TOKEN or self._read_local_token()

    # ======================== 计划名称标准化 ========================

    @staticmethod
    def _normalize_plan(raw: str) -> str:
        p = raw.lower().strip()
        if p in ("enterprise", "business"):
            return "Enterprise"
        if p in ("pro", "active"):
            return "Pro"
        if "trial" in p:
            return "Pro (Trial)"
        if p in ("hobby", "free", ""):
            return "Free"
        return raw.capitalize()

    # ======================== gRPC-web 通信 ========================

    @staticmethod
    def _encode_varint(val: int) -> bytes:
        """编码 protobuf varint"""
        result = bytearray()
        while val > 0x7F:
            result.append(0x80 | (val & 0x7F))
            val >>= 7
        result.append(val & 0x7F)
        return bytes(result)

    @staticmethod
    def _decode_varint(data: bytes, pos: int) -> tuple[int, int]:
        """解码 protobuf varint，返回 (value, new_pos)"""
        val, shift = 0, 0
        while pos < len(data):
            b = data[pos]
            val |= (b & 0x7F) << shift
            pos += 1
            if not (b & 0x80):
                break
            shift += 7
        return val, pos

    @classmethod
    def _encode_int64_field(cls, field_num: int, value: int) -> bytes:
        """编码 protobuf int64 字段 (wire type 0 = varint)"""
        tag = cls._encode_varint((field_num << 3) | 0)
        return tag + cls._encode_varint(value)

    @classmethod
    def _decode_protobuf(cls, data: bytes) -> dict:
        """通用 protobuf 解码为 dict (field_num → value)"""
        result: dict = {}
        pos = 0
        while pos < len(data):
            tag, pos = cls._decode_varint(data, pos)
            field_num = tag >> 3
            wire_type = tag & 0x07

            if wire_type == 0:  # varint
                val, pos = cls._decode_varint(data, pos)
            elif wire_type == 2:  # length-delimited
                length, pos = cls._decode_varint(data, pos)
                sub = data[pos : pos + length]
                pos += length
                # 尝试递归解析为子消息，失败则当作字符串
                try:
                    val = cls._decode_protobuf(sub)
                    if not val:
                        val = sub.decode("utf-8", errors="replace")
                except Exception:
                    val = sub
            elif wire_type == 5:  # fixed32
                val = struct.unpack("<I", data[pos : pos + 4])[0]
                pos += 4
            elif wire_type == 1:  # fixed64
                val = struct.unpack("<Q", data[pos : pos + 8])[0]
                pos += 8
            else:
                break

            # 处理重复字段 (repeated)
            if field_num in result:
                existing = result[field_num]
                if isinstance(existing, list):
                    existing.append(val)
                else:
                    result[field_num] = [existing, val]
            else:
                result[field_num] = val

        return result

    @staticmethod
    def _fixed64_to_double(raw_int: int) -> float:
        """将 protobuf fixed64 (int) 转换为 double"""
        return struct.unpack("<d", struct.pack("<Q", raw_int))[0]

    def _grpc_request(self, service: str, method: str, payload: bytes = b"") -> dict | None:
        """发送 gRPC-web 请求并返回解码后的 protobuf dict

        Returns:
            解码后的 protobuf dict，失败时返回 None
        """
        # gRPC 帧: flag(1B) + length(4B) + payload
        grpc_frame = struct.pack(">BI", 0, len(payload)) + payload

        headers = {
            "Content-Type": "application/grpc-web+proto",
            "Authorization": f"Bearer {self._token}",
            "x-grpc-web": "1",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
            "Origin": "https://cursor.com",
        }

        url = f"{self.GRPC_BASE}.{service}/{method}"
        resp = requests.post(url, data=grpc_frame, headers=headers, timeout=15)

        if resp.status_code != 200:
            return None

        data = resp.content
        if len(data) < 5:
            return None

        msg_len = struct.unpack(">I", data[1:5])[0]
        proto_data = data[5 : 5 + msg_len]

        # 检查 gRPC trailers
        trailers = data[5 + msg_len :].decode("utf-8", errors="replace")
        if "grpc-status: 0" not in trailers:
            return None

        return self._decode_protobuf(proto_data) if proto_data else {}

    # ======================== API 调用 ========================

    def _fetch_plan_info(self) -> str | None:
        """从 gRPC 获取计划信息

        Returns:
            计划名称 (如 "Enterprise", "Pro") 或 None
        """
        data = self._grpc_request("DashboardService", "GetPlanInfo")
        if not data:
            return None

        # GetPlanInfoResponse.field1 = PlanInfo
        #   .field1 = plan_name (string, e.g. "Enterprise")
        #   .field3 = billing_type (string, e.g. "Custom")
        plan_info = data.get(1, {})
        if isinstance(plan_info, dict):
            plan_name = plan_info.get(1, "")
            if isinstance(plan_name, str) and plan_name:
                return plan_name
        return None

    def _fetch_billing_cycle(self) -> tuple[int, int] | None:
        """从 gRPC 获取当前计费周期

        Returns:
            (start_ms, end_ms) 或 None
        """
        data = self._grpc_request("DashboardService", "GetCurrentBillingCycle")
        if not data:
            return None

        start = data.get(1, 0)
        end = data.get(2, 0)
        if start and end:
            return (start, end)
        return None

    def _fetch_aggregated_usage(self, start_ms: int, end_ms: int) -> dict | None:
        """从 gRPC 获取聚合用量数据

        Args:
            start_ms: 计费周期开始时间 (毫秒)
            end_ms: 计费周期结束时间 (毫秒)

        Returns:
            包含用量数据的 dict:
            {
                "total_input_tokens": int,
                "total_output_tokens": int,
                "total_cache_read_tokens": int,
                "total_cost_dollars": float,
                "models": [{"name": str, "input": int, "output": int, "cost": float}, ...]
            }
        """
        # GetAggregatedUsageEventsRequest:
        #   field 2: start_date (int64), field 3: end_date (int64)
        payload = self._encode_int64_field(2, start_ms) + self._encode_int64_field(3, end_ms)

        data = self._grpc_request("DashboardService", "GetAggregatedUsageEvents", payload)
        if data is None:
            return None

        result = {
            "total_input_tokens": data.get(2, 0),
            "total_output_tokens": data.get(3, 0),
            "total_cache_read_tokens": data.get(5, 0),
            "total_cost_dollars": 0.0,
            "models": [],
        }

        # field 6: total_cost (double encoded as fixed64, unit = cents → /100 = dollars)
        raw_cost = data.get(6, 0)
        if isinstance(raw_cost, int) and raw_cost > 0:
            result["total_cost_dollars"] = self._fixed64_to_double(raw_cost) / 100.0

        # field 1: aggregations (repeated message)
        aggs = data.get(1, [])
        if isinstance(aggs, list):
            for agg in aggs:
                if not isinstance(agg, dict):
                    continue
                model = {
                    "name": agg.get(1, "unknown"),
                    "input": agg.get(2, 0),
                    "output": agg.get(3, 0),
                    "cache_read": agg.get(5, 0),
                    "cost": 0.0,
                }
                raw_model_cost = agg.get(6, 0)
                if isinstance(raw_model_cost, int) and raw_model_cost > 0:
                    model["cost"] = self._fixed64_to_double(raw_model_cost) / 100.0
                result["models"].append(model)

        return result

    # ======================== 主抓取逻辑 ========================

    def fetch(self) -> BalanceInfo:
        if not self.is_configured():
            return self._make_error(
                "未配置凭证。请启动 Cursor 应用以自动读取 accessToken"
            )

        try:
            # Step 1: 获取计划信息 (优先 gRPC，回退到本地)
            plan_raw = self._fetch_plan_info()
            if not plan_raw:
                plan_raw = self._read_local_plan()
            plan = self._normalize_plan(plan_raw) if plan_raw else "Unknown"

            # Step 2: 获取计费周期
            cycle = self._fetch_billing_cycle()
            if cycle:
                start_ms, end_ms = cycle
                start_str = datetime.fromtimestamp(start_ms / 1000).strftime("%Y-%m-%d")
                end_str = datetime.fromtimestamp(end_ms / 1000).strftime("%Y-%m-%d")
                billing_period = f"{start_str} ~ {end_str}"
            else:
                start_ms = end_ms = 0
                billing_period = datetime.now().strftime("%Y-%m")

            # Step 3: 获取用量数据
            usage = None
            if start_ms and end_ms:
                usage = self._fetch_aggregated_usage(start_ms, end_ms)

            if usage and usage["total_cost_dollars"] > 0:
                total_cost = round(usage["total_cost_dollars"], 2)

                info = self._make_info(
                    plan_name=plan,
                    total_quota=Config.CURSOR_TOTAL_QUOTA if Config.CURSOR_TOTAL_QUOTA > 0 else None,
                    used_amount=total_cost,
                    billing_period=billing_period,
                )
                info.currency = "USD"

                # 构造 extra 数据 (token 用量 + 模型明细)
                input_m = round(usage["total_input_tokens"] / 1_000_000, 2)
                output_m = round(usage["total_output_tokens"] / 1_000_000, 2)
                cache_m = round(usage["total_cache_read_tokens"] / 1_000_000, 2)

                models = []
                for m in usage["models"]:
                    name = m["name"] if isinstance(m["name"], str) else "unknown"
                    models.append({
                        "name": name,
                        "input_m": round(m["input"] / 1_000_000, 2),
                        "output_m": round(m["output"] / 1_000_000, 2),
                        "cache_m": round(m["cache_read"] / 1_000_000, 2),
                        "cost": round(m["cost"], 2),
                    })

                info.extra = {
                    "input_tokens_m": input_m,
                    "output_tokens_m": output_m,
                    "cache_tokens_m": cache_m,
                    "models": models,
                }

                return info

            # 回退: 只显示计划信息
            info = self._make_info(
                plan_name=plan,
                total_quota=Config.CURSOR_TOTAL_QUOTA if Config.CURSOR_TOTAL_QUOTA > 0 else None,
                used_amount=0,
                billing_period=billing_period,
            )
            info.currency = "USD"
            email = self._read_local_email()
            if email:
                info.error_message = f"用量数据暂不可用 ({email})"
            else:
                info.error_message = "用量数据暂不可用"

            return info

        except requests.exceptions.Timeout:
            return self._make_error("请求超时")
        except requests.exceptions.ConnectionError:
            return self._make_error("网络连接失败")
        except Exception as e:
            return self._make_error(f"未知错误: {str(e)}")
