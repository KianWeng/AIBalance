import SwiftUI

/// watchOS 主界面 - 简约扁平设计
struct BalanceWatchView: View {
    @EnvironmentObject var store: BalanceStore

    var body: some View {
        NavigationView {
            ScrollView {
                if store.balances.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.balances.enumerated()), id: \.element.id) { index, item in
                            WatchBalanceRow(item: item)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)

                            if index < store.balances.count - 1 {
                                Divider()
                                    .padding(.leading, 30)
                            }
                        }

                        if let updated = store.lastUpdated {
                            Text(updated.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                    }
                }
            }
            .navigationTitle("AI 余额")
        }
        .onAppear {
            store.loadCachedData()
            store.requestRefresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(.secondary)
            Text("等待数据")
                .font(.system(size: 12, weight: .medium))
            Text("请打开 iPhone App")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }
}

// MARK: - 单行余额

struct WatchBalanceRow: View {
    let item: BalanceItem

    var body: some View {
        VStack(spacing: 4) {
            // 主行
            HStack(spacing: 6) {
                Image(systemName: item.iconSymbol)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.service_name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(item.plan_name)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if item.status == "error" {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                } else {
                    Text(item.shortDisplay)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(usageColor)
                }
            }

            // Cursor token 概要
            if let cx = item.cursorExtra {
                HStack(spacing: 8) {
                    watchTokenLabel("In", value: cx.input_tokens_m)
                    watchTokenLabel("Out", value: cx.output_tokens_m)
                    watchTokenLabel("C", value: cx.cache_tokens_m)
                    Spacer()
                }
                .padding(.leading, 24)
            }
        }
    }

    private func watchTokenLabel(_ label: String, value: Double) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text("\(String(format: "%.1f", value))M")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private var usageColor: Color {
        if item.used_amount > 0 { return .green }
        return .primary
    }
}
