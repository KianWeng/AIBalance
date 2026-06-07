import WidgetKit
import SwiftUI
import AppIntents

// ====================================================================
// watchOS Complication - 表盘组件
//
// 支持样式：
// - 圆形 (accessoryCircular): 外圈进度环 + 内显用量/总额 + 提供商名
// - 矩形 (accessoryRectangular): 提供商名 + 用量 + 横向进度条
// - 内联 (accessoryInline): 文字摘要
//
// 用户可通过表盘编辑选择显示哪个 AI 提供商
// ====================================================================

// MARK: - 提供商选择 (AppIntent)

enum AIProvider: String, AppEnum {
    case anthropic, openai, cursor, google

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "AI 提供商"

    static var caseDisplayRepresentations: [AIProvider: DisplayRepresentation] = [
        .anthropic: "Claude",
        .openai: "OpenAI",
        .cursor: "Cursor",
        .google: "Gemini",
    ]
}

struct ProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "AI 提供商"
    static var description: IntentDescription = "选择表盘上显示哪个 AI 服务的用量"

    @Parameter(title: "服务商", default: .cursor)
    var provider: AIProvider
}

// MARK: - Timeline

struct BalanceWidgetEntry: TimelineEntry {
    let date: Date
    let item: BalanceItem?
    let allBalances: [BalanceItem]

    static var sample: BalanceWidgetEntry {
        BalanceWidgetEntry(
            date: Date(),
            item: BalanceItem(
                service_name: "Cursor",
                service_id: "cursor",
                plan_name: "Enterprise",
                total_quota: 150,
                used_amount: 17.72,
                remaining: 132.28,
                currency: "USD",
                billing_period: "2026-06",
                usage_percentage: 11.8,
                last_updated: Date().iso8601,
                status: "active",
                error_message: ""
            ),
            allBalances: []
        )
    }
}

struct ComplicationProvider: AppIntentTimelineProvider {

    func recommendations() -> [AppIntentRecommendation<ProviderIntent>] {
        let cursor = ProviderIntent()
        cursor.provider = .cursor
        let anthropic = ProviderIntent()
        anthropic.provider = .anthropic
        let openai = ProviderIntent()
        openai.provider = .openai
        let google = ProviderIntent()
        google.provider = .google
        return [
            AppIntentRecommendation(intent: cursor, description: "Cursor 用量"),
            AppIntentRecommendation(intent: anthropic, description: "Claude 用量"),
            AppIntentRecommendation(intent: openai, description: "OpenAI 用量"),
            AppIntentRecommendation(intent: google, description: "Gemini 用量"),
        ]
    }

    func placeholder(in context: Context) -> BalanceWidgetEntry { .sample }

    func snapshot(for configuration: ProviderIntent, in context: Context) async -> BalanceWidgetEntry {
        await makeEntry(for: configuration)
    }

    func timeline(for configuration: ProviderIntent, in context: Context) async -> Timeline<BalanceWidgetEntry> {
        let entry = await makeEntry(for: configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(for config: ProviderIntent) async -> BalanceWidgetEntry {
        let balances = await loadBalances()
        let target = balances.first { $0.service_id == config.provider.rawValue }
            ?? balances.first
        return BalanceWidgetEntry(date: Date(), item: target, allBalances: balances)
    }

    // 数据加载: App Group → 标准 UserDefaults → 直接从服务器获取
    private func loadBalances() async -> [BalanceItem] {
        // 1) App Group 缓存
        if let items = loadFromDefaults(UserDefaults(suiteName: AppConstants.appGroupID)) {
            return items
        }
        // 2) 标准 UserDefaults
        if let items = loadFromDefaults(UserDefaults.standard) {
            return items
        }
        // 3) 直接从 Flask 服务器获取
        return await fetchFromServer()
    }

    private func loadFromDefaults(_ defaults: UserDefaults?) -> [BalanceItem]? {
        guard let defaults = defaults,
              let data = defaults.data(forKey: AppConstants.StorageKeys.cachedBalances),
              let items = try? JSONDecoder().decode([BalanceItem].self, from: data),
              !items.isEmpty
        else { return nil }
        return items
    }

    private func fetchFromServer() async -> [BalanceItem] {
        let urlString = UserDefaults.standard.string(forKey: "server_url")
            ?? AppConstants.defaultServerURL
        guard let url = URL(string: "\(urlString)/api/balances") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(BalancesResponse.self, from: data)
            // 缓存到标准 UserDefaults 供下次使用
            if let encoded = try? JSONEncoder().encode(response.balances) {
                UserDefaults.standard.set(encoded, forKey: AppConstants.StorageKeys.cachedBalances)
                UserDefaults.standard.set(Date(), forKey: AppConstants.StorageKeys.lastUpdated)
            }
            return response.balances
        } catch {
            return []
        }
    }
}

// MARK: - 颜色

private func progressColor(_ pct: Double) -> Color {
    if pct >= 90 { return .red }
    if pct >= 70 { return .orange }
    return .green
}

// MARK: - 主视图

struct ComplicationView: View {
    let entry: BalanceWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:   circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline:     inlineView
        case .accessoryCorner:     cornerView
        default:                   inlineView
        }
    }

    // MARK: - 圆形 Complication
    // 外圈: 进度环 (满圈=100%)
    // 内部: 用量/总额 数字
    // 底部: 提供商名称

    private var circularView: some View {
        ZStack {
            // 背景轨道环
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)

            // 进度环
            if let item = entry.item, item.total_quota != nil {
                Circle()
                    .trim(from: 0, to: min(item.usage_percentage / 100, 1.0))
                    .stroke(
                        progressColor(item.usage_percentage),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            // 中心文字
            VStack(spacing: 0) {
                if let item = entry.item {
                    // 已用量
                    Text(formatShort(item.used_amount))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    if let total = item.total_quota, total > 0 {
                        // 分隔线
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 20, height: 0.5)
                            .padding(.vertical, 1)
                        // 总额
                        Text(formatShort(total))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }

                    // 提供商名
                    Text(item.service_name)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("--")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text("无数据")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 矩形 Complication
    // 上行: 提供商图标 + 名称 + 用量/总额
    // 下行: 横向进度条 + 百分比

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let item = entry.item {
                // 标题行
                HStack(spacing: 5) {
                    Image(systemName: item.iconSymbol)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(item.service_name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    // 用量 / 总额
                    if let total = item.total_quota, total > 0 {
                        Text("\(formatShort(item.used_amount)) / \(formatShort(total))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    } else {
                        Text(formatShort(item.used_amount))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                }

                // 横向进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(progressColor(item.usage_percentage))
                            .frame(width: geo.size.width * CGFloat(min(item.usage_percentage, 100) / 100))
                    }
                }
                .frame(height: 5)

                // 底部: 百分比
                HStack(spacing: 4) {
                    Text("\(String(format: "%.1f", item.usage_percentage))%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(progressColor(item.usage_percentage))

                    if let total = item.total_quota, total > 0, let remaining = item.remaining {
                        Text("剩余 \(formatShort(remaining))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Token 摘要 (Cursor)
                    if let cx = item.cursorExtra {
                        Text("In \(String(format: "%.0f", cx.input_tokens_m))M")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack {
                    Text("AI 余额")
                        .font(.system(size: 12, weight: .semibold))
                    Text("暂无数据")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 内联 Complication

    private var inlineView: some View {
        if let item = entry.item {
            if let total = item.total_quota, total > 0 {
                Text("\(item.service_name) \(formatShort(item.used_amount))/\(formatShort(total))")
            } else {
                Text("\(item.service_name) \(formatShort(item.used_amount))")
            }
        } else {
            Text("AI 余额: 无数据")
        }
    }

    // MARK: - 角落 Complication

    private var cornerView: some View {
        Group {
            if let item = entry.item {
                Gauge(value: min(item.usage_percentage, 100), in: 0...100) {
                    Text(item.service_name)
                } currentValueLabel: {
                    Text(formatShort(item.used_amount))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(progressColor(item.usage_percentage))
            } else {
                Text("AI")
                    .font(.system(size: 12, weight: .bold))
            }
        }
    }

    // MARK: - 格式化

    private func formatShort(_ amount: Double) -> String {
        if amount >= 1000 {
            return "$\(String(format: "%.0f", amount))"
        }
        if amount >= 100 {
            return "$\(String(format: "%.1f", amount))"
        }
        return "$\(String(format: "%.2f", amount))"
    }
}

// MARK: - Widget 配置

struct BalanceComplication: Widget {
    let kind: String = "BalanceComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ProviderIntent.self,
            provider: ComplicationProvider()
        ) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI 余额")
        .description("在表盘上显示 AI 服务的用量进度")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

// MARK: - Date 扩展

extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}

// MARK: - 预览

#Preview("圆形", as: .accessoryCircular) {
    BalanceComplication()
} timeline: {
    BalanceWidgetEntry.sample
}

#Preview("矩形", as: .accessoryRectangular) {
    BalanceComplication()
} timeline: {
    BalanceWidgetEntry.sample
}

#Preview("内联", as: .accessoryInline) {
    BalanceComplication()
} timeline: {
    BalanceWidgetEntry.sample
}

#Preview("角落", as: .accessoryCorner) {
    BalanceComplication()
} timeline: {
    BalanceWidgetEntry.sample
}
