import Foundation

enum DeepSeekUsageParserError: Error {
    case invalidPayload
}

enum DeepSeekUsageParser {
    static func parseMetricRows(from data: Data) throws -> [AIUsageMetricRow] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balanceInfos = payload["balance_infos"] as? [[String: Any]],
              let first = balanceInfos.first
        else {
            throw DeepSeekUsageParserError.invalidPayload
        }

        let currency = first["currency"] as? String ?? "CNY"

        let total = AIUsageParserSupport.number(in: first, keys: ["total_balance"])
        let granted = AIUsageParserSupport.number(in: first, keys: ["granted_balance"])
        let toppedUp = AIUsageParserSupport.number(in: first, keys: ["topped_up_balance"])

        var rows: [AIUsageMetricRow] = []

        if let total {
            rows.append(
                AIUsageMetricRow(
                    label: "余额",
                    percent: nil,
                    resetDate: nil,
                    detail: AIUsageParserSupport.currencyDetail(amount: total, code: currency)
                )
            )
        }

        if let toppedUp {
            rows.append(
                AIUsageMetricRow(
                    label: "充值",
                    percent: nil,
                    resetDate: nil,
                    detail: AIUsageParserSupport.currencyDetail(amount: toppedUp, code: currency)
                )
            )
        }

        if let granted {
            rows.append(
                AIUsageMetricRow(
                    label: "赠送",
                    percent: nil,
                    resetDate: nil,
                    detail: AIUsageParserSupport.currencyDetail(amount: granted, code: currency)
                )
            )
        }

        return rows
    }
}
