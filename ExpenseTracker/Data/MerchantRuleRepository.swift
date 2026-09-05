import Foundation

protocol MerchantRuleRepository {
    func fetchRules() async throws -> [MerchantRule]
    func addRule(_ rule: MerchantRule) async throws
    func deleteRule(keyword: String) async throws
}
