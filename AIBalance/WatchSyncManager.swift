import Foundation
import Combine
import WatchConnectivity

/// 管理 iPhone ↔ Apple Watch 之间的数据同步
///
/// 工作原理：
/// 1. iPhone 从 Mac 服务器拿到余额数据
/// 2. 通过 WCSession 发送给 Watch（即时消息 + 后台传输）
/// 3. Watch 端收到后更新 UI 和 Complication
class WatchSyncManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSyncManager()

    @Published var isWatchReachable = false

    private override init() {
        super.init()
    }

    /// 激活 Watch 通信会话
    func activateSession() {
        guard WCSession.isSupported() else {
            print("当前设备不支持 WatchConnectivity")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("WatchConnectivity 会话已激活")
    }

    /// 发送余额数据到 Watch
    func sendBalances(_ balances: [BalanceItem]) {
        guard WCSession.default.isReachable else {
            // Watch 不可达，用后台传输
            sendViaBackgroundTransfer(balances)
            return
        }

        // 即时发送（Watch App 在前台时）
        let payload = WatchPayload(balances: balances, timestamp: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }

        WCSession.default.sendMessage(
            [AppConstants.WatchKeys.balancesData: data],
            replyHandler: { reply in
                print("Watch 确认收到数据: \(reply)")
            },
            errorHandler: { error in
                print("发送失败: \(error.localizedDescription)")
                // 发送失败时改用后台传输
                self.sendViaBackgroundTransfer(balances)
            }
        )
    }

    /// 后台传输（Watch App 不在前台时使用）
    private func sendViaBackgroundTransfer(_ balances: [BalanceItem]) {
        let payload = WatchPayload(balances: balances, timestamp: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }

        do {
            try WCSession.default.updateApplicationContext(
                [AppConstants.WatchKeys.balancesData: data]
            )
            print("已通过 ApplicationContext 传输余额数据")
        } catch {
            print("ApplicationContext 传输失败: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
        if let error = error {
            print("WCSession 激活错误: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = false
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = false
        }
        // 重新激活
        session.activate()
    }

    /// 接收 Watch 发来的消息（比如 Watch 请求刷新）
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message[AppConstants.WatchKeys.requestRefresh] as? Bool == true {
            print("Watch 请求刷新数据")
            DispatchQueue.main.async {
                // 通知 API Service 重新获取数据
                NotificationCenter.default.post(name: .watchRequestedRefresh, object: nil)
            }
            replyHandler([AppConstants.WatchKeys.refreshStatus: "refreshing"])
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }
}

// MARK: - 自定义通知名
extension Notification.Name {
    static let watchRequestedRefresh = Notification.Name("watchRequestedRefresh")
}
