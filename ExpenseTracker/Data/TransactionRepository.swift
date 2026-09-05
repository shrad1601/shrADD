import Foundation

protocol TransactionRepository {
    func fetchTransactions() async throws -> [Transaction]
    func addTransaction(_ transaction: Transaction) async throws
    func updateTransaction(_ transaction: Transaction) async throws
    func deleteTransaction(id: String) async throws
}
