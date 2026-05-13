import Foundation
import Testing

@testable import Roost

@Suite("DeepSeekUsageParser")
struct DeepSeekUsageParserTests {
    @Test("parses CNY balance rows")
    func parseCNYBalance() throws {
        let json = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """

        let rows = try DeepSeekUsageParser.parseMetricRows(from: Data(json.utf8))
        #expect(rows.count == 3)
        #expect(rows[0].label == "余额")
        #expect(rows[0].detail != nil)
        #expect(rows[1].label == "充值")
        #expect(rows[1].detail != nil)
        #expect(rows[2].label == "赠送")
        #expect(rows[2].detail != nil)
    }

    @Test("handles empty balance_infos")
    func emptyBalanceInfo() {
        let json = """
        {
          "is_available": true,
          "balance_infos": []
        }
        """

        #expect(throws: DeepSeekUsageParserError.invalidPayload) {
            try DeepSeekUsageParser.parseMetricRows(from: Data(json.utf8))
        }
    }
}
