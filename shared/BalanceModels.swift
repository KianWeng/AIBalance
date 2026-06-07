import Foundation

// MARK: - Cursor 附加数据模型

struct CursorModelDetail: Codable {
    let name: String
    let input_m: Double
    let output_m: Double
    let cache_m: Double
    let cost: Double
}

struct CursorExtra: Codable {
    let input_tokens_m: Double
    let output_tokens_m: Double
    let cache_tokens_m: Double
    let models: [CursorModelDetail]
}

// MARK: - 余额数据模型（与服务端 JSON 对应）

/// 单个服务的余额信息
struct BalanceItem: Codable, Identifiable {
    let service_name: String
    let service_id: String
    let plan_name: String
    let total_quota: Double?
    let used_amount: Double
    let remaining: Double?
    let currency: String
    let billing_period: String
    let usage_percentage: Double
    let last_updated: String
    let status: String
    let error_message: String
    var extra: [String: AnyCodable]? = nil

    var id: String { service_id }

    /// 解析 Cursor 附加数据
    var cursorExtra: CursorExtra? {
        guard service_id == "cursor", let extra = extra else { return nil }
        let data = try? JSONSerialization.data(withJSONObject: extra.mapValues { $0.value })
        return data.flatMap { try? JSONDecoder().decode(CursorExtra.self, from: $0) }
    }

    /// 格式化显示文本
    var displayAmount: String {
        if status == "error" {
            return error_message
        }

        if currency == "requests" {
            if let total = total_quota {
                return "\(Int(used_amount))/\(Int(total)) 次"
            }
            return "\(Int(used_amount)) 次"
        }

        if currency == "CNY" {
            if let total = total_quota, total > 0 {
                return "¥\(String(format: "%.2f", used_amount)) / ¥\(String(format: "%.0f", total))"
            }
            if used_amount > 0 {
                return "¥\(String(format: "%.2f", used_amount))"
            }
        }

        // 美元计费
        if let total = total_quota, total > 0 {
            return "$\(String(format: "%.2f", used_amount)) / $\(String(format: "%.0f", total))"
        }
        if used_amount > 0 {
            return "$\(String(format: "%.2f", used_amount))"
        }

        return plan_name
    }

    /// 简短显示（用于 Complication / Watch）
    var shortDisplay: String {
        if status == "error" { return "!" }
        if currency == "requests" {
            return "\(Int(used_amount))"
        }
        if currency == "CNY" {
            if let remaining = remaining {
                return "¥\(String(format: "%.0f", remaining))"
            }
            if used_amount > 0 {
                return "¥\(String(format: "%.2f", used_amount))"
            }
        }
        if let remaining = remaining {
            return "$\(String(format: "%.0f", remaining))"
        }
        if used_amount > 0 {
            return "$\(String(format: "%.2f", used_amount))"
        }
        return "OK"
    }

    /// 服务图标 SF Symbol 名称
    var iconSymbol: String {
        switch service_id {
        case "anthropic": return "brain.head.profile"
        case "openai": return "sparkles"
        case "cursor": return "chevron.left.forwardslash.chevron.right"
        case "google": return "g.circle"
        case "deepseek": return "fish"
        default: return "circle.dashed"
        }
    }

    /// Complication 用的颜色 tint
    var tintColorName: String {
        switch service_id {
        case "anthropic": return "AnthropicOrange"
        case "openai": return "OpenAIGreen"
        case "cursor": return "CursorBlue"
        case "google": return "GoogleBlue"
        case "deepseek": return "DeepSeekBlue"
        default: return "AccentColor"
        }
    }
}

/// 服务端返回的完整响应
struct BalancesResponse: Codable {
    let balances: [BalanceItem]
    let last_updated: String?
    let is_refreshing: Bool
    let service_count: Int
}

/// 发送到 Watch 的数据包
struct WatchPayload: Codable {
    let balances: [BalanceItem]
    let timestamp: Date
}

// MARK: - AnyCodable 辅助 (处理 extra dict 的任意类型值)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}
