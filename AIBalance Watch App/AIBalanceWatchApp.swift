import SwiftUI

@main
struct AIBalanceWatchApp: App {
    @StateObject private var store = BalanceStore()

    var body: some Scene {
        WindowGroup {
            BalanceWatchView()
                .environmentObject(store)
                .onAppear {
                    store.loadCachedData()
                    store.requestRefresh()
                }
        }
    }
}
