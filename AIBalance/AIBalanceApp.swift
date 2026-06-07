import SwiftUI

@main
struct AIBalanceApp: App {
    @StateObject private var apiService = APIService()
    @StateObject private var watchSync = WatchSyncManager.shared

    var body: some Scene {
        WindowGroup {
            BalanceListView()
                .environmentObject(apiService)
                .environmentObject(watchSync)
                .onAppear {
                    // App 启动时加载数据并同步到 Watch
                    apiService.fetchBalances()
                    watchSync.activateSession()
                }
        }
    }
}
