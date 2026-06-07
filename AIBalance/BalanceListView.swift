import SwiftUI

/// iOS App 主界面 - 简约扁平设计
struct BalanceListView: View {
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var watchSync: WatchSyncManager

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if apiService.isLoading && apiService.balances.isEmpty {
                    loadingView
                } else if let error = apiService.errorMessage, apiService.balances.isEmpty {
                    errorView(error)
                } else {
                    balanceList
                }
            }
            .navigationTitle("AI 余额")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        apiService.fetchBalances()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                    }
                }
            }
        }
    }

    // MARK: - 主列表

    private var balanceList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {

                // 概览摘要
                if !apiService.balances.isEmpty {
                    summaryHeader
                        .padding(.bottom, 8)
                }

                // 服务列表
                VStack(spacing: 0) {
                    ForEach(Array(apiService.balances.enumerated()), id: \.element.id) { index, item in
                        BalanceRow(item: item)

                        if index < apiService.balances.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .padding(.trailing, 20)
                        }
                    }
                }
                .background(Color(.systemBackground))

                // 底部信息区
                bottomInfo
            }
            .padding(.top, 8)
        }
        .refreshable {
            apiService.fetchBalances()
        }
    }

    // MARK: - 概览摘要

    private var summaryHeader: some View {
        HStack(spacing: 20) {
            summaryItem(
                label: "服务",
                value: "\(apiService.balances.count)",
                color: .primary
            )

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1, height: 24)

            summaryItem(
                label: "已用",
                value: "$\(totalUsedAmount)",
                color: .primary
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }

    private func summaryItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 底部信息

    private var bottomInfo: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(watchSync.isWatchReachable ? Color.green : Color(.tertiaryLabel))
                    .frame(width: 6, height: 6)
                Text("Watch \(watchSync.isWatchReachable ? "已连接" : "未连接")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)

            Button {
                apiService.forceRefresh()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text("强制刷新服务端")
                        .font(.system(size: 13))
                }
                .foregroundColor(.secondary)
            }

            if let updated = apiService.lastUpdated {
                Text("更新于 \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11))
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - 加载状态

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在加载")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 错误视图

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("无法连接服务器")
                    .font(.system(size: 16, weight: .medium))

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 4) {
                tipLine("Mac 上的服务正在运行")
                tipLine("iPhone 和 Mac 在同一 Wi-Fi")
                tipLine("Config.swift 中 IP 地址正确")
            }
            .padding(.horizontal, 40)

            Button {
                apiService.fetchBalances()
            } label: {
                Text("重试")
                    .font(.system(size: 14, weight: .medium))
                    .frame(minWidth: 100)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 4)

            Spacer()
        }
    }

    private func tipLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(.tertiaryLabel))
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - 计算属性

    private var totalUsedAmount: String {
        let total = apiService.balances.reduce(0.0) { $0 + $1.used_amount }
        return String(format: "%.2f", total)
    }
}

// MARK: - 单行余额（可展开详情）

struct BalanceRow: View {
    let item: BalanceItem
    @State private var isExpanded = false

    private var hasDetail: Bool {
        item.cursorExtra != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // 主行
            HStack(spacing: 14) {
                // 服务图标
                Image(systemName: item.iconSymbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(item.status == "error" ? .red : .primary)
                    .frame(width: 32)

                // 名称与计划
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.service_name)
                            .font(.system(size: 15, weight: .medium))
                        Text(item.plan_name)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    // Cursor: 显示 token 概要
                    if let cx = item.cursorExtra {
                        HStack(spacing: 10) {
                            tokenChip("In", value: cx.input_tokens_m)
                            tokenChip("Out", value: cx.output_tokens_m)
                            tokenChip("Cache", value: cx.cache_tokens_m)
                        }
                    }
                }

                Spacer(minLength: 8)

                // 金额 + 展开箭头
                HStack(spacing: 4) {
                    Text(item.displayAmount)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(item.status == "error" ? .red : .primary)
                        .lineLimit(1)

                    if hasDetail {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                if hasDetail {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                }
            }

            // 用量进度条（有总额度时显示）
            if item.total_quota != nil && item.total_quota! > 0 {
                usageBar
            }

            // 展开的模型明细
            if isExpanded, let cx = item.cursorExtra {
                cursorDetailView(cx)
            }
        }
    }

    // MARK: - 用量进度条

    private var usageBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.quaternarySystemFill))
                RoundedRectangle(cornerRadius: 2)
                    .fill(usageColor)
                    .frame(width: geo.size.width * CGFloat(min(item.usage_percentage, 100) / 100))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 20)
        .padding(.leading, 46)
        .padding(.bottom, 10)
    }

    private var usageColor: Color {
        let pct = item.usage_percentage
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        return .green
    }

    // MARK: - Token 小标签

    private func tokenChip(_ label: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(.tertiaryLabel))
            Text("\(String(format: "%.1f", value))M")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Cursor 模型明细面板

    private func cursorDetailView(_ cx: CursorExtra) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.leading, 68)

            VStack(spacing: 10) {
                // 表头
                HStack {
                    Text("模型")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Input")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(width: 55, alignment: .trailing)

                    Text("Output")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(width: 55, alignment: .trailing)

                    Text("Cache")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(width: 55, alignment: .trailing)

                    Text("Cost")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(width: 55, alignment: .trailing)
                }

                // 各模型行
                ForEach(cx.models, id: \.name) { model in
                    HStack {
                        Text(model.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Text("\(String(format: "%.2f", model.input_m))M")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .trailing)

                        Text("\(String(format: "%.2f", model.output_m))M")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .trailing)

                        Text("\(String(format: "%.1f", model.cache_m))M")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .trailing)

                        Text("$\(String(format: "%.2f", model.cost))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(width: 55, alignment: .trailing)
                    }
                }

                // 合计行
                Divider()

                HStack {
                    Text("合计")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(String(format: "%.2f", cx.input_tokens_m))M")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 55, alignment: .trailing)

                    Text("\(String(format: "%.2f", cx.output_tokens_m))M")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 55, alignment: .trailing)

                    Text("\(String(format: "%.1f", cx.cache_tokens_m))M")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 55, alignment: .trailing)

                    Text("$\(String(format: "%.2f", item.used_amount))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(width: 55, alignment: .trailing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.leading, 46) // 对齐图标右侧
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
}
