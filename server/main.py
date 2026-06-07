"""AI Balance Watch - 本地服务端入口

启动方式：python3 main.py
API 端点：
  GET /api/balances     - 获取所有服务的余额（缓存）
  GET /api/refresh      - 强制刷新所有余额
  GET /api/health       - 健康检查
"""

import json
import threading
from datetime import datetime
from flask import Flask, jsonify
from flask_cors import CORS
from apscheduler.schedulers.background import BackgroundScheduler
from config import Config
from fetchers import AnthropicFetcher, OpenAIFetcher, CursorFetcher, GoogleFetcher, DeepSeekFetcher

app = Flask(__name__)
CORS(app)  # 允许来自局域网的请求

# ===== 全局状态 =====
# 缓存所有服务的余额数据
_balance_cache: dict = {
    "data": [],
    "last_updated": None,
    "is_refreshing": False,
}
_cache_lock = threading.Lock()

# 所有抓取器实例
_fetchers = [
    AnthropicFetcher(),
    OpenAIFetcher(),
    CursorFetcher(),
    GoogleFetcher(),
    DeepSeekFetcher(),
]


def refresh_all_balances():
    """刷新所有服务的余额数据"""
    with _cache_lock:
        if _balance_cache["is_refreshing"]:
            return  # 避免并发刷新
        _balance_cache["is_refreshing"] = True

    results = []
    for fetcher in _fetchers:
        if fetcher.is_configured():
            print(f"[{datetime.now().strftime('%H:%M:%S')}] 正在获取 {fetcher.service_name} 余额...")
            info = fetcher.fetch()
            results.append(info.to_dict())
            status = "✓" if info.status == "active" else f"✗ {info.error_message}"
            print(f"  → {status}")
        else:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] 跳过 {fetcher.service_name}（未配置凭证）")

    with _cache_lock:
        _balance_cache["data"] = results
        _balance_cache["last_updated"] = datetime.now().isoformat()
        _balance_cache["is_refreshing"] = False

    print(f"[{datetime.now().strftime('%H:%M:%S')}] 刷新完成，共 {len(results)} 个服务\n")


# ===== API 路由 =====

@app.route("/api/balances")
def get_balances():
    """获取所有服务的余额"""
    with _cache_lock:
        return jsonify({
            "balances": _balance_cache["data"],
            "last_updated": _balance_cache["last_updated"],
            "is_refreshing": _balance_cache["is_refreshing"],
            "service_count": len(_balance_cache["data"]),
        })


@app.route("/api/refresh")
def force_refresh():
    """强制刷新所有余额（异步执行）"""
    thread = threading.Thread(target=refresh_all_balances)
    thread.start()
    return jsonify({"message": "刷新已开始", "ok": True})


@app.route("/api/health")
def health_check():
    """健康检查"""
    configured = [f.service_name for f in _fetchers if f.is_configured()]
    not_configured = [f.service_name for f in _fetchers if not f.is_configured()]
    return jsonify({
        "status": "ok",
        "configured_services": configured,
        "not_configured_services": not_configured,
        "refresh_interval": Config.REFRESH_INTERVAL,
    })


# ===== 启动 =====

if __name__ == "__main__":
    print("=" * 50)
    print("  AI Balance Watch - 本地余额服务")
    print("=" * 50)
    print()

    # 显示配置状态
    for fetcher in _fetchers:
        status = "已配置 ✓" if fetcher.is_configured() else "未配置 (跳过)"
        print(f"  {fetcher.service_name}: {status}")
    print()

    # 检查是否有任何服务被配置
    if not any(f.is_configured() for f in _fetchers):
        print("⚠️  没有配置任何服务！请复制 .env.example 为 .env 并填入凭证。")
        print("   cp .env.example .env")
        print()

    # 首次加载
    print("正在首次获取余额...")
    refresh_all_balances()

    # 设置定时刷新
    scheduler = BackgroundScheduler()
    scheduler.add_job(
        refresh_all_balances,
        "interval",
        seconds=Config.REFRESH_INTERVAL,
        id="balance_refresh",
    )
    scheduler.start()
    print(f"定时刷新已启动（每 {Config.REFRESH_INTERVAL} 秒）")
    print()

    # 启动 Flask 服务
    protocol = "https" if Config.use_ssl else "http"
    print(f"服务已启动: {protocol}://0.0.0.0:{Config.SERVER_PORT}")
    print(f"  余额数据: {protocol}://0.0.0.0:{Config.SERVER_PORT}/api/balances")
    print(f"  强制刷新: {protocol}://0.0.0.0:{Config.SERVER_PORT}/api/refresh")
    print(f"  健康检查: {protocol}://0.0.0.0:{Config.SERVER_PORT}/api/health")
    print()
    print("按 Ctrl+C 停止服务")
    print("-" * 50)

    try:
        app.run(host="0.0.0.0", port=Config.SERVER_PORT, debug=False, **Config.ssl_context)
    except KeyboardInterrupt:
        scheduler.shutdown()
        print("\n服务已停止")
