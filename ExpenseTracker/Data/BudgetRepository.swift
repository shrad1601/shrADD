import Foundation

protocol BudgetRepository {
    func fetchBudgets() async throws -> [CategoryBudget]
    func setBudget(category: String, limit: Double) async throws
}
