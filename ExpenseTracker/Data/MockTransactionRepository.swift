import Foundation

final class MockTransactionRepository: TransactionRepository {
    private var transactions: [Transaction] = MockTransactionRepository.seedTransactions

    func fetchTransactions() async throws -> [Transaction] {
        transactions
    }

    func addTransaction(_ transaction: Transaction) async throws {
        transactions.append(transaction)
    }

    func updateTransaction(_ transaction: Transaction) async throws {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
    }

    func deleteTransaction(id: String) async throws {
        transactions.removeAll { $0.id == id }
    }

    static let seedTransactions: [Transaction] = [
        Transaction(id: "1", merchant: "Danieles Pizza", amount: 6.00, date: Date(timeIntervalSinceNow: -3600 * 2), category: "Food", note: "Solo lunch order"),
        Transaction(id: "2", merchant: "NTUC FairPrice", amount: 42.50, date: Date(timeIntervalSinceNow: -3600 * 8), category: "Food", note: nil),
        Transaction(id: "3", merchant: "Grab", amount: 15.80, date: Date(timeIntervalSinceNow: -3600 * 26), category: "Transport", note: nil),
        Transaction(id: "4", merchant: "Netflix", amount: 20.98, date: Date(timeIntervalSinceNow: -3600 * 50), category: "Subscriptions", note: nil),
        Transaction(id: "5", merchant: "Shopee", amount: 63.40, date: Date(timeIntervalSinceNow: -3600 * 74), category: "Shopping", note: "Phone case + charger"),
        Transaction(id: "6", merchant: "SP Group", amount: 118.65, date: Date(timeIntervalSinceNow: -3600 * 98), category: "Utilities", note: nil)
    ]
}
