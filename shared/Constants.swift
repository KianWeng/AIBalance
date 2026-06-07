import Foundation

/// 共享常量 - iOS 和 watchOS 共用
enum AppConstants {
    /// App Group ID（用于数据共享）
    static let appGroupID = "group.com.yourname.aibalance"

    /// WatchConnectivity 消息 key
    enum WatchKeys {
        static let balancesData = "balancesData"
        static let requestRefresh = "requestRefresh"
        static let refreshStatus = "refreshStatus"
    }

    /// UserDefaults key（App Group 共享）
    enum StorageKeys {
        static let cachedBalances = "cached_balances"
        static let lastUpdated = "last_updated"
        static let serverURL = "server_url"
    }

    /// 默认服务地址
    static let defaultServerURL = "http://192.168.3.118:8787"
}
