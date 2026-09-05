import Foundation

final class MockBudgetRepository: BudgetRepository {
    private var budgets: [String: Double] = [
        "Food": 300,
        "Shopping": 150
    ]

    func fetchBudgets() async throws -> [CategoryBudget] {
        budgets.map { CategoryBudget(category: $0.key, limit: $0.value) }
    }

    func setBudget(category: String, limit: Double) async throws {
        budgets[category] = limit
    }
}
