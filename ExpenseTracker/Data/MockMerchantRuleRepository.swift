import Foundation

final class MockMerchantRuleRepository: MerchantRuleRepository {
    private var rules: [MerchantRule] = [
        MerchantRule(keyword: "tanvi", category: "Friends")
    ]

    func fetchRules() async throws -> [MerchantRule] {
        rules
    }

    func addRule(_ rule: MerchantRule) async throws {
        rules.removeAll { $0.keyword == rule.keyword }
        rules.append(rule)
    }

    func deleteRule(keyword: String) async throws {
        rules.removeAll { $0.keyword == keyword }
    }
}
