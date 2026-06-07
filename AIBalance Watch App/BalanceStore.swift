import Foundation
import Combine
import WatchConnectivity
import WidgetKit

/// watchOS 端的数据管理器
///
/// 数据来源有两个：
/// 1. iPhone 通过 WCSession 实时推送
/// 2. App Group UserDefaults 共享缓存（兜底）
class BalanceStore: NSObject, ObservableObject, WCSessionDelegate {

    @Published var balances: [BalanceItem] = []
    @Published var lastUpdated: Date?
    @Published var isConnected = false

    override init() {
        super.init()
        activateSession()
    }

    // MARK: - WatchConnectivity

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 请求 iPhone 端刷新数据
    func requestRefresh() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [AppConstants.WatchKeys.requestRefresh: true],
            replyHandler: { reply in
                print("iPhone 回复: \(reply)")
            },
            errorHandler: { error in
                print("请求刷新失败: \(error)")
            }
        )
    }

    // MARK: - 数据缓存

    /// 从 App Group 或标准 UserDefaults 加载缓存数据
    func loadCachedData() {
        let sources: [UserDefaults?] = [
            UserDefaults(suiteName: AppConstants.appGroupID),
            UserDefaults.standard
        ]
        for defaults in sources {
            guard let defaults = defaults,
                  let data = defaults.data(forKey: AppConstants.StorageKeys.cachedBalances),
                  let cached = try? JSONDecoder().decode([BalanceItem].self, from: data),
                  !cached.isEmpty
            else { continue }
            DispatchQueue.main.async {
                self.balances = cached
                self.lastUpdated = defaults.object(forKey: AppConstants.StorageKeys.lastUpdated) as? Date
            }
            return
        }
    }

    /// 保存数据到缓存
    private func saveToCache(_ balances: [BalanceItem]) {
        let encoded = try? JSONEncoder().encode(balances)
        // 写入 App Group（如果有）
        if let defaults = UserDefaults(suiteName: AppConstants.appGroupID), let data = encoded {
            defaults.set(data, forKey: AppConstants.StorageKeys.cachedBalances)
            defaults.set(Date(), forKey: AppConstants.StorageKeys.lastUpdated)
        }
        // 同时写入标准 UserDefaults（兜底）
        if let data = encoded {
            UserDefaults.standard.set(data, forKey: AppConstants.StorageKeys.cachedBalances)
            UserDefaults.standard.set(Date(), forKey: AppConstants.StorageKeys.lastUpdated)
        }

        // 在主线程更新 UI 数据
        DispatchQueue.main.async {
            self.balances = balances
            self.lastUpdated = Date()
        }

        // 通知 Widget 刷新 Timeline
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 解析从 iPhone 收到的数据
    private func handleReceivedData(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchPayload.self, from: data) else {
            print("解析余额数据失败")
            return
        }
        saveToCache(payload.balances)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isConnected = activationState == .activated
        }
    }

    /// 接收 iPhone 即时发送的消息
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let data = message[AppConstants.WatchKeys.balancesData] as? Data {
            handleReceivedData(data)
            replyHandler(["status": "ok"])
        }
    }

    /// 接收 iPhone 后台传输的数据（App 不在前台时）
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let data = applicationContext[AppConstants.WatchKeys.balancesData] as? Data {
            handleReceivedData(data)
        }
    }
}
