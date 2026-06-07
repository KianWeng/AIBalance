import Foundation
import Combine

/// 从 Mac 本地服务获取余额数据
class APIService: ObservableObject {
    @Published var balances: [BalanceItem] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?

    private let baseURL: String
    private var cancellables = Set<AnyCancellable>()

    init(baseURL: String = Config.serverURL) {
        self.baseURL = baseURL
        loadCachedData()
    }

    /// 获取所有服务余额
    func fetchBalances() {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/api/balances") else {
            errorMessage = "无效的服务器地址"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10 秒超时

        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: BalancesResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "无法连接到服务器: \(error.localizedDescription)"
                        print("API Error: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.balances = response.balances
                    self?.lastUpdated = Date()
                    self?.cacheData(response.balances)

                    // 同步到 Watch
                    WatchSyncManager.shared.sendBalances(response.balances)
                }
            )
            .store(in: &cancellables)
    }

    /// 强制服务端刷新
    func forceRefresh() {
        guard let url = URL(string: "\(baseURL)/api/refresh") else { return }
        URLSession.shared.dataTask(with: url) { _, _, _ in
            // 等 2 秒后重新获取数据
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.fetchBalances()
            }
        }.resume()
    }

    // MARK: - 本地缓存（通过 App Group 共享给 Watch）

    private func cacheData(_ balances: [BalanceItem]) {
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
    }

    private func loadCachedData() {
        // 先尝试 App Group，再尝试标准 UserDefaults
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
            self.balances = cached
            self.lastUpdated = defaults.object(forKey: AppConstants.StorageKeys.lastUpdated) as? Date
            return
        }
    }
}
